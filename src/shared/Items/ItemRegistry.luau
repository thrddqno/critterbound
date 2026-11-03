--!strict

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

local definitions = {
	["material.iron_shard"] = {
		schemaVersion = 1,
		id = "material.iron_shard",
		displayName = "Iron Shard",
		description = "A common metal fragment used by future crafting systems.",
		category = "MATERIAL",
		rarity = "COMMON",
		stackable = true,
		maxStack = 999,
		equipmentSlot = nil,
		modifiers = {},
		tradeable = true,
	},
	["catalyst.verdant_essence"] = {
		schemaVersion = 1,
		id = "catalyst.verdant_essence",
		displayName = "Verdant Essence",
		description = "Condensed natural energy. No use during Run 6C.",
		category = "CATALYST",
		rarity = "UNCOMMON",
		stackable = true,
		maxStack = 99,
		equipmentSlot = nil,
		modifiers = {},
		tradeable = true,
	},
	["consumable.training_tonic"] = {
		schemaVersion = 1,
		id = "consumable.training_tonic",
		displayName = "Training Tonic",
		description = "A practice consumable. Consumption is not implemented.",
		category = "CONSUMABLE",
		rarity = "COMMON",
		stackable = true,
		maxStack = 20,
		equipmentSlot = nil,
		modifiers = {},
		tradeable = false,
	},
	["equipment.training_charm"] = {
		schemaVersion = 1,
		id = "equipment.training_charm",
		displayName = "Training Charm",
		description = "Practice equipment for testing Critter loadouts.",
		category = "EQUIPMENT",
		rarity = "UNCOMMON",
		stackable = false,
		maxStack = 1,
		equipmentSlot = "CRITTER",
		modifiers = { resolve = 2 },
		tradeable = false,
	},
	["collectible.training_relic"] = {
		schemaVersion = 1,
		id = "collectible.training_relic",
		displayName = "Training Relic",
		description = "A collectible recovered from the Training Grounds.",
		category = "COLLECTIBLE",
		rarity = "RARE",
		stackable = false,
		maxStack = 1,
		equipmentSlot = nil,
		modifiers = {},
		tradeable = true,
	},
}

local function getById(id: string)
	local definition = definitions[id]
	return if definition == nil then nil else clone(definition)
end

local function allById()
	return clone(definitions)
end

return table.freeze({
	getById = getById,
	allById = allById,
})
