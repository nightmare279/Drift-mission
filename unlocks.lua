local UnlocksFile = "drift_mission_unlocks.json"
Unlocks = {}

local function SaveUnlocks()
    SaveResourceFile(GetCurrentResourceName(), UnlocksFile, json.encode(Unlocks, { indent = true }), -1)
end

local function LoadUnlocks()
    local data = LoadResourceFile(GetCurrentResourceName(), UnlocksFile)
    Unlocks = data and json.decode(data) or {}
end

LoadUnlocks()

function GetPlayerUnlocks(citizenid)
    if not citizenid then return {} end
    if not Unlocks[citizenid] then Unlocks[citizenid] = {} end
    return Unlocks[citizenid]
end

function SetPlayerUnlock(citizenid, missionId)
    if not citizenid then return end
    if not Unlocks[citizenid] then Unlocks[citizenid] = {} end
    Unlocks[citizenid][tostring(missionId)] = true
    SaveUnlocks()
end

function SetPlayerBestScore(citizenid, missionId, score)
    if not citizenid then return end
    if not Unlocks[citizenid] then Unlocks[citizenid] = {} end
    Unlocks[citizenid]["score_" .. tostring(missionId)] = score
    SaveUnlocks()
end

function GetPlayerBestScore(citizenid, missionId)
    if not citizenid then return 0 end
    if not Unlocks[citizenid] then return 0 end
    return Unlocks[citizenid]["score_" .. tostring(missionId)] or 0
end
