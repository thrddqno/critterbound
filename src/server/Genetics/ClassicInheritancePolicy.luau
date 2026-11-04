--!strict

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local GeneRegistry = requireShared("Genetics", "GeneRegistry")
local GenomeValidator = requireShared("Genetics", "GenomeValidator")
local GenotypeExpressor = requireShared("Genetics", "GenotypeExpressor")
local UnbiasedRandom = requireShared("Genetics", "UnbiasedRandom")

local ClassicInheritancePolicy = {}
local ALGORITHM = "CLASSIC_INHERITANCE_V1"

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
		return UnbiasedRandom.new(seedOrState)
	end
	if
		type(seedOrState) ~= "table"
		or seedOrState.algorithm ~= UnbiasedRandom.Algorithm
		or type(seedOrState.state) ~= "number"
		or seedOrState.state % 1 ~= 0
		or seedOrState.state < 1
		or seedOrState.state >= UnbiasedRandom.Modulus
		or type(seedOrState.drawCount) ~= "number"
		or seedOrState.drawCount % 1 ~= 0
		or seedOrState.drawCount < 0
	then
		return failure("INVALID_RNG_STATE", "Explicit deterministic RNG seed or state is required")
	end
	return { ok = true, value = clone(seedOrState) }
end

local function validateParent(parent, path: string, contentVersion: number)
	if
		type(parent) ~= "table"
		or type(parent.class) ~= "string"
		or type(parent.appearanceGenome) ~= "table"
		or type(parent.abilityGenome) ~= "table"
	then
		return failure("INVALID_GENETIC_PARENT", "Parent genetic input is malformed", path)
	end
	return GenomeValidator.validate(
		parent.appearanceGenome,
		parent.abilityGenome,
		parent.class,
		contentVersion
	)
end

local function parentPosition(random, rng)
	local roll
	rng, roll = random.nextInteger(rng, 1, 16)
	if roll <= 12 then
		return rng, "D"
	elseif roll <= 15 then
		return rng, "R1"
	end
	return rng, "R2"
end

local function inheritGenome(kind: string, slots, parentA, parentB, rng, random, trace)
	local resultSlots = {}
	local field = if kind == "APPEARANCE" then "appearanceGenome" else "abilityGenome"
	for _, slot in slots do
		local triplet = {}
		for _, childPosition in GeneRegistry.Positions do
			local parentRoll
			rng, parentRoll = random.nextInteger(rng, 1, 2)
			local parent = if parentRoll == 1 then parentA else parentB
			local inheritedPosition
			rng, inheritedPosition = parentPosition(random, rng)
			local geneId = parent[field].slots[slot][inheritedPosition]
			triplet[childPosition] = geneId
			table.insert(trace.selections, {
				genome = kind,
				slot = slot,
				childPosition = childPosition,
				parent = if parentRoll == 1 then "A" else "B",
				parentPosition = inheritedPosition,
				geneId = geneId,
			})
		end
		resultSlots[slot] = triplet
	end
	return { schemaVersion = 2, slots = resultSlots }, rng
end

-- R1 and R2 use the same independent source policy as D. This is Critterbound compatibility
-- behavior, not a claim about historical Axie recessive-slot generation.
local function inherit(parentA, parentB, offspringClass: string, seedOrState, dependencies)
	if dependencies ~= nil and type(dependencies) ~= "table" then
		return failure("INVALID_INHERITANCE_DEPENDENCIES", "Dependencies must be a table")
	end
	local contentVersion = if dependencies == nil
		then GeneRegistry.ContentVersion
		else dependencies.contentVersion or GeneRegistry.ContentVersion
	local random = if dependencies == nil
		then UnbiasedRandom
		else dependencies.random or UnbiasedRandom
	if contentVersion ~= GeneRegistry.ContentVersion then
		return failure(
			"UNSUPPORTED_GENE_CONTENT_VERSION",
			`Gene content version {tostring(contentVersion)} is not registered`
		)
	end
	if type(random) ~= "table" or type(random.nextInteger) ~= "function" then
		return failure("INVALID_RNG_DEPENDENCY", "RNG must provide nextInteger")
	end
	if GeneRegistry.defaultGenomes(offspringClass) == nil then
		return failure("INVALID_OFFSPRING_CLASS", "Offspring class is unknown")
	end
	local validationA = validateParent(parentA, "parentA", contentVersion)
	if not validationA.ok then
		return validationA
	end
	local validationB = validateParent(parentB, "parentB", contentVersion)
	if not validationB.ok then
		return validationB
	end
	local normalized = normalizeRng(seedOrState)
	if not normalized.ok then
		return normalized
	end

	local trace = {
		algorithm = ALGORITHM,
		contentVersion = contentVersion,
		selections = {},
		fallbacks = {},
	}
	local rng = normalized.value
	local appearanceGenome
	appearanceGenome, rng = inheritGenome(
		"APPEARANCE",
		GeneRegistry.AppearanceSlots,
		parentA,
		parentB,
		rng,
		random,
		trace
	)
	local abilityGenome
	abilityGenome, rng =
		inheritGenome("ABILITY", GeneRegistry.AbilitySlots, parentA, parentB, rng, random, trace)

	local genotypeValidation =
		GenomeValidator.validate(appearanceGenome, abilityGenome, offspringClass, contentVersion)
	if not genotypeValidation.ok then
		return genotypeValidation
	end
	local expression =
		GenotypeExpressor.express(appearanceGenome, abilityGenome, offspringClass, contentVersion)
	if not expression.ok then
		return expression
	end
	local phenotype = expression.value.phenotype
	for _, slot in phenotype.appearance.fallbackSlots do
		table.insert(trace.fallbacks, { genome = "APPEARANCE", slot = slot })
	end
	for _, slot in phenotype.abilities.fallbackSlots do
		table.insert(trace.fallbacks, { genome = "ABILITY", slot = slot })
	end
	trace.expression = expression.value.trace

	return {
		ok = true,
		value = {
			appearanceGenome = appearanceGenome,
			abilityGenome = abilityGenome,
			phenotype = phenotype,
			rng = rng,
			trace = trace,
		},
	}
end

ClassicInheritancePolicy.Algorithm = ALGORITHM
ClassicInheritancePolicy.ContentVersion = GeneRegistry.ContentVersion
ClassicInheritancePolicy.inherit = inherit

return table.freeze(ClassicInheritancePolicy)
