--!strict

local EquipmentService = {}

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function new(dependencies)
	local deps = dependencies
	local service = {}

	local function validateEquipment(userId: number)
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		return deps.validator.validateInventory(
			snapshot.value.inventory,
			userId,
			snapshot.value.ownedCritters,
			deps.registry
		)
	end

	local function getEquipment(userId: number)
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		local result = {}
		for critterId, critter in snapshot.value.ownedCritters do
			local itemId = critter.equipmentIds[1]
			if itemId ~= nil then
				local item = snapshot.value.inventory.uniqueItemsById[itemId]
				local definition = deps.registry.getById(item.definitionId)
				table.insert(result, {
					critterId = critterId,
					instanceId = itemId,
					definitionId = item.definitionId,
					modifiers = definition.modifiers,
				})
			end
		end
		table.sort(result, function(a, b)
			return a.critterId < b.critterId
		end)
		return { ok = true, value = result }
	end

	local function equipItem(
		userId: number,
		critterId: string,
		instanceId: string,
		expectedRevision: number?
	)
		if type(critterId) ~= "string" or type(instanceId) ~= "string" then
			return failure("INVALID_EQUIPMENT_REQUEST", "Critter and item IDs are required")
		end
		return deps.profileService.UpdateProfile(userId, function(profile)
			if expectedRevision ~= nil and profile.revision ~= expectedRevision then
				return failure("STALE_PROFILE", "Collection state is stale")
			end
			local critter = profile.ownedCritters[critterId]
			if critter == nil or critter.ownerUserId ~= userId then
				return failure("CRITTER_NOT_OWNED", "Critter is not owned by player")
			end
			local item = profile.inventory.uniqueItemsById[instanceId]
			if item == nil or item.ownerUserId ~= userId then
				return failure("ITEM_NOT_OWNED", "Item is not owned by player")
			end
			local definition = deps.registry.getById(item.definitionId)
			if definition == nil or definition.equipmentSlot ~= "CRITTER" then
				return failure("ITEM_NOT_EQUIPMENT", "Item is incompatible with Critter slot")
			end
			local equippedCritterId = item.equipment.equippedCritterId
			if equippedCritterId == critterId and critter.equipmentIds[1] == instanceId then
				return {
					ok = true,
					value = {
						critterId = critterId,
						instanceId = instanceId,
						swappedInstanceId = nil,
					},
				}
			end
			if equippedCritterId ~= nil then
				return failure("ITEM_ALREADY_EQUIPPED", "Item is equipped to another Critter")
			end
			local swappedInstanceId = critter.equipmentIds[1]
			if swappedInstanceId ~= nil then
				local previous = profile.inventory.uniqueItemsById[swappedInstanceId]
				if previous == nil then
					return failure(
						"ORPHAN_EQUIPMENT_REFERENCE",
						"Occupied slot references missing item"
					)
				end
				previous.equipment.equippedCritterId = nil
			end
			critter.equipmentIds = { instanceId }
			item.equipment.equippedCritterId = critterId
			return {
				ok = true,
				value = {
					critterId = critterId,
					instanceId = instanceId,
					swappedInstanceId = swappedInstanceId,
				},
			}
		end)
	end

	local function unequipItem(userId: number, critterId: string, expectedRevision: number?)
		if type(critterId) ~= "string" then
			return failure("INVALID_EQUIPMENT_REQUEST", "Critter ID is required")
		end
		return deps.profileService.UpdateProfile(userId, function(profile)
			if expectedRevision ~= nil and profile.revision ~= expectedRevision then
				return failure("STALE_PROFILE", "Collection state is stale")
			end
			local critter = profile.ownedCritters[critterId]
			if critter == nil or critter.ownerUserId ~= userId then
				return failure("CRITTER_NOT_OWNED", "Critter is not owned by player")
			end
			local instanceId = critter.equipmentIds[1]
			if instanceId == nil then
				return { ok = true, value = { critterId = critterId, instanceId = nil } }
			end
			local item = profile.inventory.uniqueItemsById[instanceId]
			if item == nil or item.equipment.equippedCritterId ~= critterId then
				return failure(
					"ORPHAN_EQUIPMENT_REFERENCE",
					"Equipment references are inconsistent"
				)
			end
			item.equipment.equippedCritterId = nil
			critter.equipmentIds = {}
			return { ok = true, value = { critterId = critterId, instanceId = instanceId } }
		end)
	end

	service.EquipItem = equipItem
	service.UnequipItem = unequipItem
	service.GetEquipment = getEquipment
	service.ValidateEquipment = validateEquipment
	return table.freeze(service)
end

EquipmentService.new = new
return table.freeze(EquipmentService)
