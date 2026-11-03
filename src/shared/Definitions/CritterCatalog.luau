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

local definitionsByClass = {
	Stone = {
		schemaVersion = 1,
		id = "critter.training.stone",
		displayName = "Bastion",
		class = "Stone",
		baseStats = {
			maxHealth = 120,
			attack = 22,
			defense = 34,
			speed = 10,
			skill = 2,
			resolve = 6,
		},
		abilityIds = { "stone.guard", "stone.bulwark", "stone.quake", "stone.slam" },
		abilityPool = {
			"stone.guard",
			"stone.bulwark",
			"stone.quake",
			"stone.slam",
			"stone.rampart",
			"stone.crush",
			"verdant.bloom",
		},
	},
	Feral = {
		schemaVersion = 1,
		id = "critter.training.feral",
		displayName = "Ravager",
		class = "Feral",
		baseStats = {
			maxHealth = 84,
			attack = 40,
			defense = 12,
			speed = 31,
			skill = 5,
			resolve = 2,
		},
		abilityIds = { "feral.strike", "feral.pounce", "feral.frenzy", "feral.rend" },
		abilityPool = {
			"feral.strike",
			"feral.pounce",
			"feral.frenzy",
			"feral.rend",
			"feral.maul",
			"feral.fury",
			"gale.tailwind",
		},
	},
	Verdant = {
		schemaVersion = 1,
		id = "critter.training.verdant",
		displayName = "Bloom",
		class = "Verdant",
		baseStats = {
			maxHealth = 98,
			attack = 18,
			defense = 20,
			speed = 20,
			skill = 4,
			resolve = 5,
		},
		abilityIds = { "verdant.mend", "verdant.renew", "verdant.grove", "verdant.seed" },
		abilityPool = {
			"verdant.mend",
			"verdant.renew",
			"verdant.grove",
			"verdant.seed",
			"verdant.bloom",
			"verdant.bramble",
		},
	},
	Tide = {
		schemaVersion = 1,
		id = "critter.training.tide",
		displayName = "Rill",
		class = "Tide",
		baseStats = {
			maxHealth = 102,
			attack = 20,
			defense = 22,
			speed = 17,
			skill = 5,
			resolve = 5,
		},
		abilityIds = { "tide.mend", "tide.renew", "tide.barrier", "tide.surge" },
		abilityPool = {
			"tide.mend",
			"tide.renew",
			"tide.barrier",
			"tide.surge",
			"tide.torrent",
			"tide.purge",
			"verdant.bloom",
		},
	},
	Gale = {
		schemaVersion = 1,
		id = "critter.training.gale",
		displayName = "Zephyr",
		class = "Gale",
		baseStats = {
			maxHealth = 88,
			attack = 27,
			defense = 15,
			speed = 28,
			skill = 6,
			resolve = 3,
		},
		abilityIds = { "gale.ward", "gale.shelter", "gale.gust", "gale.haste" },
		abilityPool = {
			"gale.ward",
			"gale.shelter",
			"gale.gust",
			"gale.haste",
			"gale.squall",
			"gale.tailwind",
		},
	},
	Shade = {
		schemaVersion = 1,
		id = "critter.training.shade",
		displayName = "Gloom",
		class = "Shade",
		baseStats = {
			maxHealth = 82,
			attack = 34,
			defense = 14,
			speed = 24,
			skill = 6,
			resolve = 4,
		},
		abilityIds = { "shade.bite", "shade.toxin", "shade.weaken", "shade.storm" },
		abilityPool = {
			"shade.bite",
			"shade.toxin",
			"shade.weaken",
			"shade.storm",
			"shade.curse",
			"shade.terror",
		},
	},
}

local function getByClass(className: string)
	local definition = definitionsByClass[className]
	return if definition == nil then nil else clone(definition)
end

local function getById(id: string)
	for _, definition in definitionsByClass do
		if definition.id == id then
			return clone(definition)
		end
	end
	return nil
end

local function allById()
	local result = {}
	for _, definition in definitionsByClass do
		result[definition.id] = clone(definition)
	end
	return result
end

return table.freeze({
	getByClass = getByClass,
	getById = getById,
	allById = allById,
})
