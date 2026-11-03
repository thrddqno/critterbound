--!strict

-- Authoring data for Run 7E.2 acquisition sources. Weights are internal selection
-- weights, not player-facing probabilities. Pools only reference registered genes
-- through GeneRegistry compatibility checks in VariantGenerator.

local AcquisitionPools = {}

local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
local CLASS_LOOKUP = {}
for _, className in CLASSES do
	CLASS_LOOKUP[className] = true
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

local function limits(
	maxAppearanceVariants: number,
	maxAbilityVariants: number,
	maxCrossClassGenes: number,
	maxCrossClassDominant: number,
	allowCrossClassCarriers: boolean,
	allowCrossClassDominant: boolean,
	carrierPercent: number,
	maxCarrierSlots: number
)
	return {
		maxAppearanceVariants = maxAppearanceVariants,
		maxAbilityVariants = maxAbilityVariants,
		maxCrossClassGenes = maxCrossClassGenes,
		maxCrossClassDominant = maxCrossClassDominant,
		allowCrossClassCarriers = allowCrossClassCarriers,
		allowCrossClassDominant = allowCrossClassDominant,
		carrierPercent = carrierPercent,
		maxCarrierSlots = maxCarrierSlots,
		forceVisibleVariant = true,
		maxGenerationAttempts = 3,
	}
end

local definitions = {
	COMMON_FOUNDERS = {
		id = "COMMON_FOUNDERS",
		version = 1,
		source = "ACQUISITION.COMMON_FOUNDERS",
		description = "Broad, low-variance founders for every class.",
		eligibleClasses = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" },
		classWeights = { Stone = 1, Feral = 1, Verdant = 1, Tide = 1, Gale = 1, Shade = 1 },
		requireExplicitClass = false,
		weights = {
			appearanceDefault = 10,
			appearanceVariant = 4,
			abilityDefault = 10,
			abilityVariant = 4,
			crossClass = 2,
			carrier = 6,
			overrides = {
				["gene.appearance.eyes.universal.bright"] = 3,
			},
		},
		disabledGeneIds = {},
		crossClassGeneIds = {},
		limits = limits(2, 2, 0, 0, false, false, 25, 4),
	},
	CLASS_SPECIFIC_FOUNDERS = {
		id = "CLASS_SPECIFIC_FOUNDERS",
		version = 1,
		source = "ACQUISITION.CLASS_SPECIFIC_FOUNDERS",
		description = "Class-focused founders with stronger native variant pressure.",
		eligibleClasses = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" },
		classWeights = { Stone = 1, Feral = 1, Verdant = 1, Tide = 1, Gale = 1, Shade = 1 },
		requireExplicitClass = true,
		weights = {
			appearanceDefault = 10,
			appearanceVariant = 8,
			abilityDefault = 10,
			abilityVariant = 8,
			crossClass = 2,
			carrier = 8,
			overrides = {
				["gene.appearance.eyes.universal.bright"] = 5,
			},
		},
		disabledGeneIds = {},
		crossClassGeneIds = {},
		limits = limits(3, 3, 0, 0, false, false, 40, 6),
	},
	CROSS_CLASS_CARRIERS = {
		id = "CROSS_CLASS_CARRIERS",
		version = 1,
		source = "ACQUISITION.CROSS_CLASS_CARRIERS",
		description = "Controlled cross-class carriers using explicit compatibility metadata.",
		eligibleClasses = { "Stone", "Tide", "Feral" },
		classWeights = { Stone = 2, Tide = 3, Feral = 2 },
		requireExplicitClass = false,
		weights = {
			appearanceDefault = 10,
			appearanceVariant = 5,
			abilityDefault = 10,
			abilityVariant = 5,
			crossClass = 4,
			carrier = 8,
			overrides = {},
		},
		disabledGeneIds = {},
		crossClassGeneIds = {
			"gene.appearance.tail.gale.feather",
			"gene.appearance.wings.gale.feathered",
			"gene.appearance.accessories.gale.crest",
			"gene.appearance.markings.verdant.speckled",
			"gene.ability.horn.verdant.bloom",
			"gene.ability.back.gale.tailwind",
		},
		limits = limits(2, 2, 2, 1, true, true, 55, 6),
	},
}

local function validate(poolId: string)
	local pool = definitions[poolId]
	if pool == nil then
		return failure("UNKNOWN_ACQUISITION_POOL", "Acquisition pool is not registered", "poolId")
	end
	if pool.id ~= poolId then
		return failure("INVALID_ACQUISITION_POOL", "Acquisition pool identity is invalid", "id")
	end
	if not isInteger(pool.version, 1) then
		return failure("INVALID_ACQUISITION_POOL", "Pool version is invalid", "version")
	end
	if not isIdentifier(pool.source) then
		return failure("INVALID_ACQUISITION_POOL", "Pool source is invalid", "source")
	end
	if type(pool.description) ~= "string" or #pool.description == 0 then
		return failure("INVALID_ACQUISITION_POOL", "Pool description is invalid", "description")
	end
	if type(pool.eligibleClasses) ~= "table" or #pool.eligibleClasses == 0 then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Pool requires eligible classes",
			"eligibleClasses"
		)
	end
	local seenClasses = {}
	for index, className in pool.eligibleClasses do
		if not CLASS_LOOKUP[className] then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool eligible class is unknown",
				`eligibleClasses[{index}]`
			)
		end
		if seenClasses[className] then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool eligible classes must be unique",
				`eligibleClasses[{index}]`
			)
		end
		seenClasses[className] = true
		if not isInteger(pool.classWeights[className], 1) then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool class weight is invalid",
				`classWeights.{className}`
			)
		end
	end
	if type(pool.requireExplicitClass) ~= "boolean" then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Pool explicit-class flag is invalid",
			"requireExplicitClass"
		)
	end
	local weights = pool.weights
	if type(weights) ~= "table" then
		return failure("INVALID_ACQUISITION_POOL", "Pool weights are missing", "weights")
	end
	for _, field in
		{
			"appearanceDefault",
			"appearanceVariant",
			"abilityDefault",
			"abilityVariant",
			"crossClass",
			"carrier",
		}
	do
		if not isInteger(weights[field], 0) then
			return failure("INVALID_ACQUISITION_POOL", "Pool weight is invalid", `weights.{field}`)
		end
	end
	if type(weights.overrides) ~= "table" then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Pool overrides are invalid",
			"weights.overrides"
		)
	end
	for geneId, weight in weights.overrides do
		if not isIdentifier(geneId) or not isInteger(weight, 0) then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool override is invalid",
				`weights.overrides.{tostring(geneId)}`
			)
		end
	end
	if type(pool.disabledGeneIds) ~= "table" then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Pool disabled genes are invalid",
			"disabledGeneIds"
		)
	end
	for geneId, disabled in pool.disabledGeneIds do
		if not isIdentifier(geneId) or type(disabled) ~= "boolean" then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool disabled gene entry is invalid",
				`disabledGeneIds.{tostring(geneId)}`
			)
		end
	end
	if type(pool.crossClassGeneIds) ~= "table" then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Pool cross-class gene list is invalid",
			"crossClassGeneIds"
		)
	end
	for index, geneId in pool.crossClassGeneIds do
		if not isIdentifier(geneId) then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool cross-class gene is invalid",
				`crossClassGeneIds[{index}]`
			)
		end
	end
	local poolLimits = pool.limits
	if type(poolLimits) ~= "table" then
		return failure("INVALID_ACQUISITION_POOL", "Pool limits are missing", "limits")
	end
	for _, field in
		{
			"maxAppearanceVariants",
			"maxAbilityVariants",
			"maxCrossClassGenes",
			"maxCrossClassDominant",
			"maxCarrierSlots",
		}
	do
		if not isInteger(poolLimits[field], 0) then
			return failure("INVALID_ACQUISITION_POOL", "Pool limit is invalid", `limits.{field}`)
		end
	end
	for _, field in { "allowCrossClassCarriers", "allowCrossClassDominant", "forceVisibleVariant" } do
		if type(poolLimits[field]) ~= "boolean" then
			return failure(
				"INVALID_ACQUISITION_POOL",
				"Pool limit flag is invalid",
				`limits.{field}`
			)
		end
	end
	if not isInteger(poolLimits.carrierPercent, 0) or poolLimits.carrierPercent > 100 then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Carrier percent must be between 0 and 100",
			"limits.carrierPercent"
		)
	end
	if
		not isInteger(poolLimits.maxGenerationAttempts, 1)
		or poolLimits.maxGenerationAttempts > 10
	then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Generation attempts must be between 1 and 10",
			"limits.maxGenerationAttempts"
		)
	end
	if poolLimits.allowCrossClassDominant and not poolLimits.allowCrossClassCarriers then
		return failure(
			"INVALID_ACQUISITION_POOL",
			"Cross-class dominance requires cross-class carriers",
			"limits.allowCrossClassCarriers"
		)
	end
	return { ok = true, value = clone(pool) }
end

function AcquisitionPools.get(poolId: string)
	if definitions[poolId] == nil then
		return nil
	end
	return clone(definitions[poolId])
end

function AcquisitionPools.validate(poolId: string)
	return validate(poolId)
end

function AcquisitionPools.all()
	return clone(definitions)
end

AcquisitionPools.ClassNames = table.freeze(CLASSES)
return table.freeze(AcquisitionPools)
