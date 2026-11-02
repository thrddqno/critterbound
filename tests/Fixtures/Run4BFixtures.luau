--!strict

-- Run 4B fixtures build a complete, deterministic battle state without using the deck
-- randomizer. Tests can mutate the returned state before resolving, which keeps combat
-- assertions focused on resolution rules rather than opening hands.

local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[clone(key)] = clone(child)
	end
	return result
end

local Classes = {
	Verdant = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 20,
		skill = 3,
		resolve = 3,
	},
	Tide = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 15,
		skill = 4,
		resolve = 4,
	},
	Feral = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 30,
		skill = 2,
		resolve = 2,
	},
	Gale = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 25,
		skill = 5,
		resolve = 5,
	},
	Shade = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 18,
		skill = 6,
		resolve = 6,
	},
	Stone = {
		maxHealth = 100,
		attack = 20,
		defense = 20,
		speed = 10,
		skill = 1,
		resolve = 1,
	},
}

local function definition(id, className, targetingRule, effects, energyCost)
	return {
		schemaVersion = 1,
		id = id,
		displayName = id,
		class = className,
		abilityId = `ability.{id}`,
		energyCost = energyCost or 1,
		targetingRule = targetingRule,
		effects = effects,
	}
end

local CardDefinitions = {
	Attack = definition("card.run4b.feral.attack", "Feral", "ENEMY", {
		{ kind = "DAMAGE", amount = 30 },
	}),
	Heal = definition("card.run4b.verdant.heal", "Verdant", "ALLY", {
		{ kind = "HEAL", amount = 30 },
	}),
	SelfHeal = definition("card.run4b.verdant.self-heal", "Verdant", "SELF", {
		{ kind = "HEAL", amount = 15 },
	}),
	Shield = definition("card.run4b.stone.shield", "Stone", "SELF", {
		{ kind = "SHIELD", amount = 20 },
	}),
	Poison = definition("card.run4b.shade.poison", "Shade", "ENEMY", {
		{ kind = "STATUS", statusId = "POISON", magnitude = 5, duration = 2 },
	}),
	AttackUp = definition("card.run4b.feral.attack-up", "Feral", "SELF", {
		{ kind = "STATUS", statusId = "ATTACK_UP", magnitude = 10, duration = 2 },
	}),
	AttackDown = definition("card.run4b.shade.attack-down", "Shade", "ENEMY", {
		{ kind = "STATUS", statusId = "ATTACK_DOWN", magnitude = 10, duration = 2 },
	}),
	SpeedUp = definition("card.run4b.gale.speed-up", "Gale", "SELF", {
		{ kind = "STATUS", statusId = "SPEED_UP", magnitude = 25, duration = 2 },
	}),
	SpeedDown = definition("card.run4b.tide.speed-down", "Tide", "ENEMY", {
		{ kind = "STATUS", statusId = "SPEED_DOWN", magnitude = 10, duration = 2 },
	}),
	FrontAttack = definition("card.run4b.stone.front-attack", "Stone", "FRONT_ENEMY", {
		{ kind = "DAMAGE", amount = 20 },
	}),
	AllEnemies = definition("card.run4b.verdant.all-enemies", "Verdant", "ALL_ENEMIES", {
		{ kind = "DAMAGE", amount = 10 },
	}),
	AllAlliesHeal = definition("card.run4b.verdant.all-allies", "Verdant", "ALL_ALLIES", {
		{ kind = "HEAL", amount = 10 },
	}),
	ZeroDamage = definition("card.run4b.stone.zero", "Stone", "ENEMY", {
		{ kind = "DAMAGE", amount = 0 },
	}),
}

local function indexById(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

local CardDefinitionsById = indexById(CardDefinitions)

local function findTeamState(state, teamId)
	for _, teamState in state.teamRoundStates do
		if teamState.teamId == teamId then
			return teamState
		end
	end
	return nil
end

local function findCombatant(state, combatantId)
	for _, combatant in state.combatants do
		if combatant.id == combatantId then
			return combatant
		end
	end
	return nil
end

local function createState(options)
	options = options or {}
	local rng = DeterministicRng.new(options.rngSeed or 4242)
	assert(rng.ok, "Fixture RNG seed must be valid")

	local teamSpecs = options.teams
		or {
			{
				id = "team.1",
				ownerUserId = 101,
				teamIndex = 1,
				classes = { "Stone", "Feral", "Verdant" },
			},
			{
				id = "team.2",
				ownerUserId = 202,
				teamIndex = 2,
				classes = { "Tide", "Gale", "Shade" },
			},
		}

	local state = {
		schemaVersion = 2,
		id = options.battleId or "battle.run4b.fixture",
		rngSeed = options.rngSeed or 4242,
		rng = rng.value,
		stateVersion = 1,
		eventVersion = 0,
		lastResolvedRound = 0,
		phase = options.phase or "COMMITTED",
		roundNumber = options.roundNumber or 1,
		teams = {},
		combatants = {},
		cardInstances = {},
		teamRoundStates = {},
	}

	for _, teamSpec in teamSpecs do
		local combatantIds = {}
		for slot, className in teamSpec.classes do
			local stats = clone(Classes[className])
			if teamSpec.stats ~= nil and teamSpec.stats[slot] ~= nil then
				for key, value in teamSpec.stats[slot] do
					stats[key] = value
				end
			end

			local combatantId = `combatant:t{teamSpec.teamIndex}:s{slot}`
			local health = if teamSpec.health ~= nil and teamSpec.health[slot] ~= nil
				then teamSpec.health[slot]
				else stats.maxHealth
			table.insert(state.combatants, {
				id = combatantId,
				critterInstanceId = `owned:t{teamSpec.teamIndex}:s{slot}`,
				teamId = teamSpec.id,
				slot = slot,
				class = className,
				abilityIds = {},
				stats = stats,
				currentHealth = health,
				statusEffects = {},
				shields = {},
			})
			table.insert(combatantIds, combatantId)
		end

		table.insert(state.teams, {
			id = teamSpec.id,
			ownerUserId = teamSpec.ownerUserId,
			teamIndex = teamSpec.teamIndex,
			combatantIds = combatantIds,
		})
		table.insert(state.teamRoundStates, {
			teamId = teamSpec.id,
			energy = teamSpec.energy or options.energy or 3,
			reservedEnergy = 0,
			drawPileCardInstanceIds = teamSpec.drawPileCardInstanceIds or {},
			handCardInstanceIds = teamSpec.handCardInstanceIds or {},
			discardCardInstanceIds = teamSpec.discardCardInstanceIds or {},
			queuedCards = {},
			planVersion = 0,
			committed = options.committed ~= false,
		})
	end

	if options.cardInstances ~= nil then
		for _, card in options.cardInstances do
			table.insert(state.cardInstances, clone(card))
		end
	end

	return state
end

local function makeCard(state, cardId, definitionId, sourceCombatantId)
	local source = findCombatant(state, sourceCombatantId)
	assert(source ~= nil, "Card source combatant must exist")
	table.insert(state.cardInstances, {
		id = cardId,
		definitionId = definitionId,
		sourceCritterInstanceId = source.critterInstanceId,
	})
	return cardId
end

local function addHand(state, teamId, cardId)
	local teamState = findTeamState(state, teamId)
	assert(teamState ~= nil, "Team state must exist")
	table.insert(teamState.handCardInstanceIds, cardId)
	return cardId
end

local function queue(state, teamId, cardId, sourceCombatantId, targetCombatantIds)
	local teamState = findTeamState(state, teamId)
	assert(teamState ~= nil, "Team state must exist")
	local queueIndex = 1
	for _, queued in teamState.queuedCards do
		if queued.sourceCombatantId == sourceCombatantId then
			queueIndex += 1
		end
	end
	table.insert(teamState.queuedCards, {
		cardInstanceId = cardId,
		sourceCombatantId = sourceCombatantId,
		targetCombatantIds = clone(targetCombatantIds or {}),
		queueIndex = queueIndex,
	})
	return cardId
end

local function commit(state)
	for _, teamState in state.teamRoundStates do
		teamState.committed = true
	end
	state.phase = "COMMITTED"
	return state
end

local function dependencies(overrides)
	local result = {
		cardDefinitionsById = CardDefinitionsById,
	}
	for key, value in overrides or {} do
		result[key] = value
	end
	return result
end

return {
	Classes = Classes,
	CardDefinitions = CardDefinitions,
	CardDefinitionsById = CardDefinitionsById,
	createState = createState,
	indexById = indexById,
	findTeamState = findTeamState,
	findCombatant = findCombatant,
	makeCard = makeCard,
	addHand = addHand,
	queue = queue,
	commit = commit,
	dependencies = dependencies,
	clone = clone,
}
