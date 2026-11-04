--!strict

local BattleFactory = {}

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent.Parent.Genetics[name])
	end
	return require(`../Genetics/{name}`)
end

local AbilityResolver = requireGenetics("AbilityResolver")
local GenotypeExpressor = requireGenetics("GenotypeExpressor")
local DeckBuilder = if script ~= nil
	then require(script.Parent.DeckBuilder)
	else require("./DeckBuilder")
local DeckRules = if script ~= nil then require(script.Parent.DeckRules) else require("./DeckRules")
local DeckShuffler = if script ~= nil
	then require(script.Parent.DeckShuffler)
	else require("./DeckShuffler")
local DeckState = if script ~= nil then require(script.Parent.DeckState) else require("./DeckState")
local CombatStats = if script ~= nil
	then require(script.Parent.CombatStats)
	else require("./CombatStats")

local VALID_CLASSES =
	{ Verdant = true, Tide = true, Feral = true, Gale = true, Shade = true, Stone = true }
local VALID_TARGETS = {
	SELF = true,
	ALLY = true,
	ENEMY = true,
	ANY = true,
	FRONT_ENEMY = true,
	ALL_ALLIES = true,
	ALL_ENEMIES = true,
}

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function sortedTeams(teams)
	local result = table.clone(teams)
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function arrayLength(value)
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	local maximum = 0
	for key in value do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	if count ~= maximum then
		return nil
	end
	return count
end

local function create(input, dependencies)
	if type(input) ~= "table" or type(input.battleId) ~= "string" or input.battleId == "" then
		return failure("INVALID_BATTLE_ID", "Battle ID is required", "battleId")
	end
	if
		type(dependencies) ~= "table"
		or dependencies.rng == nil
		or dependencies.criticalRngSeed == nil
		or dependencies.deck == nil
		or dependencies.validator == nil
	then
		return failure(
			"INVALID_DEPENDENCIES",
			"Explicit deck RNG, critical RNG seed, deck, and validator dependencies are required",
			nil
		)
	end
	if arrayLength(input.teams) ~= 2 then
		return failure("INVALID_TEAM_COUNT", "Exactly two teams are required", "teams")
	end

	local rngResult = dependencies.rng.new(input.rngSeed)
	if not rngResult.ok then
		return rngResult
	end
	local rng = rngResult.value
	local criticalRngResult = dependencies.rng.new(dependencies.criticalRngSeed)
	if not criticalRngResult.ok then
		return failure("INVALID_CRITICAL_RNG_SEED", "Critical RNG seed is invalid", nil)
	end
	local criticalRng = criticalRngResult.value
	local rules = dependencies.deckRules or DeckRules.Default
	local deckBuilder = dependencies.deckBuilder or DeckBuilder
	local genotypeExpressor = dependencies.genotypeExpressor or GenotypeExpressor
	local deckShuffler = dependencies.deckShuffler or DeckShuffler
	local teams = sortedTeams(input.teams)
	if teams[1].id == teams[2].id then
		return failure("DUPLICATE_TEAM_ID", "Team IDs must differ", "teams")
	end
	if teams[1].ownerUserId == teams[2].ownerUserId then
		return failure("DUPLICATE_TEAM_OWNER", "Team owners must differ", "teams")
	end

	local validAbilityIds = {}
	for _, definition in input.critterDefinitionsById or {} do
		local validation = dependencies.validator.validateCritterDefinition(definition)
		if not validation.ok then
			return validation
		end
		for _, abilityId in definition.abilityPool or definition.abilityIds do
			validAbilityIds[abilityId] = true
		end
	end

	local cardDefinitionsByAbility = {}
	for _, definition in input.cardDefinitionsById or {} do
		local validation =
			dependencies.validator.validateCardDefinition(definition, validAbilityIds)
		if not validation.ok then
			return validation
		end
		if
			type(definition.id) ~= "string"
			or type(definition.abilityId) ~= "string"
			or not VALID_CLASSES[definition.class]
			or type(definition.energyCost) ~= "number"
			or definition.energyCost % 1 ~= 0
			or definition.energyCost < 0
			or not VALID_TARGETS[definition.targetingRule]
		then
			return failure(
				"INVALID_CARD_DEFINITION",
				"Card definition is malformed",
				"cardDefinitionsById"
			)
		else
			local definitions = cardDefinitionsByAbility[definition.abilityId] or {}
			table.insert(definitions, definition)
			cardDefinitionsByAbility[definition.abilityId] = definitions
		end
	end

	local battleTeams = {}
	local combatants = {}
	local cardInstances = {}
	local teamRoundStates = {}
	local seenCritters = {}

	for teamIndex, teamInput in teams do
		if type(teamInput.id) ~= "string" or teamInput.id == "" then
			return failure("INVALID_TEAM_ID", "Team ID is required", `teams[{teamIndex}].id`)
		end
		if
			type(teamInput.ownerUserId) ~= "number"
			or teamInput.ownerUserId % 1 ~= 0
			or teamInput.ownerUserId <= 0
		then
			return failure(
				"INVALID_OWNER",
				"Team owner must be a positive integer",
				`teams[{teamIndex}].ownerUserId`
			)
		end
		if arrayLength(teamInput.critterInstances) ~= rules.CrittersPerTeam then
			return failure(
				"INVALID_TEAM_SIZE",
				`Each team requires {rules.CrittersPerTeam} Critters`,
				`teams[{teamIndex}].critterInstances`
			)
		end

		local combatantIds = {}
		local deckIds = {}
		local contributions = {}
		for slot, instance in teamInput.critterInstances do
			if type(instance) ~= "table" or type(instance.id) ~= "string" or instance.id == "" then
				return failure(
					"INVALID_CRITTER_INSTANCE",
					"Critter instance is malformed",
					`teams[{teamIndex}].critterInstances[{slot}]`
				)
			end
			if seenCritters[instance.id] then
				return failure(
					"DUPLICATE_CRITTER",
					"Critter instances must be unique",
					`teams[{teamIndex}].critterInstances[{slot}]`
				)
			end
			seenCritters[instance.id] = true
			if instance.ownerUserId ~= teamInput.ownerUserId then
				return failure(
					"CRITTER_OWNER_MISMATCH",
					"Critter owner does not own team",
					`teams[{teamIndex}].critterInstances[{slot}]`
				)
			end
			local instanceValidation = dependencies.validator.validateCritterInstance(
				instance,
				input.critterDefinitionsById,
				validAbilityIds
			)
			if not instanceValidation.ok then
				return instanceValidation
			end
			local critterDefinition = (input.critterDefinitionsById or {})[instance.definitionId]
			if critterDefinition == nil then
				return failure(
					"UNKNOWN_CRITTER_DEFINITION",
					"Critter definition is missing",
					`teams[{teamIndex}].critterInstances[{slot}].definitionId`
				)
			end
			local baseStats = instance.baseStats or critterDefinition.baseStats
			if
				not VALID_CLASSES[critterDefinition.class]
				or type(baseStats) ~= "table"
				or not CombatStats.isValidHealth(baseStats.health)
			then
				return failure(
					"INVALID_CRITTER_DEFINITION",
					"Critter definition is malformed",
					instance.definitionId
				)
			end
			local expression = genotypeExpressor.express(
				instance.appearanceGenome,
				instance.abilityGenome,
				critterDefinition.class
			)
			if not expression.ok then
				return expression
			end
			local abilities = expression.value.phenotype.abilities.abilityIds
			local seenAbilities = {}
			local definitionIds = {}
			for _, abilityId in abilities do
				if seenAbilities[abilityId] then
					return failure(
						"DUPLICATE_ABILITY_ID",
						"Critter abilities must be unique",
						`teams[{teamIndex}].critterInstances[{slot}].abilityGenome.slots`
					)
				end
				seenAbilities[abilityId] = true
				local matching = cardDefinitionsByAbility[abilityId]
				if matching == nil or #matching == 0 then
					return failure(
						"MISSING_CARD_DEFINITION",
						"Ability needs one card definition",
						abilityId
					)
				end
				if #matching ~= 1 then
					return failure(
						"AMBIGUOUS_CARD_DEFINITION",
						"Ability has multiple card definitions",
						abilityId
					)
				end
				local cardDefinition = matching[1]
				if
					cardDefinition.class ~= critterDefinition.class
					and AbilityResolver.cardClassFor(abilityId, critterDefinition.class)
						~= cardDefinition.class
				then
					return failure(
						"INVALID_CLASS_REFERENCE",
						"Card class is not expressible by source Critter",
						abilityId
					)
				end
				table.insert(definitionIds, cardDefinition.id)
			end
			table.insert(contributions, {
				sourceCritterInstanceId = instance.id,
				definitionIds = definitionIds,
			})

			local combatantId = `combatant:t{teamIndex}:s{slot}`
			table.insert(combatantIds, combatantId)
			local battleStats = table.clone(baseStats)
			battleStats.maxHealth = CombatStats.maxHealth(baseStats.health)
			table.insert(combatants, {
				id = combatantId,
				critterInstanceId = instance.id,
				teamId = teamInput.id,
				slot = slot,
				class = critterDefinition.class,
				abilityIds = table.clone(abilities),
				stats = battleStats,
				currentHealth = battleStats.maxHealth,
				statusEffects = {},
				shields = {},
			})
		end

		local built = deckBuilder.build(teamIndex, contributions, rules)
		if not built.ok then
			return built
		end
		for _, cardInstance in built.value.cardInstances do
			table.insert(cardInstances, cardInstance)
		end
		deckIds = built.value.deckIds

		if #deckIds ~= rules.TeamDeckSize then
			return failure(
				"INVALID_DECK_SIZE",
				`Team deck must contain {rules.TeamDeckSize} cards`,
				teamInput.id
			)
		end
		rng, deckIds = deckShuffler.shuffle(rng, deckIds, dependencies.rng)
		local zones = DeckState.create(deckIds)
		local function shuffle(currentRng, values)
			return deckShuffler.shuffle(currentRng, values, dependencies.rng)
		end
		local drawResult = dependencies.deck.draw(
			zones,
			rules.OpeningHandSize,
			rng,
			shuffle,
			{ maxHandSize = rules.MaxHandSize }
		)
		if not drawResult.ok then
			return drawResult
		end
		rng = drawResult.value.rng

		table.insert(battleTeams, {
			id = teamInput.id,
			ownerUserId = teamInput.ownerUserId,
			teamIndex = teamIndex,
			combatantIds = combatantIds,
		})
		table.insert(teamRoundStates, {
			teamId = teamInput.id,
			energy = 3,
			reservedEnergy = 0,
			drawPileCardInstanceIds = drawResult.value.zones.drawPileCardInstanceIds,
			handCardInstanceIds = drawResult.value.zones.handCardInstanceIds,
			discardCardInstanceIds = drawResult.value.zones.discardCardInstanceIds,
			removedCardInstanceIds = drawResult.value.zones.removedCardInstanceIds,
			lastDrawnRound = 1,
			queuedCards = {},
			planVersion = 0,
			committed = false,
		})
	end

	return {
		ok = true,
		value = {
			schemaVersion = 3,
			id = input.battleId,
			rngSeed = input.rngSeed,
			rng = rng,
			criticalRng = criticalRng,
			stateVersion = 1,
			eventVersion = 0,
			lastResolvedRound = 0,
			phase = "PLANNING",
			roundNumber = 1,
			teams = battleTeams,
			combatants = combatants,
			cardInstances = cardInstances,
			teamRoundStates = teamRoundStates,
		},
	}
end

BattleFactory.create = create
return table.freeze(BattleFactory)
