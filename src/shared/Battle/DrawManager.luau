--!strict

local function draw(zones, count: number, rng, shuffleFn, options)
	if count % 1 ~= 0 or count < 0 then
		return {
			ok = false,
			errors = {
				{ code = "INVALID_DRAW_COUNT", message = "Draw count must be non-negative" },
			},
		}
	end
	local maxHandSize = if options ~= nil and options.maxHandSize ~= nil
		then options.maxHandSize
		else math.huge
	if maxHandSize % 1 ~= 0 or maxHandSize < 0 then
		return {
			ok = false,
			errors = {
				{
					code = "INVALID_MAX_HAND_SIZE",
					message = "Maximum hand size must be a non-negative integer",
				},
			},
		}
	end

	local drawPile = table.clone(zones.drawPileCardInstanceIds or {})
	local hand = table.clone(zones.handCardInstanceIds or {})
	local discard = table.clone(zones.discardCardInstanceIds or {})
	local removed = table.clone(zones.removedCardInstanceIds or {})
	local currentRng = rng
	local drawn = {}

	local availableSlots = math.max(0, maxHandSize - #hand)
	local drawCount = math.min(count, availableSlots)
	while #drawn < drawCount do
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
				removedCardInstanceIds = removed,
			},
			rng = currentRng,
			drawnCardInstanceIds = drawn,
			requestedCount = count,
			drawnCount = #drawn,
			isPartial = #drawn < count,
		},
	}
end

return table.freeze({ draw = draw })
