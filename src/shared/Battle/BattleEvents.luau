--!strict

export type BattleEvent = {
	id: string,
	battleId: string,
	sequence: number,
	roundNumber: number,
	kind: string,
	sourceCombatantId: string?,
	targetCombatantIds: { string },
	payload: { [string]: any },
}

export type Factory = {
	emit: (
		kind: string,
		roundNumber: number,
		payload: { [string]: any }?,
		sourceCombatantId: string?,
		targetCombatantIds: { string }?
	) -> BattleEvent,
	sequence: () -> number,
}

-- Event IDs derive only from battle identity and a monotonic sequence. No wall clock and
-- no RNG are used, so identical inputs produce identical event streams.
local function create(battleId: string, startSequence: number?): Factory
	local sequence = startSequence or 0

	local function emit(
		kind: string,
		roundNumber: number,
		payload: { [string]: any }?,
		sourceCombatantId: string?,
		targetCombatantIds: { string }?
	): BattleEvent
		sequence += 1
		return {
			id = `evt:{battleId}:{sequence}`,
			battleId = battleId,
			sequence = sequence,
			roundNumber = roundNumber,
			kind = kind,
			sourceCombatantId = sourceCombatantId,
			targetCombatantIds = targetCombatantIds or {},
			payload = payload or {},
		}
	end

	local function getSequence(): number
		return sequence
	end

	return table.freeze({
		emit = emit,
		sequence = getSequence,
	})
end

return table.freeze({
	create = create,
})
