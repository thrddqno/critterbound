--!strict

export type QueueEntry = {
	card: {
		id: string,
		sourceCombatantId: string,
		[any]: any,
	},
	sourceOrder: number,
}

export type CritterIdentity = {
	id: string,
	displayName: string,
	slot: number,
	[any]: any,
}

export type QueueGroup = {
	sourceCombatantId: string,
	displayName: string,
	slot: number?,
	knownSource: boolean,
	entries: { QueueEntry },
}

local function group(entries: { QueueEntry }, critters: { CritterIdentity }): { QueueGroup }
	local crittersById: { [string]: CritterIdentity } = {}
	for _, critter in critters do
		crittersById[critter.id] = critter
	end

	local workingGroups: { [string]: { group: QueueGroup, indexedEntries: { any } } } = {}
	for index, entry in entries do
		local sourceId = entry.card.sourceCombatantId
		local working = workingGroups[sourceId]
		if working == nil then
			local critter = crittersById[sourceId]
			working = {
				group = {
					sourceCombatantId = sourceId,
					displayName = if critter ~= nil then critter.displayName else "Unknown Critter",
					slot = if critter ~= nil then critter.slot else nil,
					knownSource = critter ~= nil,
					entries = {},
				},
				indexedEntries = {},
			}
			workingGroups[sourceId] = working
		end
		table.insert(working.indexedEntries, { entry = entry, originalIndex = index })
	end

	local groups = {}
	for _, working in workingGroups do
		table.sort(working.indexedEntries, function(a, b)
			if a.entry.sourceOrder ~= b.entry.sourceOrder then
				return a.entry.sourceOrder < b.entry.sourceOrder
			end
			return a.originalIndex < b.originalIndex
		end)
		for _, indexed in working.indexedEntries do
			table.insert(working.group.entries, indexed.entry)
		end
		table.insert(groups, working.group)
	end

	table.sort(groups, function(a, b)
		if a.knownSource ~= b.knownSource then
			return a.knownSource
		end
		if a.slot ~= b.slot then
			return (a.slot or math.huge) < (b.slot or math.huge)
		end
		return a.sourceCombatantId < b.sourceCombatantId
	end)

	return groups
end

return table.freeze({ group = group })
