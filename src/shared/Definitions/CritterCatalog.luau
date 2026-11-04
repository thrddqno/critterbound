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
		schemaVersion = 2,
		id = "critter.training.stone",
		displayName = "Bastion",
		class = "Stone",
		baseStats = {
			health = 52,
			speed = 10,
			skill = 2,
			morale = 6,
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
		schemaVersion = 2,
		id = "critter.training.feral",
		displayName = "Ravager",
		class = "Feral",
		baseStats = {
			health = 31,
			speed = 31,
			skill = 5,
			morale = 2,
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
		schemaVersion = 2,
		id = "critter.training.verdant",
		displayName = "Bloom",
		class = "Verdant",
		baseStats = {
			health = 43,
			speed = 20,
			skill = 4,
			morale = 5,
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
		schemaVersion = 2,
		id = "critter.training.tide",
		displayName = "Rill",
		class = "Tide",
		baseStats = {
			health = 39,
			speed = 17,
			skill = 5,
			morale = 5,
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
		schemaVersion = 2,
		id = "critter.training.gale",
		displayName = "Zephyr",
		class = "Gale",
		baseStats = {
			health = 27,
			speed = 28,
			skill = 6,
			morale = 3,
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
		schemaVersion = 2,
		id = "critter.training.shade",
		displayName = "Gloom",
		class = "Shade",
		baseStats = {
			health = 29,
			speed = 24,
			skill = 6,
			morale = 4,
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
