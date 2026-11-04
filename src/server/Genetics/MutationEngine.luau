--!strict

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local GeneRegistry = requireShared("Genetics", "GeneRegistry")
local GenomeValidator = requireShared("Genetics", "GenomeValidator")
local UnbiasedRandom = requireShared("Genetics", "UnbiasedRandom")
local MutationPolicy = requireGenetics("MutationPolicy")

local MutationEngine = {}
local RECESSIVE_POSITIONS = { "R1", "R2" }
local ACTIVE_ABILITY_LOCI = { "mouth", "horn", "back", "tail" }
local ELIGIBLE_POSITION_COUNT = 22
local MAX_TRACE_ENTRIES = ELIGIBLE_POSITION_COUNT

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

local function validatePolicy(policy)
	if type(policy) ~= "table" then
		return failure("INVALID_MUTATION_POLICY", "Mutation policy must be a table", "policy")
	end
	if policy.version ~= MutationPolicy.Version then
		return failure(
			"UNSUPPORTED_MUTATION_POLICY",
			`Mutation policy {tostring(policy.version)} is not registered`,
			"policy.version"
		)
	end
	if type(policy.enabled) ~= "boolean" then
		return failure(
			"INVALID_MUTATION_POLICY",
			"Mutation enabled flag must be boolean",
			"policy.enabled"
		)
	end
	local numerator = policy.probabilityNumerator
	local denominator = policy.probabilityDenominator
	if
		type(numerator) ~= "number"
		or numerator % 1 ~= 0
		or type(denominator) ~= "number"
		or denominator % 1 ~= 0
		or denominator < 1
		or denominator > UnbiasedRandom.Modulus - 1
		or numerator < 0
		or numerator > denominator
	then
		return failure(
			"INVALID_MUTATION_PROBABILITY",
			"Mutation probability must be an integer fraction from zero through one",
			"policy"
		)
	end
	return { ok = true, value = true }
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
		return failure(
			"INVALID_RNG_STATE",
			"Explicit deterministic mutation RNG seed or state is required"
		)
	end
	return { ok = true, value = clone(seedOrState) }
end

local function registeredCandidateIndex(registry)
	local index = {}
	for geneId, definition in registry.allById() do
		local key = `{definition.kind}|{definition.slot}`
		local candidates = index[key] or {}
		table.insert(candidates, geneId)
		index[key] = candidates
	end
	for _, candidates in index do
		table.sort(candidates)
	end
	return index
end

local function registeredCandidates(
	candidateIndex,
	kind: string,
	locus: string,
	originalGeneId: string
)
	local candidates = {}
	for _, geneId in candidateIndex[`{kind}|{locus}`] or {} do
		if geneId ~= originalGeneId then
			table.insert(candidates, geneId)
		end
	end
	return candidates
end

local function appendOutcome(
	trace,
	layer: string,
	locus: string,
	position: string,
	previous: string,
	outcome
)
	assert(#trace.entries < MAX_TRACE_ENTRIES, "Mutation trace exceeded eligible position bound")
	table.insert(trace.entries, {
		layer = layer,
		locus = locus,
		position = position,
		previousGeneId = previous,
		newGeneId = outcome.newGeneId,
		outcome = outcome.name,
	})
end

local function mutateGenome(genome, layer: string, loci, policy, candidateIndex, random, rng, trace)
	for _, locus in loci do
		for _, position in RECESSIVE_POSITIONS do
			local previous = genome.slots[locus][position]
			local roll
			rng, roll = random.nextInteger(rng, 1, policy.probabilityDenominator)
			if roll > policy.probabilityNumerator then
				appendOutcome(trace, layer, locus, position, previous, { name = "NO_MUTATION" })
				continue
			end

			local candidates = registeredCandidates(candidateIndex, layer, locus, previous)
			if #candidates == 0 then
				appendOutcome(trace, layer, locus, position, previous, { name = "NO_ALTERNATIVE" })
				continue
			end

			local selectedIndex
			rng, selectedIndex = random.nextInteger(rng, 1, #candidates)
			local nextGeneId = candidates[selectedIndex]
			genome.slots[locus][position] = nextGeneId
			trace.mutationCount += 1
			appendOutcome(trace, layer, locus, position, previous, {
				name = "MUTATED",
				newGeneId = nextGeneId,
			})
		end
	end
	return rng
end

local function mutate(
	appearanceGenome,
	abilityGenome,
	offspringClass: string,
	seedOrState,
	policy,
	dependencies
)
	local selectedPolicy = policy or MutationPolicy.Default
	local policyValidation = validatePolicy(selectedPolicy)
	if not policyValidation.ok then
		return policyValidation
	end
	if dependencies ~= nil and type(dependencies) ~= "table" then
		return failure("INVALID_MUTATION_DEPENDENCIES", "Dependencies must be a table")
	end
	local registry = if dependencies == nil
		then GeneRegistry
		else dependencies.registry or GeneRegistry
	local validator = if dependencies == nil
		then GenomeValidator
		else dependencies.validator or GenomeValidator
	local random = if dependencies == nil
		then UnbiasedRandom
		else dependencies.random or UnbiasedRandom
	if
		type(registry) ~= "table"
		or type(registry.allById) ~= "function"
		or type(validator) ~= "table"
		or type(validator.validate) ~= "function"
		or type(random) ~= "table"
		or type(random.nextInteger) ~= "function"
	then
		return failure("INVALID_MUTATION_DEPENDENCY", "Mutation dependencies are malformed")
	end

	local genotypeValidation = validator.validate(appearanceGenome, abilityGenome, offspringClass)
	if not genotypeValidation.ok then
		return genotypeValidation
	end
	local normalized = normalizeRng(seedOrState)
	if not normalized.ok then
		return normalized
	end

	local resultAppearance = clone(appearanceGenome)
	local resultAbility = clone(abilityGenome)
	local rng = normalized.value
	local trace = {
		policyVersion = selectedPolicy.version,
		enabled = selectedPolicy.enabled,
		probabilityNumerator = selectedPolicy.probabilityNumerator,
		probabilityDenominator = selectedPolicy.probabilityDenominator,
		eligiblePositionCount = ELIGIBLE_POSITION_COUNT,
		mutationCount = 0,
		outcome = if selectedPolicy.enabled then "NO_MUTATIONS" else "DISABLED",
		rng = {
			algorithm = rng.algorithm,
			drawCountBefore = rng.drawCount,
			drawCountAfter = rng.drawCount,
		},
		entries = {},
	}

	if selectedPolicy.enabled then
		local candidateIndex = registeredCandidateIndex(registry)
		rng = mutateGenome(
			resultAppearance,
			"APPEARANCE",
			GeneRegistry.AppearanceSlots,
			selectedPolicy,
			candidateIndex,
			random,
			rng,
			trace
		)
		rng = mutateGenome(
			resultAbility,
			"ABILITY",
			ACTIVE_ABILITY_LOCI,
			selectedPolicy,
			candidateIndex,
			random,
			rng,
			trace
		)
		if trace.mutationCount > 0 then
			trace.outcome = "MUTATED"
		end
	end
	trace.rng.drawCountAfter = rng.drawCount

	local resultValidation = validator.validate(resultAppearance, resultAbility, offspringClass)
	if not resultValidation.ok then
		return resultValidation
	end
	return {
		ok = true,
		value = {
			appearanceGenome = resultAppearance,
			abilityGenome = resultAbility,
			rng = rng,
			trace = trace,
		},
	}
end

MutationEngine.EligiblePositionCount = ELIGIBLE_POSITION_COUNT
MutationEngine.MaxTraceEntries = MAX_TRACE_ENTRIES
MutationEngine.ActiveAbilityLoci = table.freeze(ACTIVE_ABILITY_LOCI)
MutationEngine.RecessivePositions = table.freeze(RECESSIVE_POSITIONS)
MutationEngine.mutate = mutate

return table.freeze(MutationEngine)
