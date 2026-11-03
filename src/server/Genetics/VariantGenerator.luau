--!strict

-- Run 7E.2: deterministic generation of breedable acquisition Critters.
-- Uses only registered reachable genes, explicit RNG, and bounded work.

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
local CritterCatalog = requireShared("Definitions", "CritterCatalog")
local AcquisitionPools = requireShared("Definitions", "AcquisitionPools")

local VariantGenerator = {}
local GENERATOR_VERSION = 1
local MODULUS = 2147483647
local ABILITY_DOMINANT_SLOTS = { "mouth", "horn", "back", "tail" }
local CARRIER_POSITIONS = { "R1", "R2" }

local genesByKindSlot = {}
for _, definition in GeneRegistry.allById() do
	local key = `{definition.kind}|{definition.slot}`
	local list = genesByKindSlot[key] or {}
	table.insert(list, definition)
	genesByKindSlot[key] = list
end
for _, list in genesByKindSlot do
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
end

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

local function success(value)
	return { ok = true, value = value }
end

local function isInteger(value: any, minimum: number): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= minimum
		and value % 1 == 0
end

local function isIdentifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function isCrossClass(definition, className: string): boolean
	if definition.classes == nil or table.find(definition.classes, className) ~= nil then
		return false
	end
	return definition.compatibleClasses ~= nil
		and table.find(definition.compatibleClasses, className) ~= nil
end

local function pickWeighted(rng, state, candidates)
	local total = 0
	for _, candidate in candidates do
		total += candidate.weight
	end
	if total <= 0 then
		return nil, state, 0, 0
	end
	local roll
	state, roll = rng.nextInteger(state, 1, total)
	local cursor = 0
	for _, candidate in candidates do
		cursor += candidate.weight
		if roll <= cursor then
			return candidate, state, roll, total
		end
	end
	return candidates[#candidates], state, total, total
end

-- Park-Miller's multiplier shares factors with some weight totals, and its first
-- output is small for small seeds, so raw modulo can lock class choice to one
-- bucket. Class selection consumes one mixed draw and scales the full RNG range.
local function pickWeightedFullRange(rng, state, candidates)
	if rng.next == nil or rng.Modulus == nil then
		return pickWeighted(rng, state, candidates)
	end
	local total = 0
	for _, candidate in candidates do
		total += candidate.weight
	end
	if total <= 0 then
		return nil, state, 0, 0
	end
	local nextState, value = rng.next(state)
	local roll = math.floor(((value - 1) * total) / (rng.Modulus - 1)) + 1
	if roll > total then
		roll = total
	end
	local cursor = 0
	for _, candidate in candidates do
		cursor += candidate.weight
		if roll <= cursor then
			return candidate, nextState, roll, total
		end
	end
	return candidates[#candidates], nextState, total, total
end

local function new(dependencies)
	local deps = dependencies or {}
	local pools = deps.pools or AcquisitionPools
	local registry = deps.registry or GeneRegistry
	local validator = deps.validator or GenomeValidator
	local appearanceResolver = deps.appearanceResolver or AppearanceResolver
	local abilityResolver = deps.abilityResolver or AbilityResolver
	local catalog = deps.catalog or CritterCatalog
	local rng = deps.rng or DeterministicRng

	local service = {}

	local function weightFor(pool, definition, category: string): number
		local override = pool.weights.overrides[definition.id]
		if override ~= nil then
			return override
		end
		return pool.weights[category] or 0
	end

	local function crossAllowed(pool, definition, className: string, counts, dominant: boolean)
		if not isCrossClass(definition, className) then
			return true
		end
		local poolLimits = pool.limits
		if counts.crossTotal >= poolLimits.maxCrossClassGenes then
			return false
		end
		if dominant then
			return poolLimits.allowCrossClassDominant
				and counts.crossDominant < poolLimits.maxCrossClassDominant
		end
		return poolLimits.allowCrossClassCarriers
	end

	local function available(pool, definition): boolean
		return pool.disabledGeneIds[definition.id] ~= true
	end

	local function crossGeneAllowed(pool, definition, className: string): boolean
		if not isCrossClass(definition, className) then
			return true
		end
		if #pool.crossClassGeneIds == 0 then
			return true
		end
		return table.find(pool.crossClassGeneIds, definition.id) ~= nil
	end

	local function classify(counts, definition, className: string, dominant: boolean)
		if isCrossClass(definition, className) then
			counts.crossTotal += 1
			if dominant then
				counts.crossDominant += 1
			end
			return true
		end
		return false
	end

	local function filterAllowed(pool, className: string, candidates, counts)
		local filtered = {}
		for _, candidate in candidates do
			if crossAllowed(pool, candidate.definition, className, counts, false) then
				table.insert(filtered, candidate)
			end
		end
		return filtered
	end

	local function candidateWeight(pool, definition, category: string, className: string): number
		if isCrossClass(definition, className) and category ~= "carrier" then
			return weightFor(pool, definition, "crossClass")
		end
		return weightFor(pool, definition, category)
	end

	local function appearanceCandidates(
		pool,
		className: string,
		slot: string,
		defaultId: string,
		counts,
		bodyContext,
		allowVariant: boolean
	)
		local candidates = {}
		for _, definition in genesByKindSlot[`APPEARANCE|{slot}`] or {} do
			if
				not available(pool, definition)
				or not crossGeneAllowed(pool, definition, className)
			then
				continue
			end
			local isVariant = definition.id ~= defaultId
			if isVariant and not allowVariant then
				continue
			end
			local legal
			if slot == "body" then
				legal = registry.classAllowed(definition, className)
					and registry.appearanceExpressible(definition, className, nil, nil, nil)
			else
				legal = registry.classExpressible(definition, className)
					and registry.speciesExpressible(definition, className, bodyContext.speciesId)
					and registry.appearanceExpressible(
						definition,
						className,
						bodyContext.rigFamily,
						bodyContext.bodyShape,
						bodyContext.tags
					)
			end
			if not legal then
				continue
			end
			if isVariant and not crossAllowed(pool, definition, className, counts, true) then
				continue
			end
			local category = if isVariant then "appearanceVariant" else "appearanceDefault"
			local weight = candidateWeight(pool, definition, category, className)
			if weight > 0 then
				table.insert(candidates, {
					definition = definition,
					weight = weight,
					variant = isVariant,
					crossClass = isCrossClass(definition, className),
				})
			end
		end
		return candidates
	end

	local function appearanceCarrierCandidates(
		pool,
		className: string,
		slot: string,
		excludeId: string,
		counts
	)
		local candidates = {}
		for _, definition in genesByKindSlot[`APPEARANCE|{slot}`] or {} do
			if
				definition.id == excludeId
				or not available(pool, definition)
				or not crossGeneAllowed(pool, definition, className)
			then
				continue
			end
			if not registry.classExpressible(definition, className) then
				continue
			end
			if slot == "body" and not registry.classAllowed(definition, className) then
				continue
			end
			if not crossAllowed(pool, definition, className, counts, false) then
				continue
			end
			local weight = candidateWeight(pool, definition, "carrier", className)
			if weight > 0 then
				table.insert(candidates, {
					definition = definition,
					weight = weight,
					variant = true,
					crossClass = isCrossClass(definition, className),
				})
			end
		end
		return candidates
	end

	local function abilityCandidates(
		pool,
		className: string,
		slot: string,
		defaultId: string,
		abilityPool,
		usedAbilities,
		counts,
		allowVariant: boolean
	)
		local candidates = {}
		for _, definition in genesByKindSlot[`ABILITY|{slot}`] or {} do
			local abilityId = definition.abilityId
			if
				abilityId == nil
				or not available(pool, definition)
				or not crossGeneAllowed(pool, definition, className)
				or not abilityPool[abilityId]
				or usedAbilities[abilityId]
				or not registry.classExpressible(definition, className)
				or abilityResolver.cardClassFor(abilityId, className) == nil
			then
				continue
			end
			local isVariant = definition.id ~= defaultId
			if isVariant and not allowVariant then
				continue
			end
			if isVariant and not crossAllowed(pool, definition, className, counts, true) then
				continue
			end
			local category = if isVariant then "abilityVariant" else "abilityDefault"
			local weight = candidateWeight(pool, definition, category, className)
			if weight > 0 then
				table.insert(candidates, {
					definition = definition,
					weight = weight,
					variant = isVariant,
					crossClass = isCrossClass(definition, className),
				})
			end
		end
		return candidates
	end

	local function abilityCarrierCandidates(
		pool,
		className: string,
		slot: string,
		excludeId: string,
		abilityPool,
		usedAbilities,
		counts
	)
		local candidates = {}
		for _, definition in genesByKindSlot[`ABILITY|{slot}`] or {} do
			local abilityId = definition.abilityId
			if
				abilityId == nil
				or definition.id == excludeId
				or not available(pool, definition)
				or not crossGeneAllowed(pool, definition, className)
				or not abilityPool[abilityId]
				or usedAbilities[abilityId]
				or not registry.classExpressible(definition, className)
				or abilityResolver.cardClassFor(abilityId, className) == nil
			then
				continue
			end
			if not crossAllowed(pool, definition, className, counts, false) then
				continue
			end
			local weight = candidateWeight(pool, definition, "carrier", className)
			if weight > 0 then
				table.insert(candidates, {
					definition = definition,
					weight = weight,
					variant = true,
					crossClass = isCrossClass(definition, className),
				})
			end
		end
		return candidates
	end

	local function attemptSeed(seed: number, attempt: number): number
		local value = seed + attempt - 1
		if value >= MODULUS then
			value = value % (MODULUS - 1) + 1
		end
		return value
	end

	local function generateOnce(pool, explicitClass: string?, seed: number)
		local rngState = rng.new(seed)
		if not rngState.ok then
			return rngState
		end
		local state = rngState.value
		-- Discard one draw so class selection is not dominated by tiny seed values.
		state = rng.next(state)
		local trace = {
			generatorVersion = GENERATOR_VERSION,
			poolId = pool.id,
			poolVersion = pool.version,
			source = pool.source,
			seed = seed,
			steps = {},
		}
		local counts = {
			appearanceVariants = 0,
			abilityVariants = 0,
			crossTotal = 0,
			crossDominant = 0,
			carrierSlots = 0,
		}

		local className = explicitClass
		if className == nil then
			local classCandidates = {}
			for _, eligibleClass in pool.eligibleClasses do
				table.insert(classCandidates, {
					className = eligibleClass,
					weight = pool.classWeights[eligibleClass],
				})
			end
			local picked, nextState, roll, total =
				pickWeightedFullRange(rng, state, classCandidates)
			if picked == nil then
				return failure("INVALID_ACQUISITION_POOL", "Pool has no class weight")
			end
			state = nextState
			className = picked.className
			table.insert(trace.steps, {
				stage = "CLASS",
				className = className,
				roll = roll,
				total = total,
			})
		else
			table.insert(trace.steps, { stage = "CLASS", className = className, explicit = true })
		end

		local definition = catalog.getByClass(className)
		local defaults = registry.defaultGenomes(className)
		if definition == nil or defaults == nil then
			return failure("UNKNOWN_CRITTER_DEFINITION", "Class definition is unavailable")
		end
		local abilityPool = {}
		for _, abilityId in definition.abilityPool or definition.abilityIds do
			abilityPool[abilityId] = true
		end

		local appearanceSlots = {}
		local abilitySlots = {}

		-- Body first: body tags/shape determine which layer variants may express.
		local bodyDefault = defaults.appearanceGenome.slots.body.D
		local bodyEntries = appearanceCandidates(
			pool,
			className,
			"body",
			bodyDefault,
			counts,
			nil,
			counts.appearanceVariants < pool.limits.maxAppearanceVariants
		)
		local bodyPick, nextState, bodyRoll, bodyTotal = pickWeighted(rng, state, bodyEntries)
		if bodyPick == nil then
			return failure("VARIANT_GENERATION_FAILED", "No legal body gene is available")
		end
		state = nextState
		local bodyTriplet = { D = bodyPick.definition.id, R1 = bodyDefault, R2 = bodyDefault }
		bodyTriplet.slotName = "body"
		if bodyPick.variant then
			counts.appearanceVariants += 1
		end
		classify(counts, bodyPick.definition, className, true)
		table.insert(trace.steps, {
			stage = "APPEARANCE",
			slot = "body",
			position = "D",
			geneId = bodyPick.definition.id,
			roll = bodyRoll,
			weight = bodyPick.weight,
			total = bodyTotal,
			variant = bodyPick.variant,
			crossClass = bodyPick.crossClass,
		})
		if counts.carrierSlots < pool.limits.maxCarrierSlots then
			local carrierCandidates =
				appearanceCarrierCandidates(pool, className, "body", bodyPick.definition.id, counts)
			local usedCarrierSlot = false
			for _, position in CARRIER_POSITIONS do
				carrierCandidates = filterAllowed(pool, className, carrierCandidates, counts)
				if #carrierCandidates == 0 then
					break
				end
				local carrierRoll
				state, carrierRoll = rng.nextInteger(state, 1, 100)
				if carrierRoll > pool.limits.carrierPercent then
					continue
				end
				local carrier
				carrier, state = pickWeighted(rng, state, carrierCandidates)
				if carrier ~= nil then
					bodyTriplet[position] = carrier.definition.id
					usedCarrierSlot = true
					classify(counts, carrier.definition, className, false)
					table.insert(trace.steps, {
						stage = "APPEARANCE",
						slot = "body",
						position = position,
						geneId = carrier.definition.id,
						weight = carrier.weight,
						variant = true,
						crossClass = carrier.crossClass,
						carrier = true,
					})
				end
			end
			if usedCarrierSlot then
				counts.carrierSlots += 1
			end
		end
		bodyTriplet.slotName = nil
		appearanceSlots.body = bodyTriplet

		local bodyDefinition = registry.get(bodyPick.definition.id)
		if bodyDefinition == nil or bodyDefinition.bodyRigFamily == nil then
			return failure("UNRESOLVED_APPEARANCE_GENE", "Body gene is unavailable")
		end
		local bodyContext = {
			rigFamily = bodyDefinition.bodyRigFamily,
			speciesId = bodyDefinition.speciesId,
			bodyShape = bodyDefinition.bodyShape or "standard",
			tags = registry.providedTags(bodyDefinition),
		}

		for _, slot in registry.AppearanceSlots do
			if slot == "body" then
				continue
			end
			local defaultId = defaults.appearanceGenome.slots[slot].D
			local entries = appearanceCandidates(
				pool,
				className,
				slot,
				defaultId,
				counts,
				bodyContext,
				counts.appearanceVariants < pool.limits.maxAppearanceVariants
			)
			local picked, newState, roll, total = pickWeighted(rng, state, entries)
			if picked == nil then
				return failure(
					"VARIANT_GENERATION_FAILED",
					`No legal appearance gene is available for {slot}`
				)
			end
			state = newState
			local triplet = { D = picked.definition.id, R1 = defaultId, R2 = defaultId }
			triplet.slotName = slot
			if picked.variant then
				counts.appearanceVariants += 1
			end
			classify(counts, picked.definition, className, true)
			table.insert(trace.steps, {
				stage = "APPEARANCE",
				slot = slot,
				position = "D",
				geneId = picked.definition.id,
				roll = roll,
				weight = picked.weight,
				total = total,
				variant = picked.variant,
				crossClass = picked.crossClass,
			})
			if counts.carrierSlots < pool.limits.maxCarrierSlots then
				local carrierCandidates =
					appearanceCarrierCandidates(pool, className, slot, picked.definition.id, counts)
				local usedCarrierSlot = false
				for _, position in CARRIER_POSITIONS do
					carrierCandidates = filterAllowed(pool, className, carrierCandidates, counts)
					if #carrierCandidates == 0 then
						break
					end
					local carrierRoll
					state, carrierRoll = rng.nextInteger(state, 1, 100)
					if carrierRoll > pool.limits.carrierPercent then
						continue
					end
					local carrier
					carrier, state = pickWeighted(rng, state, carrierCandidates)
					if carrier ~= nil then
						triplet[position] = carrier.definition.id
						usedCarrierSlot = true
						classify(counts, carrier.definition, className, false)
						table.insert(trace.steps, {
							stage = "APPEARANCE",
							slot = slot,
							position = position,
							geneId = carrier.definition.id,
							weight = carrier.weight,
							variant = true,
							crossClass = carrier.crossClass,
							carrier = true,
						})
					end
				end
				if usedCarrierSlot then
					counts.carrierSlots += 1
				end
			end
			triplet.slotName = nil
			appearanceSlots[slot] = triplet
		end

		if counts.appearanceVariants == 0 and pool.limits.forceVisibleVariant then
			local forced = {}
			for _, slot in registry.AppearanceSlots do
				if slot ~= "body" then
					local defaultId = defaults.appearanceGenome.slots[slot].D
					for _, candidate in
						appearanceCandidates(
							pool,
							className,
							slot,
							defaultId,
							counts,
							bodyContext,
							true
						)
					do
						if candidate.variant then
							table.insert(forced, {
								slot = slot,
								definition = candidate.definition,
								weight = candidate.weight,
								crossClass = candidate.crossClass,
							})
						end
					end
				end
			end
			local forcedPick, forcedState, forcedRoll, forcedTotal =
				pickWeighted(rng, state, forced)
			if forcedPick == nil then
				return failure(
					"VARIANT_GENERATION_FAILED",
					"No visible appearance variant is available"
				)
			end
			state = forcedState
			appearanceSlots[forcedPick.slot].D = forcedPick.definition.id
			counts.appearanceVariants += 1
			classify(counts, forcedPick.definition, className, true)
			trace.forcedVariant = forcedPick.slot
			table.insert(trace.steps, {
				stage = "APPEARANCE",
				slot = forcedPick.slot,
				position = "D",
				geneId = forcedPick.definition.id,
				roll = forcedRoll,
				weight = forcedPick.weight,
				total = forcedTotal,
				variant = true,
				crossClass = forcedPick.crossClass,
				forced = true,
			})
		end

		local usedAbilities = {}
		for _, slot in ABILITY_DOMINANT_SLOTS do
			local defaultId = defaults.abilityGenome.slots[slot].D
			local entries = abilityCandidates(
				pool,
				className,
				slot,
				defaultId,
				abilityPool,
				usedAbilities,
				counts,
				counts.abilityVariants < pool.limits.maxAbilityVariants
			)
			local picked, newState, roll, total = pickWeighted(rng, state, entries)
			if picked == nil then
				return failure(
					"VARIANT_GENERATION_FAILED",
					`No legal ability gene is available for {slot}`
				)
			end
			state = newState
			usedAbilities[picked.definition.abilityId] = true
			local triplet = { D = picked.definition.id, R1 = defaultId, R2 = defaultId }
			triplet.slotName = slot
			if picked.variant then
				counts.abilityVariants += 1
			end
			classify(counts, picked.definition, className, true)
			table.insert(trace.steps, {
				stage = "ABILITY",
				slot = slot,
				position = "D",
				geneId = picked.definition.id,
				abilityId = picked.definition.abilityId,
				roll = roll,
				weight = picked.weight,
				total = total,
				variant = picked.variant,
				crossClass = picked.crossClass,
			})
			if counts.carrierSlots < pool.limits.maxCarrierSlots then
				local carrierCandidates = abilityCarrierCandidates(
					pool,
					className,
					slot,
					picked.definition.id,
					abilityPool,
					usedAbilities,
					counts
				)
				local usedCarrierSlot = false
				for _, position in CARRIER_POSITIONS do
					carrierCandidates = filterAllowed(pool, className, carrierCandidates, counts)
					if #carrierCandidates == 0 then
						break
					end
					local carrierRoll
					state, carrierRoll = rng.nextInteger(state, 1, 100)
					if carrierRoll > pool.limits.carrierPercent then
						continue
					end
					local carrier
					carrier, state = pickWeighted(rng, state, carrierCandidates)
					if carrier ~= nil then
						triplet[position] = carrier.definition.id
						usedCarrierSlot = true
						classify(counts, carrier.definition, className, false)
						table.insert(trace.steps, {
							stage = "ABILITY",
							slot = slot,
							position = position,
							geneId = carrier.definition.id,
							abilityId = carrier.definition.abilityId,
							weight = carrier.weight,
							variant = true,
							crossClass = carrier.crossClass,
							carrier = true,
						})
					end
				end
				if usedCarrierSlot then
					counts.carrierSlots += 1
				end
			end
			triplet.slotName = nil
			abilitySlots[slot] = triplet
		end

		local neutralId = defaults.abilityGenome.slots.traits.D
		abilitySlots.traits = { D = neutralId, R1 = neutralId, R2 = neutralId }

		local appearanceGenome = { schemaVersion = 2, slots = appearanceSlots }
		local abilityGenome = { schemaVersion = 2, slots = abilitySlots }
		trace.counts = counts
		trace.class = className
		trace.definitionId = definition.id
		return success({
			class = className,
			definitionId = definition.id,
			appearanceGenome = appearanceGenome,
			abilityGenome = abilityGenome,
			poolId = pool.id,
			poolVersion = pool.version,
			source = pool.source,
			generatorVersion = GENERATOR_VERSION,
			seed = seed,
			trace = trace,
		})
	end

	function service.PreviewPool(poolId: string, className: string?)
		if not isIdentifier(poolId) then
			return failure("INVALID_POOL_ID", "Acquisition pool ID is malformed")
		end
		local poolResult = pools.validate(poolId)
		if not poolResult.ok then
			return poolResult
		end
		local pool = poolResult.value
		if className ~= nil and table.find(pool.eligibleClasses, className) == nil then
			return failure("CLASS_NOT_IN_POOL", "Class is not eligible for this acquisition pool")
		end
		local availabilityByClass = {}
		for _, eligibleClass in pool.eligibleClasses do
			local definition = catalog.getByClass(eligibleClass)
			local abilityPool = {}
			if definition ~= nil then
				for _, abilityId in definition.abilityPool or definition.abilityIds do
					abilityPool[abilityId] = true
				end
			end
			local appearanceCounts = {}
			for _, slot in registry.AppearanceSlots do
				local count = 0
				for _, candidate in genesByKindSlot[`APPEARANCE|{slot}`] or {} do
					if
						available(pool, candidate)
						and registry.classExpressible(candidate, eligibleClass)
					then
						count += 1
					end
				end
				appearanceCounts[slot] = count
			end
			local abilityCounts = {}
			for _, slot in registry.AbilitySlots do
				local count = 0
				for _, candidate in genesByKindSlot[`ABILITY|{slot}`] or {} do
					if
						available(pool, candidate)
						and registry.classExpressible(candidate, eligibleClass)
						and (candidate.abilityId == nil or abilityPool[candidate.abilityId])
						and (
							candidate.abilityId == nil
							or abilityResolver.cardClassFor(candidate.abilityId, eligibleClass)
								~= nil
						)
					then
						count += 1
					end
				end
				abilityCounts[slot] = count
			end
			availabilityByClass[eligibleClass] = {
				appearanceBySlot = appearanceCounts,
				abilityBySlot = abilityCounts,
			}
		end
		return success({
			id = pool.id,
			version = pool.version,
			source = pool.source,
			description = pool.description,
			eligibleClasses = clone(pool.eligibleClasses),
			classWeights = clone(pool.classWeights),
			requireExplicitClass = pool.requireExplicitClass,
			limits = clone(pool.limits),
			availabilityByClass = availabilityByClass,
		})
	end

	function service.Generate(input)
		if type(input) ~= "table" then
			return failure("INVALID_GENERATION_INPUT", "Generation input is required")
		end
		if not isIdentifier(input.poolId) then
			return failure("INVALID_POOL_ID", "Acquisition pool ID is malformed")
		end
		if not isInteger(input.seed, 1) or input.seed >= MODULUS then
			return failure("INVALID_RNG_SEED", "Seed must be an integer from 1 to 2147483646")
		end
		if input.class ~= nil and not isIdentifier(input.class) then
			return failure("INVALID_CLASS", "Requested class is malformed")
		end
		local poolResult = pools.validate(input.poolId)
		if not poolResult.ok then
			return poolResult
		end
		local pool = poolResult.value
		local explicitClass = input.class
		if explicitClass ~= nil and table.find(pool.eligibleClasses, explicitClass) == nil then
			return failure("CLASS_NOT_IN_POOL", "Class is not eligible for this acquisition pool")
		end
		if pool.requireExplicitClass and explicitClass == nil then
			return failure("CLASS_REQUIRED", "This acquisition pool requires an explicit class")
		end

		local lastFailure = nil
		for attempt = 1, pool.limits.maxGenerationAttempts do
			local generated = generateOnce(pool, explicitClass, attemptSeed(input.seed, attempt))
			if generated.ok then
				local value = generated.value
				local validation =
					validator.validate(value.appearanceGenome, value.abilityGenome, value.class)
				if validation.ok then
					local appearance =
						appearanceResolver.resolve(value.appearanceGenome, value.class)
					local abilities = if appearance.ok
						then abilityResolver.resolve(
							value.abilityGenome,
							value.class,
							appearance.value.speciesId
						)
						else nil
					if abilities ~= nil and abilities.ok and #abilities.value.abilityIds == 4 then
						value.trace.attempts = attempt
						value.trace.fallbackSlots = {
							appearance = appearance.value.fallbackSlots,
							ability = abilities.value.fallbackSlots,
						}
						return success(value)
					end
					lastFailure = abilities or appearance
				else
					lastFailure = validation
				end
			else
				lastFailure = generated
			end
		end

		local details = if lastFailure ~= nil
				and lastFailure.errors ~= nil
				and lastFailure.errors[1] ~= nil
			then lastFailure.errors[1]
			else nil
		return failure(
			"VARIANT_GENERATION_FAILED",
			if details == nil
				then "Variant generation failed validation"
				else `Variant generation failed: {details.code}`
		)
	end

	service.GeneratorVersion = GENERATOR_VERSION
	return table.freeze(service)
end

VariantGenerator.new = new
VariantGenerator.GeneratorVersion = GENERATOR_VERSION
return table.freeze(VariantGenerator)
