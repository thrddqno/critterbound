--!strict

local TargetSelection = {}

local DERIVED = { FRONT_ENEMY = true, ALL_ALLIES = true, ALL_ENEMIES = true }

local function legalTargetIds(card, model): { string }
	local source = nil
	for _, critter in model.critters do
		if critter.id == card.sourceCombatantId then
			source = critter
			break
		end
	end
	if source == nil or source.defeated then
		return {}
	end
	if card.targetingRule == "SELF" then
		return { source.id }
	end
	if DERIVED[card.targetingRule] then
		return {}
	end
	local result = {}
	for _, critter in model.critters do
		if not critter.defeated then
			local legal = card.targetingRule == "ANY"
				or (card.targetingRule == "ALLY" and critter.teamId == source.teamId and critter.id ~= source.id)
				or (card.targetingRule == "ENEMY" and critter.teamId ~= source.teamId)
			if legal then
				table.insert(result, critter.id)
			end
		end
	end
	table.sort(result)
	return result
end

local function needsSelection(card): boolean
	return card.targetingRule == "ALLY"
		or card.targetingRule == "ENEMY"
		or card.targetingRule == "ANY"
end

TargetSelection.legalTargetIds = legalTargetIds
TargetSelection.needsSelection = needsSelection
return table.freeze(TargetSelection)
