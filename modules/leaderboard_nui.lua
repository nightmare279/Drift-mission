-- Leaderboard NUI Module
local LeaderboardNUI = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local leaderboardOpen = false

function LeaderboardNUI.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
    
    -- Initialize NUI as hidden
    Citizen.CreateThread(function()
        Wait(1000) -- Wait for NUI to load
        SendNUIMessage({
            type = 'hideLeaderboard'
        })
    end)
end false

function LeaderboardNUI.Init(state)
    sharedState = state
    
    -- Initialize NUI as hidden
    Citizen.CreateThread(function()
        Wait(1000) -- Wait for NUI to load
        SendNUIMessage({
            type = 'hideLeaderboard'
        })
    end)
end

function LeaderboardNUI.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

-- NUI Callbacks
RegisterNUICallback('closeLeaderboard', function(data, cb)
    SetNuiFocus(false, false)
    leaderboardOpen = false
    SendNUIMessage({
        type = 'hideLeaderboard'
    })
    cb('ok')
end)

function LeaderboardNUI.OpenLeaderboard()
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
        currentMission = sharedState.activeMissionId or 1
    })
    -- Try to set the NUI background transparent on the client side
    SetNuiFocusKeepInput(false)
end)

function LeaderboardNUI.IsLeaderboardOpen()
    return leaderboardOpen
end

function LeaderboardNUI.Cleanup()
    if leaderboardOpen then
        SetNuiFocus(false, false)
        leaderboardOpen = false
        SendNUIMessage({
            type = 'hideLeaderboard'
        })
    end
end

return LeaderboardNUI
