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

-- Debug Thread Control Functions
function StartDebugThread()
    if debugThreadActive then return end
    debugThreadActive = true
    
    Citizen.CreateThread(function()
        while debugThreadActive do
            Citizen.Wait(0)
            if Config.DebugZone and activeMissionId and Config.Missions[activeMissionId] then
                local zone = Config.Missions[activeMissionId].Zone
                if zone then 
                    DrawZoneDebug(zone) 
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
                    local detailText = string.format(
                        "%s\n\nDetails:\nTime Limit: %d seconds\nReward Rate: $%.2f per point\nBest Score: %d points\n\n%s",
                        mission.Name or "Drift Mission",
                        mission.MissionTime or 60,
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
                    mission.Name or ('Drift Mission '..missionId), 
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
        text = "Choose your drift mission:",
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
        showDriftUI = false
        showOutOfZone = false
        playerInZone = false
        HideDriftZoneBlip()
        StopDriftDetectionThread()
        StopDebugThread()
        driftScores = {}
        activeMissionId = nil
        driftCombo = 0
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
    TempMessage("~g~New drift mission unlocked!", 3500)
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
            if missionActive and missionTimer > 0 and activeMissionId then
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
    
    -- Notify server about mission start for police presence check
    TriggerServerEvent("driftmission:missionStart", missionId)
    
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
end)

RegisterNetEvent("driftmission:turnin", function()
    HideDriftZoneBlip()
    showDriftUI = false
    showOutOfZone = false
    playerInZone = false
    StopDriftDetectionThread()
    StopDebugThread()
    local score = GetTotalScore()
    if not missionActive and score > 0 and activeMissionId then
        local mission = Config.Missions[activeMissionId]
        local reward = math.floor(score * mission.RewardPerScore)
        TempMessage(("~b~You turned in your score!\nTotal drift points: ~y~%d\n~g~Cash reward: $%d"):format(score, reward), 3000)
        TriggerServerEvent("driftmission:reward", activeMissionId, score)
        driftScores = {}
        activeMissionId = nil
        driftCombo = 0
    else
        TempMessage("~r~No score to turn in!", 1500)
    end
end)