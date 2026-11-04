--!strict

local TargetSelection = {}

local function requireTargetingRules()
	if script ~= nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage.Shared.Definitions.TargetingRules)
	end
	return require("../../shared/Definitions/TargetingRules")
end

local TargetingRules = requireTargetingRules()

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
	if TargetingRules.isAutomatic(card.targetingRule) then
		return {}
	end
	local result = {}
	for _, critter in model.critters do
		if not critter.defeated then
			local legal = card.targetingRule == "ANY"
				or (
					card.targetingRule == "ALLY"
					and critter.teamId == source.teamId
					and critter.id ~= source.id
				)
			if legal then
				table.insert(result, critter.id)
			end
		end
	end
	table.sort(result)
	return result
end

local function needsSelection(card): boolean
	return card.targetingRule == "ALLY" or card.targetingRule == "ANY"
end

local function ruleDescription(card): string
	if card.targetingRule == "ENEMY" then
		return "Target: automatic enemy"
	elseif card.targetingRule == "FRONT_ENEMY" then
		return "Target: automatic front enemy"
	elseif card.targetingRule == "ALLY" then
		return "Target: choose a highlighted ally"
	elseif card.targetingRule == "ANY" then
		return "Target: choose a highlighted Critter"
	elseif card.targetingRule == "SELF" then
		return "Target: self (automatic)"
	elseif card.targetingRule == "ALL_ALLIES" then
		return "Target: all allies (automatic)"
	elseif card.targetingRule == "ALL_ENEMIES" then
		return "Target: all enemies (automatic)"
	end
	return `Target: {card.targetingRule}`
end

TargetSelection.legalTargetIds = legalTargetIds
TargetSelection.needsSelection = needsSelection
TargetSelection.ruleDescription = ruleDescription
return table.freeze(TargetSelection)
