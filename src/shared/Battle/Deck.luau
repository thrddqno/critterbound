--!strict

export type Rng = { algorithm: string, state: number, drawCount: number }
export type Zones = {
	drawPileCardInstanceIds: { string },
	handCardInstanceIds: { string },
	discardCardInstanceIds: { string },
}

local function cloneArray<T>(values: { T }): { T }
	return table.clone(values)
end

local function withoutCards(values: { string }, removed: { [string]: boolean }): { string }
	local kept = {}
	for _, cardId in values do
		if not removed[cardId] then
			table.insert(kept, cardId)
		end
	end
	return kept
end

local function removeCards(zones: Zones, removed: { [string]: boolean }): Zones
	return {
		drawPileCardInstanceIds = withoutCards(zones.drawPileCardInstanceIds, removed),
		handCardInstanceIds = withoutCards(zones.handCardInstanceIds, removed),
		discardCardInstanceIds = withoutCards(zones.discardCardInstanceIds, removed),
	}
end

local function draw(zones: Zones, count: number, rng: Rng, shuffleFn)
	if count % 1 ~= 0 or count < 0 then
		return {
			ok = false,
			errors = {
				{ code = "INVALID_DRAW_COUNT", message = "Draw count must be non-negative" },
			},
		}
	end
	local drawPile = cloneArray(zones.drawPileCardInstanceIds)
	local hand = cloneArray(zones.handCardInstanceIds)
	local discard = cloneArray(zones.discardCardInstanceIds)
	local currentRng = rng
	local drawn = {}

	while #drawn < count and #hand < 10 do
		if #drawPile == 0 then
			if #discard == 0 then
				break
			end
			currentRng, drawPile = shuffleFn(currentRng, discard)
			discard = {}
		end
		local cardId = table.remove(drawPile)
		table.insert(hand, cardId)
		table.insert(drawn, cardId)
	end

	return {
		ok = true,
		value = {
			zones = {
				drawPileCardInstanceIds = drawPile,
				handCardInstanceIds = hand,
				discardCardInstanceIds = discard,
			},
			rng = currentRng,
			drawnCardInstanceIds = drawn,
		},
	}
end

return table.freeze({
	draw = draw,
	removeCards = removeCards,
})
