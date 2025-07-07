local QBCore = exports['qb-core']:GetCoreObject()

local unlockFile = "drift_mission_unlocks.json"
local activeMissions = {} -- Track active missions for police presence checking

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
    -- Save the timestamp when this score was achieved
    data[citizenid]["time_" .. tostring(missionId)] = os.time()
    SaveUnlockData(data)
end

-- Get player name by citizenid (only SQL we need)
function GetPlayerNameByCitizenId(citizenid)
    local result = exports.oxmysql:executeSync('SELECT JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.firstname")) as firstname, JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.lastname")) as lastname FROM players WHERE citizenid = ?', {citizenid})
    if result and result[1] then
        return result[1].firstname .. " " .. result[1].lastname
    end
    return "Unknown Player"
end

-- Generate leaderboard data from JSON file (async wrapper)
function GenerateLeaderboardData()
    -- Get all data from the JSON file
    local unlockData = GetUnlockData()
    local leaderboards = {}
    
    -- Initialize leaderboards for each mission
    for missionId, mission in pairs(Config.Missions) do
        leaderboards[missionId] = {}
    end
    
    -- Process each player's data from the JSON file
    for citizenid, playerData in pairs(unlockData) do
        local playerName = GetPlayerNameByCitizenId(citizenid)
        
        -- Look for score entries in the player's data
        for key, value in pairs(playerData) do
            if string.find(key, "score_") then
                local missionId = tonumber(string.sub(key, 7))
                if missionId and leaderboards[missionId] and value > 0 then
                    -- Look for corresponding timestamp
                    local timeKey = "time_" .. tostring(missionId)
                    local timestamp = playerData[timeKey]
                    local completionTime = "Unknown"
                    
                    if timestamp then
                        -- Convert timestamp to readable date
                        completionTime = os.date("%m/%d/%Y", timestamp)
                    end
                    
                    table.insert(leaderboards[missionId], {
                        playerName = playerName,
                        citizenid = citizenid,
                        score = value,
                        completionTime = completionTime
                    })
                end
            end
        end
    end
    
    -- Sort each mission leaderboard by score (highest first)
    for missionId, leaderboard in pairs(leaderboards) do
        table.sort(leaderboard, function(a, b)
            return a.score > b.score
        end)
        
        -- Limit to top 50 for performance
        if #leaderboard > 50 then
            for i = 51, #leaderboard do
                leaderboard[i] = nil
            end
        end
    end
    
    return leaderboards
end

-- Check if police are online
function IsPoliceOnline()
    local units = exports["lb-tablet"]:GetUnits('police')
    return units and #units > 0
end

-- Create police dispatch
function CreatePoliceDispatch(coords, vehicleColor, dispatchType)
    local dispatch = {
        priority = 'medium',
        code = '10-11',
        title = "Reckless Driving",
        description = "Reported reckless driving or stunting",
        location = {
            label = "Incident Location",
            coords = {x = coords.x, y = coords.y}
        },
        time = 300, -- 5 minutes
        job = 'police',
        sound = 'notification.mp3',
        fields = {
            {
                icon = 'fa-car',
                label = 'Vehicle Color',
                value = vehicleColor or 'Unknown'
            }
        },
        blip = {
            sprite = 161,
            color = 1,
            size = 0.8,
            shortRange = false,
            label = 'Reckless Driving'
        }
    }
    
    exports["lb-tablet"]:AddDispatch(dispatch)
    print(string.format("^3[DriftMission]^7 Police dispatch created: Reckless Driving at %s", coords))
end

-- Get vehicle primary color name
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

-- Send unlocks to player (always fresh)
RegisterNetEvent("driftmission:requestUnlocks", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    local unlocks = GetPlayerUnlocks(citizenid)
    TriggerClientEvent("driftmission:receiveUnlocks", src, unlocks)
end)

-- Handle leaderboard request
RegisterNetEvent("driftmission:requestLeaderboard", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    
    local leaderboardData = GenerateLeaderboardData()
    local missions = {}
    
    -- Send mission info for tabs
    for missionId, mission in pairs(Config.Missions) do
        missions[missionId] = {
            Name = mission.Name or ("Mission " .. missionId),
            Description = mission.Description or "No description available"
        }
    end
    
    TriggerClientEvent("driftmission:receiveLeaderboard", src, leaderboardData, missions)
end)

-- Handle mission start with police presence check
RegisterNetEvent("driftmission:missionStart", function(missionId)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    missionId = tonumber(missionId)
    local mission = Config.Missions[missionId]
    if not mission then return end
    
    -- Check if police are online and mission has dispatch chances
    local policeOnline = IsPoliceOnline()
    local hasPoliceChances = (mission.PoliceOnCrash and mission.PoliceOnCrash > 0) or 
                            (mission.PoliceOnSpinout and mission.PoliceOnSpinout > 0)
    
    -- Store mission info for police presence bonus
    activeMissions[citizenid] = {
        missionId = missionId,
        policeBonus = policeOnline and hasPoliceChances
    }
    
    -- Notify client about police presence bonus
    if policeOnline and hasPoliceChances then
        TriggerClientEvent('QBCore:Notify', src, "Police are patrolling the area! Payouts doubled for increased risk!", "primary")
    end
end)

-- Handle police dispatch triggers
RegisterNetEvent("driftmission:policeDispatch", function(dispatchType, coords, vehicleColor)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Check if player has active mission
    local missionData = activeMissions[citizenid]
    if not missionData then return end
    
    local mission = Config.Missions[missionData.missionId]
    if not mission then return end
    
    -- Check dispatch chance
    local dispatchChance = 0
    if dispatchType == "crash" and mission.PoliceOnCrash then
        dispatchChance = mission.PoliceOnCrash
    elseif dispatchType == "spinout" and mission.PoliceOnSpinout then
        dispatchChance = mission.PoliceOnSpinout
    end
    
    -- Roll for dispatch
    if dispatchChance > 0 and math.random() <= dispatchChance then
        CreatePoliceDispatch(coords, vehicleColor, dispatchType)
        TriggerClientEvent('QBCore:Notify', src, "Police have been alerted to your activities!", "error")
    end
end)

-- Check if player achieved #1 position and handle bonuses (simpler logic)
function CheckLeaderboardPosition(citizenid, missionId, previousBestScore)
    local leaderboards = GenerateLeaderboardData()
    local missionLeaderboard = leaderboards[missionId] or {}
    
    if #missionLeaderboard == 0 then
        return "not_first"
    end
    
    -- Sort to get current rankings
    table.sort(missionLeaderboard, function(a, b)
        return a.score > b.score
    end)
    
    -- Check if this player is now #1
    if #missionLeaderboard > 0 and missionLeaderboard[1].citizenid == citizenid then
        -- They are #1 now. Check if they had the previous best score.
        if previousBestScore == 0 then
            -- First time scoring on this mission
            return "first_place_new"
        else
            -- They had a previous score. Check if anyone else had a higher score before.
            -- If there's only 1 entry (theirs), they were already #1
            if #missionLeaderboard == 1 then
                return "first_place_improved" -- Only their score exists, so they were already #1
            else
                -- Check if the #2 score belongs to someone else and is lower than their previous best
                local secondPlace = missionLeaderboard[2]
                if secondPlace and secondPlace.citizenid ~= citizenid and secondPlace.score < previousBestScore then
                    return "first_place_improved" -- They were already #1, just improved their score
                else
                    return "first_place_new" -- They overtook someone
                end
            end
        end
    end
    
    return "not_first"
end
-- Fixed unlock progression - only unlock the next sequential mission
function CheckAndUnlockNextMission(citizenid, currentMissionId, score)
    local nextMissionId = currentMissionId + 1
    local nextMission = Config.Missions[nextMissionId]
    
    -- Only unlock if:
    -- 1. Next mission exists
    -- 2. Player doesn't already have it unlocked
    -- 3. Player's score meets the requirement
    if nextMission then
        local playerUnlocks = GetPlayerUnlocks(citizenid)
        local alreadyUnlocked = playerUnlocks[tostring(nextMissionId)]
        
        if not alreadyUnlocked and score >= (nextMission.UnlockScore or 999999) then
            SetPlayerUnlock(citizenid, nextMissionId)
            return nextMissionId
        end
    end
    
    return nil
end

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
    
    -- Check for police presence bonus
    local missionData = activeMissions[citizenid]
    local policeBonus = 1.0
    if missionData and missionData.policeBonus then
        policeBonus = 2.0
        TriggerClientEvent('QBCore:Notify', src, "Police presence bonus applied! (2x payout)", "success")
    end
    
    local reward = math.floor(score * payoutScale * policeBonus)
    if reward > 0 then
        xPlayer.Functions.AddMoney('cash', reward, 'drift-mission-reward')
        local bonusText = policeBonus > 1.0 and " (Police Bonus!)" or ""
        TriggerClientEvent('QBCore:Notify', src, ("You received $%d cash for drifting!%s"):format(reward, bonusText), "success")
    end

    -- Save best score if improved and check leaderboard position
    local prevBest = GetPlayerBestScore(citizenid, missionId)
    local leaderboardResult = nil
    
    if score > prevBest then
        -- Check leaderboard position BEFORE updating (pass previous best score)
        leaderboardResult = CheckLeaderboardPosition(citizenid, missionId, prevBest)
        
        -- Now save the new score
        SetPlayerBestScore(citizenid, missionId, score)
    end

    -- Handle unlock progression
    local unlockedMissionId = CheckAndUnlockNextMission(citizenid, missionId, score)
    if unlockedMissionId then
        SetTimeout(3000, function()
            TriggerClientEvent('driftmission:unlocked', src, unlockedMissionId)
        end)
    end
    
    -- Handle leaderboard bonuses and messages (after unlock message)
    if leaderboardResult then
        SetTimeout(unlockedMissionId and 6000 or 2000, function() -- 6s if unlock message, 2s otherwise
            if leaderboardResult == "first_place_new" then
                -- New #1 position - give bonus
                xPlayer.Functions.AddMoney('cash', 5000, 'drift-leaderboard-bonus')
                TriggerClientEvent('driftmission:showLeaderboardMessage', src, "new_record", 5000)
            elseif leaderboardResult == "first_place_improved" then
                -- Improved their own record
                TriggerClientEvent('driftmission:showLeaderboardMessage', src, "improved_record")
            end
        end)
    end
    
    -- Clean up mission data
    activeMissions[citizenid] = nil
end)

-- Clean up on player disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if xPlayer then
        local citizenid = xPlayer.PlayerData.citizenid
        activeMissions[citizenid] = nil
    end
end)

-- Optional: Log on start
print("^2[DriftMission]^7 server loaded and ready with police dispatch integration and leaderboard system.")