--!strict

local TrainingPlanner = {}

local function requireSharedBattle(name: string)
	if script ~= nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require((ReplicatedStorage.Shared.Battle :: any)[name])
	end
	return require(`../../shared/Battle/{name}`)
end

local function requireSharedDefinition(name: string)
	if script ~= nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require((ReplicatedStorage.Shared.Definitions :: any)[name])
	end
	return require(`../../shared/Definitions/{name}`)
end

local StatusEffects = requireSharedBattle("StatusEffects")
local PlanningRules = requireSharedBattle("PlanningRules")
local TargetingRules = requireSharedDefinition("TargetingRules")

local function indexById(values)
	local result = {}
	for _, value in values or {} do
		result[value.id] = value
	end
	return result
end

local function shieldTotal(combatant): number
	local total = 0
	for _, shield in combatant.shields or {} do
		total += shield.amount or 0
	end
	return total
end

local function orderedLiving(combatants, predicate)
	local result = {}
	for _, combatant in combatants do
		if combatant.currentHealth > 0 and predicate(combatant) then
			table.insert(result, combatant)
		end
	end
	table.sort(result, function(a, b)
		local aRatio = a.currentHealth / a.stats.maxHealth
		local bRatio = b.currentHealth / b.stats.maxHealth
		if aRatio ~= bRatio then
			return aRatio < bRatio
		end
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		return a.id < b.id
	end)
	return result
end

local function chooseTargets(rule: string, source, teamId: string, combatants): { string }?
	if TargetingRules.isAutomatic(rule) then
		return {}
	end
	if rule == "ALLY" then
		local allies = orderedLiving(combatants, function(value)
			return value.teamId == teamId and value.id ~= source.id
		end)
		return if allies[1] ~= nil then { allies[1].id } else nil
	end
	local enemies = orderedLiving(combatants, function(value)
		return value.teamId ~= teamId
	end)
	if rule == "ENEMY" or rule == "ANY" then
		return if enemies[1] ~= nil then { enemies[1].id } else nil
	end
	return nil
end

local function slowestEnemy(source, combatants)
	local enemies = {}
	for _, combatant in combatants do
		if combatant.currentHealth > 0 and combatant.teamId ~= source.teamId then
			table.insert(enemies, combatant)
		end
	end
	table.sort(enemies, function(a, b)
		local aSpeed = StatusEffects.effectiveSpeed(a)
		local bSpeed = StatusEffects.effectiveSpeed(b)
		if aSpeed ~= bSpeed then
			return aSpeed < bSpeed
		end
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end
		return a.id < b.id
	end)
	return enemies[1]
end

local function effectTotals(definition)
	local totals = { damage = 0, heal = 0, shield = 0, status = 0 }
	for _, effect in definition.effects or {} do
		if effect.kind == "DAMAGE" then
			totals.damage += effect.amount or 0
		elseif effect.kind == "HEAL" then
			totals.heal += effect.amount or 0
		elseif effect.kind == "SHIELD" then
			totals.shield += effect.amount or 0
		elseif effect.kind == "STATUS" then
			totals.status += effect.magnitude or 0
		end
	end
	return totals
end

local function targetForScore(targetIds, combatantsById, source)
	local target = if targetIds[1] ~= nil then combatantsById[targetIds[1]] else nil
	return target or source
end

local function scoreCandidate(definition, targetIds, combatantsById, source): number
	local totals = effectTotals(definition)
	local target = targetForScore(targetIds, combatantsById, source)
	local ratio = target.currentHealth / target.stats.maxHealth
	local score = totals.damage * 10 + totals.status * 5
	if totals.damage > 0 then
		score += 400
		if totals.damage >= target.currentHealth then
			score += 250
		end
	end
	if totals.heal > 0 then
		score += if ratio <= 0.6 then 1000 + (1 - ratio) * 200 else 40
	end
	if totals.shield > 0 then
		local useful = ratio <= 0.8 and shieldTotal(target) == 0
		score += if useful then 700 + (1 - ratio) * 100 else 90
	end
	return score - definition.energyCost * 2
end

local function plan(state, teamId: string, cardDefinitionsById)
	local teamState = nil
	for _, value in state.teamRoundStates do
		if value.teamId == teamId then
			teamState = value
			break
		end
	end
	if teamState == nil then
		return {
			ok = false,
			errors = { { code = "TEAM_NOT_FOUND", message = "AI team is missing" } },
		}
	end

	local combatantsById = indexById(state.combatants)
	local cardsById = indexById(state.cardInstances)
	local sourceByInstanceId = {}
	for _, combatant in state.combatants do
		sourceByInstanceId[combatant.critterInstanceId] = combatant
	end

	local candidates = {}
	for _, cardId in teamState.handCardInstanceIds or {} do
		local instance = cardsById[cardId]
		local definition = instance and cardDefinitionsById[instance.definitionId]
		local source = instance and sourceByInstanceId[instance.sourceCritterInstanceId]
		if
			definition ~= nil
			and source ~= nil
			and source.teamId == teamId
			and source.currentHealth > 0
		then
			local targets =
				chooseTargets(definition.targetingRule, source, teamId, state.combatants)
			if targets ~= nil then
				local scoreTargets = targets
				if definition.targetingRule == "ENEMY" then
					local target = slowestEnemy(source, state.combatants)
					scoreTargets = if target ~= nil then { target.id } else {}
				end
				table.insert(candidates, {
					cardInstanceId = cardId,
					sourceCombatantId = source.id,
					targetCombatantIds = targets,
					energyCost = definition.energyCost,
					score = scoreCandidate(definition, scoreTargets, combatantsById, source),
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.cardInstanceId < b.cardInstanceId
	end)

	local remaining = math.max(0, (teamState.energy or 0) - (teamState.reservedEnergy or 0))
	local requests = {}
	local sourceCounts = {}
	local alreadyQueued = {}
	for _, queued in teamState.queuedCards or {} do
		sourceCounts[queued.sourceCombatantId] = (sourceCounts[queued.sourceCombatantId] or 0) + 1
		alreadyQueued[queued.cardInstanceId] = true
	end
	for _, candidate in candidates do
		local sourceCount = sourceCounts[candidate.sourceCombatantId] or 0
		if
			not alreadyQueued[candidate.cardInstanceId]
			and candidate.energyCost <= remaining
			and sourceCount < PlanningRules.MaxQueuedCardsPerCritter
		then
			remaining -= candidate.energyCost
			sourceCounts[candidate.sourceCombatantId] = sourceCount + 1
			table.insert(requests, {
				cardInstanceId = candidate.cardInstanceId,
				sourceCombatantId = candidate.sourceCombatantId,
				targetCombatantIds = candidate.targetCombatantIds,
			})
		end
	end
	return { ok = true, value = { requests = requests, remainingEnergy = remaining } }
end

TrainingPlanner.plan = plan
return table.freeze(TrainingPlanner)
