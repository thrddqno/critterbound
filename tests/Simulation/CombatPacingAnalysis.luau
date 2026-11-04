--!strict

-- Run 5.1 offline instrumentation and isolated counterfactuals. Production modules and authored
-- definitions are never mutated; each scenario receives detached definitions and battle state.

local BaseSimulation = require("./CombatBalanceSimulation")
local BattleFactory = require("../../src/shared/Battle/BattleFactory")
local BattlePlan = require("../../src/shared/Battle/BattlePlan")
local CardCatalog = require("../../src/shared/Definitions/CardCatalog")
local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
local DamageCalculator = require("../../src/shared/Battle/DamageCalculator")
local Deck = require("../../src/shared/Battle/Deck")
local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
local DomainValidator = require("../../src/shared/Validation/DomainValidator")
local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
local RoundResolver = require("../../src/shared/Battle/RoundResolver")
local StatusEffects = require("../../src/shared/Battle/StatusEffects")
local TargetResolver = require("../../src/shared/Battle/TargetResolver")
local TrainingPlanner = require("../../src/server/AI/TrainingPlanner")

local MODULUS = 2_147_483_647
local MAX_ROUNDS = 100

local SCENARIOS = {
	{ id = "baseline", name = "Production baseline", planner = "PRODUCTION" },
	{ id = "improved_ai", name = "Tactical AI", planner = "TACTICAL" },
	{ id = "aggressive_spending", name = "Maximum-spend AI", planner = "MAX_SPEND" },
	{ id = "combo_ai", name = "Combo-valuing AI", planner = "COMBO" },
	{ id = "healing_50", name = "Healing x0.50", planner = "PRODUCTION", heal = 0.5 },
	{ id = "shield_50", name = "Shield x0.50", planner = "PRODUCTION", shield = 0.5 },
	{ id = "damage_150", name = "Direct damage x1.50", planner = "PRODUCTION", damage = 1.5 },
	{ id = "damage_200", name = "Direct damage x2.00", planner = "PRODUCTION", damage = 2.0 },
	{ id = "damage_300", name = "Direct damage x3.00", planner = "PRODUCTION", damage = 3.0 },
	{ id = "hp_75", name = "Battle HP x0.75", planner = "PRODUCTION", hp = 0.75 },
	{ id = "hp_50", name = "Battle HP x0.50", planner = "PRODUCTION", hp = 0.5 },
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

local function definitionsForScenario(scenario)
	local definitions = CardCatalog.allById()
	for _, definition in definitions do
		for _, effect in definition.effects or {} do
			local multiplier = if effect.kind == "DAMAGE"
				then scenario.damage
				elseif effect.kind == "HEAL" then scenario.heal
				elseif effect.kind == "SHIELD" then scenario.shield
				else nil
			if multiplier ~= nil then
				effect.amount = math.floor((effect.amount or 0) * multiplier)
			end
		end
	end
	return definitions
end

local function makeInstance(className: string, ownerUserId: number, id: string)
	local definition = CritterCatalog.getByClass(className)
	assert(definition ~= nil, `Unknown pacing-analysis class {className}`)
	local genomes = GeneRegistry.defaultGenomes(className)
	assert(genomes ~= nil, `Missing pacing-analysis genomes for {className}`)
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

local function indexById(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

local function findTeamState(state, teamId: string)
	for _, value in state.teamRoundStates do
		if value.teamId == teamId then
			return value
		end
	end
	error(`Missing team {teamId}`)
end

local function category(definition): string
	local hasHeal = false
	local hasShield = false
	for _, effect in definition.effects or {} do
		if effect.kind == "DAMAGE" then
			return "damage"
		elseif effect.kind == "HEAL" then
			hasHeal = true
		elseif effect.kind == "SHIELD" then
			hasShield = true
		end
	end
	if hasHeal then
		return "healing"
	elseif hasShield then
		return "defensive"
	end
	return "status"
end

local function effectTotals(definition)
	local result = { damage = 0, healing = 0, shield = 0, status = 0 }
	for _, effect in definition.effects or {} do
		if effect.kind == "DAMAGE" then
			result.damage += effect.amount or 0
		elseif effect.kind == "HEAL" then
			result.healing += effect.amount or 0
		elseif effect.kind == "SHIELD" then
			result.shield += effect.amount or 0
		else
			result.status += effect.magnitude or 0
		end
	end
	return result
end

local function chooseTargets(definition, source, state): { string }?
	local combatantsById = indexById(state.combatants)
	if definition.targetingRule == "ALLY" then
		local allies = {}
		for _, combatant in state.combatants do
			if
				combatant.teamId == source.teamId
				and combatant.id ~= source.id
				and combatant.currentHealth > 0
			then
				table.insert(allies, combatant)
			end
		end
		table.sort(allies, function(a, b)
			local aRatio = a.currentHealth / a.stats.maxHealth
			local bRatio = b.currentHealth / b.stats.maxHealth
			if aRatio ~= bRatio then
				return aRatio < bRatio
			end
			return a.id < b.id
		end)
		return if allies[1] ~= nil then { allies[1].id } else nil
	elseif definition.targetingRule == "ANY" then
		local enemies = {}
		for _, combatant in state.combatants do
			if combatant.teamId ~= source.teamId and combatant.currentHealth > 0 then
				table.insert(enemies, combatant)
			end
		end
		table.sort(enemies, function(a, b)
			if a.currentHealth ~= b.currentHealth then
				return a.currentHealth < b.currentHealth
			end
			return a.id < b.id
		end)
		return if enemies[1] ~= nil then { enemies[1].id } else nil
	end
	local resolved = TargetResolver.resolve(definition.targetingRule, source, {}, combatantsById)
	return if resolved.skipped then nil else {}
end

local function buildCandidates(state, teamId: string, definitions)
	local teamState = findTeamState(state, teamId)
	local cards = indexById(state.cardInstances)
	local combatants = indexById(state.combatants)
	local sourceByCritter = {}
	for _, combatant in state.combatants do
		sourceByCritter[combatant.critterInstanceId] = combatant
	end
	local result = {}
	local unavailable = { defeatedSource = 0, noTarget = 0, unaffordable = 0 }
	for _, cardId in teamState.handCardInstanceIds do
		local instance = cards[cardId]
		local definition = if instance ~= nil then definitions[instance.definitionId] else nil
		local source = if instance ~= nil
			then sourceByCritter[instance.sourceCritterInstanceId]
			else nil
		if source == nil or source.currentHealth <= 0 then
			unavailable.defeatedSource += 1
		elseif definition ~= nil then
			local targets = chooseTargets(definition, source, state)
			if targets == nil then
				unavailable.noTarget += 1
			else
				local totals = effectTotals(definition)
				local score = totals.damage * 10 + totals.status * 5 - definition.energyCost * 2
				if totals.healing > 0 then
					local missing = source.stats.maxHealth - source.currentHealth
					if targets[1] ~= nil then
						local target = combatants[targets[1]]
						missing = target.stats.maxHealth - target.currentHealth
					end
					score += if missing > 0 then 800 + missing else -200
				end
				if totals.shield > 0 then
					score += 100
				end
				local candidate = {
					cardInstanceId = cardId,
					sourceCombatantId = source.id,
					targetCombatantIds = targets,
					definition = definition,
					energyCost = definition.energyCost,
					category = category(definition),
					score = score,
				}
				table.insert(result, candidate)
				if definition.energyCost > teamState.energy then
					unavailable.unaffordable += 1
				end
			end
		end
	end
	return result, unavailable
end

local function isLethal(candidate, state): boolean
	if candidate.category ~= "damage" then
		return false
	end
	local source = indexById(state.combatants)[candidate.sourceCombatantId]
	local combatants = indexById(state.combatants)
	local targetResolution = TargetResolver.resolve(
		candidate.definition.targetingRule,
		source,
		candidate.targetCombatantIds,
		combatants
	)
	for _, targetId in targetResolution.targetIds do
		local target = combatants[targetId]
		local shield = 0
		for _, value in target.shields or {} do
			shield += value.amount or 0
		end
		for _, effect in candidate.definition.effects do
			if effect.kind == "DAMAGE" then
				local breakdown = DamageCalculator.calculate(
					source,
					target,
					effect.amount or 0,
					candidate.definition.class,
					StatusEffects.damageModifier(source),
					false,
					false
				)
				if breakdown.damageBeforeShield >= target.currentHealth + shield then
					return true
				end
			end
		end
	end
	return false
end

local function sourceCounts(requests)
	local result = {}
	for _, request in requests do
		result[request.sourceCombatantId] = (result[request.sourceCombatantId] or 0) + 1
	end
	return result
end

local function canAdd(requests, candidate): boolean
	for _, request in requests do
		if request.cardInstanceId == candidate.cardInstanceId then
			return false
		end
	end
	return (sourceCounts(requests)[candidate.sourceCombatantId] or 0) < 4
end

local function requestFor(candidate)
	return {
		cardInstanceId = candidate.cardInstanceId,
		sourceCombatantId = candidate.sourceCombatantId,
		targetCombatantIds = candidate.targetCombatantIds,
	}
end

local function customPlan(state, teamId: string, definitions, mode: string)
	local candidates = buildCandidates(state, teamId, definitions)
	local energy = findTeamState(state, teamId).energy
	local requests = {}
	if mode == "COMBO" then
		local bySource = {}
		for _, candidate in candidates do
			local list = bySource[candidate.sourceCombatantId] or {}
			table.insert(list, candidate)
			bySource[candidate.sourceCombatantId] = list
		end
		local bestTriple = nil
		local bestScore = -math.huge
		for _, list in bySource do
			for first = 1, #list - 2 do
				for second = first + 1, #list - 1 do
					for third = second + 1, #list do
						local triple = { list[first], list[second], list[third] }
						local cost = triple[1].energyCost
							+ triple[2].energyCost
							+ triple[3].energyCost
						local score = triple[1].score + triple[2].score + triple[3].score
						if cost <= energy and score > bestScore then
							bestTriple = triple
							bestScore = score
						end
					end
				end
			end
		end
		for _, candidate in bestTriple or {} do
			table.insert(requests, requestFor(candidate))
			energy -= candidate.energyCost
		end
	end

	table.sort(candidates, function(a, b)
		if mode == "MAX_SPEND" and a.energyCost ~= b.energyCost then
			return a.energyCost > b.energyCost
		end
		if mode == "TACTICAL" then
			local aLethal = isLethal(a, state)
			local bLethal = isLethal(b, state)
			if aLethal ~= bLethal then
				return aLethal
			end
			local aDamage = a.category == "damage"
			local bDamage = b.category == "damage"
			if aDamage ~= bDamage then
				return aDamage
			end
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.cardInstanceId < b.cardInstanceId
	end)
	for _, candidate in candidates do
		if candidate.energyCost <= energy and canAdd(requests, candidate) then
			table.insert(requests, requestFor(candidate))
			energy -= candidate.energyCost
		end
	end
	return { ok = true, value = { requests = requests, remainingEnergy = energy } }
end

local function countTriples(candidates, energy: number): number
	local bySource = {}
	for _, candidate in candidates do
		local list = bySource[candidate.sourceCombatantId] or {}
		table.insert(list, candidate)
		bySource[candidate.sourceCombatantId] = list
	end
	local count = 0
	for _, list in bySource do
		for first = 1, #list - 2 do
			for second = first + 1, #list - 1 do
				for third = second + 1, #list do
					if
						list[first].energyCost
							+ list[second].energyCost
							+ list[third].energyCost
						<= energy
					then
						count += 1
					end
				end
			end
		end
	end
	return count
end

local function emptyMetrics()
	return {
		matches = 0,
		rounds = 0,
		completed = 0,
		timeouts = 0,
		teamTurns = 0,
		availableCards = 0,
		cardsPlayed = 0,
		energyAvailable = 0,
		energySpent = 0,
		passesWithAffordable = 0,
		affordableCards = 0,
		played = { damage = 0, healing = 0, defensive = 0, status = 0 },
		healRequested = 0,
		healRestored = 0,
		overhealing = 0,
		supportOverLethal = 0,
		comboOpportunities = 0,
		comboActivations = 0,
		fullHandTurns = 0,
		fullHandUsefulUnplayed = 0,
		handSizeTotal = 0,
		cardsDrawn = 0,
		drawTurns = 0,
		zeroDraws = 0,
		cardAgeTotal = 0,
		cardAgeSamples = 0,
		reshuffles = 0,
		originCounts = { 0, 0, 0 },
		originSamples = 0,
		blockedByDefeat = 0,
		blockedByTarget = 0,
		individuallyUnaffordable = 0,
		unplayedBlockedByEnergy = 0,
		directDamage = 0,
		shieldAbsorbed = 0,
		healing = 0,
		poison = 0,
		netHpProgress = 0,
		neutralizedTeamRounds = 0,
		unusedShieldExpired = 0,
		shieldPrepared = 0,
		firstDefeatRoundTotal = 0,
		firstDefeatSamples = 0,
		postDefeatRoundsTotal = 0,
		failures = 0,
	}
end

local function inspectPlanning(state, teamId: string, definitions, requests, ages, metrics)
	local roundState = findTeamState(state, teamId)
	local candidates, unavailable = buildCandidates(state, teamId, definitions)
	metrics.teamTurns += 1
	metrics.availableCards += #candidates
	metrics.cardsPlayed += #requests
	metrics.energyAvailable += roundState.energy
	metrics.handSizeTotal += #roundState.handCardInstanceIds
	metrics.blockedByDefeat += unavailable.defeatedSource
	metrics.blockedByTarget += unavailable.noTarget
	metrics.individuallyUnaffordable += unavailable.unaffordable
	local affordable = 0
	for _, candidate in candidates do
		if candidate.energyCost <= roundState.energy then
			affordable += 1
		end
	end
	metrics.affordableCards += affordable
	if #requests == 0 and affordable > 0 then
		metrics.passesWithAffordable += 1
	end
	metrics.comboOpportunities += countTriples(candidates, roundState.energy)
	local counts = sourceCounts(requests)
	for _, count in counts do
		if count >= 3 then
			metrics.comboActivations += 1
		end
	end

	local selected = {}
	local selectedSupport = false
	local spentThisTurn = 0
	for _, request in requests do
		selected[request.cardInstanceId] = true
	end
	for _, candidate in candidates do
		if selected[candidate.cardInstanceId] then
			metrics.played[candidate.category] += 1
			selectedSupport = selectedSupport or candidate.category ~= "damage"
			metrics.energySpent += candidate.energyCost
			spentThisTurn += candidate.energyCost
		end
	end
	if selectedSupport then
		for _, candidate in candidates do
			if
				not selected[candidate.cardInstanceId]
				and candidate.energyCost <= roundState.energy
				and isLethal(candidate, state)
			then
				metrics.supportOverLethal += 1
				break
			end
		end
	end

	local cardsById = indexById(state.cardInstances)
	local combatantByCritter = {}
	for _, combatant in state.combatants do
		combatantByCritter[combatant.critterInstanceId] = combatant
	end
	local perSlot = { 0, 0, 0 }
	local usefulUnplayed = false
	local remainingEnergy = roundState.energy - spentThisTurn
	for _, cardId in roundState.handCardInstanceIds do
		ages[cardId] = (ages[cardId] or -1) + 1
		metrics.cardAgeTotal += ages[cardId]
		metrics.cardAgeSamples += 1
		local card = cardsById[cardId]
		local source = if card ~= nil then combatantByCritter[card.sourceCritterInstanceId] else nil
		if source ~= nil then
			perSlot[source.slot] += 1
		end
	end
	for slot = 1, 3 do
		metrics.originCounts[slot] += perSlot[slot]
	end
	metrics.originSamples += 1
	if #roundState.handCardInstanceIds == 9 then
		metrics.fullHandTurns += 1
		for _, candidate in candidates do
			if not selected[candidate.cardInstanceId] then
				if candidate.energyCost <= remainingEnergy then
					usefulUnplayed = true
				else
					metrics.unplayedBlockedByEnergy += 1
				end
			end
		end
		if usefulUnplayed then
			metrics.fullHandUsefulUnplayed += 1
		end
	end
end

local function processRoundEvents(events, stateBefore, stateAfter, metrics)
	local hpBeforeByTeam = {}
	local hpAfterByTeam = {}
	for _, combatant in stateBefore.combatants do
		hpBeforeByTeam[combatant.teamId] = (hpBeforeByTeam[combatant.teamId] or 0)
			+ combatant.currentHealth
	end
	for _, combatant in stateAfter.combatants do
		hpAfterByTeam[combatant.teamId] = (hpAfterByTeam[combatant.teamId] or 0)
			+ combatant.currentHealth
	end
	local incomingByTeam = {}
	local sustainByTeam = {}
	local combatants = indexById(stateBefore.combatants)
	local firstDefeat = nil
	for _, event in events do
		if event.kind == "DAMAGE_APPLIED" then
			metrics.directDamage += event.payload.hpDamage or 0
			local target = combatants[event.payload.targetCombatantId]
			if target ~= nil then
				incomingByTeam[target.teamId] = (incomingByTeam[target.teamId] or 0)
					+ (event.payload.hpDamage or 0)
			end
		elseif event.kind == "SHIELD_ABSORBED" then
			metrics.shieldAbsorbed += event.payload.absorbed or 0
			local target = combatants[event.payload.targetCombatantId]
			if target ~= nil then
				sustainByTeam[target.teamId] = (sustainByTeam[target.teamId] or 0)
					+ (event.payload.absorbed or 0)
			end
		elseif event.kind == "HEAL_APPLIED" then
			local requested = event.payload.requested or 0
			local restored = event.payload.restored or 0
			metrics.healRequested += requested
			metrics.healRestored += restored
			metrics.overhealing += math.max(0, requested - restored)
			metrics.healing += restored
			local target = combatants[event.payload.targetCombatantId]
			if target ~= nil then
				sustainByTeam[target.teamId] = (sustainByTeam[target.teamId] or 0) + restored
			end
		elseif event.kind == "STATUS_TICKED" and event.payload.statusId == "POISON" then
			local actual =
				math.max(0, (event.payload.healthBefore or 0) - (event.payload.healthAfter or 0))
			metrics.poison += actual
			local target = combatants[event.payload.targetCombatantId]
			if target ~= nil then
				incomingByTeam[target.teamId] = (incomingByTeam[target.teamId] or 0) + actual
			end
		elseif event.kind == "SHIELD_PREPARED" then
			metrics.shieldPrepared += event.payload.amount or 0
		elseif event.kind == "STATUS_EXPIRED" and event.payload.statusId == "SHIELD" then
			metrics.unusedShieldExpired += event.payload.remainingAmount or 0
		elseif event.kind == "CRITTER_DEFEATED" and firstDefeat == nil then
			firstDefeat = event.roundNumber
		end
	end
	for teamId, before in hpBeforeByTeam do
		local after = hpAfterByTeam[teamId] or 0
		metrics.netHpProgress += before - after
		if
			(incomingByTeam[teamId] or 0) > 0
			and after >= before
			and (sustainByTeam[teamId] or 0) > 0
		then
			metrics.neutralizedTeamRounds += 1
		end
	end
	return firstDefeat
end

local function applyHpScale(state, multiplier: number?)
	if multiplier == nil then
		return
	end
	for _, combatant in state.combatants do
		combatant.stats.maxHealth = math.max(1, math.floor(combatant.stats.maxHealth * multiplier))
		combatant.currentHealth = combatant.stats.maxHealth
	end
end

local function simulate(matchup, seed: number, swapped: boolean, scenario, metrics)
	local definitions = definitionsForScenario(scenario)
	local plannerDefinitions = CardCatalog.allById()
	local firstConfig = if swapped then matchup.b else matchup.a
	local secondConfig = if swapped then matchup.a else matchup.b
	local criticalSeed = (seed * 48_271 + 97_531) % (MODULUS - 1) + 1
	local created = BattleFactory.create({
		battleId = `pacing:{scenario.id}:{matchup.id}:{seed}:{tostring(swapped)}`,
		rngSeed = seed,
		teams = {
			teamInput("team.a", 20_001, firstConfig.classes),
			teamInput("team.b", 20_002, secondConfig.classes),
		},
		critterDefinitionsById = CritterCatalog.allById(),
		cardDefinitionsById = definitions,
	}, {
		rng = DeterministicRng,
		criticalRngSeed = criticalSeed,
		deck = Deck,
		validator = DomainValidator,
	})
	if not created.ok then
		metrics.failures += 1
		return
	end
	local state = created.value
	applyHpScale(state, scenario.hp)
	local agesByTeam = { ["team.a"] = {}, ["team.b"] = {} }
	local firstDefeatRound = nil
	local rounds = 0
	while state.phase ~= "FINISHED" and rounds < MAX_ROUNDS do
		for _, teamId in { "team.a", "team.b" } do
			local plannerResult = if scenario.planner == "PRODUCTION"
				then TrainingPlanner.plan(state, teamId, plannerDefinitions)
				else customPlan(state, teamId, plannerDefinitions, scenario.planner)
			if not plannerResult.ok then
				metrics.failures += 1
				return
			end
			inspectPlanning(
				state,
				teamId,
				plannerDefinitions,
				plannerResult.value.requests,
				agesByTeam[teamId],
				metrics
			)
			for _, request in plannerResult.value.requests do
				local queued = BattlePlan.queueCard(state, teamId, request, definitions)
				if not queued.ok then
					metrics.failures += 1
					return
				end
				state = queued.value
			end
			local committed = BattlePlan.commitPlan(state, teamId, definitions)
			if not committed.ok then
				metrics.failures += 1
				return
			end
			state = committed.value
		end
		local stateBefore = clone(state)
		local reshufflesThisRound = 0
		for _, roundState in state.teamRoundStates do
			local handAfterDiscard = #roundState.handCardInstanceIds - #roundState.queuedCards
			local wanted = math.min(3, math.max(0, 9 - handAfterDiscard))
			if
				wanted > #roundState.drawPileCardInstanceIds
				and #roundState.discardCardInstanceIds + #roundState.queuedCards > 0
			then
				reshufflesThisRound += 1
			end
		end
		local resolved = RoundResolver.resolveRound(state, {
			cardDefinitionsById = definitions,
			deck = Deck,
			economy = RoundEconomy,
			rng = DeterministicRng,
			drawPerRound = 3,
		})
		if not resolved.ok then
			metrics.failures += 1
			return
		end
		state = resolved.value.state
		rounds += 1
		local defeated = processRoundEvents(resolved.value.events, stateBefore, state, metrics)
		if firstDefeatRound == nil and defeated ~= nil then
			firstDefeatRound = defeated
		end
		metrics.reshuffles += reshufflesThisRound
		if state.phase ~= "FINISHED" then
			for _, teamId in { "team.a", "team.b" } do
				local roundState = findTeamState(state, teamId)
				local draw = roundState.lastDrawResult
				metrics.drawTurns += 1
				metrics.cardsDrawn += draw.drawnCount
				if draw.drawnCount == 0 then
					metrics.zeroDraws += 1
				end
				local inHand = {}
				for _, cardId in roundState.handCardInstanceIds do
					inHand[cardId] = true
				end
				for cardId in agesByTeam[teamId] do
					if not inHand[cardId] then
						agesByTeam[teamId][cardId] = nil
					end
				end
			end
		end
	end
	metrics.matches += 1
	metrics.rounds += rounds
	if state.phase == "FINISHED" then
		metrics.completed += 1
		if firstDefeatRound ~= nil then
			metrics.firstDefeatRoundTotal += firstDefeatRound
			metrics.firstDefeatSamples += 1
			metrics.postDefeatRoundsTotal += rounds - firstDefeatRound
		end
	else
		metrics.timeouts += 1
	end
end

local function run(matchesPerMatchup: number)
	assert(
		matchesPerMatchup >= 2 and matchesPerMatchup % 2 == 0,
		"Match count must be an even integer >= 2"
	)
	local output = {}
	local pairs = matchesPerMatchup // 2
	for _, scenario in SCENARIOS do
		local metrics = emptyMetrics()
		for matchupIndex, matchup in BaseSimulation.Matchups do
			for pair = 1, pairs do
				local seed = ((matchupIndex * 1_000_003 + pair * 7_919) % (MODULUS - 1)) + 1
				simulate(matchup, seed, false, scenario, metrics)
				simulate(matchup, seed, true, scenario, metrics)
			end
		end
		table.insert(output, { scenario = scenario, metrics = metrics })
	end
	return output
end

return table.freeze({ Scenarios = SCENARIOS, run = run })
