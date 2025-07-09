-- Main client.lua - Entry point and core initialization
local QBCore = exports['qb-core']:GetCoreObject()

-- Global state variables
local playerProgress = {}
local playerBestScore = {}
local driftNpc = nil
local activeMissionId = nil
local missionActive = false
local missionTimer = 0
local driftScores = {}
local missionDisplayText = ""

-- Import modules
local DriftDetection = require('client/modules/drift_detection')
local SprintMission = require('client/modules/sprint_mission')
local UIManager = require('client/modules/ui_manager')
local NPCManager = require('client/modules/npc_manager')
local LeaderboardNUI = require('client/modules/leaderboard_nui')
local MissionFlow = require('client/modules/mission_flow')
local DialogManager = require('client/modules/dialog_manager')

-- Global access functions for modules to call each other
_G.DriftDetection = DriftDetection
_G.SprintMission = SprintMission  
_G.UIManager = UIManager
_G.NPCManager = NPCManager
_G.LeaderboardNUI = LeaderboardNUI
_G.MissionFlow = MissionFlow
_G.DialogManager = DialogManager
    -- Pass shared state to modules
    local sharedState = {
        playerProgress = playerProgress,
        playerBestScore = playerBestScore,
        driftNpc = driftNpc,
        activeMissionId = activeMissionId,
        missionActive = missionActive,
        missionTimer = missionTimer,
        driftScores = driftScores,
        missionDisplayText = missionDisplayText
    }
    
    DriftDetection.Init(sharedState)
    SprintMission.Init(sharedState)
    UIManager.Init(sharedState)
    NPCManager.Init(sharedState)
    LeaderboardNUI.Init(sharedState)
    MissionFlow.Init(sharedState)
    DialogManager.Init(sharedState)
end

-- Resource lifecycle
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        InitializeModules()
        NPCManager.CreateDriftKingZone()
        
        -- Request unlocks for already loaded players
        if LocalPlayer.state.isLoggedIn then
            TriggerServerEvent('driftmission:requestUnlocks')
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        NPCManager.Cleanup()
        UIManager.Cleanup()
        DriftDetection.Cleanup()
        SprintMission.Cleanup()
        LeaderboardNUI.Cleanup()
    end
end)

-- Player loading events
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('driftmission:requestUnlocks')
    
    -- Ensure drift zone is created for newly loaded players
    Citizen.SetTimeout(2000, function()
        NPCManager.CreateDriftKingZone()
    end)
end)

-- Handle player spawning after resource is already running
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    Citizen.SetTimeout(5000, function() -- Give some time for everything to load
        NPCManager.EnsureDriftKingZone()
        TriggerServerEvent('driftmission:requestUnlocks')
    end)
end)

-- Global state update functions
function UpdateSharedState(key, value)
    if key == "playerProgress" then playerProgress = value
    elseif key == "playerBestScore" then playerBestScore = value
    elseif key == "driftNpc" then driftNpc = value
    elseif key == "activeMissionId" then activeMissionId = value
    elseif key == "missionActive" then missionActive = value
    elseif key == "missionTimer" then missionTimer = value
    elseif key == "driftScores" then driftScores = value
    elseif key == "missionDisplayText" then missionDisplayText = value
    end
    
    -- Notify all modules of state change
    for _, module in pairs(Modules) do
        if module.UpdateState then
            module.UpdateState(key, value)
        end
    end
end

-- Export functions for other modules to access shared state
function GetSharedState(key)
    if key == "playerProgress" then return playerProgress
    elseif key == "playerBestScore" then return playerBestScore
    elseif key == "driftNpc" then return driftNpc
    elseif key == "activeMissionId" then return activeMissionId
    elseif key == "missionActive" then return missionActive
    elseif key == "missionTimer" then return missionTimer
    elseif key == "driftScores" then return driftScores
    elseif key == "missionDisplayText" then return missionDisplayText
    end
end

-- Debug command
local debugEnabled = false
RegisterCommand("driftdbg", function()
    debugEnabled = not debugEnabled
    print("^2[driftmission]^7 Debugging is now " .. (debugEnabled and "ON" or "OFF"))
    
    for _, module in pairs(Modules) do
        if module.SetDebugMode then
            module.SetDebugMode(debugEnabled)
        end
    end
end)

-- Event handlers for unlocks
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
    UpdateSharedState("playerProgress", playerProgress)
    UpdateSharedState("playerBestScore", playerBestScore)
    if Modules.NPCManager and Modules.NPCManager.RefreshNPC then
        Modules.NPCManager.RefreshNPC()
    end
end)

RegisterNetEvent("driftmission:unlocked", function(missionId)
    missionId = tonumber(missionId)
    playerProgress[missionId] = true
    UpdateSharedState("playerProgress", playerProgress)
    if Modules.UIManager and Modules.UIManager.TempMessage then
        Modules.UIManager.TempMessage("~g~New mission unlocked!", 3500)
    end
    if Modules.NPCManager and Modules.NPCManager.RefreshNPC then
        Modules.NPCManager.RefreshNPC()
    end
end)

-- Mission event handlers
RegisterNetEvent("driftmission:start", function(missionId)
    if Modules.MissionFlow and Modules.MissionFlow.StartMission then
        Modules.MissionFlow.StartMission(missionId)
    end
end)

RegisterNetEvent("driftmission:turnin", function()
    if Modules.MissionFlow and Modules.MissionFlow.TurnInMission then
        Modules.MissionFlow.TurnInMission()
    end
end)

-- Leaderboard message events
RegisterNetEvent("driftmission:showLeaderboardMessage", function(messageType, bonusAmount)
    if not Modules.UIManager or not Modules.UIManager.ShowLeaderboardMessage then return end
    
    if messageType == "new_record" then
        Modules.UIManager.ShowLeaderboardMessage("~y~🏆 NEW RECORD!~w~\n~g~You're now #1!~w~\n~g~Bonus: $" .. (bonusAmount or 5000) .. "!", 18000)
    elseif messageType == "improved_record" then
        Modules.UIManager.ShowLeaderboardMessage("~y~🏁 You beat your previous record!~w~\n~b~You're still #1!", 10000)
    end
end)
