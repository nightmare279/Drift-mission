
local AP_RESOURCE_NAME <const> = "AdvancedParking"

if (GetCurrentResourceName() == AP_RESOURCE_NAME) then return end

local AP = exports[AP_RESOURCE_NAME]

-- replaces DeleteEntity native on client and server side
local DeleteEntityOriginal <const> = DeleteEntity
DeleteEntity = function(entity)
	if (not DoesEntityExist(entity)) then return end

	if (GetEntityType(entity) ~= 2 or GetResourceState(AP_RESOURCE_NAME) ~= "started") then
		DeleteEntityOriginal(entity)
		return
	end
	TriggerEvent("Pug:client:PutFlatbedAwayCustomEvent")

	AP:DeleteVehicle(entity)
end

-- replaces DeleteVehicle native on client side
if (not IsDuplicityVersion()) then
	local DeleteVehicleOriginal <const> = DeleteVehicle
	DeleteVehicle = function(vehicle)
		if (GetResourceState(AP_RESOURCE_NAME) ~= "started") then
			DeleteVehicleOriginal(vehicle)
			return
		end

		AP:DeleteVehicle(vehicle)
	end
end
