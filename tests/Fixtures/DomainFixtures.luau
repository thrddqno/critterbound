--!strict

local Definitions = {
	Stone = {
		schemaVersion = 1,
		id = "critter.stone.bastion",
		displayName = "Bastion",
		class = "Stone",
		baseStats = { maxHealth = 120, attack = 20, defense = 35, speed = 10 },
		abilityIds = { "stone.guard", "stone.riposte", "stone.bulwark", "stone.quake" },
	},
	Feral = {
		schemaVersion = 1,
		id = "critter.feral.ravager",
		displayName = "Ravager",
		class = "Feral",
		baseStats = { maxHealth = 80, attack = 42, defense = 12, speed = 30 },
		abilityIds = { "feral.strike", "feral.pounce", "feral.rend", "feral.frenzy" },
	},
	Verdant = {
		schemaVersion = 1,
		id = "critter.verdant.bloom",
		displayName = "Bloom",
		class = "Verdant",
		baseStats = { maxHealth = 95, attack = 18, defense = 20, speed = 20 },
		abilityIds = { "verdant.mend", "verdant.seed", "verdant.renew", "verdant.grove" },
	},
}

local Instances = {
	Stone = {
		schemaVersion = 1,
		id = "owned.stone.1",
		definitionId = Definitions.Stone.id,
		ownerUserId = 101,
		appearanceGenome = {
			schemaVersion = 1,
			speciesId = "stoneback",
			bodyVariantId = "broad",
			paletteId = "granite",
			patternId = "mossy",
		},
		abilityGenome = { schemaVersion = 1, abilityIds = Definitions.Stone.abilityIds },
	},
	Feral = {
		schemaVersion = 1,
		id = "owned.feral.1",
		definitionId = Definitions.Feral.id,
		ownerUserId = 101,
		appearanceGenome = {
			schemaVersion = 1,
			speciesId = "fangcat",
			bodyVariantId = "lean",
			paletteId = "ember",
			patternId = "striped",
		},
		abilityGenome = { schemaVersion = 1, abilityIds = Definitions.Feral.abilityIds },
	},
	Verdant = {
		schemaVersion = 1,
		id = "owned.verdant.1",
		definitionId = Definitions.Verdant.id,
		ownerUserId = 101,
		appearanceGenome = {
			schemaVersion = 1,
			speciesId = "sprigfox",
			bodyVariantId = "round",
			paletteId = "spring",
			patternId = "leafmask",
		},
		abilityGenome = { schemaVersion = 1, abilityIds = Definitions.Verdant.abilityIds },
	},
}

local CardDefinitions = {
	StoneGuard = {
		schemaVersion = 1,
		id = "card.stone.guard",
		displayName = "Granite Guard",
		class = "Stone",
		abilityId = "stone.guard",
		energyCost = 1,
		targetingRule = "SELF",
	},
	FeralStrike = {
		schemaVersion = 1,
		id = "card.feral.strike",
		displayName = "Feral Strike",
		class = "Feral",
		abilityId = "feral.strike",
		energyCost = 2,
		targetingRule = "ENEMY",
	},
	VerdantMend = {
		schemaVersion = 1,
		id = "card.verdant.mend",
		displayName = "Verdant Mend",
		class = "Verdant",
		abilityId = "verdant.mend",
		energyCost = 1,
		targetingRule = "ALLY",
	},
}

local CardInstances = {
	stone = {
		id = "hand.stone.guard.1",
		definitionId = CardDefinitions.StoneGuard.id,
		sourceCritterInstanceId = Instances.Stone.id,
	},
	feral = {
		id = "hand.feral.strike.1",
		definitionId = CardDefinitions.FeralStrike.id,
		sourceCritterInstanceId = Instances.Feral.id,
	},
	verdant = {
		id = "hand.verdant.mend.1",
		definitionId = CardDefinitions.VerdantMend.id,
		sourceCritterInstanceId = Instances.Verdant.id,
	},
}

local Combatants = {
	stone = {
		id = "combatant.team1.stone",
		critterInstanceId = Instances.Stone.id,
		teamId = "team.1",
		slot = 1,
		class = "Stone",
		abilityIds = Definitions.Stone.abilityIds,
		stats = Definitions.Stone.baseStats,
		currentHealth = 120,
		statusEffects = {},
	},
	feral = {
		id = "combatant.team1.feral",
		critterInstanceId = Instances.Feral.id,
		teamId = "team.1",
		slot = 2,
		class = "Feral",
		abilityIds = Definitions.Feral.abilityIds,
		stats = Definitions.Feral.baseStats,
		currentHealth = 80,
		statusEffects = {},
	},
	verdant = {
		id = "combatant.team1.verdant",
		critterInstanceId = Instances.Verdant.id,
		teamId = "team.1",
		slot = 3,
		class = "Verdant",
		abilityIds = Definitions.Verdant.abilityIds,
		stats = Definitions.Verdant.baseStats,
		currentHealth = 95,
		statusEffects = {},
	},
	enemyStone = {
		id = "combatant.team2.stone",
		critterInstanceId = "owned.enemy.stone",
		teamId = "team.2",
		slot = 1,
		class = "Stone",
		abilityIds = Definitions.Stone.abilityIds,
		stats = Definitions.Stone.baseStats,
		currentHealth = 120,
		statusEffects = {},
	},
	enemyFeral = {
		id = "combatant.team2.feral",
		critterInstanceId = "owned.enemy.feral",
		teamId = "team.2",
		slot = 2,
		class = "Feral",
		abilityIds = Definitions.Feral.abilityIds,
		stats = Definitions.Feral.baseStats,
		currentHealth = 80,
		statusEffects = {},
	},
	enemyVerdant = {
		id = "combatant.team2.verdant",
		critterInstanceId = "owned.enemy.verdant",
		teamId = "team.2",
		slot = 3,
		class = "Verdant",
		abilityIds = Definitions.Verdant.abilityIds,
		stats = Definitions.Verdant.baseStats,
		currentHealth = 95,
		statusEffects = {},
	},
}

local Team = {
	id = "team.1",
	ownerUserId = 101,
	combatantIds = { Combatants.stone.id, Combatants.feral.id, Combatants.verdant.id },
}

local function indexById(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

local allCombatants = {
	Combatants.stone,
	Combatants.feral,
	Combatants.verdant,
	Combatants.enemyStone,
	Combatants.enemyFeral,
	Combatants.enemyVerdant,
}

local Context = {
	team = Team,
	combatantsById = indexById(allCombatants),
	cardInstancesById = indexById({
		CardInstances.stone,
		CardInstances.feral,
		CardInstances.verdant,
	}),
	cardDefinitionsById = indexById({
		CardDefinitions.StoneGuard,
		CardDefinitions.FeralStrike,
		CardDefinitions.VerdantMend,
	}),
	handCardInstanceIds = {
		CardInstances.stone.id,
		CardInstances.feral.id,
		CardInstances.verdant.id,
	},
	availableEnergy = 3,
}

local ValidCommand = {
	kind = "COMMIT_PLAN",
	id = "command.round1.team1",
	battleId = "battle.fixture",
	actorUserId = 101,
	teamId = Team.id,
	queuedCards = {
		{
			cardInstanceId = CardInstances.stone.id,
			sourceCombatantId = Combatants.stone.id,
			targetCombatantIds = { Combatants.stone.id },
			queueIndex = 1,
		},
		{
			cardInstanceId = CardInstances.feral.id,
			sourceCombatantId = Combatants.feral.id,
			targetCombatantIds = { Combatants.enemyStone.id },
			queueIndex = 1,
		},
	},
}

return {
	Definitions = Definitions,
	Instances = Instances,
	CardDefinitions = CardDefinitions,
	CardInstances = CardInstances,
	Combatants = Combatants,
	Team = Team,
	Context = Context,
	ValidCommand = ValidCommand,
}
