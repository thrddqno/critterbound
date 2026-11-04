--!strict

local function build(teamIndex: number, contributions, rules)
	local cardInstances = {}
	local deckIds = {}
	for slot, contribution in contributions do
		if #contribution.definitionIds ~= rules.AbilitiesPerCritter then
			return {
				ok = false,
				errors = {
					{
						code = "INVALID_ABILITY_COUNT",
						message = `Critter must contribute exactly {rules.AbilitiesPerCritter} abilities`,
						path = contribution.sourceCritterInstanceId,
					},
				},
			}
		end
		for abilityIndex, definitionId in contribution.definitionIds do
			for copyIndex = 1, rules.CopiesPerCard do
				local cardId = `card:t{teamIndex}:s{slot}:a{abilityIndex}:c{copyIndex}`
				table.insert(cardInstances, {
					id = cardId,
					definitionId = definitionId,
					sourceCritterInstanceId = contribution.sourceCritterInstanceId,
				})
				table.insert(deckIds, cardId)
			end
		end
	end
	if #cardInstances ~= rules.TeamDeckSize then
		return {
			ok = false,
			errors = {
				{
					code = "INVALID_DECK_SIZE",
					message = `Team deck must contain {rules.TeamDeckSize} cards`,
				},
			},
		}
	end
	return { ok = true, value = { cardInstances = cardInstances, deckIds = deckIds } }
end

return table.freeze({ build = build })
