--!strict

local function requireGeneRegistry()
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared.Genetics.GeneRegistry)
	end
	return require("../../shared/Genetics/GeneRegistry")
end

local GeneRegistry = requireGeneRegistry()

local definitions = {
	stone = {
		schemaVersion = 1,
		id = "critter.stone.bastion",
		displayName = "Bastion",
		class = "Stone",
		baseStats = { maxHealth = 120, attack = 20, defense = 35, speed = 10 },
		abilityIds = { "stone.guard", "stone.bulwark", "stone.quake", "stone.slam" },
	},
	feral = {
		schemaVersion = 1,
		id = "critter.feral.ravager",
		displayName = "Ravager",
		class = "Feral",
		baseStats = { maxHealth = 80, attack = 42, defense = 12, speed = 30 },
		abilityIds = { "feral.strike", "feral.pounce", "feral.frenzy", "feral.rend" },
	},
	verdant = {
		schemaVersion = 1,
		id = "critter.verdant.bloom",
		displayName = "Bloom",
		class = "Verdant",
		baseStats = { maxHealth = 95, attack = 18, defense = 20, speed = 20 },
		abilityIds = { "verdant.mend", "verdant.renew", "verdant.grove", "verdant.seed" },
	},
}

local cardDefinitions = {
	stone = {
		schemaVersion = 1,
		id = "card.stone.guard",
		displayName = "Granite Guard",
		class = "Stone",
		abilityId = "stone.guard",
		energyCost = 1,
		targetingRule = "SELF",
	},
	feral = {
		schemaVersion = 1,
		id = "card.feral.strike",
		displayName = "Feral Strike",
		class = "Feral",
		abilityId = "feral.strike",
		energyCost = 2,
		targetingRule = "ENEMY",
	},
	verdant = {
		schemaVersion = 1,
		id = "card.verdant.mend",
		displayName = "Verdant Mend",
		class = "Verdant",
		abilityId = "verdant.mend",
		energyCost = 1,
		targetingRule = "ALLY",
	},
}

local critterInstancesById = {}
local combatants = {}
local teams = {}

for teamIndex = 1, 2 do
	local teamId = `team.{teamIndex}`
	local combatantIds = {}
	for slot, key in { "stone", "feral", "verdant" } do
		local definition = definitions[key]
		local instanceId = `owned.team{teamIndex}.{key}`
		local combatantId = `combatant.team{teamIndex}.{key}`
		local genomes = GeneRegistry.defaultGenomes(definition.class)
		assert(genomes ~= nil, `Missing mock genomes for {definition.class}`)
		critterInstancesById[instanceId] = {
			schemaVersion = 2,
			id = instanceId,
			definitionId = definition.id,
			ownerUserId = 100 + teamIndex,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
		}
		table.insert(combatants, {
			id = combatantId,
			critterInstanceId = instanceId,
			teamId = teamId,
			slot = slot,
			class = definition.class,
			abilityIds = definition.abilityIds,
			stats = definition.baseStats,
			currentHealth = definition.baseStats.maxHealth - (slot - 1) * 5,
			statusEffects = {},
		})
		table.insert(combatantIds, combatantId)
	end
	table.insert(teams, { id = teamId, ownerUserId = 100 + teamIndex, combatantIds = combatantIds })
end

local cardInstancesById = {}
local handIds = {}
for _, key in { "stone", "feral", "verdant" } do
	for copy = 1, 2 do
		local id = `hand.{key}.{copy}`
		cardInstancesById[id] = {
			id = id,
			definitionId = cardDefinitions[key].id,
			sourceCritterInstanceId = `owned.team1.{key}`,
		}
		table.insert(handIds, id)
	end
end

local function byId(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

local function deepClone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = table.clone(value)
	for key, child in result do
		result[key] = deepClone(child)
	end
	return result
end

local function createSnapshot()
	return deepClone({
		revision = 1,
		viewerTeamId = "team.1",
		battleState = {
			schemaVersion = 1,
			id = "battle.presentation.demo",
			rngSeed = 3001,
			phase = "PLANNING",
			roundNumber = 1,
			teams = teams,
			combatants = combatants,
			teamRoundStates = {
				{ teamId = "team.1", energy = 3, handCardInstanceIds = handIds, committed = false },
				{ teamId = "team.2", energy = 3, handCardInstanceIds = {}, committed = false },
			},
		},
		critterInstancesById = critterInstancesById,
		critterDefinitionsById = byId({ definitions.stone, definitions.feral, definitions.verdant }),
		cardInstancesById = cardInstancesById,
		cardDefinitionsById = byId({
			cardDefinitions.stone,
			cardDefinitions.feral,
			cardDefinitions.verdant,
		}),
		shieldsByCombatantId = { ["combatant.team1.stone"] = 12, ["combatant.team2.stone"] = 8 },
		initiativeCombatantIds = {
			"combatant.team1.feral",
			"combatant.team2.feral",
			"combatant.team1.verdant",
			"combatant.team2.verdant",
			"combatant.team1.stone",
			"combatant.team2.stone",
		},
		visibleQueuedCards = {},
	})
end

return table.freeze({ createSnapshot = createSnapshot })
