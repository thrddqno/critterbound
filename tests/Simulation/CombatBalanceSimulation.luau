--!strict

-- Offline Run 5 analysis harness. Uses production battle construction, planning, resolution,
-- definitions, deck, and RNG modules without adding simulation behavior to production code.

local BattleFactory = require("../../src/shared/Battle/BattleFactory")
local BattlePlan = require("../../src/shared/Battle/BattlePlan")
local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
local Deck = require("../../src/shared/Battle/Deck")
local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
local DomainValidator = require("../../src/shared/Validation/DomainValidator")
local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
local RoundResolver = require("../../src/shared/Battle/RoundResolver")
local TrainingPlanner = require("../../src/server/AI/TrainingPlanner")

local MODULUS = 2_147_483_647
local MAX_ROUNDS = 100

local MATCHUPS = {
	{
		id = "offense_vs_offense",
		name = "Offensive vs offensive",
		a = { name = "Offense A", classes = { "Feral", "Shade", "Gale" } },
		b = { name = "Offense B", classes = { "Shade", "Feral", "Gale" } },
	},
	{
		id = "offense_vs_defense",
		name = "Offensive vs defensive",
		a = { name = "Offensive", classes = { "Feral", "Shade", "Gale" } },
		b = { name = "Defensive", classes = { "Stone", "Tide", "Gale" } },
	},
	{
		id = "poison_vs_shield",
		name = "Poison-focused vs shield-focused",
		a = { name = "Poison", classes = { "Shade", "Verdant", "Feral" } },
		b = { name = "Shield", classes = { "Stone", "Gale", "Tide" } },
	},
	{
		id = "high_speed_vs_low_speed",
		name = "High-Speed vs low-Speed",
		a = { name = "High-Speed", classes = { "Feral", "Gale", "Shade" } },
		b = { name = "Low-Speed", classes = { "Stone", "Tide", "Verdant" } },
	},
	{
		id = "high_morale_vs_low_morale",
		name = "High-Morale vs low-Morale",
		a = { name = "High-Morale", classes = { "Stone", "Verdant", "Tide" } },
		b = { name = "Low-Morale", classes = { "Feral", "Gale", "Shade" } },
	},
	{
		id = "high_skill_vs_ordinary",
		name = "High-Skill combo vs ordinary",
		a = { name = "High-Skill", classes = { "Gale", "Shade", "Gale" } },
		b = { name = "Ordinary", classes = { "Stone", "Feral", "Verdant" } },
	},
	{
		id = "mixed_vs_specialized",
		name = "Mixed-class vs specialized",
		a = { name = "Mixed", classes = { "Stone", "Feral", "Verdant" } },
		b = { name = "Specialized Feral", classes = { "Feral", "Feral", "Feral" } },
	},
	{
		id = "healing_vs_burst",
		name = "Healing-heavy vs burst-damage",
		a = { name = "Healing", classes = { "Verdant", "Tide", "Verdant" } },
		b = { name = "Burst", classes = { "Shade", "Feral", "Gale" } },
	},
}

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

local function makeInstance(className: string, ownerUserId: number, id: string)
	local definition = CritterCatalog.getByClass(className)
	assert(definition ~= nil, `Unknown simulation class {className}`)
	local genomes = GeneRegistry.defaultGenomes(className)
	assert(genomes ~= nil, `Missing default genomes for {className}`)
	return {
		schemaVersion = 3,
		id = id,
		definitionId = definition.id,
		ownerUserId = ownerUserId,
		appearanceGenome = genomes.appearanceGenome,
		abilityGenome = genomes.abilityGenome,
		baseStats = clone(definition.baseStats),
		acquisition = { source = "TRAINING", acquiredAt = 0, sourceVersion = 1 },
		breeding = {
			breedable = false,
			generation = 0,
			parentIds = {},
			successfulBreedCount = 0,
		},
		tradable = false,
		equipmentIds = {},
	}
end

local function teamInput(teamId: string, ownerUserId: number, classes: { string })
	local instances = {}
	for slot, className in classes do
		table.insert(instances, makeInstance(className, ownerUserId, `{teamId}:{slot}:{className}`))
	end
	return { id = teamId, ownerUserId = ownerUserId, critterInstances = instances }
end

local function factoryDependencies(criticalSeed: number)
	return {
		rng = DeterministicRng,
		criticalRngSeed = criticalSeed,
		deck = Deck,
		validator = DomainValidator,
	}
end

local function indexById(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

local function teamState(state, teamId: string)
	for _, value in state.teamRoundStates do
		if value.teamId == teamId then
			return value
		end
	end
	error(`Missing team state {teamId}`)
end

local function emptyRoleMetrics()
	return {
		wins = 0,
		hpDamage = 0,
		shieldAbsorbed = 0,
		healing = 0,
		poisonDamage = 0,
		criticalHits = 0,
		criticalRolls = 0,
		skillComboActivations = 0,
		energySpent = 0,
		unusedEnergy = 0,
		cardsDrawn = 0,
		partialDraws = 0,
		drawOpportunities = 0,
		handCapBlocks = 0,
		blockedCards = 0,
	}
end

local function emptyAggregate(matchup)
	return {
		id = matchup.id,
		name = matchup.name,
		aName = matchup.a.name,
		bName = matchup.b.name,
		aClasses = table.concat(matchup.a.classes, "/"),
		bClasses = table.concat(matchup.b.classes, "/"),
		matches = 0,
		draws = 0,
		rounds = {},
		shortest = math.huge,
		longest = 0,
		firstDefeatRounds = {},
		winnerRemainingHp = 0,
		timeouts = 0,
		failures = 0,
		stalemates = 0,
		zeroProgressRounds = 0,
		maxZeroProgressStreak = 0,
		conservationErrors = 0,
		sequenceErrors = 0,
		shieldOrderErrors = 0,
		statusExpiryErrors = 0,
		replayErrors = 0,
		bloodMoonDamage = 0,
		environmentalDefeats = 0,
		mutualDestructions = 0,
		reachedRound10 = 0,
		endedRounds10To14 = 0,
		sideOneWins = 0,
		sideTwoWins = 0,
		a = emptyRoleMetrics(),
		b = emptyRoleMetrics(),
	}
end

local function stableHash(hash: number, text: string): number
	for index = 1, #text do
		hash = (hash * 31 + string.byte(text, index)) % MODULUS
	end
	return hash
end

local function eventHash(hash: number, event): number
	hash = stableHash(hash, event.kind)
	hash = stableHash(hash, tostring(event.sequence))
	hash = stableHash(hash, tostring(event.roundNumber))
	hash = stableHash(hash, tostring(event.sourceCombatantId))
	for _, targetId in event.targetCombatantIds or {} do
		hash = stableHash(hash, targetId)
	end
	local keys = {}
	for key in event.payload or {} do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local value = event.payload[key]
		if type(value) ~= "table" then
			hash = stableHash(hash, `{key}={tostring(value)}`)
		end
	end
	return hash
end

local function roleForTeam(teamId: string, aTeamId: string): string
	return if teamId == aTeamId then "a" else "b"
end

local function validateConservation(state): boolean
	local combatantsByCritter = {}
	for _, combatant in state.combatants do
		combatantsByCritter[combatant.critterInstanceId] = combatant.teamId
	end
	local expected = {}
	for _, card in state.cardInstances do
		local ownerTeamId = combatantsByCritter[card.sourceCritterInstanceId]
		if ownerTeamId == nil then
			return false
		end
		expected[ownerTeamId] = (expected[ownerTeamId] or 0) + 1
	end
	for _, roundState in state.teamRoundStates do
		local seen = {}
		local count = 0
		for _, zone in
			{
				roundState.drawPileCardInstanceIds,
				roundState.handCardInstanceIds,
				roundState.discardCardInstanceIds,
				roundState.removedCardInstanceIds,
			}
		do
			for _, cardId in zone or {} do
				if seen[cardId] then
					return false
				end
				seen[cardId] = true
				count += 1
			end
		end
		if count ~= expected[roundState.teamId] then
			return false
		end
	end
	return true
end

local function validateExpiredState(state): boolean
	if state.phase == "FINISHED" then
		return true
	end
	local completedRound = state.roundNumber - 1
	for _, combatant in state.combatants do
		for _, status in combatant.statusEffects or {} do
			if status.expiresAtRound <= completedRound then
				return false
			end
		end
		for _, shield in combatant.shields or {} do
			if (shield.expiresAtRound or completedRound) <= completedRound then
				return false
			end
		end
	end
	return true
end

local function totalHp(state): number
	local result = 0
	for _, combatant in state.combatants do
		result += combatant.currentHealth
	end
	return result
end

local function winningHp(state, winnerTeamId: string?): number
	local result = 0
	if winnerTeamId == nil then
		return result
	end
	for _, combatant in state.combatants do
		if combatant.teamId == winnerTeamId then
			result += combatant.currentHealth
		end
	end
	return result
end

local function queueAndCommit(state, teamId: string, definitions, roleMetrics)
	local planned = TrainingPlanner.plan(state, teamId, definitions)
	if not planned.ok then
		return nil, "PLAN_FAILED"
	end
	for _, request in planned.value.requests do
		local queued = BattlePlan.queueCard(state, teamId, request, definitions)
		if not queued.ok then
			return nil, "QUEUE_FAILED"
		end
		state = queued.value
	end

	local counts = {}
	local beforeEnergy = teamState(state, teamId).energy
	for _, queued in teamState(state, teamId).queuedCards do
		counts[queued.sourceCombatantId] = (counts[queued.sourceCombatantId] or 0) + 1
	end
	for _, count in counts do
		if count >= 3 then
			roleMetrics.skillComboActivations += 1
		end
	end

	local committed = BattlePlan.commitPlan(state, teamId, definitions)
	if not committed.ok then
		return nil, "COMMIT_FAILED"
	end
	state = committed.value
	local afterEnergy = teamState(state, teamId).energy
	roleMetrics.energySpent += beforeEnergy - afterEnergy
	roleMetrics.unusedEnergy += afterEnergy
	return state, nil
end

local function processDrawMetrics(state, teamId: string, metrics)
	local roundState = teamState(state, teamId)
	local draw = roundState.lastDrawResult
	if draw == nil then
		return
	end
	metrics.drawOpportunities += 1
	metrics.cardsDrawn += draw.drawnCount
	if draw.isPartial then
		metrics.partialDraws += 1
	end
	if draw.drawnCount < draw.requestedCount and #roundState.handCardInstanceIds >= 9 then
		metrics.handCapBlocks += 1
		metrics.blockedCards += draw.requestedCount - draw.drawnCount
	end
end

local function processEvents(
	events,
	combatantsById,
	aTeamId: string,
	aggregate,
	traceHash: number,
	firstDefeatRound: number?
)
	local previousSequence = nil
	local initiativeSeen = false
	local roundHpProgress = 0
	for _, event in events do
		traceHash = eventHash(traceHash, event)
		if previousSequence ~= nil and event.sequence ~= previousSequence + 1 then
			aggregate.sequenceErrors += 1
		end
		previousSequence = event.sequence
		if event.kind == "INITIATIVE_DETERMINED" then
			initiativeSeen = true
		elseif event.kind == "SHIELD_PREPARED" and initiativeSeen then
			aggregate.shieldOrderErrors += 1
		end

		local source = if event.sourceCombatantId ~= nil
			then combatantsById[event.sourceCombatantId]
			else nil
		local sourceRole = if source ~= nil then roleForTeam(source.teamId, aTeamId) else nil
		if event.kind == "DAMAGE_APPLIED" and sourceRole ~= nil then
			local metrics = aggregate[sourceRole]
			metrics.hpDamage += event.payload.hpDamage or 0
			metrics.criticalRolls += 1
			if event.payload.isCritical then
				metrics.criticalHits += 1
			end
			roundHpProgress += event.payload.hpDamage or 0
		elseif event.kind == "SHIELD_ABSORBED" then
			local target = combatantsById[event.payload.targetCombatantId]
			if target ~= nil then
				aggregate[roleForTeam(target.teamId, aTeamId)].shieldAbsorbed += event.payload.absorbed or 0
			end
		elseif event.kind == "HEAL_APPLIED" and sourceRole ~= nil then
			aggregate[sourceRole].healing += event.payload.restored or 0
		elseif event.kind == "STATUS_TICKED" and event.payload.statusId == "POISON" then
			local poisonRole = sourceRole
			if poisonRole ~= nil then
				local actual = math.max(
					0,
					(event.payload.healthBefore or 0) - (event.payload.healthAfter or 0)
				)
				aggregate[poisonRole].poisonDamage += actual
				roundHpProgress += actual
			end
		elseif event.kind == "BLOOD_MOON_DAMAGE" then
			aggregate.bloodMoonDamage += event.payload.hpDamage or 0
			roundHpProgress += event.payload.hpDamage or 0
			if event.payload.defeated then
				aggregate.environmentalDefeats += 1
			end
		elseif event.kind == "CRITTER_DEFEATED" and firstDefeatRound == nil then
			firstDefeatRound = event.roundNumber
		end
	end
	return traceHash, firstDefeatRound, roundHpProgress
end

local function simulate(
	matchup,
	seed: number,
	swapped: boolean,
	aggregate,
	captureEvents: boolean?,
	bloodMoonConfig: any?
)
	local aTeamId = if swapped then "team.b" else "team.a"
	local aConfig = matchup.a
	local bConfig = matchup.b
	local teamAConfig = if swapped then bConfig else aConfig
	local teamBConfig = if swapped then aConfig else bConfig
	local criticalSeed = (seed * 48_271 + 97_531) % (MODULUS - 1) + 1
	local created = BattleFactory.create({
		battleId = `simulation:{matchup.id}:{seed}:{if swapped then "swap" else "base"}`,
		rngSeed = seed,
		teams = {
			teamInput("team.a", 10_001, teamAConfig.classes),
			teamInput("team.b", 10_002, teamBConfig.classes),
		},
		critterDefinitionsById = CritterCatalog.allById(),
		cardDefinitionsById = CardCatalog.allById(),
	}, factoryDependencies(criticalSeed))
	if not created.ok then
		return { ok = false, error = "FACTORY_FAILED" }
	end

	local state = created.value
	local definitions = CardCatalog.allById()
	local traceHash = 17
	local captured = if captureEvents then {} else nil
	local firstDefeatRound = nil
	local zeroProgressStreak = 0
	local maximumZeroProgressStreak = 0
	local roundsResolved = 0
	local terminalOutcome = nil
	local localErrors = { conservation = 0, sequence = 0, shieldOrder = 0, expiry = 0 }

	while state.phase ~= "FINISHED" and roundsResolved < MAX_ROUNDS do
		local beforeSequenceErrors = aggregate.sequenceErrors
		local beforeShieldErrors = aggregate.shieldOrderErrors
		local nextState, planError =
			queueAndCommit(state, "team.a", definitions, aggregate[roleForTeam("team.a", aTeamId)])
		if planError ~= nil then
			return { ok = false, error = planError }
		end
		state = nextState
		nextState, planError =
			queueAndCommit(state, "team.b", definitions, aggregate[roleForTeam("team.b", aTeamId)])
		if planError ~= nil then
			return { ok = false, error = planError }
		end
		state = nextState

		local hpBefore = totalHp(state)
		local combatantsById = indexById(state.combatants)
		local resolved = RoundResolver.resolveRound(state, {
			cardDefinitionsById = definitions,
			deck = Deck,
			economy = RoundEconomy,
			rng = DeterministicRng,
			drawPerRound = 3,
			bloodMoonConfig = bloodMoonConfig,
		})
		if not resolved.ok then
			return { ok = false, error = "RESOLUTION_FAILED" }
		end
		state = resolved.value.state
		terminalOutcome = resolved.value.matchOutcome or terminalOutcome
		roundsResolved += 1
		local roundHpProgress
		traceHash, firstDefeatRound, roundHpProgress = processEvents(
			resolved.value.events,
			combatantsById,
			aTeamId,
			aggregate,
			traceHash,
			firstDefeatRound
		)
		if captured ~= nil then
			for _, event in resolved.value.events do
				table.insert(captured, clone(event))
			end
		end
		localErrors.sequence += aggregate.sequenceErrors - beforeSequenceErrors
		localErrors.shieldOrder += aggregate.shieldOrderErrors - beforeShieldErrors

		if roundHpProgress == 0 and totalHp(state) >= hpBefore then
			zeroProgressStreak += 1
			aggregate.zeroProgressRounds += 1
		else
			zeroProgressStreak = 0
		end
		maximumZeroProgressStreak = math.max(maximumZeroProgressStreak, zeroProgressStreak)

		if not validateConservation(state) then
			aggregate.conservationErrors += 1
			localErrors.conservation += 1
		end
		if not validateExpiredState(state) then
			aggregate.statusExpiryErrors += 1
			localErrors.expiry += 1
		end
		if state.phase ~= "FINISHED" then
			processDrawMetrics(state, "team.a", aggregate[roleForTeam("team.a", aTeamId)])
			processDrawMetrics(state, "team.b", aggregate[roleForTeam("team.b", aTeamId)])
		end
	end

	local outcome = terminalOutcome
	if state.phase == "FINISHED" then
		for _, event in captured or {} do
			if event.kind == "MATCH_COMPLETED" then
				outcome = event.payload
			end
		end
		if outcome == nil then
			-- Event capture is optional; derive terminal winner from living combatants.
			local living = {}
			for _, combatant in state.combatants do
				if combatant.currentHealth > 0 then
					living[combatant.teamId] = true
				end
			end
			local winner = nil
			local count = 0
			for teamId in living do
				winner = teamId
				count += 1
			end
			outcome = { isDraw = count ~= 1, winnerTeamId = if count == 1 then winner else nil }
		end
	end

	return {
		ok = true,
		state = state,
		outcome = outcome,
		rounds = roundsResolved,
		firstDefeatRound = firstDefeatRound,
		traceHash = traceHash,
		events = captured,
		maximumZeroProgressStreak = maximumZeroProgressStreak,
		localErrors = localErrors,
		aTeamId = aTeamId,
	}
end

local function percentile(sorted: { number }, fraction: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function mean(values: { number }): number
	local total = 0
	for _, value in values do
		total += value
	end
	return if #values == 0 then 0 else total / #values
end

local function wilson(wins: number, total: number): (number, number)
	if total == 0 then
		return 0, 0
	end
	local z = 1.96
	local p = wins / total
	local denominator = 1 + z * z / total
	local center = (p + z * z / (2 * total)) / denominator
	local margin = z * math.sqrt((p * (1 - p) + z * z / (4 * total)) / total) / denominator
	return math.max(0, center - margin), math.min(1, center + margin)
end

local function finalize(aggregate)
	table.sort(aggregate.rounds)
	table.sort(aggregate.firstDefeatRounds)
	aggregate.averageRounds = mean(aggregate.rounds)
	aggregate.medianRounds = percentile(aggregate.rounds, 0.5)
	aggregate.p90Rounds = percentile(aggregate.rounds, 0.9)
	aggregate.averageFirstDefeatRound = mean(aggregate.firstDefeatRounds)
	aggregate.medianFirstDefeatRound = percentile(aggregate.firstDefeatRounds, 0.5)
	aggregate.averageWinnerRemainingHp = if aggregate.matches == aggregate.draws
		then 0
		else aggregate.winnerRemainingHp / (aggregate.matches - aggregate.draws)
	aggregate.aWinRate = aggregate.a.wins / math.max(1, aggregate.matches)
	aggregate.bWinRate = aggregate.b.wins / math.max(1, aggregate.matches)
	aggregate.drawRate = aggregate.draws / math.max(1, aggregate.matches)
	aggregate.aCiLow, aggregate.aCiHigh = wilson(aggregate.a.wins, aggregate.matches)
	aggregate.bCiLow, aggregate.bCiHigh = wilson(aggregate.b.wins, aggregate.matches)
	return aggregate
end

local function runWithOptions(matchCount: number, options: any?)
	assert(matchCount >= 2 and matchCount % 2 == 0, "Match count must be an even integer >= 2")
	local results = {}
	local pairs = matchCount // 2
	for matchupIndex, matchup in MATCHUPS do
		local aggregate = emptyAggregate(matchup)
		for pairIndex = 1, pairs do
			local seed = ((matchupIndex * 1_000_003 + pairIndex * 7_919) % (MODULUS - 1)) + 1
			for _, swapped in { false, true } do
				local result = simulate(
					matchup,
					seed,
					swapped,
					aggregate,
					false,
					if options ~= nil then options.bloodMoonConfig else nil
				)
				aggregate.matches += 1
				if not result.ok then
					aggregate.failures += 1
					continue
				end
				table.insert(aggregate.rounds, result.rounds)
				if result.rounds >= 10 then
					aggregate.reachedRound10 += 1
				end
				if result.rounds >= 10 and result.rounds <= 14 then
					aggregate.endedRounds10To14 += 1
				end
				aggregate.shortest = math.min(aggregate.shortest, result.rounds)
				aggregate.longest = math.max(aggregate.longest, result.rounds)
				aggregate.maxZeroProgressStreak =
					math.max(aggregate.maxZeroProgressStreak, result.maximumZeroProgressStreak)
				if result.firstDefeatRound ~= nil then
					table.insert(aggregate.firstDefeatRounds, result.firstDefeatRound)
				end
				if result.outcome == nil then
					aggregate.timeouts += 1
					if result.rounds >= 15 then
						aggregate.stalemates += 1
					end
				elseif result.outcome.isDraw then
					aggregate.draws += 1
					if result.outcome.reason == "MUTUAL_DESTRUCTION" then
						aggregate.mutualDestructions += 1
					end
				else
					local winnerRole = roleForTeam(result.outcome.winnerTeamId, result.aTeamId)
					aggregate[winnerRole].wins += 1
					aggregate.winnerRemainingHp += winningHp(
						result.state,
						result.outcome.winnerTeamId
					)
					if result.outcome.winnerTeamId == "team.a" then
						aggregate.sideOneWins += 1
					else
						aggregate.sideTwoWins += 1
					end
				end
			end
		end

		-- Re-run one exact input and compare event-derived trace hashes.
		local replaySeed = ((matchupIndex * 1_000_003 + 7_919) % (MODULUS - 1)) + 1
		local replayAggregateA = emptyAggregate(matchup)
		local replayAggregateB = emptyAggregate(matchup)
		local replayA = simulate(
			matchup,
			replaySeed,
			false,
			replayAggregateA,
			true,
			if options ~= nil then options.bloodMoonConfig else nil
		)
		local replayB = simulate(
			matchup,
			replaySeed,
			false,
			replayAggregateB,
			true,
			if options ~= nil then options.bloodMoonConfig else nil
		)
		if
			not replayA.ok
			or not replayB.ok
			or replayA.traceHash ~= replayB.traceHash
			or replayA.rounds ~= replayB.rounds
		then
			aggregate.replayErrors += 1
		end
		table.insert(results, finalize(aggregate))
	end
	return results
end

local function run(matchCount: number)
	return runWithOptions(matchCount, nil)
end

local function capture(matchupId: string, seed: number, swapped: boolean?)
	for _, matchup in MATCHUPS do
		if matchup.id == matchupId then
			local aggregate = emptyAggregate(matchup)
			return simulate(matchup, seed, swapped == true, aggregate, true, nil)
		end
	end
	return { ok = false, error = "MATCHUP_NOT_FOUND" }
end

return table.freeze({
	Matchups = MATCHUPS,
	MaxRounds = MAX_ROUNDS,
	capture = capture,
	run = run,
	runWithOptions = runWithOptions,
})
