--!strict

local function removeCards(zones, removedSet)
	local removed = table.clone(zones.removedCardInstanceIds or {})
	local alreadyRemoved = {}
	for _, cardId in removed do
		alreadyRemoved[cardId] = true
	end

	local function filter(values)
		local kept = {}
		for _, cardId in values or {} do
			if removedSet[cardId] then
				if not alreadyRemoved[cardId] then
					table.insert(removed, cardId)
					alreadyRemoved[cardId] = true
				end
			else
				table.insert(kept, cardId)
			end
		end
		return kept
	end

	return {
		drawPileCardInstanceIds = filter(zones.drawPileCardInstanceIds),
		handCardInstanceIds = filter(zones.handCardInstanceIds),
		discardCardInstanceIds = filter(zones.discardCardInstanceIds),
		removedCardInstanceIds = removed,
	}
end

local function discardPlayed(zones, playedCardInstanceIds, removedSet)
	local played = {}
	for _, cardId in playedCardInstanceIds do
		played[cardId] = true
	end
	local hand = {}
	for _, cardId in zones.handCardInstanceIds or {} do
		if not played[cardId] then
			table.insert(hand, cardId)
		end
	end
	local discard = table.clone(zones.discardCardInstanceIds or {})
	for _, cardId in playedCardInstanceIds do
		if not removedSet[cardId] then
			table.insert(discard, cardId)
		end
	end
	return {
		drawPileCardInstanceIds = table.clone(zones.drawPileCardInstanceIds or {}),
		handCardInstanceIds = hand,
		discardCardInstanceIds = discard,
		removedCardInstanceIds = table.clone(zones.removedCardInstanceIds or {}),
	}
end

return table.freeze({
	removeCards = removeCards,
	discardPlayed = discardPlayed,
})
