--!strict

local ConceptionRng = {}
local MAX_SEED = 2_147_483_646

local function validSeed(value): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= 1
		and value <= MAX_SEED
end

local function hashParts(parts): number
	local value = 1
	for _, part in parts do
		local text = tostring(part)
		local framed = `{#text}:{text};`
		for index = 1, #framed do
			value = (value * 131 + string.byte(framed, index)) % MAX_SEED
		end
	end
	return value + 1
end

local function canonicalParents(parentAId: string, parentBId: string)
	if parentAId <= parentBId then
		return parentAId, parentBId
	end
	return parentBId, parentAId
end

local function derive(seed: number, parentAId: string, parentBId: string, versions, stream: string)
	if not validSeed(seed) then
		return nil
	end
	local first, second = canonicalParents(parentAId, parentBId)
	return hashParts({
		"CRITTERBOUND_CONCEPTION_V1",
		seed,
		first,
		second,
		versions.classInheritancePolicyVersion,
		versions.inheritancePolicyVersion,
		versions.mutationPolicyVersion,
		versions.geneContentVersion,
		versions.expressionVersion,
		stream,
	})
end

local function outcomeDigest(className: string, appearanceGenome, abilityGenome, metadata): string
	local parts = {
		"CRITTERBOUND_GENETICS_OUTCOME_V1",
		className,
		metadata.geneticsMode,
		metadata.classInheritancePolicyVersion,
		metadata.inheritancePolicyVersion,
		metadata.mutationPolicyVersion,
		metadata.mutationEnabled,
		metadata.geneContentVersion,
		metadata.expressionVersion,
		metadata.conceptionSeed,
		metadata.canonicalParentIds[1],
		metadata.canonicalParentIds[2],
	}
	local appearanceSlots = { "body", "eyes", "wings", "tail", "color", "markings", "accessories" }
	local abilitySlots = { "mouth", "horn", "back", "tail", "traits" }
	for _, slot in appearanceSlots do
		for _, position in { "D", "R1", "R2" } do
			table.insert(parts, appearanceGenome.slots[slot][position])
		end
	end
	for _, slot in abilitySlots do
		for _, position in { "D", "R1", "R2" } do
			table.insert(parts, abilityGenome.slots[slot][position])
		end
	end
	return `g1:{string.format("%08x", hashParts(parts))}`
end

ConceptionRng.MaxSeed = MAX_SEED
ConceptionRng.validSeed = validSeed
ConceptionRng.hashParts = hashParts
ConceptionRng.canonicalParents = canonicalParents
ConceptionRng.derive = derive
ConceptionRng.outcomeDigest = outcomeDigest

return table.freeze(ConceptionRng)
