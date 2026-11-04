--!strict

local function requirePlanningRules()
	if script ~= nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage.Shared.Battle.PlanningRules)
	end
	return require("../../shared/Battle/PlanningRules")
end

local PlanningRules = requirePlanningRules()

export type PlanningCard = {
	id: string,
	energyCost: number,
	sourceCombatantId: string,
	[any]: any,
}
export type QueueEntry = { card: PlanningCard, sourceOrder: number }
export type State = {
	selectedCardInstanceId: string?,
	queuedCards: { QueueEntry },
	committed: boolean,
	error: string?,
}
export type EnergyPreview = { available: number, allocated: number, remaining: number }
export type OperationResult = { ok: boolean, state: State, error: string? }

local function copyQueue(queue)
	return table.clone(queue)
end

local function new(): State
	return { selectedCardInstanceId = nil, queuedCards = {}, committed = false, error = nil }
end

local function energy(model, state: State): EnergyPreview
	local allocated = 0
	for _, entry in state.queuedCards do
		allocated += entry.card.energyCost
	end
	return {
		available = model.energy.available,
		allocated = allocated,
		remaining = model.energy.available - allocated,
	}
end

local function sourceQueueCount(state: State, sourceCombatantId: string): number
	local count = 0
	for _, entry in state.queuedCards do
		if entry.card.sourceCombatantId == sourceCombatantId then
			count += 1
		end
	end
	return count
end

local function cardDisabledReason(state: State, card: PlanningCard, model): string?
	if state.committed or not model.canPlan then
		return "Planning is locked"
	end
	for _, entry in state.queuedCards do
		if entry.card.id == card.id then
			return "Queued — tap queued card to remove"
		end
	end
	local source = nil
	for _, critter in model.critters or {} do
		if critter.id == card.sourceCombatantId then
			source = critter
			break
		end
	end
	if source == nil then
		return "Source Critter unavailable"
	end
	if source.defeated then
		return "Source Critter is defeated"
	end
	if
		sourceQueueCount(state, card.sourceCombatantId) >= PlanningRules.MaxQueuedCardsPerCritter
	then
		return `Queue full ({PlanningRules.MaxQueuedCardsPerCritter}/{PlanningRules.MaxQueuedCardsPerCritter})`
	end
	if energy(model, state).remaining < card.energyCost then
		return `Needs {card.energyCost} energy`
	end
	return nil
end

local function queueCard(state: State, card: PlanningCard, model): OperationResult
	if state.committed or not model.canPlan then
		return { ok = false, state = state, error = "PLANNING_LOCKED" }
	end
	for _, entry in state.queuedCards do
		if entry.card.id == card.id then
			return { ok = false, state = state, error = "CARD_ALREADY_QUEUED" }
		end
	end
	if
		sourceQueueCount(state, card.sourceCombatantId) >= PlanningRules.MaxQueuedCardsPerCritter
	then
		return { ok = false, state = state, error = "CRITTER_QUEUE_LIMIT_EXCEEDED" }
	end
	if energy(model, state).remaining < card.energyCost then
		return { ok = false, state = state, error = "INSUFFICIENT_ENERGY" }
	end

	local queue = copyQueue(state.queuedCards)
	local sourceOrder = 1
	for _, entry in queue do
		if entry.card.sourceCombatantId == card.sourceCombatantId then
			sourceOrder += 1
		end
	end
	table.insert(queue, { card = card, sourceOrder = sourceOrder })
	return {
		ok = true,
		state = {
			selectedCardInstanceId = card.id,
			queuedCards = queue,
			committed = false,
			error = nil,
		},
	}
end

local function removeCard(state: State, cardInstanceId: string): OperationResult
	if state.committed then
		return { ok = false, state = state, error = "PLANNING_LOCKED" }
	end
	local queue = {}
	local found = false
	for _, entry in state.queuedCards do
		if entry.card.id == cardInstanceId then
			found = true
		else
			table.insert(queue, { card = entry.card, sourceOrder = 0 })
		end
	end
	local sourceCounts = {}
	for _, entry in queue do
		local sourceId = entry.card.sourceCombatantId
		sourceCounts[sourceId] = (sourceCounts[sourceId] or 0) + 1
		entry.sourceOrder = sourceCounts[sourceId]
	end
	if not found then
		return { ok = false, state = state, error = "CARD_NOT_QUEUED" }
	end
	return {
		ok = true,
		state = {
			selectedCardInstanceId = nil,
			queuedCards = queue,
			committed = false,
			error = nil,
		},
	}
end

local function undo(state: State): OperationResult
	local last = state.queuedCards[#state.queuedCards]
	if last == nil then
		return { ok = false, state = state, error = "QUEUE_EMPTY" }
	end
	return removeCard(state, last.card.id)
end

local function clear(state: State): OperationResult
	if state.committed then
		return { ok = false, state = state, error = "PLANNING_LOCKED" }
	end
	return { ok = true, state = new() }
end

local function commit(state: State, model): OperationResult
	if state.committed or not model.canRequestCommit then
		return { ok = false, state = state, error = "COMMIT_LOCKED" }
	end
	return {
		ok = true,
		state = {
			selectedCardInstanceId = state.selectedCardInstanceId,
			queuedCards = copyQueue(state.queuedCards),
			committed = true,
			error = nil,
		},
	}
end

return table.freeze({
	new = new,
	energy = energy,
	sourceQueueCount = sourceQueueCount,
	MaxQueuedCardsPerCritter = PlanningRules.MaxQueuedCardsPerCritter,
	cardDisabledReason = cardDisabledReason,
	queueCard = queueCard,
	removeCard = removeCard,
	undo = undo,
	clear = clear,
	commit = commit,
	reset = new,
})
