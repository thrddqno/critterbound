--!strict

local ProfileProjector = {}

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function projectCritter(instance, catalog)
	local definition = catalog.getById(instance.definitionId)
	return {
		schemaVersion = instance.schemaVersion,
		id = instance.id,
		definitionId = instance.definitionId,
		displayName = if definition == nil then "Unknown Critter" else definition.displayName,
		class = if definition == nil then nil else definition.class,
		ownerUserId = instance.ownerUserId,
		appearanceGenome = clone(instance.appearanceGenome),
		abilityGenome = clone(instance.abilityGenome),
		baseStats = clone(instance.baseStats),
		acquisition = clone(instance.acquisition),
		breeding = clone(instance.breeding),
		tradable = instance.tradable,
		equipmentIds = clone(instance.equipmentIds),
	}
end

local function ownedCritters(profile, catalog)
	local result = {}
	for _, instance in profile.ownedCritters do
		table.insert(result, projectCritter(instance, catalog))
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function collection(profileValue, catalog, itemRegistry)
	local selectedSlots = {}
	for slot, critterId in profileValue.selectedTeam do
		selectedSlots[critterId] = slot
	end
	local critters = ownedCritters(profileValue, catalog)
	for _, critter in critters do
		critter.selectedTeamSlot = selectedSlots[critter.id]
		local equipmentId = critter.equipmentIds[1]
		local item = if equipmentId == nil
			then nil
			else profileValue.inventory.uniqueItemsById[equipmentId]
		local definition = if item == nil then nil else itemRegistry.getById(item.definitionId)
		critter.equippedItem = if item == nil or definition == nil
			then nil
			else {
				instanceId = item.instanceId,
				definitionId = item.definitionId,
				displayName = definition.displayName,
				rarity = definition.rarity,
			}
		critter.ownerUserId = nil
		critter.equipmentIds = nil
	end
	return {
		schemaVersion = 1,
		revision = profileValue.revision,
		critters = critters,
		selectedTeam = clone(profileValue.selectedTeam),
	}
end

local function selectedTeam(profile, catalog)
	local result = {}
	for _, id in profile.selectedTeam do
		local instance = profile.ownedCritters[id]
		if instance == nil then
			return nil
		end
		table.insert(result, projectCritter(instance, catalog))
	end
	return result
end

local function profile(profileValue, catalog)
	return {
		schemaVersion = profileValue.schemaVersion,
		userId = profileValue.userId,
		revision = profileValue.revision,
		createdAt = profileValue.createdAt,
		updatedAt = profileValue.updatedAt,
		starterGrantVersion = profileValue.starterGrantVersion,
		ownedCritters = ownedCritters(profileValue, catalog),
		selectedTeam = clone(profileValue.selectedTeam),
		inventory = { schemaVersion = profileValue.inventory.schemaVersion },
		progression = { schemaVersion = profileValue.progression.schemaVersion },
	}
end

ProfileProjector.project = profile
ProfileProjector.projectCritter = projectCritter
ProfileProjector.ownedCritters = ownedCritters
ProfileProjector.selectedTeam = selectedTeam
ProfileProjector.collection = collection
return table.freeze(ProfileProjector)
