-- NPC Manager Module
local NPCManager = {}

-- Local state
local sharedState = {}
local modules = {} -- Module registry
local driftKingZone = nil
local driftNpcSpawned = false

function NPCManager.Init(state, moduleRegistry)
    sharedState = state
    modules = moduleRegistry or {}
end

function NPCManager.UpdateState(key, value)
    if sharedState[key] then
        sharedState[key] = value
    end
end

function NPCManager.RemoveDriftNpc()
    if sharedState.driftNpc and DoesEntityExist(sharedState.driftNpc) then
        DeleteEntity(sharedState.driftNpc)
        sharedState.driftNpc = nil
        driftNpcSpawned = false
    end
end

function NPCManager.targetLocalEntity(entity, options, distance)
    for _, option in ipairs(options) do
        option.distance = distance
        option.onSelect = option.action
        option.action = nil
    end
    exports.ox_target:addLocalEntity(entity, options)
end

function NPCManager.SpawnDriftNpc()
    if sharedState.driftNpc and DoesEntityExist(sharedState.driftNpc) then return end
    
    RequestModel(Config.NpcModel)
    while not HasModelLoaded(Config.NpcModel) do Wait(10) end
    
    local x, y, z = table.unpack(Config.NpcCoords)
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z+10, 0)
    if foundGround then z = groundZ end
    
    sharedState.driftNpc = CreatePed(4, Config.NpcModel, x, y, z, Config.NpcHeading or 333.0, false, false)
    SetEntityInvincible(sharedState.driftNpc, true)
    SetBlockingOfNonTemporaryEvents(sharedState.driftNpc, true)
    FreezeEntityPosition(sharedState.driftNpc, true)
    SetEntityCoords(sharedState.driftNpc, x, y, z, false, false, false, true)
    SetEntityAsMissionEntity(sharedState.driftNpc, true, true)
    
    NPCManager.targetLocalEntity(sharedState.driftNpc, {
        {
            icon = 'fa-solid fa-car',
            label = 'Talk to Drift King',
            canInteract = function() return true end,
            action = function()
                TriggerServerEvent('driftmission:requestUnlocks')
                Citizen.SetTimeout(250, function()
                    if modules.DialogManager and modules.DialogManager.ShowDriftKingDialog then
                        modules.DialogManager.ShowDriftKingDialog()
                    end
                end)
            end,
        },
    }, 1.5)
    
    driftNpcSpawned = true
end

function NPCManager.CreateDriftKingZone()
    if driftKingZone then 
        driftKingZone:remove() 
        driftKingZone = nil 
    end
    
    driftKingZone = lib.points.new({
        coords = Config.NpcCoords.xyz or Config.NpcCoords,
        distance = 60.0,
        onEnter = function()
            if not driftNpcSpawned then 
                NPCManager.SpawnDriftNpc() 
            end
        end,
        onExit = function()
            NPCManager.RemoveDriftNpc()
        end
    })
end

function NPCManager.EnsureDriftKingZone()
    if not driftKingZone then
        NPCManager.CreateDriftKingZone()
    end
end

function NPCManager.RefreshNPC()
    if driftNpcSpawned then 
        NPCManager.SpawnDriftNpc() 
    end
end

function NPCManager.Cleanup()
    if driftKingZone then 
        driftKingZone:remove() 
        driftKingZone = nil 
    end
    NPCManager.RemoveDriftNpc()
end

return NPCManager
