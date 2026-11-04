--!strict

local BattleSnapshotOrder = {}

export type Version = { battleId: string?, revision: number, planVersion: number }

local function version(snapshot): Version?
	if type(snapshot) ~= "table" or type(snapshot.revision) ~= "number" then
		return nil
	end
	return {
		battleId = if type(snapshot.battleState) == "table"
				and type(snapshot.battleState.id) == "string"
			then snapshot.battleState.id
			else nil,
		revision = snapshot.revision,
		planVersion = if type(snapshot.planVersion) == "number" then snapshot.planVersion else 0,
	}
end

local function shouldApply(current: Version?, snapshot): boolean
	local nextVersion = version(snapshot)
	if nextVersion == nil then
		return false
	end
	if current == nil then
		return true
	end
	if nextVersion.battleId ~= current.battleId then
		return false
	end
	if nextVersion.revision ~= current.revision then
		return nextVersion.revision > current.revision
	end
	return nextVersion.planVersion >= current.planVersion
end

BattleSnapshotOrder.version = version
BattleSnapshotOrder.shouldApply = shouldApply
return table.freeze(BattleSnapshotOrder)
