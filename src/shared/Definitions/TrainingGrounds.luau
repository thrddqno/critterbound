--!strict

-- Replaceable Training Grounds content. Runtime state is always built by BattleFactory.

local function requireSibling(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local CritterCatalog = requireSibling("CritterCatalog")

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

local critters = {
	Stone = CritterCatalog.getByClass("Stone"),
	Feral = CritterCatalog.getByClass("Feral"),
	Verdant = CritterCatalog.getByClass("Verdant"),
	Tide = CritterCatalog.getByClass("Tide"),
	Gale = CritterCatalog.getByClass("Gale"),
	Shade = CritterCatalog.getByClass("Shade"),
}

local function card(id, className, cost, target, description, effects)
	return {
		schemaVersion = 1,
		id = `card.training.{id}`,
		displayName = string.gsub(id, "^%l", string.upper),
		class = className,
		abilityId = id,
		energyCost = cost,
		targetingRule = target,
		description = description,
		effects = effects,
	}
end

local cards = {
	card(
		"stone.guard",
		"Stone",
		1,
		"SELF",
		"Gain 22 shield.",
		{ { kind = "SHIELD", amount = 22 } }
	),
	card(
		"stone.bulwark",
		"Stone",
		2,
		"ALL_ALLIES",
		"All allies gain 10 shield.",
		{ { kind = "SHIELD", amount = 10 } }
	),
	card(
		"stone.quake",
		"Stone",
		2,
		"ALL_ENEMIES",
		"Deal 18 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 18 } }
	),
	card(
		"stone.slam",
		"Stone",
		1,
		"FRONT_ENEMY",
		"Deal 32 damage to front enemy.",
		{ { kind = "DAMAGE", amount = 32 } }
	),
	card(
		"feral.strike",
		"Feral",
		1,
		"ENEMY",
		"Deal 38 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 38 } }
	),
	card(
		"feral.pounce",
		"Feral",
		1,
		"FRONT_ENEMY",
		"Deal 34 damage to front enemy.",
		{ { kind = "DAMAGE", amount = 34 } }
	),
	card(
		"feral.frenzy",
		"Feral",
		1,
		"SELF",
		"Gain Attack Up for 2 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_UP", magnitude = 8, duration = 2 } }
	),
	card("feral.rend", "Feral", 2, "ENEMY", "Damage and poison slowest enemy.", {
		{ kind = "DAMAGE", amount = 25 },
		{ kind = "STATUS", statusId = "POISON", magnitude = 4, duration = 2 },
	}),
	card(
		"verdant.mend",
		"Verdant",
		1,
		"ALLY",
		"Heal an ally for 28.",
		{ { kind = "HEAL", amount = 28 } }
	),
	card(
		"verdant.renew",
		"Verdant",
		1,
		"SELF",
		"Heal self for 24.",
		{ { kind = "HEAL", amount = 24 } }
	),
	card(
		"verdant.grove",
		"Verdant",
		2,
		"ALL_ALLIES",
		"Heal all allies for 15.",
		{ { kind = "HEAL", amount = 15 } }
	),
	card(
		"verdant.seed",
		"Verdant",
		1,
		"ENEMY",
		"Poison slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "POISON", magnitude = 6, duration = 2 } }
	),
	card(
		"tide.mend",
		"Tide",
		1,
		"ALLY",
		"Heal an ally for 26.",
		{ { kind = "HEAL", amount = 26 } }
	),
	card("tide.renew", "Tide", 1, "SELF", "Heal self for 22.", { { kind = "HEAL", amount = 22 } }),
	card(
		"tide.barrier",
		"Tide",
		2,
		"ALL_ALLIES",
		"All allies gain 9 shield.",
		{ { kind = "SHIELD", amount = 9 } }
	),
	card(
		"tide.surge",
		"Tide",
		1,
		"ENEMY",
		"Deal 42 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 42 } }
	),
	card("gale.ward", "Gale", 1, "SELF", "Gain 20 shield.", { { kind = "SHIELD", amount = 20 } }),
	card(
		"gale.shelter",
		"Gale",
		2,
		"ALL_ALLIES",
		"All allies gain 8 shield.",
		{ { kind = "SHIELD", amount = 8 } }
	),
	card(
		"gale.gust",
		"Gale",
		1,
		"ENEMY",
		"Deal 40 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 40 } }
	),
	card(
		"gale.haste",
		"Gale",
		1,
		"SELF",
		"Gain Speed Up for 2 rounds.",
		{ { kind = "STATUS", statusId = "SPEED_UP", magnitude = 8, duration = 2 } }
	),
	card(
		"shade.bite",
		"Shade",
		1,
		"ENEMY",
		"Deal 48 damage to slowest enemy.",
		{ { kind = "DAMAGE", amount = 48 } }
	),
	card(
		"shade.toxin",
		"Shade",
		1,
		"ENEMY",
		"Poison slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "POISON", magnitude = 8, duration = 2 } }
	),
	card(
		"shade.weaken",
		"Shade",
		1,
		"ENEMY",
		"Weaken slowest enemy for 2 rounds.",
		{ { kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 6, duration = 2 } }
	),
	card(
		"shade.storm",
		"Shade",
		2,
		"ALL_ENEMIES",
		"Deal 22 damage to all enemies.",
		{ { kind = "DAMAGE", amount = 22 } }
	),
}

local cardDefinitionsById = {}
for _, definition in cards do
	cardDefinitionsById[definition.id] = definition
end

local function makeInstance(definition, ownerUserId: number, suffix: string)
	return {
		schemaVersion = 1,
		id = `owned.training.{string.lower(definition.class)}.{suffix}`,
		definitionId = definition.id,
		ownerUserId = ownerUserId,
		appearanceGenome = {
			schemaVersion = 1,
			speciesId = `training.{string.lower(definition.class)}`,
			bodyVariantId = "placeholder",
			paletteId = suffix,
			patternId = "placeholder",
		},
		abilityGenome = { schemaVersion = 1, abilityIds = clone(definition.abilityIds) },
		baseStats = clone(definition.baseStats),
		acquisition = { source = "TRAINING", acquiredAt = 0, sourceVersion = 1 },
		breeding = { breedable = false, generation = 0, parentIds = {} },
		tradable = false,
		equipmentIds = {},
	}
end

local function createInput(playerUserId: number, generation: number)
	local aiOwnerUserId = 1_000_000_000_000 + playerUserId
	local playerInstances = {
		makeInstance(critters.Stone, playerUserId, `player.{generation}`),
		makeInstance(critters.Feral, playerUserId, `player.{generation}`),
		makeInstance(critters.Verdant, playerUserId, `player.{generation}`),
	}
	local aiInstances = {
		makeInstance(critters.Tide, aiOwnerUserId, `ai.{generation}`),
		makeInstance(critters.Gale, aiOwnerUserId, `ai.{generation}`),
		makeInstance(critters.Shade, aiOwnerUserId, `ai.{generation}`),
	}
	local critterDefinitionsById = CritterCatalog.allById()
	return {
		battleId = `training:{playerUserId}:{generation}`,
		rngSeed = ((playerUserId % 2_000_000_000) + generation * 7919) % 2_147_483_646 + 1,
		teams = {
			{ id = "team.player", ownerUserId = playerUserId, critterInstances = playerInstances },
			{ id = "team.training", ownerUserId = aiOwnerUserId, critterInstances = aiInstances },
		},
		critterDefinitionsById = critterDefinitionsById,
		cardDefinitionsById = clone(cardDefinitionsById),
		playerTeamId = "team.player",
		aiTeamId = "team.training",
		aiOwnerUserId = aiOwnerUserId,
	}
end

return table.freeze({
	createInput = createInput,
})
