-- local Config = lib.require and lib.require('config') or require('config')
local playerProgress = {}
local playerBestScore = {}
local driftNpc = nil

local activeMissionId = nil
local missionActive = false
local missionTimer = 0
local driftScores = {}
local driftActive = false
local currentDrift = {score = 0, duration = 0, crashed = false}
local missionDisplayText = ""

local driftZoneBlip = nil
local driftZoneBlip_icon = nil
local driftPolyZones = {}

-- Debug
local debugEnabled = false
local function debug(msg, ...)
    if debugEnabled then print(("[driftmission DEBUG] " .. msg):format(...)) end
end

RegisterCommand("driftdbg", function()
    debugEnabled = not debugEnabled
    print("^2[driftmission]^7 Debugging is now " .. (debugEnabled and "ON" or "OFF"))
end)

-----------------------------------
-- Utility
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

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if missionDisplayText ~= "" then
            DrawMissionText(missionDisplayText)
        end
    end
end)

function SetStatusText(txt)
    missionDisplayText = txt or ""
end

function TempMessage(txt, time)
    SetStatusText(txt)
    Citizen.CreateThread(function()
        Wait(time or 1200)
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

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if Config.DebugZone and activeMissionId and Config.Missions[activeMissionId] then
            local zone = Config.Missions[activeMissionId].Zone
            if zone then DrawZoneDebug(zone) end
        else
            Citizen.Wait(300)
        end
    end
end)

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

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateDriftKingZone()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if driftKingZone then driftKingZone:remove() driftKingZone = nil end
        RemoveDriftNpc()
    end
end)

-----------------------------------
-- Dialog logic (same as before)
-----------------------------------

local Dialog = {}

function GetTotalScore()
    local total = 0
    for i, v in ipairs(driftScores) do
        total = total + v
    end
    return math.floor(total)
end

function RefreshDriftMissionDialog()
    local missionBtns = {}
    local unlockedCount = 0
    for missionId, mission in pairs(Config.Missions) do
        missionId = tonumber(missionId)
        if mission.UnlockScore == 0 or playerProgress[missionId] then
            unlockedCount = unlockedCount + 1
            table.insert(missionBtns, {
                label = mission.Name or ('Drift Mission '..missionId),
                nextDialog = nil,
                close = true,
                onSelect = function()
                    TriggerEvent("driftmission:start", missionId)
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
            label = 'Nothing',
            close = true,
        },
    }
    if not missionActive and activeMissionId and GetTotalScore() > 0 then
        table.insert(mainBtns, 2, {
            label = 'Turn In Score',
            close = true,
            onSelect = function()
                TriggerEvent("driftmission:turnin")
            end,
        })
    end
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

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('driftmission:requestUnlocks')
end)

Citizen.CreateThread(function()
    Wait(1200)
    CreateDriftKingZone()
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

RegisterNetEvent("driftmission:start", function(missionId)
    missionId = tonumber(missionId) or 1
    local mission = Config.Missions[missionId]
    if missionActive then 
        TempMessage("~r~Already on a mission!", 1200)
        return 
    end
    ShowDriftZoneBlip(missionId)
    SetStatusText("~b~Head to the drift area. The timer will start when you arrive.")
    -- Wait until IN the zone (poly or circle)
    while not IsPlayerInDriftZone(mission.Zone, PlayerPedId()) do
        Wait(500)
    end
    missionActive = true
    activeMissionId = missionId
    missionTimer = mission.MissionTime
    driftScores = {}
    SetStatusText("~g~Drift mission started! ~w~Drift as much as you can in the zone!")
    Citizen.CreateThread(function()
        while missionActive and missionTimer > 0 do
            SetStatusText(("~b~DRIFT!~w~ Time: ~b~%ds~w~ | Score: ~y~%d"):format(missionTimer, GetTotalScore()))
            Wait(1000)
            missionTimer = missionTimer - 1
            if not IsPlayerInDriftZone(mission.Zone, PlayerPedId()) then
                SetStatusText("~r~You left the drift zone! Get back in!")
                Wait(1200)
            end
        end
        missionActive = false
        HideDriftZoneBlip()
        SetStatusText("~b~Time's up! Return to the Drift King to submit your score.")
        Wait(4000)
        SetStatusText("")
    end)
end)

Citizen.CreateThread(function()
    while true do
        Wait(10)
        if missionActive and missionTimer > 0 and activeMissionId then
            local mission = Config.Missions[activeMissionId]
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                if driftActive then
                    if currentDrift.score > 0 and not currentDrift.crashed then
                        table.insert(driftScores, currentDrift.score)
                    end
                    driftActive = false
                    currentDrift = {score = 0, duration = 0, crashed = false}
                end
                goto continue
            end
            local veh = GetVehiclePedIsIn(ped, false)
            local speed = GetEntitySpeed(veh) * 2.23694
            local angle = 0
            do
                local heading = GetEntityHeading(veh)
                local vel = GetEntityVelocity(veh)
                local v = math.sqrt(vel.x^2 + vel.y^2)
                if v > 1.5 then
                    local carDir = math.rad(heading + 90)
                    local velDir = math.atan2(vel.y, vel.x)
                    angle = math.abs((math.deg(velDir - carDir) + 180) % 360 - 180)
                end
            end
            local inZone = IsPlayerInDriftZone(mission.Zone, ped)
            local drifting = (angle > 10 and speed > 20 and inZone)
            if drifting then
                if not driftActive then
                    driftActive = true
                    currentDrift = {score = 0, duration = 0, crashed = false}
                end
                currentDrift.duration = currentDrift.duration + 0.01
                local gear = GetVehicleCurrentGear(veh)
                local reverseMultiplier = 1.0
                if gear == 0 then
                    reverseMultiplier = 0.25
                end
                currentDrift.score = currentDrift.score + (angle * speed * 0.002 * reverseMultiplier)
                if HasEntityCollidedWithAnything(veh) or (IsEntityInAir(veh) and not IsVehicleOnAllWheels(veh)) then
                    currentDrift.crashed = true
                    currentDrift.score = 0
                end
            else
                if driftActive then
                    if currentDrift.score > 0 and not currentDrift.crashed then
                        table.insert(driftScores, currentDrift.score)
                    end
                    driftActive = false
                    currentDrift = {score = 0, duration = 0, crashed = false}
                end
            end
        end
        ::continue::
    end
end)

RegisterNetEvent("driftmission:turnin", function()
    HideDriftZoneBlip()
    local score = GetTotalScore()
    if not missionActive and score > 0 and activeMissionId then
        local mission = Config.Missions[activeMissionId]
        local reward = math.floor(score * mission.RewardPerScore)
        TempMessage(("~b~You turned in your score!\nTotal drift points: ~y~%d\n~g~Cash reward: $%d"):format(score, reward), 3000)
        TriggerServerEvent("driftmission:reward", activeMissionId, score)
        driftScores = {}
        activeMissionId = nil
    else
        TempMessage("~r~No score to turn in!", 1500)
    end
end)
