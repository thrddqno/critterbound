--!strict

local function create(drawPileCardInstanceIds)
	return {
		drawPileCardInstanceIds = table.clone(drawPileCardInstanceIds or {}),
		handCardInstanceIds = {},
		discardCardInstanceIds = {},
		removedCardInstanceIds = {},
	}
end

local function validateUnique(zones)
	local seen = {}
	local cardCount = 0
	for _, zoneName in
		{
			"drawPileCardInstanceIds",
			"handCardInstanceIds",
			"discardCardInstanceIds",
			"removedCardInstanceIds",
		}
	do
		for _, cardId in zones[zoneName] or {} do
			cardCount += 1
			if seen[cardId] ~= nil then
				return {
					ok = false,
					errors = {
						{
							code = "CARD_IN_MULTIPLE_ZONES",
							message = `Card {cardId} exists in {seen[cardId]} and {zoneName}`,
						},
					},
				}
			end
			seen[cardId] = zoneName
		end
	end
	return { ok = true, value = { cardCount = cardCount } }
end

return table.freeze({
	create = create,
	validateUnique = validateUnique,
})
