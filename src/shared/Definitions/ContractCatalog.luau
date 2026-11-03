--!strict

-- Authoring data for Run 7E.3 contracts. Definitions are immutable server and
-- client data; contract instances live only in the owning player's profile.

local function requireSibling(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local AcquisitionPools = requireSibling("AcquisitionPools")

local ContractCatalog = {}
local definitions = {
	TRAINING_VICTORY = {
		schemaVersion = 1,
		id = "TRAINING_VICTORY",
		version = 1,
		displayName = "Training Victory",
		description = "Win a Training Grounds PvE battle.",
		repeatable = true,
		maxActivePerDefinition = 1,
		requirement = {
			kind = "TRAINING_PVE_WINS",
			count = 1,
		},
		reward = {
			kind = "CRITTER",
			poolId = "COMMON_FOUNDERS",
			count = 1,
			source = "CONTRACT.TRAINING_VICTORY",
		},
	},
}

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

local function isIdentifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function isInteger(value: any, minimum: number): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= minimum
		and value % 1 == 0
end

local function validate(definitionId: string, expectedVersion: number?)
	local definition = definitions[definitionId]
	if definition == nil then
		return failure("UNKNOWN_CONTRACT", "Contract definition is not registered")
	end
	if expectedVersion ~= nil and definition.version ~= expectedVersion then
		return failure("CONTRACT_VERSION_MISMATCH", "Contract definition version is unsupported")
	end
	if not isIdentifier(definition.id) or definition.id ~= definitionId then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract identity is invalid")
	end
	if not isInteger(definition.version, 1) then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract version is invalid")
	end
	if type(definition.displayName) ~= "string" or #definition.displayName == 0 then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract display name is invalid")
	end
	if type(definition.description) ~= "string" or #definition.description == 0 then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract description is invalid")
	end
	if type(definition.repeatable) ~= "boolean" then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract repeatable flag is invalid")
	end
	if not isInteger(definition.maxActivePerDefinition, 1) then
		return failure("INVALID_CONTRACT_DEFINITION", "Contract active limit is invalid")
	end
	local requirement = definition.requirement
	if
		type(requirement) ~= "table"
		or requirement.kind ~= "TRAINING_PVE_WINS"
		or not isInteger(requirement.count, 1)
	then
		return failure("INVALID_CONTRACT_REQUIREMENT", "Contract requirement is invalid")
	end
	local reward = definition.reward
	if
		type(reward) ~= "table"
		or reward.kind ~= "CRITTER"
		or not isIdentifier(reward.poolId)
		or not isInteger(reward.count, 1)
		or reward.count ~= 1
		or not isIdentifier(reward.source)
	then
		return failure("INVALID_CONTRACT_REWARD", "Contract reward is invalid")
	end
	local pool = AcquisitionPools.validate(reward.poolId)
	if not pool.ok then
		return failure("INVALID_CONTRACT_REWARD", "Contract reward pool is unavailable")
	end
	if not pool.value.eligibleClasses or #pool.value.eligibleClasses == 0 then
		return failure("INVALID_CONTRACT_REWARD", "Contract reward pool has no eligible classes")
	end
	return { ok = true, value = clone(definition) }
end

local function get(definitionId: string)
	local definition = definitions[definitionId]
	if definition == nil then
		return nil
	end
	return clone(definition)
end

local function all()
	return clone(definitions)
end

ContractCatalog.validate = validate
ContractCatalog.get = get
ContractCatalog.all = all
return table.freeze(ContractCatalog)
