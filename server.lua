local QBCore = exports['qb-core']:GetCoreObject()

local unlockFile = "drift_mission_unlocks.json"
local activeMissions = {} -- Track active missions for police presence checking
local activeRentals = {} -- Track active rentals

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

-- FIXED: Check if player achieved #1 position and handle bonuses
function CheckLeaderboardPosition(citizenid, missionId, newScore, previousBestScore)
    -- Generate fresh leaderboard data BEFORE updating the score
    local currentLeaderboards = GenerateLeaderboardData()
    local missionLeaderboard = currentLeaderboards[missionId] or {}
    
    -- Get the current #1 player (before this score update)
    local currentFirstPlace = nil
    if #missionLeaderboard > 0 then
        -- Sort to ensure we have the correct order
        table.sort(missionLeaderboard, function(a, b)
            return a.score > b.score
        end)
        currentFirstPlace = missionLeaderboard[1]
    end
    
    -- Check different scenarios
    if not currentFirstPlace then
        -- No one has scored on this mission yet, so this player gets #1
        return "first_place_new"
    elseif currentFirstPlace.citizenid == citizenid then
        -- Player was already #1, just improving their score
        return "first_place_improved"
    elseif newScore > currentFirstPlace.score then
        -- Player is overtaking someone else for #1
        return "first_place_new"
    else
        -- Player is not #1
        return "not_first"
    end
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

-- FIXED: Reward logic, with payout and unlock progression
RegisterNetEvent("driftmission:reward", function(missionId, score)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid

    -- Load Config from shared file
    local Config = Config or {}
    if not Config.Missions then
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

    -- Check leaderboard position BEFORE updating the score
    local prevBest = GetPlayerBestScore(citizenid, missionId)
    local leaderboardResult = nil
    
    if score > prevBest then
        -- Check leaderboard position BEFORE updating the score
        leaderboardResult = CheckLeaderboardPosition(citizenid, missionId, score, prevBest)
        
        -- Now save the new score (this updates the leaderboard)
        SetPlayerBestScore(citizenid, missionId, score)
        
        print(string.format("^3[DriftMission DEBUG]^7 Player %s scored %d (prev: %d) on mission %d. Result: %s", 
            citizenid, score, prevBest, missionId, leaderboardResult or "none"))
    end

    -- Handle unlock progression
    local unlockedMissionId = CheckAndUnlockNextMission(citizenid, missionId, score)
    if unlockedMissionId then
        SetTimeout(3000, function()
            TriggerClientEvent('driftmission:unlocked', src, unlockedMissionId)
        end)
    end
    
    -- FIXED: Handle leaderboard bonuses and messages
    if leaderboardResult then
        SetTimeout(unlockedMissionId and 6000 or 2000, function() -- 6s if unlock message, 2s otherwise
            if leaderboardResult == "first_place_new" then
                -- New #1 position - give bonus
                local bonusAmount = 5000
                xPlayer.Functions.AddMoney('cash', bonusAmount, 'drift-leaderboard-bonus')
                print(string.format("^2[DriftMission]^7 Awarded $%d leaderboard bonus to %s for new #1 position", bonusAmount, citizenid))
                TriggerClientEvent('driftmission:showLeaderboardMessage', src, "new_record", bonusAmount)
            elseif leaderboardResult == "first_place_improved" then
                -- Improved their own record
                print(string.format("^2[DriftMission]^7 Player %s improved their #1 record", citizenid))
                TriggerClientEvent('driftmission:showLeaderboardMessage', src, "improved_record")
            end
        end)
    end
    
    -- Clean up mission data
    activeMissions[citizenid] = nil
end)

-----------------------------------
-- Rental System Events
-----------------------------------

-- Handle rental request
RegisterNetEvent("driftmission:rentVehicle", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Check if player already has a rental
    if activeRentals[citizenid] then
        TriggerClientEvent('driftmission:rentalDenied', src, "You already have an active rental!")
        return
    end
    
    -- Check if player has enough cash
    local cashBalance = xPlayer.Functions.GetMoney('cash')
    if cashBalance < 500 then
        TriggerClientEvent('driftmission:rentalDenied', src, "You need $500 cash for the rental deposit!")
        return
    end
    
    -- Take initial payment
    xPlayer.Functions.RemoveMoney('cash', 500, 'drift-car-rental-initial')
    
    -- Create rental record
    activeRentals[citizenid] = {
        startTime = os.time(),
        paymentIntervals = 0,
        playerId = src
    }
    
    -- Start rental timer
    CreateThread(function()
        local rentalData = activeRentals[citizenid]
        while rentalData and activeRentals[citizenid] do
            Wait(60000) -- Check every minute
            
            -- Check if rental still exists
            if not activeRentals[citizenid] then break end
            
            local elapsedMinutes = (os.time() - rentalData.startTime) / 60
            
            -- Check for 5-minute intervals
            local intervalsNeeded = math.floor(elapsedMinutes / 5)
            if intervalsNeeded > rentalData.paymentIntervals then
                -- Time for another payment
                rentalData.paymentIntervals = intervalsNeeded
                
                local player = QBCore.Functions.GetPlayer(rentalData.playerId)
                if player then
                    player.Functions.RemoveMoney('bank', 1000, 'drift-car-rental-recurring')
                    TriggerClientEvent('QBCore:Notify', rentalData.playerId, "$1000 rental fee charged to your bank account.", "primary")
                end
            end
            
            -- Check for 30-minute expiration
            if elapsedMinutes >= 30 then
                -- Force expire the rental
                if activeRentals[citizenid] then
                    activeRentals[citizenid] = nil
                end
                break
            end
        end
    end)
    
    TriggerClientEvent('driftmission:rentalApproved', src)
    print(string.format("^2[DriftMission]^7 Player %s started a vehicle rental", citizenid))
end)

-- Handle rental refund (if spawn point was blocked)
RegisterNetEvent("driftmission:refundRental", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Clean up rental record
    if activeRentals[citizenid] then
        activeRentals[citizenid] = nil
    end
    
    -- Refund the payment
    xPlayer.Functions.AddMoney('cash', 500, 'drift-car-rental-refund')
    TriggerClientEvent('QBCore:Notify', src, "Your $500 rental fee has been refunded.", "success")
    print(string.format("^2[DriftMission]^7 Refunded rental fee to player %s (spawn blocked)", citizenid))
end)

-- Handle rental payment charges
RegisterNetEvent("driftmission:chargeRentalPayment", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Verify rental exists
    if not activeRentals[citizenid] then return end
    
    -- Charge bank account
    xPlayer.Functions.RemoveMoney('bank', 1000, 'drift-car-rental-recurring')
    TriggerClientEvent('QBCore:Notify', src, "$1000 rental fee charged to your bank account.", "primary")
end)

-- Handle rental return
RegisterNetEvent("driftmission:returnRental", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Clean up rental
    if activeRentals[citizenid] then
        activeRentals[citizenid] = nil
        print(string.format("^2[DriftMission]^7 Player %s returned their rental vehicle", citizenid))
    end
end)

-- Handle rental expiration with penalty
RegisterNetEvent("driftmission:rentalExpired", function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid
    
    -- Clean up rental and charge penalty
    if activeRentals[citizenid] then
        activeRentals[citizenid] = nil
        xPlayer.Functions.RemoveMoney('bank', 5000, 'drift-car-rental-penalty')
        print(string.format("^1[DriftMission]^7 Player %s's rental expired! $5000 penalty charged.", citizenid))
    end
end)

-- Clean up on player disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if xPlayer then
        local citizenid = xPlayer.PlayerData.citizenid
        activeMissions[citizenid] = nil
        
        -- Clean up rental if active
        if activeRentals[citizenid] then
            activeRentals[citizenid] = nil
            print(string.format("^3[DriftMission]^7 Cleaned up rental for disconnected player %s", citizenid))
        end
    end
end)

-- Optional: Log on start
print("^2[DriftMission]^7 server loaded and ready with police dispatch integration, leaderboard system, and vehicle rental.")