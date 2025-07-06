local QBCore = exports['qb-core']:GetCoreObject()

local unlockFile = "drift_mission_unlocks.json"

-- Utility: Load unlocks from file
function GetUnlockData()
    local file = LoadResourceFile(GetCurrentResourceName(), unlockFile)
    return file and json.decode(file) or {}
end

-- Utility: Save unlocks to file
function SaveUnlockData(data)
    SaveResourceFile(GetCurrentResourceName(), unlockFile, json.encode(data, {indent = true}), -1)
end

-- Get a player's unlocks
function GetPlayerUnlocks(citizenid)
    local data = GetUnlockData()
    return data[citizenid] or {}
end

-- Set a player's unlock for a mission
function SetPlayerUnlock(citizenid, missionId)
    local data = GetUnlockData()
    data[citizenid] = data[citizenid] or {}
    data[citizenid][tostring(missionId)] = true
    SaveUnlockData(data)
end

-- Get a player's best score for a mission
function GetPlayerBestScore(citizenid, missionId)
    local data = GetUnlockData()
    data[citizenid] = data[citizenid] or {}
    return data[citizenid]["score_" .. tostring(missionId)] or 0
end

-- Set a player's best score for a mission
function SetPlayerBestScore(citizenid, missionId, score)
    local data = GetUnlockData()
    data[citizenid] = data[citizenid] or {}
    data[citizenid]["score_" .. tostring(missionId)] = score
    SaveUnlockData(data)
end

-- Send unlocks to player (always fresh)
RegisterNetEvent("driftmission:requestUnlocks", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    local unlocks = GetPlayerUnlocks(citizenid)
    TriggerClientEvent("driftmission:receiveUnlocks", src, unlocks)
end)

-- Reward logic, with payout and unlock progression
RegisterNetEvent("driftmission:reward", function(missionId, score)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid

    -- Load Config from shared file
    local Config = Config or {}
    if not Config.Missions then
        -- If you want, you can load config here or require it if needed
        print("[DriftMission] Config.Missions missing. Define Config.Missions in a shared file!")
        return
    end

    missionId = tonumber(missionId)
    score = tonumber(score) or 0
    local mission = Config.Missions[missionId]
    if not mission then return end

    local payoutScale = mission.RewardPerScore or 8
    local reward = math.floor(score * payoutScale)
    if reward > 0 then
        xPlayer.Functions.AddMoney('cash', reward, 'drift-mission-reward')
        TriggerClientEvent('QBCore:Notify', src, ("You received $%d cash for drifting!"):format(reward), "success")
    end

    -- Save best score if improved
    local prevBest = GetPlayerBestScore(citizenid, missionId)
    if score > prevBest then
        SetPlayerBestScore(citizenid, missionId, score)
    end

    -- Unlock next mission if applicable
    local nextId = missionId + 1
    if Config.Missions[nextId] and score >= (Config.Missions[nextId].UnlockScore or 999999) then
        SetPlayerUnlock(citizenid, nextId)
        SetTimeout(3000, function()
            TriggerClientEvent('driftmission:unlocked', src, nextId)
        end)
    end
end)

-- Optional: Log on start
print("^2[DriftMission]^7 server loaded and ready.")
