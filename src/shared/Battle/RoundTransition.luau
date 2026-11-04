--!strict

-- Resolve sibling modules in Roblox and under the Lune test runner.
local function requireSibling(name: string)
	if script ~= nil then
		return require((script.Parent :: any)[name])
	end
	return require(`./{name}`)
end

local CombatConstants = requireSibling("CombatConstants")
local DeepClone = requireSibling("DeepClone")
local Deck = requireSibling("Deck")
local DeckRules = requireSibling("DeckRules")
local DeckShuffler = requireSibling("DeckShuffler")
local DeterministicRng = requireSibling("DeterministicRng")
local RoundEconomy = requireSibling("RoundEconomy")

-- Applies the post-resolution round transition. Resolved cards leave hand for discard,
-- queues clear, commitment resets, unused energy carries and gains +2 (cap 10), then each
-- team draws three cards in team-index order. The RNG stream continues from state.rng.
--
-- Callers must guard against resolving the same round twice. RoundResolver does this with
-- state.lastResolvedRound and the RESOLVING phase check.

local function orderedTeamStates(state)
	local teamsById = {}
	for _, team in state.teams do
		teamsById[team.id] = team
	end

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

local function apply(state, resolvedCardsByTeamId, dependencies)
	local deps = dependencies or {}
	local deck = deps.deck or Deck
	local economy = deps.economy or RoundEconomy
	local shuffle = deps.shuffle
		or function(rng, values)
			return DeckShuffler.shuffle(rng, values, DeterministicRng)
		end
	local drawPerRound = deps.drawPerRound or CombatConstants.DrawPerRound
	local maxHandSize = deps.maxHandSize or DeckRules.Default.MaxHandSize
	local resolvedByTeam = resolvedCardsByTeamId or {}
	local retired = deps.retiredCardInstanceIds or {}

	local nextState = DeepClone.clone(state)
	local rng = nextState.rng
	if rng == nil then
		local created = DeterministicRng.new(nextState.rngSeed)
		if not created.ok then
			return created
		end
		rng = created.value
	end

	local ordered = orderedTeamStates(nextState)

	for _, teamState in ordered do
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

		local resolved = resolvedByTeam[teamState.teamId] or {}
		local resolvedSet = {}
		for _, cardId in resolved do
			resolvedSet[cardId] = true
		end

		local hand = {}
		for _, cardId in teamState.handCardInstanceIds or {} do
			if not resolvedSet[cardId] then
				table.insert(hand, cardId)
			end
		end
		local discard = table.clone(teamState.discardCardInstanceIds or {})
		for _, cardId in resolved do
			if not retired[cardId] then
				table.insert(discard, cardId)
			end
		end

		teamState.handCardInstanceIds = hand
		teamState.discardCardInstanceIds = discard
		teamState.queuedCards = {}
		teamState.reservedEnergy = 0
		teamState.committed = false
		teamState.planVersion = (teamState.planVersion or 0) + 1

		local energy = economy.nextRoundEnergy(teamState.energy or 0)
		if not energy.ok then
			return energy
		end
		teamState.energy = energy.value
	end

	for _, teamState in ordered do
		local drawResult = deck.draw({
			drawPileCardInstanceIds = teamState.drawPileCardInstanceIds or {},
			handCardInstanceIds = teamState.handCardInstanceIds or {},
			discardCardInstanceIds = teamState.discardCardInstanceIds or {},
			removedCardInstanceIds = teamState.removedCardInstanceIds or {},
		}, drawPerRound, rng, shuffle, { maxHandSize = maxHandSize })
		if not drawResult.ok then
			return drawResult
		end
		teamState.drawPileCardInstanceIds = drawResult.value.zones.drawPileCardInstanceIds
		teamState.handCardInstanceIds = drawResult.value.zones.handCardInstanceIds
		teamState.discardCardInstanceIds = drawResult.value.zones.discardCardInstanceIds
		teamState.removedCardInstanceIds = drawResult.value.zones.removedCardInstanceIds
		teamState.lastDrawnRound = (nextState.roundNumber or 1) + 1
		teamState.lastDrawResult = {
			requestedCount = drawResult.value.requestedCount,
			drawnCount = drawResult.value.drawnCount,
			isPartial = drawResult.value.isPartial,
		}
		rng = drawResult.value.rng
	end

	nextState.rng = rng
	nextState.roundNumber = (nextState.roundNumber or 1) + 1
	nextState.phase = "PLANNING"
	return { ok = true, value = nextState }
end

return table.freeze({
	apply = apply,
})
