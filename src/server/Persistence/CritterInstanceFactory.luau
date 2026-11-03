--!strict

-- Creates the persisted owned-Critter shape for Run 7E.2 acquisitions.
-- Class stats are copied exactly; no random stat rolls and no starter metadata.

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local CritterCatalog = requireShared("Definitions", "CritterCatalog")
local GenomeValidator = requireShared("Genetics", "GenomeValidator")

local CritterInstanceFactory = {}

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

local function new(dependencies)
	local deps = dependencies or {}
	local catalog = deps.catalog or CritterCatalog
	local genomeValidator = deps.genomeValidator or GenomeValidator
	local service = {}

	function service.Create(input)
		if type(input) ~= "table" then
			return failure("INVALID_CRITTER_INPUT", "Critter instance input is required")
		end
		if not isIdentifier(input.id) then
			return failure("INVALID_CRITTER_ID", "Critter ID is malformed", "id")
		end
		if not isInteger(input.ownerUserId, 1) then
			return failure("INVALID_OWNER", "Critter owner is invalid", "ownerUserId")
		end
		if not isIdentifier(input.definitionId) then
			return failure(
				"INVALID_CRITTER_DEFINITION",
				"Critter definition is invalid",
				"definitionId"
			)
		end
		local definition = catalog.getById(input.definitionId)
		if definition == nil then
			return failure(
				"UNKNOWN_CRITTER_DEFINITION",
				"Critter definition is unknown",
				"definitionId"
			)
		end
		if not isIdentifier(input.source) then
			return failure("INVALID_ACQUISITION_SOURCE", "Acquisition source is invalid", "source")
		end
		if not isInteger(input.sourceVersion, 1) then
			return failure(
				"INVALID_ACQUISITION_VERSION",
				"Acquisition source version is invalid",
				"sourceVersion"
			)
		end
		if not isInteger(input.acquiredAt, 0) then
			return failure(
				"INVALID_ACQUISITION_TIME",
				"Acquisition timestamp is invalid",
				"acquiredAt"
			)
		end
		if input.tradable ~= nil and type(input.tradable) ~= "boolean" then
			return failure("INVALID_TRADEABILITY", "Tradeability must be boolean", "tradable")
		end
		local validation =
			genomeValidator.validate(input.appearanceGenome, input.abilityGenome, definition.class)
		if not validation.ok then
			local genomeError = validation.errors[1]
			return failure(genomeError.code, genomeError.message, genomeError.path)
		end
		return {
			ok = true,
			value = {
				schemaVersion = 2,
				id = input.id,
				definitionId = definition.id,
				ownerUserId = input.ownerUserId,
				appearanceGenome = clone(input.appearanceGenome),
				abilityGenome = clone(input.abilityGenome),
				baseStats = clone(definition.baseStats),
				acquisition = {
					source = input.source,
					acquiredAt = input.acquiredAt,
					sourceVersion = input.sourceVersion,
				},
				breeding = {
					breedable = true,
					generation = 0,
					parentIds = {},
					successfulBreedCount = 0,
				},
				tradable = input.tradable == true,
				equipmentIds = {},
			},
		}
	end

	return table.freeze(service)
end

CritterInstanceFactory.new = new
return table.freeze(CritterInstanceFactory)
