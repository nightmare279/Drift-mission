-- Sprint Mission Module
local SprintMission = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local sprintMission = false
local currentCheckpoint = 0
local checkpointBlips = {}
local flareObjects = {}
local startingBlip = nil
local finishBlip = nil
local countdownActive = false
local playerInCorrectDirection = true
local startFlags = nil
local finishFlags = nil

-- Thread control
local sprintDetectionThreadActive = false
local debugThreadActive = false
local debugEnabled = false

function SprintMission.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
end

function SprintMission.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

function SprintMission.SetDebugMode(enabled)
    debugEnabled = enabled
end

function SprintMission.IsSprintMission()
    return sprintMission
end

-- Flare creation and management
function SprintMission.CreateFlares(position, heading, distance)
    local flares = {}
    
    -- Convert GTA heading to radians
    local headingRad = math.rad(heading)
    
    -- Get the perpendicular vector (left and right of the heading)
    local perpX = math.cos(headingRad)
    local perpY = math.sin(headingRad)
    
    -- Calculate left and right positions
    local halfDistance = distance / 2
    local leftX = position.x + perpX * halfDistance
    local leftY = position.y + perpY * halfDistance
    local rightX = position.x - perpX * halfDistance
    local rightY = position.y - perpY * halfDistance
    
    -- Get ground Z coordinates
    local leftZ = position.z
    local rightZ = position.z
    local foundLeft, groundLeft = GetGroundZFor_3dCoord(leftX, leftY, position.z + 10.0, 0)
    local foundRight, groundRight = GetGroundZFor_3dCoord(rightX, rightY, position.z + 10.0, 0)
    if foundLeft then leftZ = groundLeft + 0.1 end
    if foundRight then rightZ = groundRight + 0.1 end
    
    -- Create smoke effects
    UseParticleFxAssetNextCall("core")
    local leftSmoke = StartParticleFxLoopedAtCoord("exp_grd_flare", leftX, leftY, leftZ, 0.0, 0.0, 0.0, 1.5, false, false, false, false)
    
    UseParticleFxAssetNextCall("core")
    local rightSmoke = StartParticleFxLoopedAtCoord("exp_grd_flare", rightX, rightY, rightZ, 0.0, 0.0, 0.0, 1.5, false, false, false, false)
    
    -- Set smoke color to red
    SetParticleFxLoopedColour(leftSmoke, 1.0, 0.0, 0.0, 0)
    SetParticleFxLoopedColour(rightSmoke, 1.0, 0.0, 0.0, 0)
    
    flares.left = leftSmoke
    flares.right = rightSmoke
    flares.leftPos = vector3(leftX, leftY, leftZ)
    flares.rightPos = vector3(rightX, rightY, rightZ)
    flares.isSmoke = true
    
    return flares
end

function SprintMission.RemoveFlares(flares)
    if flares then
        if flares.isSmoke then
            if flares.left then
                StopParticleFxLooped(flares.left, 0)
            end
            if flares.right then
                StopParticleFxLooped(flares.right, 0)
            end
        else
            -- Remove objects (for backwards compatibility)
            if flares.left and DoesEntityExist(flares.left) then
                DeleteObject(flares.left)
            end
            if flares.right and DoesEntityExist(flares.right) then
                DeleteObject(flares.right)
            end
        end
    end
end

-- Blip management
function SprintMission.CreateSprintBlips(mission)
    -- Create start and finish flares
    local flareDistance = mission.FlareDistance or 8.0
    startFlags = SprintMission.CreateFlares(mission.StartingPosition, mission.StartingPosition.w, flareDistance)
    finishFlags = SprintMission.CreateFlares(mission.FinishPosition, mission.FinishPosition.w, flareDistance)
    
    -- Starting position blip
    if startingBlip then RemoveBlip(startingBlip) end
    startingBlip = AddBlipForCoord(mission.StartingPosition.x, mission.StartingPosition.y, mission.StartingPosition.z)
    SetBlipSprite(startingBlip, 38) -- start line
    SetBlipColour(startingBlip, 2) -- green
    SetBlipScale(startingBlip, 0.8)
    SetBlipAsShortRange(startingBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Sprint Start")
    EndTextCommandSetBlipName(startingBlip)
    
    -- Checkpoint blips
    for i, checkpoint in ipairs(mission.Checkpoints) do
        local blip = AddBlipForCoord(checkpoint.position.x, checkpoint.position.y, checkpoint.position.z)
        SetBlipSprite(blip, checkpoint.blipSprite or 1)
        SetBlipColour(blip, checkpoint.blipColor or 5)
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName("Checkpoint " .. i)
        EndTextCommandSetBlipName(blip)
        table.insert(checkpointBlips, blip)
    end
    
    -- Finish position blip
    if finishBlip then RemoveBlip(finishBlip) end
    finishBlip = AddBlipForCoord(mission.FinishPosition.x, mission.FinishPosition.y, mission.FinishPosition.z)
    SetBlipSprite(finishBlip, 38) -- finish line
    SetBlipColour(finishBlip, 1) -- red
    SetBlipScale(finishBlip, 0.8)
    SetBlipAsShortRange(finishBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Sprint Finish")
    EndTextCommandSetBlipName(finishBlip)
end

function SprintMission.RemoveSprintBlips()
    if startingBlip then RemoveBlip(startingBlip) startingBlip = nil end
    if finishBlip then RemoveBlip(finishBlip) finishBlip = nil end
    for _, blip in ipairs(checkpointBlips) do
        if blip then RemoveBlip(blip) end
    end
    checkpointBlips = {}
    
    -- Remove start and finish flares
    if startFlags then SprintMission.RemoveFlares(startFlags) startFlags = nil end
    if finishFlags then SprintMission.RemoveFlares(finishFlags) finishFlags = nil end
end

function SprintMission.UpdateActiveFlares(mission)
    -- Remove all existing flares first
    for i, flares in pairs(flareObjects) do
        if flares then
            SprintMission.RemoveFlares(flares)
        end
    end
    flareObjects = {}
    
    -- Only show flares for next 2 checkpoints
    local nextCheckpoint = currentCheckpoint + 1
    for i = nextCheckpoint, math.min(nextCheckpoint + 1, #mission.Checkpoints) do
        local checkpoint = mission.Checkpoints[i]
        if checkpoint then
            local flares = SprintMission.CreateFlares(checkpoint.position, checkpoint.position.w, mission.FlareDistance or 8.0)
            if flares then
                flareObjects[i] = flares
            end
        end
    end
end

function SprintMission.IsPlayerBetweenFlares(flares)
    if not flares or not flares.leftPos or not flares.rightPos then return false end
    
    local playerPos = GetEntityCoords(PlayerPedId())
    local leftPos = flares.leftPos
    local rightPos = flares.rightPos
    
    -- Calculate if player is between the flares using cross product
    local lineVec = vector3(rightPos.x - leftPos.x, rightPos.y - leftPos.y, 0)
    local playerVec = vector3(playerPos.x - leftPos.x, playerPos.y - leftPos.y, 0)
    
    -- Check if player is within the line segment
    local dot = playerVec.x * lineVec.x + playerVec.y * lineVec.y
    local lineLength = #lineVec
    
    if dot < 0 or dot > lineLength * lineLength then
        return false
    end
    
    -- Check distance from line
    local distance = #(playerPos - vector3(leftPos.x, leftPos.y, playerPos.z))
    local distance2 = #(playerPos - vector3(rightPos.x, rightPos.y, playerPos.z))
    
    return math.min(distance, distance2) < 12.0
end

-- Countdown system
function SprintMission.StartCountdown(callback)
    countdownActive = true
    local ped = PlayerPedId()
    local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or nil
    
    if vehicle then
        FreezeEntityPosition(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
    end
    
    for i = 5, 1, -1 do
        if not countdownActive then break end
        
        if modules.UIManager and modules.UIManager.SetStatusText then
            modules.UIManager.SetStatusText("~r~" .. i)
        end
        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true)
        Wait(1000)
    end
    
    if countdownActive then
        if modules.UIManager and modules.UIManager.SetStatusText then
            modules.UIManager.SetStatusText("~g~GO!")
        end
        PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", true)
        
        if vehicle then
            FreezeEntityPosition(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        end
        
        Wait(1000)
        if modules.UIManager and modules.UIManager.SetStatusText then
            modules.UIManager.SetStatusText("")
        end
        countdownActive = false
        
        if callback then callback() end
    end
end

-- Sprint Detection Thread
function SprintMission.StartSprintDetectionThread()
    if sprintDetectionThreadActive then return end
    sprintDetectionThreadActive = true
    
    Citizen.CreateThread(function()
        while sprintDetectionThreadActive do
            Wait(10)
            
            if sprintMission and sharedState.missionActive and sharedState.missionTimer > 0 and sharedState.activeMissionId then
                local mission = Config.Missions[sharedState.activeMissionId]
                local ped = PlayerPedId()
                
                -- Player is always in zone for sprint missions
                playerInCorrectDirection = true
                
                -- Check if player is in vehicle for drift detection
                if IsPedInAnyVehicle(ped, false) then
                    local veh = GetVehiclePedIsIn(ped, false)
                    local currentSpeed = GetEntitySpeed(veh) * 2.23694
                    
                    -- Calculate drift angle
                    local heading = GetEntityHeading(veh)
                    local vel = GetEntityVelocity(veh)
                    local v = math.sqrt(vel.x^2 + vel.y^2)
                    local currentAngle = 0
                    if v > 1.5 then
                        local carDir = math.rad(heading + 90)
                        local velDir = math.atan2(vel.y, vel.x)
                        currentAngle = math.abs((math.deg(velDir - carDir) + 180) % 360 - 180)
                    end
                    
                    -- Drift detection logic - always in zone for sprint missions
                    local drifting = (currentAngle > 10 and currentSpeed > 15)
                    
                    -- Use drift detection from main system but adapt for sprint
                    if modules.DriftDetection and modules.DriftDetection.ProcessSprintDrift then
                        modules.DriftDetection.ProcessSprintDrift(drifting, currentAngle, currentSpeed, veh)
                    end
                end
                
                -- Check checkpoint progression
                local nextCheckpointIndex = currentCheckpoint + 1
                if nextCheckpointIndex <= #mission.Checkpoints then
                    local checkpoint = mission.Checkpoints[nextCheckpointIndex]
                    local flares = flareObjects[nextCheckpointIndex]
                    
                    if flares and SprintMission.IsPlayerBetweenFlares(flares) then
                        -- Checkpoint reached!
                        currentCheckpoint = nextCheckpointIndex
                        sharedState.missionTimer = sharedState.missionTimer + checkpoint.timeBonus
                        
                        -- Remove this checkpoint's flares
                        SprintMission.RemoveFlares(flares)
                        flareObjects[nextCheckpointIndex] = nil
                        
                        -- Update active flares for next checkpoints
                        SprintMission.UpdateActiveFlares(mission)
                        
                        -- Show checkpoint notification
                        if modules.UIManager and modules.UIManager.TempMessage then
                            modules.UIManager.TempMessage(string.format("~g~Checkpoint %d reached!\n~b~+%d seconds", nextCheckpointIndex, checkpoint.timeBonus), 2000)
                        end
                        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true)
                        
                        -- Check if this was the last checkpoint
                        if currentCheckpoint >= #mission.Checkpoints then
                            if modules.UIManager and modules.UIManager.TempMessage then
                                modules.UIManager.TempMessage("~y~Head to the finish line!", 3000)
                            end
                        end
                    end
                elseif currentCheckpoint >= #mission.Checkpoints then
                    -- Check finish line using flares
                    local finishFlares = finishFlags
                    if finishFlares and SprintMission.IsPlayerBetweenFlares(finishFlares) then
                        -- Mission complete!
                        SprintMission.CompleteMission()
                    end
                end
            else
                Wait(500)
            end
        end
    end)
end

function SprintMission.StopSprintDetectionThread()
    sprintDetectionThreadActive = false
end

function SprintMission.CompleteMission()
    sharedState.missionActive = false
    sprintMission = false
    
    -- Clean up ALL flares
    for i, flares in pairs(flareObjects) do
        if flares then
            SprintMission.RemoveFlares(flares)
        end
    end
    flareObjects = {}
    
    SprintMission.RemoveSprintBlips()
    SprintMission.StopSprintDetectionThread()
    
    if modules.UIManager and modules.UIManager.TempMessage then
        modules.UIManager.TempMessage("~g~Sprint completed!\n~b~Return to the Drift King to submit your score.", 4000)
    end
    PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", true)
end

-- Debug drawing
function SprintMission.DrawSprintDebug()
    if not sprintMission or not sharedState.activeMissionId then return end
    
    local mission = Config.Missions[sharedState.activeMissionId]
    if not mission then return end
    
    -- Draw checkpoints
    for i, checkpoint in ipairs(mission.Checkpoints) do
        local color = i <= currentCheckpoint and {0, 255, 0, 150} or {255, 255, 0, 150}
        if i == currentCheckpoint + 1 then
            color = {255, 100, 100, 200} -- Next checkpoint in red
        end
        
        DrawMarker(1, checkpoint.position.x, checkpoint.position.y, checkpoint.position.z - 1.0, 
                  0, 0, 0, 0, 0, 0, 3.0, 3.0, 2.0, 
                  color[1], color[2], color[3], color[4], 
                  false, false, 2, false, nil, nil, false)
    end
    
    -- Draw finish line
    local finishColor = currentCheckpoint >= #mission.Checkpoints and {0, 255, 0, 200} or {100, 100, 100, 150}
    DrawMarker(1, mission.FinishPosition.x, mission.FinishPosition.y, mission.FinishPosition.z - 1.0,
              0, 0, 0, 0, 0, 0, 4.0, 4.0, 2.0,
              finishColor[1], finishColor[2], finishColor[3], finishColor[4],
              false, false, 2, false, nil, nil, false)
              
    -- Draw flares
    for i, flares in pairs(flareObjects) do
        if flares and flares.leftPos and flares.rightPos then
            DrawLine(flares.leftPos.x, flares.leftPos.y, flares.leftPos.z + 1.0,
                    flares.rightPos.x, flares.rightPos.y, flares.rightPos.z + 1.0,
                    255, 0, 0, 255)
        end
    end
end

-- Mission control
function SprintMission.StartSprintMission(missionId)
    sprintMission = true
    currentCheckpoint = 0
    playerInCorrectDirection = true
    
    local mission = Config.Missions[missionId]
    
    -- Create blips for all checkpoints and finish
    SprintMission.CreateSprintBlips(mission)
    
    -- Set initial status
    if modules.UIManager and modules.UIManager.SetStatusText then
        modules.UIManager.SetStatusText("~b~Head to the starting line to begin the sprint.")
    end
    
    -- Start detection threads
    SprintMission.StartSprintDetectionThread()
    
    -- Wait until player reaches starting position
    local startPos = vector3(mission.StartingPosition.x, mission.StartingPosition.y, mission.StartingPosition.z)
    while #(GetEntityCoords(PlayerPedId()) - startPos) > 15.0 do
        Wait(500)
    end
    
    -- Position and lock vehicle at starting line
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        SetEntityCoords(vehicle, mission.StartingPosition.x, mission.StartingPosition.y, mission.StartingPosition.z, false, false, false, true)
        SetEntityHeading(vehicle, mission.StartingPosition.w)
    end
    
    -- Start countdown
    SprintMission.StartCountdown(function()
        -- Mission officially starts after countdown
        sharedState.missionActive = true
        sharedState.missionTimer = mission.InitialTime or 20
        
        -- Update flares for first 2 checkpoints
        SprintMission.UpdateActiveFlares(mission)
        
        if modules.UIManager then
            if modules.UIManager.SetStatusText then
                modules.UIManager.SetStatusText("")
            end
            if modules.UIManager.TempMessage then
                modules.UIManager.TempMessage("~g~Sprint started! Reach the checkpoints before time runs out!", 3000)
            end
        end
        
        -- Sprint timer thread
        Citizen.CreateThread(function()
            while sharedState.missionActive and sharedState.missionTimer > 0 do
                Wait(1000)
                sharedState.missionTimer = sharedState.missionTimer - 1
            end
            if sharedState.missionActive then
                -- Time's up!
                sharedState.missionActive = false
                sprintMission = false
                
                -- Clean up
                for _, flares in pairs(flareObjects) do
                    SprintMission.RemoveFlares(flares)
                end
                flareObjects = {}
                SprintMission.RemoveSprintBlips()
                SprintMission.StopSprintDetectionThread()
                sharedState.driftScores = {}
                sharedState.activeMissionId = nil
                currentCheckpoint = 0
                if modules.UIManager and modules.UIManager.TempMessage then
                    modules.UIManager.TempMessage("~r~Time's up! Mission failed.", 4000)
                end
            end
        end)
    end)
end

function SprintMission.CancelSprintMission()
    if sprintMission then
        sprintMission = false
        countdownActive = false
        
        -- Clean up ALL flares
        for i = 1, 10 do
            if flareObjects[i] then
                SprintMission.RemoveFlares(flareObjects[i])
                flareObjects[i] = nil
            end
        end
        flareObjects = {}
        
        SprintMission.RemoveSprintBlips()
        SprintMission.StopSprintDetectionThread()
        currentCheckpoint = 0
    end
end

-- Getters
function SprintMission.GetSprintData()
    return {
        sprintMission = sprintMission,
        currentCheckpoint = currentCheckpoint,
        playerInCorrectDirection = playerInCorrectDirection,
        countdownActive = countdownActive
    }
end

function SprintMission.Cleanup()
    SprintMission.StopSprintDetectionThread()
    SprintMission.CancelSprintMission()
end

return SprintMission
