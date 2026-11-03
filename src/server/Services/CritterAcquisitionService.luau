--!strict

-- Server/internal acquisition service. There is deliberately no client remote in Run 7E.2.

local function requireServer(folder: string, name: string)
	if script ~= nil then
		return require(script.Parent.Parent[folder][name])
	end
	return require(`../{folder}/{name}`)
end

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local VariantGenerator = requireServer("Genetics", "VariantGenerator")
local CritterInstanceFactory = requireServer("Persistence", "CritterInstanceFactory")
local AcquisitionPools = requireShared("Definitions", "AcquisitionPools")

local CritterAcquisitionService = {}
local MODULUS = 2147483647
local DEFAULT_MAX_OPERATION_RECORDS = 64

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

local function defaultAuthorize(context): boolean
	if type(context) ~= "table" or context.kind ~= "SERVER" then
		return false
	end
	return isIdentifier(context.source) and context.source ~= "CLIENT"
end

local function new(dependencies)
	local deps = dependencies
	assert(deps ~= nil, "CritterAcquisitionService requires dependencies")
	assert(deps.profileService ~= nil, "CritterAcquisitionService requires profileService")
	local generator = deps.generator or VariantGenerator.new()
	local factory = deps.factory or CritterInstanceFactory.new()
	local pools = deps.pools or AcquisitionPools
	local authorize = deps.authorizeGrant or defaultAuthorize
	local maxOperationRecords =
		math.min(deps.maxOperationRecords or DEFAULT_MAX_OPERATION_RECORDS, 128)
	local activeMutation = {}
	local service = {}

	function service.PreviewPool(poolId: string)
		return generator.PreviewPool(poolId)
	end

	function service.GenerateCandidate(request)
		if type(request) ~= "table" then
			return failure("INVALID_GENERATION_INPUT", "Generation request is required")
		end
		if not authorize(request.context) then
			return failure("UNAUTHORIZED_GENERATION", "Server authorization is required")
		end
		local generated = generator.Generate({
			poolId = request.poolId,
			seed = request.seed,
			class = request.class,
		})
		if not generated.ok then
			return generated
		end
		local value = generated.value
		return success({
			class = value.class,
			definitionId = value.definitionId,
			appearanceGenome = clone(value.appearanceGenome),
			abilityGenome = clone(value.abilityGenome),
			poolId = value.poolId,
			poolVersion = value.poolVersion,
			source = value.source,
			generatorVersion = value.generatorVersion,
			seed = value.seed,
			trace = clone(value.trace),
		})
	end

	function service.GrantCritter(userId: number, request)
		if not isInteger(userId, 1) then
			return failure("INVALID_USER", "User ID is invalid")
		end
		if type(request) ~= "table" then
			return failure("INVALID_GRANT_REQUEST", "Grant request is required")
		end
		if not authorize(request.context) then
			return failure("UNAUTHORIZED_GRANT", "Authorized server grant context is required")
		end
		if not isIdentifier(request.commandId) or not isIdentifier(request.grantId) then
			return failure("INVALID_COMMAND", "Command and grant IDs are required")
		end
		if not isIdentifier(request.poolId) then
			return failure("INVALID_POOL_ID", "Acquisition pool ID is malformed")
		end
		if not isInteger(request.seed, 1) or request.seed >= MODULUS then
			return failure("INVALID_RNG_SEED", "Seed must be an integer from 1 to 2147483646")
		end
		if request.class ~= nil and not isIdentifier(request.class) then
			return failure("INVALID_CLASS", "Requested class is malformed")
		end
		if request.expectedRevision ~= nil and not isInteger(request.expectedRevision, 0) then
			return failure("INVALID_COMMAND", "Expected revision is invalid")
		end

		local poolResult = pools.validate(request.poolId)
		if not poolResult.ok then
			return poolResult
		end
		local pool = poolResult.value

		local profileResult = deps.profileService.ReadProfile(userId)
		if not profileResult.ok then
			return profileResult
		end
		local profile = profileResult.value
		local existing = profile.acquisitionOperationsById
			and profile.acquisitionOperationsById[request.commandId]
		if existing ~= nil then
			if
				existing.grantId ~= request.grantId
				or existing.poolId ~= request.poolId
				or existing.seed ~= request.seed
				or (request.class ~= nil and existing.class ~= request.class)
			then
				return failure(
					"COMMAND_ID_CONFLICT",
					"Command ID was used for another acquisition grant"
				)
			end
			local critter = profile.ownedCritters[existing.critterId]
			if critter == nil then
				return failure(
					"ACQUISITION_OPERATION_CORRUPT",
					"Recorded acquisition result is missing"
				)
			end
			return success({
				revision = profile.revision,
				critter = clone(critter),
				operation = clone(existing),
				duplicate = true,
			})
		end

		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another acquisition grant is running")
		end
		activeMutation[userId] = true
		local ok, result = pcall(function()
			local generated = generator.Generate({
				poolId = request.poolId,
				seed = request.seed,
				class = request.class,
			})
			if not generated.ok then
				return generated
			end
			local candidate = generated.value
			local critterId = `critter:{deps.generateId()}`
			local now = deps.now()
			local factoryResult = factory.Create({
				id = critterId,
				ownerUserId = userId,
				definitionId = candidate.definitionId,
				appearanceGenome = candidate.appearanceGenome,
				abilityGenome = candidate.abilityGenome,
				source = candidate.source,
				sourceVersion = candidate.poolVersion,
				acquiredAt = now,
				tradable = false,
			})
			if not factoryResult.ok then
				return factoryResult
			end
			local critter = factoryResult.value
			local operation = {
				schemaVersion = 1,
				commandId = request.commandId,
				grantId = request.grantId,
				critterId = critterId,
				poolId = pool.id,
				poolVersion = pool.version,
				configVersion = candidate.generatorVersion,
				source = pool.source,
				grantedBy = request.context.source,
				class = candidate.class,
				seed = candidate.seed,
				createdAt = now,
			}

			local mutationResult = deps.profileService.UpdateProfile(
				userId,
				function(candidateProfile)
					if candidateProfile.acquisitionOperationsById[request.commandId] ~= nil then
						return failure(
							"COMMAND_ID_CONFLICT",
							"Command ID was used for another acquisition grant"
						)
					end
					if
						request.expectedRevision ~= nil
						and candidateProfile.revision ~= request.expectedRevision
					then
						return failure("STALE_REVISION", "Profile revision is stale")
					end
					if candidateProfile.ownedCritters[critterId] ~= nil then
						return failure(
							"DUPLICATE_CRITTER_ID",
							"Generated Critter ID already exists"
						)
					end
					candidateProfile.ownedCritters[critterId] = clone(critter)
					candidateProfile.acquisitionOperationsById[request.commandId] = clone(operation)
					table.insert(candidateProfile.acquisitionOperationOrder, request.commandId)
					while #candidateProfile.acquisitionOperationOrder > maxOperationRecords do
						local oldCommandId =
							table.remove(candidateProfile.acquisitionOperationOrder, 1)
						candidateProfile.acquisitionOperationsById[oldCommandId] = nil
					end
					return success({ critterId = critterId })
				end
			)
			if not mutationResult.ok then
				return mutationResult
			end

			local updated = deps.profileService.ReadProfile(userId)
			if not updated.ok then
				return updated
			end
			local persisted = updated.value.ownedCritters[critterId]
			if persisted == nil then
				return failure("ACQUISITION_OPERATION_CORRUPT", "Granted Critter was not persisted")
			end
			return success({
				revision = updated.value.revision,
				critter = clone(persisted),
				operation = clone(updated.value.acquisitionOperationsById[request.commandId]),
				duplicate = false,
			})
		end)
		activeMutation[userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Acquisition grant failed")
		end
		return result
	end

	function service.removePlayer(userId: number)
		activeMutation[userId] = nil
	end

	function service.authorize(context): boolean
		return authorize(context)
	end

	return table.freeze(service)
end

CritterAcquisitionService.new = new
return table.freeze(CritterAcquisitionService)
