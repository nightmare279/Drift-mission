-- Mission Flow Module
local MissionFlow = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local driftZoneBlip = nil
local driftZoneBlip_icon = nil

function MissionFlow.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
end

function MissionFlow.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

-- Blip management
function MissionFlow.ShowDriftZoneBlip(missionId)
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

function MissionFlow.HideDriftZoneBlip()
    if driftZoneBlip then RemoveBlip(driftZoneBlip) driftZoneBlip = nil end
    if driftZoneBlip_icon then RemoveBlip(driftZoneBlip_icon) driftZoneBlip_icon = nil end
end

-- Mission control
function MissionFlow.StartMission(missionId)
    missionId = tonumber(missionId) or 1
    local mission = Config.Missions[missionId]
    
    if sharedState.missionActive then 
        UIManager.TempMessage("~r~Already on a mission!", 1200)
        return 
    end
    
    -- Check mission type
    local isSprintMission = mission.Type == "sprint"
    
    -- Notify server about mission start for police presence check
    TriggerServerEvent("driftmission:missionStart", missionId)
    
    -- Reset shared state
    sharedState.activeMissionId = missionId
    sharedState.driftScores = {}
    
    if isSprintMission then
        -- Sprint mission logic
        if modules.SprintMission and modules.SprintMission.StartSprintMission then
            modules.SprintMission.StartSprintMission(missionId)
        end
        if modules.UIManager and modules.UIManager.ShowDriftUI then
            modules.UIManager.ShowDriftUI(true)
        end
    else
        -- Regular drift mission logic
        MissionFlow.ShowDriftZoneBlip(missionId)
        if modules.UIManager then
            modules.UIManager.SetStatusText("~b~Head to the drift area. The timer will start when you arrive.")
        end
        
        -- Start necessary threads for mission
        if modules.DriftDetection and modules.DriftDetection.StartDriftDetectionThread then
            modules.DriftDetection.StartDriftDetectionThread()
        end
        
        -- Wait until IN the zone (poly or circle)
        while modules.DriftDetection and not modules.DriftDetection.IsPlayerInDriftZone(mission.Zone, PlayerPedId()) do
            Wait(500)
        end
        
        sharedState.missionActive = true
        sharedState.missionTimer = mission.MissionTime
        if modules.UIManager then
            modules.UIManager.ShowDriftUI(true)
            modules.UIManager.SetStatusText("")
        end
        
        -- Mission timer thread
        Citizen.CreateThread(function()
            while sharedState.missionActive and sharedState.missionTimer > 0 do
                Wait(1000)
                sharedState.missionTimer = sharedState.missionTimer - 1
            end
            if sharedState.missionActive then
                sharedState.missionActive = false
                if modules.UIManager then
                    modules.UIManager.ShowDriftUI(false)
                    modules.UIManager.TempMessage("~b~Time's up! Return to the Drift King to submit your score.", 4000)
                end
                MissionFlow.HideDriftZoneBlip()
                if modules.DriftDetection and modules.DriftDetection.StopDriftDetectionThread then
                    modules.DriftDetection.StopDriftDetectionThread()
                end
            end
        end)
    end
end

function MissionFlow.TurnInMission()
    MissionFlow.HideDriftZoneBlip()
    if modules.UIManager then
        modules.UIManager.ShowDriftUI(false)
    end
    
    -- Clean up sprint mission objects
    if modules.SprintMission and modules.SprintMission.CancelSprintMission then
        modules.SprintMission.CancelSprintMission()
    end
    
    if modules.DriftDetection and modules.DriftDetection.StopDriftDetectionThread then
        modules.DriftDetection.StopDriftDetectionThread()
    end
    if modules.SprintMission and modules.SprintMission.StopSprintDetectionThread then
        modules.SprintMission.StopSprintDetectionThread()
    end
    
    local score = modules.UIManager and modules.UIManager.GetTotalScore() or 0
    if not sharedState.missionActive and score > 0 and sharedState.activeMissionId then
        local mission = Config.Missions[sharedState.activeMissionId]
        local reward = math.floor(score * mission.RewardPerScore)
        local missionTypeText = mission.Type == "sprint" and "sprint" or "drift"
        if modules.UIManager then
            modules.UIManager.TempMessage(("~b~You turned in your score!\nTotal %s points: ~y~%d\n~g~Cash reward: $%d"):format(missionTypeText, score, reward), 3000)
        end
        TriggerServerEvent("driftmission:reward", sharedState.activeMissionId, score)
        sharedState.driftScores = {}
        sharedState.activeMissionId = nil
    else
        if modules.UIManager then
            modules.UIManager.TempMessage("~r~No score to turn in!", 1500)
        end
    end
end

function MissionFlow.CancelCurrentMission()
    if sharedState.missionActive then
        sharedState.missionActive = false
        if modules.UIManager then
            modules.UIManager.ShowDriftUI(false)
            modules.UIManager.TempMessage("~r~Mission cancelled!", 2000)
        end
        
        MissionFlow.HideDriftZoneBlip()
        
        -- Clean up sprint mission
        if modules.SprintMission and modules.SprintMission.CancelSprintMission then
            modules.SprintMission.CancelSprintMission()
        end
        
        if modules.DriftDetection and modules.DriftDetection.StopDriftDetectionThread then
            modules.DriftDetection.StopDriftDetectionThread()
        end
        if modules.SprintMission and modules.SprintMission.StopSprintDetectionThread then
            modules.SprintMission.StopSprintDetectionThread()
        end
        
        sharedState.driftScores = {}
        sharedState.activeMissionId = nil
    end
end

return MissionFlow
