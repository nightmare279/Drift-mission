-- Getters for UI
function DriftDetection.GetDriftData()
    return {
        driftActive = driftActive,
        currentDrift = currentDrift,
        currentAngle = currentAngle,
        currentSpeed = currentSpeed,
        driftCombo = driftCombo,
        playerInZone = playerInZone,
        showOutOfZone = showOutOfZone,
        showDriftResult = showDriftResult,
        driftResultScore = driftResultScore,
        driftResultType = driftResultType,
        driftResultEndTime = driftResultEndTime,
        screenEffectEndTime = screenEffectEndTime
    }
end

function DriftDetection.ClearDriftResult()
    showDriftResult = false
end

-- Sprint drift processing (called from sprint mission)
function DriftDetection.ProcessSprintDrift(drifting, currentAngle, currentSpeed, veh)
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
        
        -- Only accumulate score if not crashed or spun out - SAME AS DRIFT ZONES
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
                table.insert(sharedState.driftScores, finalScore)
            end
            DriftDetection.ShowDriftResult(finalScore, "spinout")
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
            
            if-- Drift Detection Module
local DriftDetection = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local updateSharedState = nil -- Function to update shared state
local driftActive = false
local currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
local currentAngle = 0
local lastAngle = 0
local currentSpeed = 0
local driftCombo = 0
local lastDriftTime = 0
local comboResetTime = 3000 -- 3 seconds between drifts to maintain combo

-- Zone tracking
local playerInZone = false
local showOutOfZone = false

-- Thread control
local driftDetectionThreadActive = false
local debugThreadActive = false
local debugEnabled = false

-- Police dispatch tracking
local lastCrashDispatch = 0
local lastSpinoutDispatch = 0
local dispatchCooldown = 30000 -- 30 seconds between dispatches

-- Drift result display
local showDriftResult = false
local driftResultScore = 0
local driftResultType = "good" -- "good", "crashed", "spinout", "out_of_zone"
local driftResultEndTime = 0
local screenEffectEndTime = 0

function DriftDetection.Init(state, moduleRegistry, updateStateFn)
    sharedState = state
    modules = moduleRegistry or {}
    updateSharedState = updateStateFn
end

function DriftDetection.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

function DriftDetection.SetDebugMode(enabled)
    debugEnabled = enabled
    if enabled then
        DriftDetection.StartDebugThread()
    else
        DriftDetection.StopDebugThread()
    end
end

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

function DriftDetection.IsPlayerInDriftZone(zone, ped)
    local pos = GetEntityCoords(ped)
    if zone.poly then
        return IsPointInPoly(pos, zone.poly)
    elseif zone.center and zone.radius then
        return #(pos - zone.center) < zone.radius
    end
    return false
end

function DriftDetection.ShowDriftResult(score, resultType)
    driftResultScore = math.floor(score)
    driftResultType = resultType
    showDriftResult = true
    driftResultEndTime = GetGameTimer() + 1000 -- Show for 1 second
    screenEffectEndTime = GetGameTimer() + 1000 -- Screen effect for 1 second
    
    -- Trigger police dispatch for crashes and spinouts
    if resultType == "crashed" or resultType == "spinout" then
        DriftDetection.TriggerPoliceDispatch(resultType)
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

function DriftDetection.TriggerPoliceDispatch(dispatchType)
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
    local colorName = DriftDetection.GetVehicleColorName(primaryColor)
    
    -- Send dispatch to server
    TriggerServerEvent("driftmission:policeDispatch", dispatchType, coords, colorName)
    
    -- Update cooldown
    if dispatchType == "crash" then
        lastCrashDispatch = currentTime
    elseif dispatchType == "spinout" then
        lastSpinoutDispatch = currentTime
    end
end

function DriftDetection.GetVehicleColorName(colorIndex)
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

-- Drift Detection Thread
function DriftDetection.StartDriftDetectionThread()
    if driftDetectionThreadActive then return end
    driftDetectionThreadActive = true
    
    Citizen.CreateThread(function()
        while driftDetectionThreadActive do
            Wait(10)
            if sharedState.missionActive and sharedState.missionTimer > 0 and sharedState.activeMissionId and not (modules.SprintMission and modules.SprintMission.IsSprintMission()) then
                local mission = Config.Missions[sharedState.activeMissionId]
                local ped = PlayerPedId()
                
                -- Check if player is in zone
                local inZone = DriftDetection.IsPlayerInDriftZone(mission.Zone, ped)
                
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
                            table.insert(sharedState.driftScores, currentDrift.score)
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
                
                local drifting = (currentAngle > 10 and currentSpeed > 15 and inZone)
                
                -- Check combo timeout
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
                    
                    -- Check for spinout
                    if currentAngle >= 135 and not currentDrift.spinout then
                        currentDrift.spinout = true
                        currentDrift.score = currentDrift.score * 0.3
                    end
                    
                    -- Accumulate score if not crashed or spun out
                    if not currentDrift.crashed and not currentDrift.spinout then
                        local gear = GetVehicleCurrentGear(veh)
                        local reverseMultiplier = gear == 0 and 0.25 or 1.0
                        
                        -- Enhanced scoring system
                        local angleMultiplier = 1.0
                        if currentAngle > 45 then angleMultiplier = 1.5 end
                        if currentAngle > 90 then angleMultiplier = 2.0 end
                        
                        local speedMultiplier = math.min(currentSpeed / 60, 2.0)
                        local comboMultiplier = 1.0 + (driftCombo * 0.1)
                        
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
                            table.insert(sharedState.driftScores, finalScore)
                        end
                        DriftDetection.ShowDriftResult(finalScore, "spinout")
                        driftCombo = 0
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
                                table.insert(sharedState.driftScores, finalScore)
                                driftCombo = driftCombo + 1
                                lastDriftTime = currentTime
                            else
                                driftCombo = 0
                            end
                        end
                        
                        DriftDetection.ShowDriftResult(finalScore, resultType)
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
                Citizen.Wait(500)
            end
            ::continue::
        end
    end)
end

function DriftDetection.StopDriftDetectionThread()
    driftDetectionThreadActive = false
end

-- Debug zone drawing
function DriftDetection.DrawZoneDebug(zone)
    if zone.poly then
        local color = {60, 200, 255, 150}
        for i = 1, #zone.poly do
            local pt1 = zone.poly[i]
            local pt2 = zone.poly[(i % #zone.poly) + 1]
            DrawLine(pt1.x, pt1.y, pt1.z or 32.0, pt2.x, pt2.y, pt2.z or 32.0, color[1], color[2], color[3], color[4])
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

-- Debug Thread
function DriftDetection.StartDebugThread()
    if debugThreadActive then return end
    debugThreadActive = true
    
    Citizen.CreateThread(function()
        while debugThreadActive do
            Citizen.Wait(0)
            if debugEnabled and sharedState.activeMissionId and Config.Missions[sharedState.activeMissionId] then
                local mission = Config.Missions[sharedState.activeMissionId]
                if not (modules.SprintMission and modules.SprintMission.IsSprintMission()) and mission.Zone then 
                    DriftDetection.DrawZoneDebug(mission.Zone) 
                else
                    Citizen.Wait(300)
                end
            else
                Citizen.Wait(300)
            end
        end
    end)
end

function DriftDetection.StopDebugThread()
    debugThreadActive = false
end

-- Getters for UI
function DriftDetection.GetDriftData()
    return {
        driftActive = driftActive,
        currentDrift = currentDrift,
        currentAngle = currentAngle,
        currentSpeed = currentSpeed,
        driftCombo = driftCombo,
        playerInZone = playerInZone,
        showOutOfZone = showOutOfZone,
        showDriftResult = showDriftResult,
        driftResultScore = driftResultScore,
        driftResultType = driftResultType,
        driftResultEndTime = driftResultEndTime,
        screenEffectEndTime = screenEffectEndTime
    }
end

            if currentDrift.crashed then
                resultType = "crashed"
                driftCombo = 0
            elseif currentDrift.spinout then
                resultType = "spinout"
                driftCombo = 0
            else
                if finalScore > 0 then
                    table.insert(sharedState.driftScores, finalScore)
                    driftCombo = driftCombo + 1
                    lastDriftTime = currentTime -- Update last successful drift time
                else
                    driftCombo = 0
                end
            end
            
            DriftDetection.ShowDriftResult(finalScore, resultType)
            driftActive = false
            currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
        end
    end
end

function DriftDetection.Cleanup()
    DriftDetection.StopDriftDetectionThread()
    DriftDetection.StopDebugThread()
    
    -- Reset state
    driftActive = false
    currentDrift = {score = 0, duration = 0, crashed = false, spinout = false}
    currentAngle = 0
    currentSpeed = 0
    driftCombo = 0
    playerInZone = false
    showOutOfZone = false
    showDriftResult = false
end

return DriftDetection
