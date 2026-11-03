--!strict

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local DeterministicRng = requireShared("Battle", "DeterministicRng")
local GeneRegistry = requireShared("Genetics", "GeneRegistry")
local GenomeValidator = requireShared("Genetics", "GenomeValidator")
local AppearanceResolver = requireShared("Genetics", "AppearanceResolver")
local AbilityResolver = requireShared("Genetics", "AbilityResolver")

local InheritanceEngine = {}

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function normalizeRng(seedOrState)
	if type(seedOrState) == "number" then
		return DeterministicRng.new(seedOrState)
	end
	if
		type(seedOrState) ~= "table"
		or seedOrState.algorithm ~= DeterministicRng.Algorithm
		or type(seedOrState.state) ~= "number"
		or seedOrState.state % 1 ~= 0
		or seedOrState.state < 1
		or seedOrState.state >= DeterministicRng.Modulus
		or type(seedOrState.drawCount) ~= "number"
		or seedOrState.drawCount % 1 ~= 0
		or seedOrState.drawCount < 0
	then
		return failure("INVALID_RNG_STATE", "Explicit deterministic RNG seed or state is required")
	end
	return { ok = true, value = clone(seedOrState) }
end

local function validateParent(parent, path: string)
	if
		type(parent) ~= "table"
		or type(parent.class) ~= "string"
		or type(parent.appearanceGenome) ~= "table"
		or type(parent.abilityGenome) ~= "table"
	then
		return failure("INVALID_GENETIC_PARENT", "Parent genetic input is malformed", path)
	end
	local validation =
		GenomeValidator.validate(parent.appearanceGenome, parent.abilityGenome, parent.class)
	if not validation.ok then
		return { ok = false, errors = validation.errors }
	end
	return { ok = true, value = true }
end

local function inheritedGenome(kind: string, slots, parentA, parentB, rng, trace)
	local resultSlots = {}
	local field = if kind == "APPEARANCE" then "appearanceGenome" else "abilityGenome"
	for _, slot in slots do
		local triplet = {}
		for _, childPosition in GeneRegistry.Positions do
			local parentRoll
			rng, parentRoll = DeterministicRng.nextInteger(rng, 1, 2)
			local parent = if parentRoll == 1 then parentA else parentB
			local alleleRoll
			rng, alleleRoll = DeterministicRng.nextInteger(rng, 1, 100)
			local parentPosition = if alleleRoll <= 75
				then "D"
				elseif alleleRoll <= 95 then "R1"
				else "R2"
			local geneId = parent[field].slots[slot][parentPosition]
			triplet[childPosition] = geneId
			table.insert(trace.selections, {
				genome = kind,
				slot = slot,
				childPosition = childPosition,
				parent = if parentRoll == 1 then "A" else "B",
				parentPosition = parentPosition,
				geneId = geneId,
			})
		end
		resultSlots[slot] = triplet
	end
	return { schemaVersion = 2, slots = resultSlots }, rng
end

local function compatibleMutationCandidates(
	kind: string,
	slot: string,
	className: string,
	rigFamily: string?,
	speciesId: string?,
	currentId: string
)
	local candidates = {}
	for geneId, definition in GeneRegistry.allById() do
		if
			geneId ~= currentId
			and definition.kind == kind
			and definition.slot == slot
			and GeneRegistry.classAllowed(definition, className)
			and (speciesId == nil or definition.speciesIds == nil or table.find(
				definition.speciesIds,
				speciesId
			) ~= nil)
			and (
				kind ~= "APPEARANCE"
				or slot == "body"
				or definition.bodyRigFamilies == nil
				or table.find(definition.bodyRigFamilies, rigFamily) ~= nil
			)
		then
			table.insert(candidates, geneId)
		end
	end
	table.sort(candidates)
	return candidates
end

local function mutateGenome(
	genome,
	kind: string,
	slots,
	className: string,
	rigFamily: string?,
	speciesId: string?,
	rng,
	chance: number,
	trace
)
	for _, slot in slots do
		for _, position in GeneRegistry.Positions do
			local chanceRoll
			rng, chanceRoll = DeterministicRng.nextInteger(rng, 1, 10_000)
			if chanceRoll <= chance then
				local currentId = genome.slots[slot][position]
				local candidates = compatibleMutationCandidates(
					kind,
					slot,
					className,
					rigFamily,
					speciesId,
					currentId
				)
				if #candidates > 0 then
					local candidateIndex
					rng, candidateIndex = DeterministicRng.nextInteger(rng, 1, #candidates)
					local replacementId = candidates[candidateIndex]
					genome.slots[slot][position] = replacementId
					table.insert(trace.mutations, {
						genome = kind,
						slot = slot,
						position = position,
						fromGeneId = currentId,
						toGeneId = replacementId,
					})
				end
			end
		end
	end
	return rng
end

local function repairFallbacks(
	genome,
	kind: string,
	className: string,
	resolver,
	trace,
	speciesId: string?
)
	local resolution = resolver.resolve(genome, className, speciesId)
	if not resolution.ok then
		return resolution
	end
	for _, slot in resolution.value.fallbackSlots do
		local previousId = genome.slots[slot].D
		local replacementId = resolution.value.resolvedGenesBySlot[slot]
		genome.slots[slot].D = replacementId
		table.insert(trace.fallbacks, {
			genome = kind,
			slot = slot,
			position = "D",
			fromGeneId = previousId,
			toGeneId = replacementId,
		})
	end
	return { ok = true, value = resolution.value }
end

local function inherit(parentA, parentB, offspringClass: string, seedOrState, options)
	if options ~= nil and type(options) ~= "table" then
		return failure("INVALID_INHERITANCE_OPTIONS", "Inheritance options must be a table")
	end
	local offspringDefaults = GeneRegistry.defaultGenomes(offspringClass)
	if offspringDefaults == nil then
		return failure("INVALID_OFFSPRING_CLASS", "Offspring class is unknown")
	end
	local validationA = validateParent(parentA, "parentA")
	if not validationA.ok then
		return validationA
	end
	local validationB = validateParent(parentB, "parentB")
	if not validationB.ok then
		return validationB
	end
	local normalized = normalizeRng(seedOrState)
	if not normalized.ok then
		return normalized
	end
	local mutation = if options == nil then nil else options.mutation
	local mutationEnabled = mutation ~= nil and mutation.enabled == true
	local mutationChance = if mutationEnabled then mutation.chancePerTenThousand else 0
	if
		mutationEnabled
		and (
			type(mutationChance) ~= "number"
			or mutationChance % 1 ~= 0
			or mutationChance < 0
			or mutationChance > 10_000
		)
	then
		return failure("INVALID_MUTATION_RATE", "Mutation chance must be integer 0-10000")
	end

	local trace = {
		algorithm = "INHERITANCE_V1",
		selections = {},
		fallbacks = {},
		mutations = {},
	}
	local rng = normalized.value
	local appearanceGenome
	appearanceGenome, rng =
		inheritedGenome("APPEARANCE", GeneRegistry.AppearanceSlots, parentA, parentB, rng, trace)
	local abilityGenome
	abilityGenome, rng =
		inheritedGenome("ABILITY", GeneRegistry.AbilitySlots, parentA, parentB, rng, trace)

	if mutationEnabled then
		local inheritedAppearance = AppearanceResolver.resolve(appearanceGenome, offspringClass)
		if not inheritedAppearance.ok then
			return inheritedAppearance
		end
		rng = mutateGenome(
			appearanceGenome,
			"APPEARANCE",
			GeneRegistry.AppearanceSlots,
			offspringClass,
			inheritedAppearance.value.bodyRigFamily,
			inheritedAppearance.value.speciesId,
			rng,
			mutationChance,
			trace
		)
		rng = mutateGenome(
			abilityGenome,
			"ABILITY",
			GeneRegistry.AbilitySlots,
			offspringClass,
			nil,
			inheritedAppearance.value.speciesId,
			rng,
			mutationChance,
			trace
		)
	end

	local appearanceRepair = repairFallbacks(
		appearanceGenome,
		"APPEARANCE",
		offspringClass,
		AppearanceResolver,
		trace,
		nil
	)
	if not appearanceRepair.ok then
		return appearanceRepair
	end
	local abilityRepair = repairFallbacks(
		abilityGenome,
		"ABILITY",
		offspringClass,
		AbilityResolver,
		trace,
		appearanceRepair.value.speciesId
	)
	if not abilityRepair.ok then
		return abilityRepair
	end
	local finalValidation =
		GenomeValidator.validate(appearanceGenome, abilityGenome, offspringClass)
	if not finalValidation.ok then
		return finalValidation
	end
	return {
		ok = true,
		value = {
			appearanceGenome = appearanceGenome,
			abilityGenome = abilityGenome,
			rng = rng,
			trace = trace,
		},
	}
end

InheritanceEngine.inherit = inherit
return table.freeze(InheritanceEngine)
