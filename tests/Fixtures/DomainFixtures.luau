--!strict

local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
local CombatStats = require("../../src/shared/Battle/CombatStats")

local Definitions = {
	Stone = {
		schemaVersion = 2,
		id = "critter.stone.bastion",
		displayName = "Bastion",
		class = "Stone",
		baseStats = { health = 52, speed = 10, skill = 2, morale = 6 },
		abilityIds = { "stone.guard", "stone.bulwark", "stone.quake", "stone.slam" },
	},
	Feral = {
		schemaVersion = 2,
		id = "critter.feral.ravager",
		displayName = "Ravager",
		class = "Feral",
		baseStats = { health = 31, speed = 30, skill = 5, morale = 2 },
		abilityIds = { "feral.strike", "feral.pounce", "feral.frenzy", "feral.rend" },
	},
	Verdant = {
		schemaVersion = 2,
		id = "critter.verdant.bloom",
		displayName = "Bloom",
		class = "Verdant",
		baseStats = { health = 43, speed = 20, skill = 4, morale = 5 },
		abilityIds = { "verdant.mend", "verdant.renew", "verdant.grove", "verdant.seed" },
	},
}

local Instances = {
	Stone = {
		schemaVersion = 3,
		id = "owned.stone.1",
		definitionId = Definitions.Stone.id,
		ownerUserId = 101,
		appearanceGenome = GeneRegistry.defaultGenomes("Stone").appearanceGenome,
		abilityGenome = GeneRegistry.defaultGenomes("Stone").abilityGenome,
	},
	Feral = {
		schemaVersion = 3,
		id = "owned.feral.1",
		definitionId = Definitions.Feral.id,
		ownerUserId = 101,
		appearanceGenome = GeneRegistry.defaultGenomes("Feral").appearanceGenome,
		abilityGenome = GeneRegistry.defaultGenomes("Feral").abilityGenome,
	},
	Verdant = {
		schemaVersion = 3,
		id = "owned.verdant.1",
		definitionId = Definitions.Verdant.id,
		ownerUserId = 101,
		appearanceGenome = GeneRegistry.defaultGenomes("Verdant").appearanceGenome,
		abilityGenome = GeneRegistry.defaultGenomes("Verdant").abilityGenome,
	},
}

for className, instance in Instances do
	instance.baseStats = Definitions[className].baseStats
	instance.acquisition = { source = "FIXTURE", acquiredAt = 1, sourceVersion = 1 }
	instance.breeding =
		{ breedable = false, generation = 0, parentIds = {}, successfulBreedCount = 0 }
	instance.tradable = false
	instance.equipmentIds = {}
end

local function battleStats(stats)
	local value = table.clone(stats)
	value.maxHealth = CombatStats.maxHealth(stats.health)
	return value
end

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
		stats = battleStats(Definitions.Stone.baseStats),
		currentHealth = 358,
		statusEffects = {},
	},
	feral = {
		id = "combatant.team1.feral",
		critterInstanceId = Instances.Feral.id,
		teamId = "team.1",
		slot = 2,
		class = "Feral",
		abilityIds = Definitions.Feral.abilityIds,
		stats = battleStats(Definitions.Feral.baseStats),
		currentHealth = 274,
		statusEffects = {},
	},
	verdant = {
		id = "combatant.team1.verdant",
		critterInstanceId = Instances.Verdant.id,
		teamId = "team.1",
		slot = 3,
		class = "Verdant",
		abilityIds = Definitions.Verdant.abilityIds,
		stats = battleStats(Definitions.Verdant.baseStats),
		currentHealth = 322,
		statusEffects = {},
	},
	enemyStone = {
		id = "combatant.team2.stone",
		critterInstanceId = "owned.enemy.stone",
		teamId = "team.2",
		slot = 1,
		class = "Stone",
		abilityIds = Definitions.Stone.abilityIds,
		stats = battleStats(Definitions.Stone.baseStats),
		currentHealth = 358,
		statusEffects = {},
	},
	enemyFeral = {
		id = "combatant.team2.feral",
		critterInstanceId = "owned.enemy.feral",
		teamId = "team.2",
		slot = 2,
		class = "Feral",
		abilityIds = Definitions.Feral.abilityIds,
		stats = battleStats(Definitions.Feral.baseStats),
		currentHealth = 274,
		statusEffects = {},
	},
	enemyVerdant = {
		id = "combatant.team2.verdant",
		critterInstanceId = "owned.enemy.verdant",
		teamId = "team.2",
		slot = 3,
		class = "Verdant",
		abilityIds = Definitions.Verdant.abilityIds,
		stats = battleStats(Definitions.Verdant.baseStats),
		currentHealth = 322,
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
	commandType = "COMMIT_PLAN",
	id = "command.round1.team1",
	battleId = "battle.fixture",
	actorUserId = 101,
	teamId = Team.id,
	queuedCards = {
		{
			cardInstanceId = CardInstances.stone.id,
			sourceCombatantId = Combatants.stone.id,
			targetCombatantIds = {},
			queueIndex = 1,
		},
		{
			cardInstanceId = CardInstances.feral.id,
			sourceCombatantId = Combatants.feral.id,
			targetCombatantIds = {},
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
