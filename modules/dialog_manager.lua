-- Dialog Manager Module
local DialogManager = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local Dialog = {}

function DialogManager.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
end

function DialogManager.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

function DialogManager.RefreshDriftMissionDialog()
    local missionBtns = {}
    local unlockedCount = 0
    
    for missionId, mission in pairs(Config.Missions) do
        missionId = tonumber(missionId)
        if mission.UnlockScore == 0 or sharedState.playerProgress[missionId] then
            unlockedCount = unlockedCount + 1
            local bestScore = sharedState.playerBestScore[missionId] or 0
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
                        ped = sharedState.driftNpc,
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
                    if modules.UIManager then
                        modules.UIManager.TempMessage(string.format("~r~Mission locked!~w~\nRequires %d drift points to unlock.", mission.UnlockScore), 3000)
                    end
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

function DialogManager.RefreshDriftMainDialog()
    local mainBtns = {
        {
            label = "Let's Drift",
            nextDialog = 'driftking_missions',
        },
        {
            label = 'View Leaderboard',
            close = true,
            onSelect = function()
                if modules.LeaderboardNUI and modules.LeaderboardNUI.OpenLeaderboard then
                    modules.LeaderboardNUI.OpenLeaderboard()
                end
            end,
        },
    }
    
    -- Add cancel mission option if currently active
    if sharedState.missionActive and sharedState.activeMissionId then
        table.insert(mainBtns, 1, {
            label = 'Cancel Current Mission',
            close = true,
            onSelect = function()
                if modules.MissionFlow and modules.MissionFlow.CancelCurrentMission then
                    modules.MissionFlow.CancelCurrentMission()
                end
            end,
        })
    end
    
    if not sharedState.missionActive and sharedState.activeMissionId and (modules.UIManager and modules.UIManager.GetTotalScore() or 0) > 0 then
        table.insert(mainBtns, #mainBtns, {
            label = string.format('Turn In Score (%d points)', modules.UIManager and modules.UIManager.GetTotalScore() or 0),
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

function DialogManager.ShowDriftKingDialog()
    DialogManager.RefreshDriftMissionDialog()
    DialogManager.RefreshDriftMainDialog()
    exports.bl_dialog:showDialog({
        ped = sharedState.driftNpc,
        dialog = Dialog,
        startId = 'driftking_main'
    })
end

return DialogManager
