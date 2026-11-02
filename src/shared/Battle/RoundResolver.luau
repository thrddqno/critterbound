--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local BattleEvents = requireSibling("BattleEvents")
local CardEffectResolver = requireSibling("CardEffectResolver")
local CombatConstants = requireSibling("CombatConstants")
local DeepClone = requireSibling("DeepClone")
local Deck = requireSibling("Deck")
local DeterministicRng = requireSibling("DeterministicRng")
local Initiative = requireSibling("Initiative")
local RoundEconomy = requireSibling("RoundEconomy")
local RoundTransition = requireSibling("RoundTransition")
local StatusEffects = requireSibling("StatusEffects")
local TargetResolver = requireSibling("TargetResolver")

-- Server-authoritative, pure round resolution. The caller supplies card definitions.
-- Optional dependencies let tests swap deck/economy/shuffle implementations.
--
-- Lifecycle inside one atomic call:
--   COMMITTED -> RESOLVING -> ROUND_END -> PLANNING
--   COMMITTED -> RESOLVING -> ROUND_END -> COMPLETED
--
-- Guard: state.phase must be COMMITTED and the round must not already be resolved.

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

local function resolveRound(state, dependencies)
	if type(state) ~= "table" then
		return failure("INVALID_STATE", "Battle state is required", nil)
	end
	if state.phase ~= "COMMITTED" then
		return failure("INVALID_PHASE", "Battle is not in COMMITTED phase", "phase")
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
	local shuffle = deps.shuffle or DeterministicRng.shuffle
	local drawPerRound = deps.drawPerRound or CombatConstants.DrawPerRound

	local nextState = DeepClone.clone(state)
	nextState.phase = "RESOLVING"
	local events = {}
	local factory = BattleEvents.create(nextState.id, nextState.eventVersion or 0)
	local roundNumber = nextState.roundNumber or 1
	local combatantsById = indexCombatants(nextState)
	local cardsById = indexCards(nextState)
	local teamsById = indexTeams(nextState)
	local combatantOrder = orderedCombatants(nextState, teamsById)

	local resolvedByTeam = {}
	local defeated = {}
	local matchOutcome = nil

	local cardsBySource = {}
	for _, teamState in sortedTeamStates(nextState, teamsById) do
		for _, queued in teamState.queuedCards or {} do
			local list = cardsBySource[queued.sourceCombatantId] or {}
			table.insert(list, queued)
			cardsBySource[queued.sourceCombatantId] = list
			resolvedByTeam[teamState.teamId] = resolvedByTeam[teamState.teamId] or {}
			table.insert(resolvedByTeam[teamState.teamId], queued.cardInstanceId)
		end
	end

	local entries = {}
	for _, combatant in combatantOrder do
		local queuedCards = cardsBySource[combatant.id]
		if queuedCards ~= nil and #queuedCards > 0 then
			table.sort(queuedCards, function(a, b)
				return a.queueIndex < b.queueIndex
			end)
			local team = teamsById[combatant.teamId]
			table.insert(entries, {
				combatantId = combatant.id,
				teamIndex = if team ~= nil and team.teamIndex ~= nil then team.teamIndex else 0,
				slot = combatant.slot,
				speed = StatusEffects.effectiveSpeed(combatant),
				currentHealth = combatant.currentHealth,
				skill = combatant.stats.skill or 0,
				resolve = combatant.stats.resolve or 0,
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
						events
					)
					for _, targetId in defeatedTargets do
						emitDefeat(targetId)
					end
				end

				matchOutcome = evaluateOutcome(nextState, combatantsById)
			end
		end
	end

	-- A completed match is terminal. Round-end poison and expiry only run while the match
	-- is still live. Poison is simultaneous; victory is evaluated once after all ticks.
	nextState.phase = "ROUND_END"
	if matchOutcome == nil then
		local poisonDefeated =
			StatusEffects.tickPoison(combatantOrder, roundNumber, factory, events)
		for _, combatantId in poisonDefeated do
			emitDefeat(combatantId)
		end
		matchOutcome = evaluateOutcome(nextState, combatantsById)
		StatusEffects.expire(combatantOrder, roundNumber, factory, events)
	end

	nextState.lastResolvedRound = roundNumber

	if matchOutcome ~= nil then
		nextState.phase = "COMPLETED"
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
