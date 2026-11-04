--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local BattleEvents = requireSibling("BattleEvents")
local BloodMoon = requireSibling("BloodMoon")
local CardEffectResolver = requireSibling("CardEffectResolver")
local CombatConstants = requireSibling("CombatConstants")
local DeepClone = requireSibling("DeepClone")
local Deck = requireSibling("Deck")
local DeckRules = requireSibling("DeckRules")
local DeckShuffler = requireSibling("DeckShuffler")
local DeterministicRng = requireSibling("DeterministicRng")
local CriticalHits = requireSibling("CriticalHits")
local Initiative = requireSibling("Initiative")
local RoundEconomy = requireSibling("RoundEconomy")
local RoundTransition = requireSibling("RoundTransition")
local StatusEffects = requireSibling("StatusEffects")
local TargetResolver = requireSibling("TargetResolver")

-- Server-authoritative, pure round resolution. The caller supplies card definitions.
-- Optional dependencies let tests swap deck/economy/shuffle implementations.
--
-- Lifecycle inside one atomic call:
--   RESOLVING -> PLANNING
--   RESOLVING -> FINISHED
--
-- Guard: state.phase must be RESOLVING and the round must not already be resolved.

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function indexCombatants(state)
	local result = {}
	for _, combatant in state.combatants do
		result[combatant.id] = combatant
	end
	return result
end

local function indexTeams(state)
	local result = {}
	for _, team in state.teams do
		result[team.id] = team
	end
	return result
end

local function indexCards(state)
	local result = {}
	for _, card in state.cardInstances or {} do
		result[card.id] = card
	end
	return result
end

local function retiredCardInstanceIds(state): { [string]: boolean }
	local defeatedCritterInstances = {}
	for _, combatant in state.combatants do
		if combatant.currentHealth <= 0 then
			defeatedCritterInstances[combatant.critterInstanceId] = true
		end
	end

	local retired = {}
	for _, card in state.cardInstances or {} do
		if defeatedCritterInstances[card.sourceCritterInstanceId] then
			retired[card.id] = true
		end
	end
	return retired
end

local function retireCardsFromActiveZones(state, retired, deck)
	for _, teamState in state.teamRoundStates do
		local zones = deck.removeCards({
			drawPileCardInstanceIds = teamState.drawPileCardInstanceIds or {},
			handCardInstanceIds = teamState.handCardInstanceIds or {},
			discardCardInstanceIds = teamState.discardCardInstanceIds or {},
			removedCardInstanceIds = teamState.removedCardInstanceIds or {},
		}, retired)
		teamState.drawPileCardInstanceIds = zones.drawPileCardInstanceIds
		teamState.handCardInstanceIds = zones.handCardInstanceIds
		teamState.discardCardInstanceIds = zones.discardCardInstanceIds
		teamState.removedCardInstanceIds = zones.removedCardInstanceIds

		local queue = {}
		for _, queued in teamState.queuedCards or {} do
			if not retired[queued.cardInstanceId] then
				table.insert(queue, queued)
			end
		end
		teamState.queuedCards = queue
	end
end

local function sortedTeamStates(state, teamsById)
	local ordered = table.clone(state.teamRoundStates)
	table.sort(ordered, function(a, b)
		local aTeam = teamsById[a.teamId]
		local bTeam = teamsById[b.teamId]
		local aIndex = if aTeam ~= nil and aTeam.teamIndex ~= nil then aTeam.teamIndex else 0
		local bIndex = if bTeam ~= nil and bTeam.teamIndex ~= nil then bTeam.teamIndex else 0
		if aIndex ~= bIndex then
			return aIndex < bIndex
		end
		return a.teamId < b.teamId
	end)
	return ordered
end

-- Stable combatant order: team index, battlefield slot, then combatant identifier.
local function orderedCombatants(state, teamsById)
	local ordered = table.clone(state.combatants)
	table.sort(ordered, function(a, b)
		local aTeam = teamsById[a.teamId]
		local bTeam = teamsById[b.teamId]
		local aIndex = if aTeam ~= nil and aTeam.teamIndex ~= nil then aTeam.teamIndex else 0
		local bIndex = if bTeam ~= nil and bTeam.teamIndex ~= nil then bTeam.teamIndex else 0
		if aIndex ~= bIndex then
			return aIndex < bIndex
		end
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		return a.id < b.id
	end)
	return ordered
end

local function evaluateOutcome(state, combatantsById)
	local livingByTeam = {}
	for _, team in state.teams do
		livingByTeam[team.id] = 0
	end
	for _, combatant in combatantsById do
		if combatant.currentHealth > 0 and livingByTeam[combatant.teamId] ~= nil then
			livingByTeam[combatant.teamId] += 1
		end
	end

	local livingTeams = {}
	for _, team in state.teams do
		if livingByTeam[team.id] > 0 then
			table.insert(livingTeams, team.id)
		end
	end

	if #livingTeams == 0 then
		return { isDraw = true, winnerTeamId = nil, reason = "MUTUAL_DESTRUCTION" }
	end
	if #livingTeams == 1 then
		return { isDraw = false, winnerTeamId = livingTeams[1], reason = "TEAM_DEFEATED" }
	end
	return nil
end

local function containsShieldEffect(definition): boolean
	for _, effect in definition.effects or {} do
		if effect.kind == "SHIELD" then
			return true
		end
	end
	return false
end

local function resolveRound(state, dependencies)
	if type(state) ~= "table" then
		return failure("INVALID_STATE", "Battle state is required", nil)
	end
	if state.phase ~= "RESOLVING" then
		return failure("INVALID_PHASE", "Battle is not resolving", "phase")
	end
	if (state.lastResolvedRound or 0) >= (state.roundNumber or 1) then
		return failure("ROUND_ALREADY_RESOLVED", "Round has already been resolved", "roundNumber")
	end
	for _, teamState in state.teamRoundStates do
		if not teamState.committed then
			return failure(
				"NOT_COMMITTED",
				"Both teams must commit before resolution",
				"teamRoundStates"
			)
		end
	end

	local deps = dependencies or {}
	local cardDefinitionsById = deps.cardDefinitionsById or {}
	local deck = deps.deck or Deck
	local economy = deps.economy or RoundEconomy
	local shuffle = deps.shuffle
		or function(rng, values)
			return DeckShuffler.shuffle(rng, values, DeterministicRng)
		end
	local drawPerRound = deps.drawPerRound or CombatConstants.DrawPerRound
	local maxHandSize = deps.maxHandSize or DeckRules.Default.MaxHandSize
	local defeatPolicy = deps.defeatPolicy or DeckRules.Default.DefeatPolicy
	local bloodMoonConfig = deps.bloodMoonConfig

	local nextState = DeepClone.clone(state)
	if nextState.criticalRng == nil then
		return failure("MISSING_CRITICAL_RNG", "Critical RNG state is required", "criticalRng")
	end
	local events = {}
	local factory = BattleEvents.create(nextState.id, nextState.eventVersion or 0)
	local roundNumber = nextState.roundNumber or 1
	local combatantsById = indexCombatants(nextState)
	local cardsById = indexCards(nextState)
	local teamsById = indexTeams(nextState)
	local combatantOrder = orderedCombatants(nextState, teamsById)
	local criticalRng = deps.criticalRng or DeterministicRng
	local function rollCritical(source): boolean
		local nextCriticalRng, isCritical =
			CriticalHits.roll(nextState.criticalRng, source.stats.morale or 0, criticalRng)
		nextState.criticalRng = nextCriticalRng
		return isCritical
	end

	local resolvedByTeam = {}
	local defeated = {}
	local matchOutcome = nil

	local cardsBySource = {}
	local queuedTeamIdByCardInstanceId = {}
	for _, teamState in sortedTeamStates(nextState, teamsById) do
		for _, queued in teamState.queuedCards or {} do
			local list = cardsBySource[queued.sourceCombatantId] or {}
			table.insert(list, queued)
			cardsBySource[queued.sourceCombatantId] = list
			queuedTeamIdByCardInstanceId[queued.cardInstanceId] = teamState.teamId
			resolvedByTeam[teamState.teamId] = resolvedByTeam[teamState.teamId] or {}
			table.insert(resolvedByTeam[teamState.teamId], queued.cardInstanceId)
		end
	end
	for _, queuedCards in cardsBySource do
		table.sort(queuedCards, function(a, b)
			return a.queueIndex < b.queueIndex
		end)
	end

	-- Preparation order is independent of initiative: team index, source slot, source ID,
	-- queue index, authored effect index, then TargetResolver's deterministic target order.
	-- Every valid shield is established before INITIATIVE_DETERMINED is emitted.
	local preparationOrder = 0
	local function nextPreparationOrder(): number
		preparationOrder += 1
		return preparationOrder
	end
	for _, source in combatantOrder do
		if source.currentHealth > 0 then
			for _, card in cardsBySource[source.id] or {} do
				local cardInstance = cardsById[card.cardInstanceId]
				local definition = if cardInstance ~= nil
					then cardDefinitionsById[cardInstance.definitionId]
					else nil
				if
					cardInstance ~= nil
					and definition ~= nil
					and cardInstance.sourceCritterInstanceId == source.critterInstanceId
					and queuedTeamIdByCardInstanceId[card.cardInstanceId] == source.teamId
					and containsShieldEffect(definition)
				then
					local targetResolution = TargetResolver.resolve(
						definition.targetingRule,
						source,
						card.targetCombatantIds or {},
						combatantsById
					)
					if not targetResolution.skipped then
						CardEffectResolver.prepareShields(
							source,
							targetResolution.targetIds,
							definition,
							combatantsById,
							roundNumber,
							factory,
							events,
							card.cardInstanceId,
							nextPreparationOrder
						)
					end
				end
			end
		end
	end

	local entries = {}
	for _, combatant in combatantOrder do
		local queuedCards = cardsBySource[combatant.id]
		if queuedCards ~= nil and #queuedCards > 0 then
			local team = teamsById[combatant.teamId]
			table.insert(entries, {
				combatantId = combatant.id,
				teamIndex = if team ~= nil and team.teamIndex ~= nil then team.teamIndex else 0,
				slot = combatant.slot,
				speed = StatusEffects.effectiveSpeed(combatant),
				currentHealth = combatant.currentHealth,
				skill = combatant.stats.skill or 0,
				morale = combatant.stats.morale or 0,
				queuedCards = queuedCards,
			})
		end
	end

	local ordered = Initiative.orderCombat(entries)
	local initiativeIds = {}
	for _, entry in ordered do
		table.insert(initiativeIds, entry.combatantId)
	end
	table.insert(
		events,
		factory.emit("INITIATIVE_DETERMINED", roundNumber, {
			initiativeCombatantIds = initiativeIds,
		})
	)

	local function emitDefeat(combatantId: string)
		if defeated[combatantId] then
			return
		end
		defeated[combatantId] = true
		table.insert(
			events,
			factory.emit("CRITTER_DEFEATED", roundNumber, {
				combatantId = combatantId,
				health = 0,
			}, combatantId, { combatantId })
		)
	end

	local function cancelCard(card, reason: string)
		table.insert(
			events,
			factory.emit("ACTION_CANCELED", roundNumber, {
				cardInstanceId = card.cardInstanceId,
				sourceCombatantId = card.sourceCombatantId,
				reason = reason,
			}, card.sourceCombatantId, {})
		)
	end

	local function cancelFrom(entryIndex: number, cardIndex: number, reason: string)
		for index = entryIndex, #ordered do
			local entry = ordered[index]
			local startIndex = if index == entryIndex then cardIndex else 1
			for offset = startIndex, #entry.queuedCards do
				cancelCard(entry.queuedCards[offset], reason)
			end
		end
	end

	for entryIndex, entry in ordered do
		if matchOutcome ~= nil then
			cancelFrom(entryIndex, 1, "MATCH_COMPLETED")
			break
		end

		local source = combatantsById[entry.combatantId]
		if source == nil or source.currentHealth <= 0 then
			for _, card in entry.queuedCards do
				cancelCard(card, "DEFEATED")
			end
			continue
		end

		for cardIndex, card in entry.queuedCards do
			if matchOutcome ~= nil then
				cancelFrom(entryIndex, cardIndex, "MATCH_COMPLETED")
				break
			end
			if source.currentHealth <= 0 then
				for offset = cardIndex, #entry.queuedCards do
					cancelCard(entry.queuedCards[offset], "DEFEATED")
				end
				break
			end

			local cardInstance = cardsById[card.cardInstanceId]
			local definition = if cardInstance ~= nil
				then cardDefinitionsById[cardInstance.definitionId]
				else nil
			if definition == nil then
				cancelCard(card, "MISSING_DEFINITION")
			else
				table.insert(
					events,
					factory.emit("CARD_PLAYED", roundNumber, {
						cardInstanceId = card.cardInstanceId,
						cardDefinitionId = definition.id,
						sourceCombatantId = source.id,
						queueIndex = card.queueIndex,
					}, source.id, {})
				)

				local targetResolution = TargetResolver.resolve(
					definition.targetingRule,
					source,
					card.targetCombatantIds or {},
					combatantsById
				)
				table.insert(
					events,
					factory.emit("TARGET_SELECTED", roundNumber, {
						cardInstanceId = card.cardInstanceId,
						targetingRule = definition.targetingRule,
						targetCombatantIds = targetResolution.targetIds,
						retargeted = targetResolution.retargeted,
						skipped = targetResolution.skipped,
					}, source.id, targetResolution.targetIds)
				)

				if not targetResolution.skipped then
					local defeatedTargets = CardEffectResolver.applyCard(
						source,
						targetResolution.targetIds,
						definition,
						combatantsById,
						roundNumber,
						factory,
						events,
						{
							skillComboActive = #entry.queuedCards
								>= CombatConstants.SkillComboMinimumCards,
							rollCritical = rollCritical,
							skipShieldEffects = true,
						}
					)
					for _, targetId in defeatedTargets do
						emitDefeat(targetId)
					end
				end

				matchOutcome = evaluateOutcome(nextState, combatantsById)
			end
		end
	end

	-- A card-completed match is terminal. Otherwise poison and Blood Moon are simultaneous
	-- batches, with one final victory evaluation after both. Expiry runs only for a live match.
	if matchOutcome == nil then
		local poisonDefeated =
			StatusEffects.tickPoison(combatantOrder, roundNumber, factory, events)
		for _, combatantId in poisonDefeated do
			emitDefeat(combatantId)
		end
		local bloodMoon = BloodMoon.apply(
			nextState,
			combatantOrder,
			roundNumber,
			bloodMoonConfig,
			factory,
			events
		)
		for _, combatantId in bloodMoon.defeatedCombatantIds do
			emitDefeat(combatantId)
		end
		matchOutcome = evaluateOutcome(nextState, combatantsById)
		if matchOutcome == nil then
			StatusEffects.expire(combatantOrder, roundNumber, factory, events)
		end
	end

	nextState.lastResolvedRound = roundNumber
	local retired = if defeatPolicy == "REMOVE_IMMEDIATELY"
		then retiredCardInstanceIds(nextState)
		else {}

	if matchOutcome ~= nil then
		retireCardsFromActiveZones(nextState, retired, deck)
		nextState.phase = "FINISHED"
		nextState.stateVersion = (nextState.stateVersion or 0) + 1
		table.insert(
			events,
			factory.emit("MATCH_COMPLETED", roundNumber, {
				isDraw = matchOutcome.isDraw,
				winnerTeamId = matchOutcome.winnerTeamId,
				reason = matchOutcome.reason,
			})
		)
		nextState.eventVersion = factory.sequence()
		return {
			ok = true,
			value = {
				state = nextState,
				events = events,
				stateVersion = nextState.stateVersion,
				matchOutcome = matchOutcome,
			},
		}
	end

	local transition = RoundTransition.apply(nextState, resolvedByTeam, {
		deck = deck,
		economy = economy,
		shuffle = shuffle,
		drawPerRound = drawPerRound,
		maxHandSize = maxHandSize,
		retiredCardInstanceIds = retired,
	})
	if not transition.ok then
		return transition
	end
	nextState = transition.value
	nextState.stateVersion = (nextState.stateVersion or 0) + 1
	table.insert(
		events,
		factory.emit("ROUND_COMPLETED", roundNumber, {
			nextRoundNumber = nextState.roundNumber,
			phase = nextState.phase,
		})
	)
	nextState.eventVersion = factory.sequence()

	return {
		ok = true,
		value = {
			state = nextState,
			events = events,
			stateVersion = nextState.stateVersion,
			matchOutcome = nil,
		},
	}
end

return table.freeze({
	resolveRound = resolveRound,
})
