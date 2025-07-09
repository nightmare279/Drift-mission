-- UI Manager Module
local UIManager = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local showDriftUI = false
local uiThreadActive = false
local debugEnabled = false

function UIManager.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
end

function UIManager.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
end

function UIManager.StopUIThread()
    uiThreadActive = false
end

-- UI state control
function UIManager.ShowDriftUI(show)
    showDriftUI = show
    if show then
        UIManager.StartUIThread()
    end
end

function UIManager.IsDriftUIVisible()
    return showDriftUI
end

function UIManager.Cleanup()
    UIManager.StopUIThread()
    showDriftUI = false
    sharedState.missionDisplayText = ""
end

return UIManagerd
end

function UIManager.SetDebugMode(enabled)
    debugEnabled = enabled
end

-- Status text management
function UIManager.SetStatusText(txt)
    sharedState.missionDisplayText = txt or ""
    if txt and txt ~= "" then
        UIManager.StartUIThread()
    end
end

function UIManager.TempMessage(txt, time)
    UIManager.SetStatusText(txt)
    CreateThread(function()
        Wait(time or 5000)
        UIManager.SetStatusText("")
    end)
end

function UIManager.ShowLeaderboardMessage(txt, duration)
    UIManager.SetStatusText(txt)
    CreateThread(function()
        Wait(duration)
        UIManager.SetStatusText("")
    end)
end

-- UI display functions
function UIManager.GetAngleColor(angle)
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

function UIManager.GetSpeedColor(speed)
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

function UIManager.GetTotalScore()
    local total = 0
    for i, v in ipairs(sharedState.driftScores) do
        total = total + v
    end
    return math.floor(total)
end

function UIManager.DrawDriftUI()
    if not showDriftUI then return end
    
    -- Get drift data from detection module
    local driftData = modules.DriftDetection and modules.DriftDetection.GetDriftData() or {}
    local sprintData = modules.SprintMission and modules.SprintMission.GetSprintData() or {}
    
    -- Simplified UI - single horizontal line at top center, fixed positions
    local centerX = 0.5
    local topY = 0.02
    local spacing = 0.08
    
    -- Fixed positions for each element
    local timeX = centerX - spacing
    local currentScoreX = centerX  -- Current score now in center
    local totalScoreX = centerX + spacing  -- Total score now on right
    
    -- Time remaining (fixed position) - using GTA font and increased size
    local timeColor = sharedState.missionTimer > 30 and {110, 193, 255, 255} or {255, 100, 100, 255}
    SetTextFont(4) -- Font 4 is the GTA style font
    SetTextScale(0.575, 0.575) -- Increased by 15% from 0.5 to 0.575
    SetTextColour(timeColor[1], timeColor[2], timeColor[3], timeColor[4])
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(string.format("Time: %02d:%02d", math.floor(sharedState.missionTimer / 60), sharedState.missionTimer % 60))
    EndTextCommandDisplayText(timeX, topY)
    
    -- Total score (fixed position - now on right)
    SetTextFont(4) -- Changed to GTA font
    SetTextScale(0.575, 0.575) -- Increased by 15% from 0.5 to 0.575
    SetTextColour(110, 193, 255, 255) -- Changed to light blue
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(string.format("Total: %d", UIManager.GetTotalScore()))
    EndTextCommandDisplayText(totalScoreX, topY)
    
    -- Current score and status (fixed position - now in center, only when drifting, showing result, or out of zone)
    if driftData.driftActive or driftData.showDriftResult or driftData.showOutOfZone then
        local displayScore = driftData.showDriftResult and driftData.driftResultScore or math.floor(driftData.currentDrift.score)
        local scoreColor = {110, 193, 255, 255} -- Changed to light blue as default
        local displayText = ""
        
        if driftData.showOutOfZone then
            scoreColor = {255, 50, 50, 255} -- Red for out of zone
            displayText = "OUT OF ZONE!"
        elseif driftData.showDriftResult or driftData.driftActive then
            if (driftData.showDriftResult and driftData.driftResultType == "crashed") or (driftData.driftActive and driftData.currentDrift.crashed) then
                scoreColor = {255, 50, 50, 255}
                displayText = "CRASHED!" -- Only show status, no score
            elseif (driftData.showDriftResult and driftData.driftResultType == "spinout") or (driftData.driftActive and driftData.currentDrift.spinout) then
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
        if driftData.driftActive and not driftData.showDriftResult and not driftData.showOutOfZone then
            local barWidth = 0.2 -- Reduced from 0.3 to make it shorter
            local barHeight = 0.015
            local barX = centerX - barWidth/2
            local barY = topY + 0.055
            
            -- Background bar
            DrawRect(centerX, barY, barWidth, barHeight, 50, 50, 50, 200)
            
            -- Angle progress (0-180 degrees)
            local angleColor = UIManager.GetAngleColor(driftData.currentAngle)
            local angleProgress = math.min(driftData.currentAngle / 180, 1.0)
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
            if driftData.driftCombo > 1 then
                local comboX = barX + barWidth - 0.015 -- Adjusted for shorter bar width
                local comboY = barY - 0.025 -- Same height as spinout label
                local comboMultiplier = 1.0 + (driftData.driftCombo * 0.1)
                
                SetTextFont(4) -- GTA font
                SetTextScale(0.3, 0.3)
                SetTextColour(255, 165, 0, 255) -- Orange color
                SetTextOutline()
                SetTextCentre(true)
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName(string.format("x%d (%.1fx)", driftData.driftCombo, comboMultiplier))
                EndTextCommandDisplayText(comboX, comboY)
            end
        end
    end
    
    -- Sprint mission specific UI
    if sprintData.sprintMission then
        -- Show checkpoint progress
        local mission = Config.Missions[sharedState.activeMissionId]
        if mission then
            local progressY = topY + 0.12
            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(string.format("Checkpoint: %d/%d", sprintData.currentCheckpoint, #mission.Checkpoints))
            EndTextCommandDisplayText(centerX, progressY)
        end
    end
    
    -- Handle drift result display timeout
    if driftData.showDriftResult and GetGameTimer() > driftData.driftResultEndTime then
        if modules.DriftDetection and modules.DriftDetection.ClearDriftResult then
            modules.DriftDetection.ClearDriftResult()
        end
    end
    
    -- Handle screen effects
    local currentTime = GetGameTimer()
    if currentTime < driftData.screenEffectEndTime then
        if driftData.driftResultType == "crashed" then
            -- Red filter for crash
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 0, 0, 100)
        elseif driftData.driftResultType == "spinout" then
            -- Orange filter for spinout
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 150, 0, 80)
        end
    end
end

function UIManager.DrawMissionText(text, color)
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

-- UI Thread Control
function UIManager.StartUIThread()
    if uiThreadActive then return end
    uiThreadActive = true
    
    Citizen.CreateThread(function()
        while uiThreadActive do
            Citizen.Wait(0)
            if showDriftUI then
                UIManager.DrawDriftUI()
            elseif sharedState.missionDisplayText ~= "" then
                UIManager.DrawMissionText(sharedState.missionDisplayText)
            else
                Citizen.Wait(100)
            end
        end
    end)
en
