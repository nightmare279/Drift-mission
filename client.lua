-- local Config = lib.require and lib.require('config') or require('config')
local playerProgress = {}
local playerBestScore = {}
local driftNpc = nil

local activeMissionId = nil
local missionActive = false
local missionTimer = 0
local driftScores = {}
local driftActive = false
local currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
local missionDisplayText = ""

local driftZoneBlip = nil
local driftZoneBlip_icon = nil
local driftPolyZones = {}

-- Sprint mission variables
local sprintMission = false
local currentCheckpoint = 0
local checkpointBlips = {}
local flareObjects = {}
local startingBlip = nil
local finishBlip = nil
local countdownActive = false
local playerInCorrectDirection = true
local lastDirectionCheck = 0
local startFlags = nil
local finishFlags = nil

-- Enhanced drift tracking
local currentAngle = 0
local lastAngle = 0
local currentSpeed = 0
local driftCombo = 0
local showDriftUI = false
local lastDriftTime = 0
local comboResetTime = 3000 -- 3 seconds between drifts to maintain combo

-- Drift result display
local showDriftResult = false
local driftResultScore = 0
local driftResultType = "good" -- "good", "crashed", "spinout", "out_of_zone"
local driftResultEndTime = 0
local screenEffectEndTime = 0

-- Out of zone tracking
local playerInZone = false
local showOutOfZone = false

-- Thread control variables
local uiThreadActive = false
local debugThreadActive = false
local driftDetectionThreadActive = false
local sprintDetectionThreadActive = false

-- Police dispatch tracking
local lastCrashDispatch = 0
local lastSpinoutDispatch = 0
local dispatchCooldown = 30000 -- 30 seconds between dispatches

-- NUI Management
local leaderboardOpen = false

-- Initialize NUI as hidden
Citizen.CreateThread(function()
    Wait(1000) -- Wait for NUI to load
    SendNUIMessage({
        type = 'hideLeaderboard'
    })
end)

-- Debug
local debugEnabled = false
local function debug(msg, ...)
    if debugEnabled then print(("[driftmission DEBUG] " .. msg):format(...)) end
end

RegisterCommand("driftdbg", function()
    debugEnabled = not debugEnabled
    print("^2[driftmission]^7 Debugging is now " .. (debugEnabled and "ON" or "OFF"))
    
    -- Start/stop debug thread based on state
    if debugEnabled then
        StartDebugThread()
    else
        StopDebugThread()
    end
end)

-----------------------------------
-- Sprint Mission Functions
-----------------------------------

function CreateFlares(position, heading, distance)
    local flares = {}
    
    -- Convert GTA heading to radians (GTA heading: 0 = North, 90 = East, 180 = South, 270 = West)
    -- We need to get the perpendicular direction (left and right of the heading)
    local headingRad = math.rad(heading)
    
    -- Get the perpendicular vector (90 degrees to the left and right)
    -- For GTA coordinates: forward direction is -sin(heading), cos(heading)
    -- So perpendicular (left/right) is cos(heading), sin(heading)
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
    
    -- Create smoke effects instead of flare objects
    UseParticleFxAssetNextCall("core")
    local leftSmoke = StartParticleFxLoopedAtCoord("exp_grd_flare", leftX, leftY, leftZ, 0.0, 0.0, 0.0, 1.5, false, false, false, false)
    
    UseParticleFxAssetNextCall("core")
    local rightSmoke = StartParticleFxLoopedAtCoord("exp_grd_flare", rightX, rightY, rightZ, 0.0, 0.0, 0.0, 1.5, false, false, false, false)
    
    -- Set smoke color to make them more visible (red)
    SetParticleFxLoopedColour(leftSmoke, 1.0, 0.0, 0.0, 0)
    SetParticleFxLoopedColour(rightSmoke, 1.0, 0.0, 0.0, 0)
    
    flares.left = leftSmoke
    flares.right = rightSmoke
    flares.leftPos = vector3(leftX, leftY, leftZ)
    flares.rightPos = vector3(rightX, rightY, rightZ)
    flares.isSmoke = true -- Flag to identify smoke effects
    
    print(string.format("^2[DriftMission] Created smoke flares at: Left(%.2f, %.2f, %.2f) Right(%.2f, %.2f, %.2f)", 
        leftX, leftY, leftZ, rightX, rightY, rightZ))
    
    return flares
end

function RemoveFlares(flares)
    if flares then
        if flares.isSmoke then
            -- Remove smoke effects
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

function CreateRacingFlags(position, heading, distance, flagType)
    -- flagType: "start" or "finish"
    -- Create two flags, left and right of the position
    local flags = {}
    
    -- Convert GTA heading to radians and get perpendicular direction
    local headingRad = math.rad(heading)
    local halfDist = distance / 2
    
    -- Get the perpendicular vector (left and right of heading direction)
    local perpX = math.cos(headingRad)
    local perpY = math.sin(headingRad)
    
    -- Calculate left and right positions
    local leftX = position.x + perpX * halfDist
    local leftY = position.y + perpY * halfDist
    local rightX = position.x - perpX * halfDist
    local rightY = position.y - perpY * halfDist
    
    -- Get ground Z coordinates
    local leftZ = position.z
    local rightZ = position.z
    local foundLeft, groundLeft = GetGroundZFor_3dCoord(leftX, leftY, position.z + 10.0, 0)
    local foundRight, groundRight = GetGroundZFor_3dCoord(rightX, rightY, position.z + 10.0, 0)
    if foundLeft then leftZ = groundLeft end
    if foundRight then rightZ = groundRight end
    
    local flagModel = GetHashKey("prop_flag_us")
    RequestModel(flagModel)
    
    local timeout = 0
    while not HasModelLoaded(flagModel) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(flagModel) then
        print("^1[DriftMission] Failed to load flag model!")
        return nil
    end
    
    -- Create left flag
    local leftFlag = CreateObject(flagModel, leftX, leftY, leftZ, true, true, false)
    if DoesEntityExist(leftFlag) then
        SetEntityHeading(leftFlag, heading) -- Use original heading for flag orientation
        SetEntityAsMissionEntity(leftFlag, true, true)
        FreezeEntityPosition(leftFlag, true)
        SetEntityCollision(leftFlag, false, false)
    end
    
    -- Create right flag
    local rightFlag = CreateObject(flagModel, rightX, rightY, rightZ, true, true, false)
    if DoesEntityExist(rightFlag) then
        SetEntityHeading(rightFlag, heading) -- Use original heading for flag orientation
        SetEntityAsMissionEntity(rightFlag, true, true)
        FreezeEntityPosition(rightFlag, true)
        SetEntityCollision(rightFlag, false, false)
    end
    
    flags.left = leftFlag
    flags.right = rightFlag
    flags.leftPos = vector3(leftX, leftY, leftZ)
    flags.rightPos = vector3(rightX, rightY, rightZ)
    
    print(string.format("^2[DriftMission] Created %s flags at: Left(%.2f, %.2f, %.2f) Right(%.2f, %.2f, %.2f)", 
        flagType, leftX, leftY, leftZ, rightX, rightY, rightZ))
    
    return flags
end

function RemoveRacingFlags(flags)
    if flags then
        if flags.left and DoesEntityExist(flags.left) then
            DeleteObject(flags.left)
        end
        if flags.right and DoesEntityExist(flags.right) then
            DeleteObject(flags.right)
        end
    end
end

function CreateRacingFlag(position, heading, flagType)
    -- flagType: "start" or "finish"
    local flagModel = GetHashKey("prop_flag_us")  -- US flag instead of UK!
    RequestModel(flagModel)
    
    local timeout = 0
    while not HasModelLoaded(flagModel) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if not HasModelLoaded(flagModel) then
        print("^1[DriftMission] Failed to load flag model!")
        return nil
    end
    
    -- Get ground Z coordinate
    local flagZ = position.z
    local found, groundZ = GetGroundZFor_3dCoord(position.x, position.y, position.z + 10.0, 0)
    if found then flagZ = groundZ end
    
    local flag = CreateObject(flagModel, position.x, position.y, flagZ, true, true, false)
    
    if not DoesEntityExist(flag) then
        print("^1[DriftMission] Failed to create flag object!")
        return nil
    end
    
    SetEntityHeading(flag, heading)
    SetEntityAsMissionEntity(flag, true, true)
    FreezeEntityPosition(flag, true)
    SetEntityCollision(flag, false, false)
    
    print(string.format("^2[DriftMission] Created %s flag at: %.2f, %.2f, %.2f", flagType, position.x, position.y, flagZ))
    
    return flag
end

function RemoveRacingFlag(flag)
    if flag and DoesEntityExist(flag) then
        DeleteObject(flag)
    end
end

function CreateSprintBlips(mission)
    -- Create start and finish flares instead of flags
    local flareDistance = mission.FlareDistance or 8.0
    startFlags = CreateFlares(mission.StartingPosition, mission.StartingPosition.w, flareDistance)
    finishFlags = CreateFlares(mission.FinishPosition, mission.FinishPosition.w, flareDistance)
    
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

function RemoveSprintBlips()
    if startingBlip then RemoveBlip(startingBlip) startingBlip = nil end
    if finishBlip then RemoveBlip(finishBlip) finishBlip = nil end
    for _, blip in ipairs(checkpointBlips) do
        if blip then RemoveBlip(blip) end
    end
    checkpointBlips = {}
    
    -- Remove start and finish flares (instead of racing flags)
    if startFlags then RemoveFlares(startFlags) startFlags = nil end
    if finishFlags then RemoveFlares(finishFlags) finishFlags = nil end
end

function UpdateActiveFlares(mission)
    -- Remove all existing flares first
    for i, flares in pairs(flareObjects) do
        if flares then
            print(string.format("^1[DEBUG] Removing flares for checkpoint %d", i))
            RemoveFlares(flares)
        end
    end
    flareObjects = {} -- Clear the table completely
    
    -- Only show flares for next 2 checkpoints
    local nextCheckpoint = currentCheckpoint + 1
    for i = nextCheckpoint, math.min(nextCheckpoint + 1, #mission.Checkpoints) do
        local checkpoint = mission.Checkpoints[i]
        if checkpoint then
            print(string.format("^2[DEBUG] Creating flares for checkpoint %d", i))
            local flares = CreateFlares(checkpoint.position, checkpoint.position.w, mission.FlareDistance or 8.0)
            if flares then
                flareObjects[i] = flares
            end
        end
    end
    
    print(string.format("^3[DEBUG] Active flares count: %d", #flareObjects))
end

function IsPlayerBetweenFlares(flares)
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
        return false -- Player is outside the line segment
    end
    
    -- Check distance from line
    local distance = #(playerPos - vector3(leftPos.x, leftPos.y, playerPos.z))
    local distance2 = #(playerPos - vector3(rightPos.x, rightPos.y, playerPos.z))
    
    return math.min(distance, distance2) < (GetConfigValue("CheckpointTriggerDistance") or 12.0)
end

function GetConfigValue(key)
    if activeMissionId and Config.Missions[activeMissionId] then
        return Config.Missions[activeMissionId][key]
    end
    return nil
end

function CheckPlayerDirection(mission)
    -- Removed direction checking - entire map is now in zone for sprint missions
    return
end

function StartCountdown(callback)
    countdownActive = true
    local ped = PlayerPedId()
    local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or nil
    
    if vehicle then
        FreezeEntityPosition(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
    end
    
    for i = 5, 1, -1 do
        if not countdownActive then break end
        
        SetStatusText("~r~" .. i)
        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true)
        Wait(1000)
    end
    
    if countdownActive then
        SetStatusText("~g~GO!")
        PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", true)
        
        if vehicle then
            FreezeEntityPosition(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
        end
        
        Wait(1000)
        SetStatusText("")
        countdownActive = false
        
        if callback then callback() end
    end
end

-- Sprint Detection Thread
-- Sprint Detection Thread
function StartSprintDetectionThread()
    if sprintDetectionThreadActive then return end
    sprintDetectionThreadActive = true
    
    Citizen.CreateThread(function()
        while sprintDetectionThreadActive do
            Wait(10) -- Increased wait time to reduce lag
            
            if sprintMission and missionActive and missionTimer > 0 and activeMissionId then
                local mission = Config.Missions[activeMissionId]
                local ped = PlayerPedId()
                
                -- Skip direction checking - entire map is in zone now
                playerInCorrectDirection = true
                showOutOfZone = false
                
                -- Check if player is in vehicle for drift detection
                if IsPedInAnyVehicle(ped, false) then
                    local veh = GetVehiclePedIsIn(ped, false)
                    currentSpeed = GetEntitySpeed(veh) * 2.23694
                    
                    -- Calculate drift angle
                    local heading = GetEntityHeading(veh)
                    local vel = GetEntityVelocity(veh)
                    local v = math.sqrt(vel.x^2 + vel.y^2)
                    if v > 1.5 then
                        local carDir = math.rad(heading + 90)
                        local velDir = math.atan2(vel.y, vel.x)
                        currentAngle = math.abs((math.deg(velDir - carDir) + 180) % 360 - 180)
                    else
                        currentAngle = 0
                    end
                    
                    -- Drift detection logic - always in zone for sprint missions
                    local drifting = (currentAngle > 10 and currentSpeed > 15)
                    
                    -- Check combo timeout (reset if too much time between drifts)
                    local currentTime = GetGameTimer()
                    if not drifting and driftCombo > 0 and (currentTime - lastDriftTime) > comboResetTime then
                        driftCombo = 0
                    end
                    
                    if drifting then
                        if not driftActive then
                            driftActive = true
                            currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                        end
                        
                        currentDrift.duration = currentDrift.duration + 0.01 -- Changed from 0.25 to match drift zones
                        
                        -- Check for spinout
                        if currentAngle >= 135 and not currentDrift.spinout then
                            currentDrift.spinout = true
                            currentDrift.score = currentDrift.score * 0.3
                        end
                        
                        -- Accumulate score if not crashed or spun out - SAME AS DRIFT ZONES
                        if not currentDrift.crashed and not currentDrift.spinout then
                            local gear = GetVehicleCurrentGear(veh)
                            local reverseMultiplier = gear == 0 and 0.25 or 1.0
                            
                            -- Enhanced scoring system - SAME AS DRIFT ZONES
                            local angleMultiplier = 1.0
                            if currentAngle > 45 then
                                angleMultiplier = 1.5 -- Bonus for higher angles
                            end
                            if currentAngle > 90 then
                                angleMultiplier = 2.0 -- Higher bonus for extreme angles
                            end
                            
                            local speedMultiplier = math.min(currentSpeed / 60, 2.0) -- Cap speed bonus
                            local comboMultiplier = 1.0 + (driftCombo * 0.1) -- 10% bonus per combo
                            
                            -- FIXED: Use same scoring calculation as drift zones (0.002 instead of 0.05)
                            local scoreGain = currentAngle * currentSpeed * 0.002 * reverseMultiplier * angleMultiplier * speedMultiplier * comboMultiplier
                            currentDrift.score = currentDrift.score + scoreGain
                        end
                        
                        -- Check for crashes
                        if HasEntityCollidedWithAnything(veh) or (IsEntityInAir(veh) and not IsVehicleOnAllWheels(veh)) then
                            if not currentDrift.crashed then
                                currentDrift.crashed = true
                                currentDrift.score = 0
                            end
                        end
                        
                        -- End drift if spun out
                        if currentDrift.spinout then
                            Wait(500)
                            local finalScore = currentDrift.score
                            if finalScore > 0 then
                                table.insert(driftScores, finalScore)
                            end
                            ShowDriftResult(finalScore, "spinout")
                            driftCombo = 0
                            lastDriftTime = currentTime -- Added missing lastDriftTime update
                            driftActive = false
                            currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                        end
                    else
                        if driftActive then
                            -- End current drift
                            local finalScore = currentDrift.score
                            local resultType = "good"
                            
                            if currentDrift.crashed then
                                resultType = "crashed"
                                driftCombo = 0
                            elseif currentDrift.spinout then
                                resultType = "spinout"
                                driftCombo = 0
                            else
                                if finalScore > 0 then
                                    table.insert(driftScores, finalScore)
                                    driftCombo = driftCombo + 1
                                    lastDriftTime = currentTime -- Update last successful drift time
                                else
                                    driftCombo = 0
                                end
                            end
                            
                            ShowDriftResult(finalScore, resultType)
                            driftActive = false
                            currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                        end
                    end
                end
                
                -- Check checkpoint progression (moved to slower update cycle)
                local nextCheckpointIndex = currentCheckpoint + 1
                if nextCheckpointIndex <= #mission.Checkpoints then
                    local checkpoint = mission.Checkpoints[nextCheckpointIndex]
                    local flares = flareObjects[nextCheckpointIndex]
                    
                    if flares and IsPlayerBetweenFlares(flares) then
                        -- Checkpoint reached!
                        currentCheckpoint = nextCheckpointIndex
                        missionTimer = missionTimer + checkpoint.timeBonus
                        
                        -- Remove this checkpoint's flares
                        RemoveFlares(flares)
                        flareObjects[nextCheckpointIndex] = nil
                        
                        -- Update active flares for next checkpoints
                        UpdateActiveFlares(mission)
                        
                        -- Show checkpoint notification
                        TempMessage(string.format("~g~Checkpoint %d reached!\n~b~+%d seconds", nextCheckpointIndex, checkpoint.timeBonus), 2000)
                        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", true)
                        
                        -- Check if this was the last checkpoint
                        if currentCheckpoint >= #mission.Checkpoints then
                            -- Now player needs to reach finish line
                            TempMessage("~y~Head to the finish line!", 3000)
                        end
                    end
                elseif currentCheckpoint >= #mission.Checkpoints then
                    -- Check finish line using flares
                    local finishFlares = finishFlags
                    if finishFlares and IsPlayerBetweenFlares(finishFlares) then
                        -- Mission complete!
                        CompleteMission()
                    end
                end
            else
                Wait(500)
            end
        end
    end)
end

function StopSprintDetectionThread()
    sprintDetectionThreadActive = false
end

function CompleteMission()
    missionActive = false
    sprintMission = false
    showDriftUI = false
    showOutOfZone = false
    playerInCorrectDirection = true
    
    -- Clean up ALL flares with detailed logging
    print("^1[DEBUG] Starting mission completion cleanup...")
    for i, flares in pairs(flareObjects) do
        if flares then
            print(string.format("^1[DEBUG] Removing flares for checkpoint %d", i))
            RemoveFlares(flares)
        end
    end
    flareObjects = {} -- Clear the entire table
    print("^1[DEBUG] Flares cleanup completed")
    
    RemoveSprintBlips()
    StopSprintDetectionThread()
    StopDebugThread()
    
    TempMessage("~g~Sprint completed!\n~b~Return to the Drift King to submit your score.", 4000)
    PlaySoundFrontend(-1, "RACE_PLACED", "HUD_AWARDS", true)
end

-----------------------------------
-- NUI Callbacks
-----------------------------------

RegisterNUICallback('closeLeaderboard', function(data, cb)
    SetNuiFocus(false, false)
    leaderboardOpen = false
    SendNUIMessage({
        type = 'hideLeaderboard'
    })
    cb('ok')
end)

function OpenLeaderboard()
    if leaderboardOpen then return end
    
    leaderboardOpen = true
    TriggerServerEvent('driftmission:requestLeaderboard')
end

RegisterNetEvent('driftmission:receiveLeaderboard', function(leaderboardData, missions)
    SetNuiFocus(true, true)
    -- Force NUI to be transparent
    SendNUIMessage({
        type = 'showLeaderboard',
        leaderboardData = leaderboardData,
        missions = missions,
        currentMission = activeMissionId or 1
    })
    -- Try to set the NUI background transparent on the client side
    SetNuiFocusKeepInput(false)
end)

-----------------------------------
-- Enhanced UI Display Functions
-----------------------------------

function GetAngleColor(angle)
    if angle < 15 then
        return {100, 255, 100, 255} -- Green
    elseif angle < 45 then
        return {255, 255, 100, 255} -- Yellow
    elseif angle < 90 then
        return {255, 165, 0, 255} -- Orange
    elseif angle < 135 then
        return {255, 100, 100, 255} -- Red
    else
        return {255, 50, 50, 255} -- Dark Red (spinout territory)
    end
end

function GetSpeedColor(speed)
    if speed < 15 then
        return {150, 150, 150, 255} -- Gray (too slow)
    elseif speed < 30 then
        return {255, 255, 100, 255} -- Yellow
    elseif speed < 60 then
        return {100, 255, 100, 255} -- Green
    else
        return {100, 200, 255, 255} -- Blue (high speed)
    end
end

function DrawDriftUI()
    if not showDriftUI then return end
    
    -- Simplified UI - single horizontal line at top center, fixed positions
    local centerX = 0.5
    local topY = 0.02
    local spacing = 0.08 -- Reduced horizontal spacing between elements
    
    -- Fixed positions for each element to prevent movement (swapped current and total)
    local timeX = centerX - spacing
    local currentScoreX = centerX  -- Current score now in center
    local totalScoreX = centerX + spacing  -- Total score now on right
    
    -- Time remaining (fixed position) - using GTA font and increased size
    local timeColor = missionTimer > 30 and {110, 193, 255, 255} or {255, 100, 100, 255}
    SetTextFont(4) -- Font 4 is the GTA style font
    SetTextScale(0.575, 0.575) -- Increased by 15% from 0.5 to 0.575
    SetTextColour(timeColor[1], timeColor[2], timeColor[3], timeColor[4])
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(string.format("Time: %02d:%02d", math.floor(missionTimer / 60), missionTimer % 60))
    EndTextCommandDisplayText(timeX, topY)
    
    -- Total score (fixed position - now on right)
    SetTextFont(4) -- Changed to GTA font
    SetTextScale(0.575, 0.575) -- Increased by 15% from 0.5 to 0.575
    SetTextColour(110, 193, 255, 255) -- Changed to light blue
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(string.format("Total: %d", GetTotalScore()))
    EndTextCommandDisplayText(totalScoreX, topY)
    
    -- Current score and status (fixed position - now in center, only when drifting, showing result, or out of zone)
    if driftActive or showDriftResult or showOutOfZone then
        local displayScore = showDriftResult and driftResultScore or math.floor(currentDrift.score)
        local scoreColor = {110, 193, 255, 255} -- Changed to light blue as default
        local displayText = ""
        
        if showOutOfZone then
            scoreColor = {255, 50, 50, 255} -- Red for out of zone
            displayText = "OUT OF ZONE!"
        elseif showDriftResult or driftActive then
            if (showDriftResult and driftResultType == "crashed") or (driftActive and currentDrift.crashed) then
                scoreColor = {255, 50, 50, 255}
                displayText = "CRASHED!" -- Only show status, no score
            elseif (showDriftResult and driftResultType == "spinout") or (driftActive and currentDrift.spinout) then
                scoreColor = {255, 150, 50, 255}
                displayText = "SPUN OUT!" -- Only show status, no score
            else
                displayText = string.format("Current: %d", displayScore) -- Normal display with score
            end
        else
            displayText = string.format("Current: %d", displayScore)
        end
        
        SetTextFont(4) -- Changed to GTA font
        SetTextScale(0.575, 0.575) -- Increased by 15% from 0.5 to 0.575
        SetTextColour(scoreColor[1], scoreColor[2], scoreColor[3], scoreColor[4])
        SetTextOutline()
        SetTextCentre(true)
        BeginTextCommandDisplayText("STRING")
        AddTextComponentSubstringPlayerName(displayText)
        EndTextCommandDisplayText(currentScoreX, topY)
        
        -- Angle indicator bar (only when actively drifting and in zone) - made shorter
        if driftActive and not showDriftResult and not showOutOfZone then
            local barWidth = 0.2 -- Reduced from 0.3 to make it shorter
            local barHeight = 0.015
            local barX = centerX - barWidth/2
            local barY = topY + 0.055
            
            -- Background bar
            DrawRect(centerX, barY, barWidth, barHeight, 50, 50, 50, 200)
            
            -- Angle progress (0-180 degrees)
            local angleColor = GetAngleColor(currentAngle)
            local angleProgress = math.min(currentAngle / 180, 1.0)
            local progressWidth = barWidth * angleProgress
            DrawRect(barX + progressWidth/2, barY, progressWidth, barHeight, angleColor[1], angleColor[2], angleColor[3], 255)
            
            -- Spinout threshold line (135 degrees)
            local spinoutThreshold = barWidth * (135 / 180)
            DrawRect(barX + spinoutThreshold, barY, 0.003, barHeight + 0.01, 255, 0, 0, 255) -- Increased thickness
            
            -- Spinout label (adjusted for new bar position)
            SetTextFont(4) -- GTA font
            SetTextScale(0.3, 0.3)
            SetTextColour(255, 0, 0, 255)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName("SPINOUT")
            EndTextCommandDisplayText(barX + spinoutThreshold, barY - 0.025) -- Adjusted for new bar position
            
            -- Combo text (positioned above and to the right of spinout label, over the right end of the shorter bar)
            if driftCombo > 1 then
                local comboX = barX + barWidth - 0.015 -- Adjusted for shorter bar width
                local comboY = barY - 0.025 -- Same height as spinout label
                local comboMultiplier = 1.0 + (driftCombo * 0.1)
                
                SetTextFont(4) -- GTA font
                SetTextScale(0.3, 0.3)
                SetTextColour(255, 165, 0, 255) -- Orange color
                SetTextOutline()
                SetTextCentre(true)
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName(string.format("x%d (%.1fx)", driftCombo, comboMultiplier))
                EndTextCommandDisplayText(comboX, comboY)
            end
        end
    end
    
    -- Sprint mission specific UI
    if sprintMission then
        -- Show checkpoint progress
        local mission = Config.Missions[activeMissionId]
        if mission then
            local progressY = topY + 0.12
            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(string.format("Checkpoint: %d/%d", currentCheckpoint, #mission.Checkpoints))
            EndTextCommandDisplayText(centerX, progressY)
        end
    end
end

-- UI Thread Control Functions
function StartUIThread()
    if uiThreadActive then return end
    uiThreadActive = true
    
    Citizen.CreateThread(function()
        while uiThreadActive do
            Citizen.Wait(0)
            if showDriftUI then
                DrawDriftUI()
                
                -- Handle drift result display timeout
                if showDriftResult and GetGameTimer() > driftResultEndTime then
                    showDriftResult = false
                end
                
                -- Handle screen effects
                local currentTime = GetGameTimer()
                if currentTime < screenEffectEndTime then
                    if driftResultType == "crashed" then
                        -- Red filter for crash
                        DrawRect(0.5, 0.5, 1.0, 1.0, 255, 0, 0, 100)
                    elseif driftResultType == "spinout" then
                        -- Orange filter for spinout
                        DrawRect(0.5, 0.5, 1.0, 1.0, 255, 150, 0, 80)
                    end
                end
            elseif missionDisplayText ~= "" then
                DrawMissionText(missionDisplayText)
            else
                Citizen.Wait(100)
            end
        end
    end)
end

function StopUIThread()
    uiThreadActive = false
end

-----------------------------------
-- Police Dispatch Functions
-----------------------------------

function TriggerPoliceDispatch(dispatchType)
    local currentTime = GetGameTimer()
    
    -- Check cooldown
    if (dispatchType == "crash" and currentTime - lastCrashDispatch < dispatchCooldown) or
       (dispatchType == "spinout" and currentTime - lastSpinoutDispatch < dispatchCooldown) then
        return
    end
    
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    local coords = GetEntityCoords(ped)
    
    -- Get vehicle primary color
    local primaryColor, secondaryColor = GetVehicleColours(vehicle)
    local colorName = GetVehicleColorName(primaryColor)
    
    -- Send dispatch to server
    TriggerServerEvent("driftmission:policeDispatch", dispatchType, coords, colorName)
    
    -- Update cooldown
    if dispatchType == "crash" then
        lastCrashDispatch = currentTime
    elseif dispatchType == "spinout" then
        lastSpinoutDispatch = currentTime
    end
end

function GetVehicleColorName(colorIndex)
    local colors = {
        [0] = "Black", [1] = "Graphite", [2] = "Black Steel", [3] = "Dark Silver", [4] = "Silver",
        [5] = "Blue Silver", [6] = "Steel Gray", [7] = "Shadow Silver", [8] = "Stone Silver",
        [9] = "Midnight Silver", [10] = "Gun Metal", [11] = "Anthracite", [12] = "Red",
        [13] = "Torino Red", [14] = "Formula Red", [15] = "Lava Red", [16] = "Blaze Red",
        [17] = "Grace Red", [18] = "Garnet Red", [19] = "Sunset Red", [20] = "Cabernet Red",
        [21] = "Wine Red", [22] = "Candy Red", [23] = "Hot Pink", [24] = "Pfsiter Pink",
        [25] = "Salmon Pink", [26] = "Sunrise Orange", [27] = "Orange", [28] = "Bright Orange",
        [29] = "Gold", [30] = "Bronze", [31] = "Yellow", [32] = "Race Yellow", [33] = "Dew Yellow",
        [34] = "Dark Green", [35] = "Racing Green", [36] = "Sea Green", [37] = "Olive Green",
        [38] = "Bright Green", [39] = "Gasoline Green", [40] = "Lime Green", [41] = "Midnight Blue",
        [42] = "Galaxy Blue", [43] = "Dark Blue", [44] = "Saxon Blue", [45] = "Blue",
        [46] = "Mariner Blue", [47] = "Harbor Blue", [48] = "Diamond Blue", [49] = "Surf Blue",
        [50] = "Nautical Blue", [51] = "Racing Blue", [52] = "Ultra Blue", [53] = "Light Blue",
        [54] = "Chocolate Brown", [55] = "Bison Brown", [56] = "Creek Brown", [57] = "Feltzer Brown",
        [58] = "Maple Brown", [59] = "Beechwood Brown", [60] = "Sienna Brown", [61] = "Saddle Brown",
        [62] = "Moss Brown", [63] = "Woodbeech Brown", [64] = "Straw Brown", [65] = "Sandy Brown",
        [66] = "Bleached Brown", [67] = "Schafter Purple", [68] = "Spinnaker Purple", [69] = "Midnight Purple",
        [70] = "Bright Purple", [71] = "Cream", [72] = "Ice White", [73] = "Frost White"
    }
    return colors[colorIndex] or "Unknown"
end

-----------------------------------
-- Utility Functions
-----------------------------------

function DrawMissionText(text, color)
    color = color or {255, 255, 255, 220}
    SetTextFont(7)
    SetTextScale(0.7, 0.7)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.80)
end

function SetStatusText(txt)
    missionDisplayText = txt or ""
    if txt and txt ~= "" then
        StartUIThread()
    end
end

function TempMessage(txt, time)
    SetStatusText(txt)
    CreateThread(function()
        Wait(time or 5000) -- Increased default from 1200 to 5000
        SetStatusText("")
    end)
end

function ShowDriftZoneBlip(missionId)
    local mission = Config.Missions[missionId]
    if driftZoneBlip then RemoveBlip(driftZoneBlip) driftZoneBlip = nil end
    if driftZoneBlip_icon then RemoveBlip(driftZoneBlip_icon) driftZoneBlip_icon = nil end
    if mission.Zone and mission.Zone.center and mission.Zone.radius then
        driftZoneBlip = AddBlipForRadius(mission.Zone.center.x, mission.Zone.center.y, mission.Zone.center.z, mission.Zone.radius)
        SetBlipColour(driftZoneBlip, mission.BlipColor or 1)
        SetBlipAlpha(driftZoneBlip, 128)
        SetBlipAsShortRange(driftZoneBlip, false)
        driftZoneBlip_icon = AddBlipForCoord(mission.Zone.center.x, mission.Zone.center.y, mission.Zone.center.z)
        SetBlipSprite(driftZoneBlip_icon, mission.BlipSprite or 398)
        SetBlipColour(driftZoneBlip_icon, mission.BlipColor or 1)
        SetBlipScale(driftZoneBlip_icon, 0.9)
        SetBlipAsShortRange(driftZoneBlip_icon, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(mission.Name or "Drift Mission")
        EndTextCommandSetBlipName(driftZoneBlip_icon)
    elseif mission.Zone and mission.Zone.poly then
        -- For poly, just add a blip at its first point or average center
        local poly = mission.Zone.poly
        local x, y, z = 0, 0, 0
        for _, pt in ipairs(poly) do
            x = x + pt.x; y = y + pt.y; z = z + (pt.z or 0)
        end
        x = x / #poly; y = y / #poly; z = z / #poly
        driftZoneBlip_icon = AddBlipForCoord(x, y, z)
        SetBlipSprite(driftZoneBlip_icon, mission.BlipSprite or 398)
        SetBlipColour(driftZoneBlip_icon, mission.BlipColor or 1)
        SetBlipScale(driftZoneBlip_icon, 0.9)
        SetBlipAsShortRange(driftZoneBlip_icon, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(mission.Name or "Drift Mission")
        EndTextCommandSetBlipName(driftZoneBlip_icon)
    end
end

function HideDriftZoneBlip()
    if driftZoneBlip then RemoveBlip(driftZoneBlip) driftZoneBlip = nil end
    if driftZoneBlip_icon then RemoveBlip(driftZoneBlip_icon) driftZoneBlip_icon = nil end
end

function ShowDriftResult(score, resultType)
    driftResultScore = math.floor(score)
    driftResultType = resultType
    showDriftResult = true
    driftResultEndTime = GetGameTimer() + 1000 -- Show for 1 second
    screenEffectEndTime = GetGameTimer() + 1000 -- Screen effect for 1 second
    
    -- Trigger police dispatch for crashes and spinouts
    if resultType == "crashed" or resultType == "spinout" then
        TriggerPoliceDispatch(resultType)
    end
    
    -- Apply native effects
    if resultType == "crashed" then
        -- Small explosion shake for crash
        ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", 1.0)
        -- Stop the shake after 1 second
        Citizen.SetTimeout(1000, function()
            StopGameplayCamShaking(true)
        end)
    elseif resultType == "spinout" then
        -- Drunk shake for spinout
        ShakeGameplayCam("DRUNK_SHAKE", 1.0)
        -- Stop the shake after 1 second
        Citizen.SetTimeout(1000, function()
            StopGameplayCamShaking(true)
        end)
    end
end

function GetTotalScore()
    local total = 0
    for i, v in ipairs(driftScores) do
        total = total + v
    end
    return math.floor(total)
end

-----------------------------------
-- Debug Zone Drawing
-----------------------------------

function DrawZoneDebug(zone)
    if zone.poly then
        local color = {60, 200, 255, 150}
        for i = 1, #zone.poly do
            local pt1 = zone.poly[i]
            local pt2 = zone.poly[(i % #zone.poly) + 1]
            DrawLine(pt1.x, pt1.y, pt1.z or pt1.z or 32.0, pt2.x, pt2.y, pt2.z or pt1.z or 32.0, color[1], color[2], color[3], color[4])
        end
        -- Center marker
        local sumx, sumy, sumz = 0,0,0
        for _, pt in ipairs(zone.poly) do sumx = sumx + pt.x; sumy = sumy + pt.y; sumz = sumz + (pt.z or 32.0) end
        local n = #zone.poly
        DrawMarker(1, sumx/n, sumy/n, (sumz/n) - 1.0, 0,0,0, 0,0,0, 2.0,2.0,1.0, 0,255,255,70, false,false,2,false,nil,nil,false)
    elseif zone.center and zone.radius then
        local steps = 72
        local color = {60, 200, 255, 150}
        local playerPos = GetEntityCoords(PlayerPedId())
        local drawZ = zone.center.z
        if #(playerPos - zone.center) < (zone.radius + 30.0) then
            local found, groundZ = GetGroundZFor_3dCoord(zone.center.x, zone.center.y, playerPos.z + 10.0, 0)
            if found then drawZ = groundZ end
        end
        for i = 0, steps do
            local theta1 = (i / steps) * 2 * math.pi
            local theta2 = ((i + 1) / steps) * 2 * math.pi
            local x1 = zone.center.x + zone.radius * math.cos(theta1)
            local y1 = zone.center.y + zone.radius * math.sin(theta1)
            local x2 = zone.center.x + zone.radius * math.cos(theta2)
            local y2 = zone.center.y + zone.radius * math.sin(theta2)
            DrawLine(x1, y1, drawZ, x2, y2, drawZ, color[1], color[2], color[3], color[4])
        end
        DrawMarker(1, zone.center.x, zone.center.y, drawZ - 1.0, 0,0,0, 0,0,0, 2.0,2.0,1.0, 0,255,255,70, false,false,2,false,nil,nil,false)
    end
end

function DrawSprintDebug()
    if not sprintMission or not activeMissionId then return end
    
    local mission = Config.Missions[activeMissionId]
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
    for i, flares in ipairs(flareObjects) do
        if flares and flares.leftPos and flares.rightPos then
            DrawLine(flares.leftPos.x, flares.leftPos.y, flares.leftPos.z + 1.0,
                    flares.rightPos.x, flares.rightPos.y, flares.rightPos.z + 1.0,
                    255, 0, 0, 255)
        end
    end
end

-- Debug Thread Control Functions
function StartDebugThread()
    if debugThreadActive then return end
    debugThreadActive = true
    
    Citizen.CreateThread(function()
        while debugThreadActive do
            Citizen.Wait(0)
            if Config.DebugZone and activeMissionId and Config.Missions[activeMissionId] then
                local mission = Config.Missions[activeMissionId]
                if sprintMission then
                    DrawSprintDebug()
                elseif mission.Zone then 
                    DrawZoneDebug(mission.Zone) 
                else
                    Citizen.Wait(300)
                end
            else
                Citizen.Wait(300)
            end
        end
    end)
end

function StopDebugThread()
    debugThreadActive = false
end

-----------------------------------
-- NPC, Target, and Dialog (zone spawn logic)
-----------------------------------

local driftKingZone = nil
local driftNpcSpawned = false

function RemoveDriftNpc()
    if driftNpc and DoesEntityExist(driftNpc) then
        DeleteEntity(driftNpc)
        driftNpc = nil
        driftNpcSpawned = false
    end
end

function targetLocalEntity(entity, options, distance)
    for _, option in ipairs(options) do
        option.distance = distance
        option.onSelect = option.action
        option.action = nil
    end
    exports.ox_target:addLocalEntity(entity, options)
end

function SpawnDriftNpc()
    if driftNpc and DoesEntityExist(driftNpc) then return end
    RequestModel(Config.NpcModel)
    while not HasModelLoaded(Config.NpcModel) do Wait(10) end
    local x, y, z = table.unpack(Config.NpcCoords)
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z+10, 0)
    if foundGround then z = groundZ end
    driftNpc = CreatePed(4, Config.NpcModel, x, y, z, Config.NpcHeading or 333.0, false, false)
    SetEntityInvincible(driftNpc, true)
    SetBlockingOfNonTemporaryEvents(driftNpc, true)
    FreezeEntityPosition(driftNpc, true)
    SetEntityCoords(driftNpc, x, y, z, false, false, false, true)
    SetEntityAsMissionEntity(driftNpc, true, true)
    targetLocalEntity(driftNpc, {
        {
            icon = 'fa-solid fa-car',
            label = 'Talk to Drift King',
            canInteract = function() return true end,
            action = function()
                TriggerServerEvent('driftmission:requestUnlocks')
                Citizen.SetTimeout(250, ShowDriftKingDialog)
            end,
        },
    }, 1.5)
    driftNpcSpawned = true
end

function CreateDriftKingZone()
    if driftKingZone then driftKingZone:remove() driftKingZone = nil end
    driftKingZone = lib.points.new({
        coords = Config.NpcCoords.xyz or Config.NpcCoords,
        distance = 60.0,
        onEnter = function()
            if not driftNpcSpawned then SpawnDriftNpc() end
        end,
        onExit = function()
            RemoveDriftNpc()
        end
    })
end

-- Fixed player loading issue
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateDriftKingZone()
        -- Request unlocks for already loaded players
        if LocalPlayer.state.isLoggedIn then
            TriggerServerEvent('driftmission:requestUnlocks')
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if driftKingZone then driftKingZone:remove() driftKingZone = nil end
        RemoveDriftNpc()
        StopUIThread()
        StopDebugThread()
        StopDriftDetectionThread()
        StopSprintDetectionThread()
        
        -- Clean up sprint mission objects
        for _, flares in ipairs(flareObjects) do
            RemoveFlares(flares)
        end
        flareObjects = {}
        RemoveSprintBlips()
        startFlags = nil
        finishFlags = nil
        
        -- Close NUI if open
        if leaderboardOpen then
            SetNuiFocus(false, false)
            leaderboardOpen = false
            SendNUIMessage({
                type = 'hideLeaderboard'
            })
        end
    end
end)

-----------------------------------
-- Enhanced Dialog logic
-----------------------------------

local Dialog = {}

function RefreshDriftMissionDialog()
    local missionBtns = {}
    local unlockedCount = 0
    
    for missionId, mission in pairs(Config.Missions) do
        missionId = tonumber(missionId)
        if mission.UnlockScore == 0 or playerProgress[missionId] then
            unlockedCount = unlockedCount + 1
            local bestScore = playerBestScore[missionId] or 0
            local scoreText = bestScore > 0 and string.format(" (Best: %d)", bestScore) or ""
            
            table.insert(missionBtns, {
                label = (mission.Name or ('Drift Mission '..missionId)) .. scoreText,
                nextDialog = nil,
                close = false,
                onSelect = function()
                    -- Show mission details dialog
                    local missionTypeText = mission.Type == "sprint" and "Sprint Mission" or "Drift Mission"
                    local detailText = string.format(
                        "%s - %s\n\nDetails:\n%s\nReward Rate: $%.2f per point\nBest Score: %d points\n\n%s",
                        mission.Name or "Mission",
                        missionTypeText,
                        mission.Type == "sprint" and 
                            string.format("Initial Time: %d seconds\nCheckpoints: %d", mission.InitialTime or 20, #(mission.Checkpoints or {})) or
                            string.format("Time Limit: %d seconds", mission.MissionTime or 60),
                        mission.RewardPerScore or 0,
                        bestScore,
                        mission.Description or "No description available."
                    )
                    
                    -- Create temporary detail dialog
                    local detailDialog = {
                        [1] = {
                            id = 'mission_detail',
                            job = 'Drift King',
                            name = 'Slider Sam',
                            text = detailText,
                            buttons = {
                                {
                                    label = 'Accept Mission',
                                    close = true,
                                    onSelect = function()
                                        TriggerEvent("driftmission:start", missionId)
                                    end,
                                },
                                {
                                    label = 'Back to Missions',
                                    nextDialog = 'driftking_missions',
                                    close = false,
                                },
                            },
                        },
                        [2] = Dialog[2], -- Include the missions dialog
                        [3] = Dialog[1]  -- Include the main dialog
                    }
                    
                    exports.bl_dialog:showDialog({
                        ped = driftNpc,
                        dialog = detailDialog,
                        startId = 'mission_detail'
                    })
                end,
            })
        else
            -- Show locked missions with unlock requirements
            table.insert(missionBtns, {
                label = string.format("LOCKED %s (Requires %d points)", 
                    mission.Name or ('Mission '..missionId), 
                    mission.UnlockScore
                ),
                close = false,
                nextDialog = 'driftking_missions',
                onSelect = function()
                    TempMessage(string.format("~r~Mission locked!~w~\nRequires %d drift points to unlock.", mission.UnlockScore), 3000)
                end,
            })
        end
    end
    
    if unlockedCount == 0 then
        table.insert(missionBtns, {
            label = 'No missions unlocked yet!',
            close = true,
        })
    end
    
    table.insert(missionBtns, {
        label = '< Back',
        nextDialog = 'driftking_main',
        close = false,
    })
    
    Dialog[2] = {
        id = 'driftking_missions',
        job = 'Drift King',
        name = 'Slider Sam',
        text = "Choose your mission:",
        buttons = missionBtns,
    }
end

function RefreshDriftMainDialog()
    local mainBtns = {
        {
            label = "Let's Drift",
            nextDialog = 'driftking_missions',
        },
        {
            label = 'View Leaderboard',
            close = true,
            onSelect = function()
                OpenLeaderboard()
            end,
        },
    }
    
    -- Add cancel mission option if currently active
    if missionActive and activeMissionId then
        table.insert(mainBtns, 1, {
            label = 'Cancel Current Mission',
            close = true,
            onSelect = function()
                CancelCurrentMission()
            end,
        })
    end
    
    if not missionActive and activeMissionId and GetTotalScore() > 0 then
        table.insert(mainBtns, #mainBtns, {
            label = string.format('Turn In Score (%d points)', GetTotalScore()),
            close = true,
            onSelect = function()
                TriggerEvent("driftmission:turnin")
            end,
        })
    end
    
    table.insert(mainBtns, {
        label = 'Nothing',
        close = true,
    })
    
    Dialog[1] = {
        id = 'driftking_main',
        job = 'Drift King',
        name = 'Slider Sam',
        text = "Ready to burn rubber? What do you want to do?",
        buttons = mainBtns,
    }
end

function ShowDriftKingDialog()
    RefreshDriftMissionDialog()
    RefreshDriftMainDialog()
    exports.bl_dialog:showDialog({
        ped = driftNpc,
        dialog = Dialog,
        startId = 'driftking_main'
    })
end

function CancelCurrentMission()
    if missionActive then
        missionActive = false
        sprintMission = false
        showDriftUI = false
        showOutOfZone = false
        playerInZone = false
        playerInCorrectDirection = true
        countdownActive = false
        
        HideDriftZoneBlip()
        
        -- Clean up ALL sprint mission objects
        for i = 1, 10 do -- Check more indices to be safe
            if flareObjects[i] then
                RemoveFlares(flareObjects[i])
                flareObjects[i] = nil
            end
        end
        flareObjects = {} -- Clear the entire table
        
        RemoveSprintBlips()
        
        StopDriftDetectionThread()
        StopSprintDetectionThread()
        StopDebugThread()
        driftScores = {}
        activeMissionId = nil
        driftCombo = 0
        currentCheckpoint = 0
        TempMessage("~r~Mission cancelled!", 2000)
    end
end

-----------------------------------
-- Unlocks & Event Logic
-----------------------------------

RegisterNetEvent("driftmission:receiveUnlocks", function(unlocks)
    playerProgress = {}
    playerBestScore = {}
    for k, v in pairs(unlocks or {}) do
        local num = tonumber(k:match("^%d+$") and k)
        if tostring(k):find("score_") then
            playerBestScore[tonumber(k:sub(7))] = v
        elseif num then
            playerProgress[num] = v
        end
    end
    if driftNpcSpawned then SpawnDriftNpc() end
end)

RegisterNetEvent("driftmission:unlocked", function(missionId)
    missionId = tonumber(missionId)
    playerProgress[missionId] = true
    TempMessage("~g~New mission unlocked!", 3500)
    if driftNpcSpawned then SpawnDriftNpc() end
end)

function ShowLeaderboardMessage(txt, duration)
    SetStatusText(txt)
    CreateThread(function()
        Wait(duration)
        SetStatusText("")
    end)
end

RegisterNetEvent("driftmission:showLeaderboardMessage", function(messageType, bonusAmount)
    if messageType == "new_record" then
        ShowLeaderboardMessage("~y~🏆 NEW RECORD!~w~\n~g~You're now #1!~w~\n~g~Bonus: $" .. (bonusAmount or 5000) .. "!", 18000)
    elseif messageType == "improved_record" then
        ShowLeaderboardMessage("~y~🏁 You beat your previous record!~w~\n~b~You're still #1!", 10000)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('driftmission:requestUnlocks')
    -- Ensure drift zone is created for newly loaded players
    Citizen.SetTimeout(2000, function()
        CreateDriftKingZone()
    end)
end)

-- Handle player spawning after resource is already running
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    Citizen.SetTimeout(5000, function() -- Give some time for everything to load
        if not driftKingZone then
            CreateDriftKingZone()
        end
        TriggerServerEvent('driftmission:requestUnlocks')
    end)
end)

-----------------------------------
-- Mission Flow & Drift Zone Poly/radius
-----------------------------------
-- Simple 2D polygon test (ray-cast, works for {x, y} points in order)
local function IsPointInPoly(pos, poly)
    local x, y = pos.x, pos.y
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local xi, yi = poly[i].x, poly[i].y
        local xj, yj = poly[j].x, poly[j].y
        if ((yi > y) ~= (yj > y)) and
            (x < (xj - xi) * (y - yi) / ((yj - yi) ~= 0 and (yj - yi) or 0.00001) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function IsPlayerInDriftZone(zone, ped)
    local pos = GetEntityCoords(ped)
    if zone.poly then
        return IsPointInPoly(pos, zone.poly)
    elseif zone.center and zone.radius then
        return #(pos - zone.center) < zone.radius
    end
    return false
end

-- Drift Detection Thread Control Functions
function StartDriftDetectionThread()
    if driftDetectionThreadActive then return end
    driftDetectionThreadActive = true
    
    Citizen.CreateThread(function()
        while driftDetectionThreadActive do
            Wait(10)
            if missionActive and missionTimer > 0 and activeMissionId and not sprintMission then
                local mission = Config.Missions[activeMissionId]
                local ped = PlayerPedId()
                
                -- Check if player is in zone
                local inZone = IsPlayerInDriftZone(mission.Zone, ped)
                
                -- Update zone status
                if inZone ~= playerInZone then
                    playerInZone = inZone
                    if not inZone then
                        showOutOfZone = true
                        -- End any active drift when leaving zone
                        if driftActive then
                            driftActive = false
                            currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                            driftCombo = 0
                        end
                    else
                        showOutOfZone = false
                    end
                end
                
                if not IsPedInAnyVehicle(ped, false) then
                    if driftActive then
                        -- End current drift when exiting vehicle
                        if currentDrift.score > 0 and not currentDrift.crashed and not currentDrift.spinout then
                            table.insert(driftScores, currentDrift.score)
                            driftCombo = driftCombo + 1
                        else
                            driftCombo = 0
                        end
                        driftActive = false
                        currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                    end
                    currentAngle = 0
                    currentSpeed = 0
                    goto continue
                end
                
                local veh = GetVehiclePedIsIn(ped, false)
                currentSpeed = GetEntitySpeed(veh) * 2.23694
                currentAngle = 0
                
                -- Calculate drift angle
                do
                    local heading = GetEntityHeading(veh)
                    local vel = GetEntityVelocity(veh)
                    local v = math.sqrt(vel.x^2 + vel.y^2)
                    if v > 1.5 then
                        local carDir = math.rad(heading + 90)
                        local velDir = math.atan2(vel.y, vel.x)
                        currentAngle = math.abs((math.deg(velDir - carDir) + 180) % 360 - 180)
                    end
                end
                
                local drifting = (currentAngle > 10 and currentSpeed > 15 and inZone) -- Reduced speed requirement to 15mph
                
                -- Check combo timeout (reset if too much time between drifts)
                local currentTime = GetGameTimer()
                if not drifting and driftCombo > 0 and (currentTime - lastDriftTime) > comboResetTime then
                    driftCombo = 0
                end
                
                if drifting then
                    if not driftActive then
                        driftActive = true
                        currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                    end
                    
                    currentDrift.duration = currentDrift.duration + 0.01
                    
                    -- Check for spinout (135+ degrees)
                    if currentAngle >= 135 and not currentDrift.spinout then
                        currentDrift.spinout = true
                        -- Give only 30% of accumulated score when spinning out
                        currentDrift.score = currentDrift.score * 0.3
                    end
                    
                    -- Only accumulate score if not crashed or spun out
                    if not currentDrift.crashed and not currentDrift.spinout then
                        local gear = GetVehicleCurrentGear(veh)
                        local reverseMultiplier = gear == 0 and 0.25 or 1.0
                        
                        -- Enhanced scoring system
                        local angleMultiplier = 1.0
                        if currentAngle > 45 then
                            angleMultiplier = 1.5 -- Bonus for higher angles
                        end
                        if currentAngle > 90 then
                            angleMultiplier = 2.0 -- Higher bonus for extreme angles
                        end
                        
                        local speedMultiplier = math.min(currentSpeed / 60, 2.0) -- Cap speed bonus
                        local comboMultiplier = 1.0 + (driftCombo * 0.1) -- 10% bonus per combo
                        
                        local scoreGain = currentAngle * currentSpeed * 0.002 * reverseMultiplier * angleMultiplier * speedMultiplier * comboMultiplier
                        currentDrift.score = currentDrift.score + scoreGain
                    end
                    
                    -- Check for crashes
                    if HasEntityCollidedWithAnything(veh) or (IsEntityInAir(veh) and not IsVehicleOnAllWheels(veh)) then
                        if not currentDrift.crashed then
                            currentDrift.crashed = true
                            currentDrift.score = 0 -- Zero out score on crash
                        end
                    end
                    
                    -- End drift if spun out
                    if currentDrift.spinout then
                        Wait(500) -- Brief delay to show spinout status
                        local finalScore = currentDrift.score
                        if finalScore > 0 then
                            table.insert(driftScores, finalScore)
                        end
                        ShowDriftResult(finalScore, "spinout")
                        driftCombo = 0 -- Reset combo on spinout
                        lastDriftTime = currentTime
                        driftActive = false
                        currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                    end
                else
                    if driftActive then
                        -- End current drift
                        local finalScore = currentDrift.score
                        local resultType = "good"
                        
                        if currentDrift.crashed then
                            resultType = "crashed"
                            driftCombo = 0
                        elseif currentDrift.spinout then
                            resultType = "spinout"
                            driftCombo = 0
                        else
                            if finalScore > 0 then
                                table.insert(driftScores, finalScore)
                                driftCombo = driftCombo + 1
                                lastDriftTime = currentTime -- Update last successful drift time
                            else
                                driftCombo = 0
                            end
                        end
                        
                        ShowDriftResult(finalScore, resultType)
                        driftActive = false
                        currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                    end
                end
            else
                -- Reset when not in mission
                if driftActive then
                    driftActive = false
                    currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
                end
                currentAngle = 0
                currentSpeed = 0
                driftCombo = 0
                playerInZone = false
                showOutOfZone = false
                -- Sleep longer when not in mission to reduce CPU usage
                Citizen.Wait(500)
            end
            ::continue::
        end
    end)
end

function StopDriftDetectionThread()
    driftDetectionThreadActive = false
end

RegisterNetEvent("driftmission:start", function(missionId)
    missionId = tonumber(missionId) or 1
    local mission = Config.Missions[missionId]
    if missionActive then 
        TempMessage("~r~Already on a mission!", 1200)
        return 
    end
    
    -- Check mission type
    local isSprintMission = mission.Type == "sprint"
    
    -- Notify server about mission start for police presence check
    TriggerServerEvent("driftmission:missionStart", missionId)
    
    if isSprintMission then
        -- Sprint mission logic
        sprintMission = true
        activeMissionId = missionId
        currentCheckpoint = 0
        driftScores = {}
        driftCombo = 0
        playerInCorrectDirection = true
        showOutOfZone = false
        
        -- Create blips for all checkpoints and finish
        CreateSprintBlips(mission)
        
        -- Set initial status
        SetStatusText("~b~Head to the starting line to begin the sprint.")
        
        -- Start detection threads
        StartSprintDetectionThread()
        if debugEnabled then
            StartDebugThread()
        end
        
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
        StartCountdown(function()
            -- Mission officially starts after countdown
            missionActive = true
            missionTimer = mission.InitialTime or 20
            showDriftUI = true
            
            -- Update flares for first 2 checkpoints
            UpdateActiveFlares(mission)
            
            SetStatusText("")
            TempMessage("~g~Sprint started! Reach the checkpoints before time runs out!", 3000)
            
            -- Sprint timer thread
            Citizen.CreateThread(function()
                while missionActive and missionTimer > 0 do
                    Wait(1000)
                    missionTimer = missionTimer - 1
                end
                if missionActive then
                    -- Time's up!
                    missionActive = false
                    sprintMission = false
                    showDriftUI = false
                    showOutOfZone = false
                    playerInCorrectDirection = true
                    
                    -- Clean up
                    for _, flares in ipairs(flareObjects) do
                        RemoveFlares(flares)
                    end
                    flareObjects = {}
                    RemoveSprintBlips()
                    StopSprintDetectionThread()
                    StopDebugThread()
                    
                    driftScores = {}
                    activeMissionId = nil
                    driftCombo = 0
                    currentCheckpoint = 0
                    TempMessage("~r~Time's up! Mission failed.", 4000)
                end
            end)
        end)
    else
        -- Regular drift mission logic
        sprintMission = false
        ShowDriftZoneBlip(missionId)
        SetStatusText("~b~Head to the drift area. The timer will start when you arrive.")
        
        -- Start necessary threads for mission
        StartDriftDetectionThread()
        if debugEnabled then
            StartDebugThread()
        end
        
        -- Wait until IN the zone (poly or circle)
        while not IsPlayerInDriftZone(mission.Zone, PlayerPedId()) do
            Wait(500)
        end
        missionActive = true
        activeMissionId = missionId
        missionTimer = mission.MissionTime
        driftScores = {}
        driftCombo = 0
        showDriftUI = true
        playerInZone = true
        showOutOfZone = false
        SetStatusText("")
        
        -- Mission timer thread
        Citizen.CreateThread(function()
            while missionActive and missionTimer > 0 do
                Wait(1000)
                missionTimer = missionTimer - 1
            end
            if missionActive then
                missionActive = false
                showDriftUI = false
                showOutOfZone = false
                playerInZone = false
                HideDriftZoneBlip()
                StopDriftDetectionThread()
                StopDebugThread()
                TempMessage("~b~Time's up! Return to the Drift King to submit your score.", 4000)
            end
        end)
    end
end)

RegisterNetEvent("driftmission:turnin", function()
    HideDriftZoneBlip()
    showDriftUI = false
    showOutOfZone = false
    playerInZone = false
    playerInCorrectDirection = true
    
    -- Clean up sprint mission objects
    for _, flares in ipairs(flareObjects) do
        RemoveFlares(flares)
    end
    flareObjects = {}
    RemoveSprintBlips()
    
    StopDriftDetectionThread()
    StopSprintDetectionThread()
    StopDebugThread()
    
    local score = GetTotalScore()
    if not missionActive and score > 0 and activeMissionId then
        local mission = Config.Missions[activeMissionId]
        local reward = math.floor(score * mission.RewardPerScore)
        local missionTypeText = mission.Type == "sprint" and "sprint" or "drift"
        TempMessage(("~b~You turned in your score!\nTotal %s points: ~y~%d\n~g~Cash reward: $%d"):format(missionTypeText, score, reward), 3000)
        TriggerServerEvent("driftmission:reward", activeMissionId, score)
        driftScores = {}
        activeMissionId = nil
        driftCombo = 0
        currentCheckpoint = 0
        sprintMission = false
    else
        TempMessage("~r~No score to turn in!", 1500)
    end
end)