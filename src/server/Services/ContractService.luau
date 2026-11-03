--!strict

-- Run 7E.3 server-authoritative Training Victory contracts. Contract instances
-- and durable reward redemptions live in the player profile. There is no
-- client-facing acquisition or completion API.

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local ContractCatalog = requireShared("Definitions", "ContractCatalog")
local ContractProtocol = requireShared("Network", "ContractProtocol")
local AcquisitionPools = requireShared("Definitions", "AcquisitionPools")
local CritterCatalog = requireShared("Definitions", "CritterCatalog")

local ContractService = {}
local MAX_CONTRACT_INSTANCES = 128
local MAX_REDEMPTIONS = 2048
local MODULUS = 2147483647

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

local function seedFor(value: string): number
	local hash = 5381
	for index = 1, #value do
		hash = (hash * 33 + string.byte(value, index)) % MODULUS
	end
	return (hash % (MODULUS - 1)) + 1
end

local function suffixAfterColon(value: string): string
	local _, suffix = string.match(value, "^[^:]+:(.+)$")
	return suffix or value
end

local function removeOrderEntry(order, id: string)
	for index, value in order do
		if value == id then
			table.remove(order, index)
			return
		end
	end
end

local function pruneClaimed(contracts, targetCount: number)
	while #contracts.instanceOrder > targetCount do
		local removed = false
		for _, contractId in contracts.instanceOrder do
			local instance = contracts.instancesById[contractId]
			if type(instance) == "table" and instance.status == "CLAIMED" then
				local entitlementId = instance.rewardEntitlementId
				contracts.instancesById[contractId] = nil
				contracts.entitlementsById[entitlementId] = nil
				removeOrderEntry(contracts.instanceOrder, contractId)
				removeOrderEntry(contracts.entitlementOrder, entitlementId)
				removed = true
				break
			end
		end
		if not removed then
			return
		end
	end
end

local function new(dependencies)
	local deps = dependencies
	assert(deps ~= nil, "ContractService requires dependencies")
	assert(deps.profileService ~= nil, "ContractService requires profileService")
	assert(deps.acquisitionService ~= nil, "ContractService requires acquisitionService")
	assert(deps.factory ~= nil, "ContractService requires a Critter instance factory")
	assert(deps.projector ~= nil, "ContractService requires a profile projector")
	local catalog = deps.catalog or CritterCatalog
	local protocolVersion = deps.protocolVersion or ContractProtocol.Version
	local maxInstances = math.min(deps.maxInstances or MAX_CONTRACT_INSTANCES, 128)
	local maxRedemptions = math.min(deps.maxRedemptions or MAX_REDEMPTIONS, 2048)
	local service = {}
	local activeMutation = {}

	local function now(): number
		return deps.now()
	end

	local function generateId(): string
		return deps.generateId()
	end

	local function readContracts(userId: number)
		local profile = deps.profileService.ReadProfile(userId)
		if not profile.ok then
			return profile
		end
		return success(profile.value)
	end

	local function outstandingContract(contracts, definitionId: string)
		for _, contractId in contracts.instanceOrder do
			local instance = contracts.instancesById[contractId]
			if
				type(instance) == "table"
				and instance.definitionId == definitionId
				and (instance.status == "ACTIVE" or instance.status == "COMPLETED")
			then
				return instance
			end
		end
		return nil
	end

	local function findAcceptCommand(contracts, commandId: string)
		for _, contractId in contracts.instanceOrder do
			local instance = contracts.instancesById[contractId]
			if type(instance) == "table" and instance.acceptCommandId == commandId then
				return instance
			end
		end
		return nil
	end

	local function contractDTO(instance, definition, canAccept: boolean)
		return {
			id = instance.id,
			definitionId = instance.definitionId,
			definitionVersion = instance.definitionVersion,
			displayName = definition.displayName,
			description = definition.description,
			requirementKind = definition.requirement.kind,
			requirementText = definition.description,
			progressCurrent = instance.progress.current,
			progressRequired = instance.progress.required,
			status = instance.status,
			canAccept = canAccept,
			canClaim = instance.status == "COMPLETED",
			acceptedAt = instance.acceptedAt,
			completedAt = instance.completedAt,
			claimedAt = instance.claimedAt,
			rewardPoolId = definition.reward.poolId,
			rewardSource = definition.reward.source,
		}
	end

	local function instanceDefinition(instance)
		return ContractCatalog.validate(instance.definitionId, instance.definitionVersion)
	end

	local function serializeContracts(profile)
		local contracts = profile.contracts
		local outstanding = {}
		for definitionId in ContractCatalog.all() do
			outstanding[definitionId] = outstandingContract(contracts, definitionId) ~= nil
		end
		local capacityAvailable = #contracts.redemptionOrder < maxRedemptions
		local result = {}
		for _, contractId in contracts.instanceOrder do
			local instance = contracts.instancesById[contractId]
			local definition = instanceDefinition(instance)
			if definition.ok then
				local canAccept = capacityAvailable
					and not outstanding[definition.value.id]
					and definition.value.repeatable
				table.insert(result, contractDTO(instance, definition.value, canAccept))
			end
		end
		table.sort(result, function(a, b)
			if a.acceptedAt == b.acceptedAt then
				return a.id < b.id
			end
			return a.acceptedAt > b.acceptedAt
		end)
		local available = {}
		local definitions = ContractCatalog.all()
		local definitionIds = {}
		for definitionId in definitions do
			table.insert(definitionIds, definitionId)
		end
		table.sort(definitionIds)
		for _, definitionId in definitionIds do
			local definition = definitions[definitionId]
			if definition.repeatable and not outstanding[definitionId] and capacityAvailable then
				table.insert(available, {
					id = definition.id,
					version = definition.version,
					displayName = definition.displayName,
					description = definition.description,
					requirementKind = definition.requirement.kind,
					requirementCount = definition.requirement.count,
					rewardPoolId = definition.reward.poolId,
					rewardCount = definition.reward.count,
				})
			end
		end
		return {
			revision = profile.revision,
			contracts = result,
			availableDefinitions = available,
			capacityAvailable = capacityAvailable,
			maxRedemptions = maxRedemptions,
		}
	end

	local function projectReward(profile, redemption)
		if redemption == nil then
			return failure("REWARD_INTEGRITY_ERROR", "Contract reward redemption is missing")
		end
		local critter = profile.ownedCritters[redemption.awardedCritterId]
		if critter == nil then
			return failure("REWARD_INTEGRITY_ERROR", "Awarded Critter is missing")
		end
		return success(deps.projector.projectCritter(critter, catalog))
	end

	local function claimedResponse(
		userId: number,
		contractId: string,
		commandId: string,
		duplicate: boolean
	)
		local profile = readContracts(userId)
		if not profile.ok then
			return profile
		end
		local contracts = profile.value.contracts
		local redemption = contracts.redemptionsById[contractId]
		if redemption == nil then
			return failure("REWARD_INTEGRITY_ERROR", "Contract redemption record is missing")
		end
		if redemption.ownerUserId ~= userId then
			return failure("CONTRACT_NOT_FOUND", "Contract reward does not belong to player")
		end
		local projected = projectReward(profile.value, redemption)
		if not projected.ok then
			return projected
		end
		local instance = contracts.instancesById[contractId]
		local contract = nil
		if instance ~= nil then
			local definition = instanceDefinition(instance)
			if definition.ok then
				contract = contractDTO(instance, definition.value, false)
			end
		end
		return success({
			revision = profile.value.revision,
			contract = contract,
			critter = projected.value,
			redemption = {
				contractInstanceId = redemption.contractInstanceId,
				entitlementId = redemption.entitlementId,
				critterId = redemption.awardedCritterId,
				class = redemption.awardedClass,
				claimedAt = redemption.claimedAt,
			},
			duplicate = duplicate,
			commandId = commandId,
		})
	end

	local function validateMutationRequest(request, requireContract: boolean)
		if type(request) ~= "table" then
			return failure("INVALID_REQUEST", "Contract request is malformed")
		end
		if request.protocolVersion ~= protocolVersion then
			return failure("INVALID_REQUEST", "Contract protocol version is unsupported")
		end
		if not isIdentifier(request.commandId) then
			return failure("INVALID_COMMAND", "Contract command ID is required")
		end
		if not isInteger(request.expectedRevision, 0) then
			return failure("INVALID_COMMAND", "Expected profile revision is required")
		end
		if requireContract and not isIdentifier(request.contractId) then
			return failure("INVALID_COMMAND", "Contract ID is required")
		end
		return nil
	end

	function service.GetContracts(userId: number)
		if not isInteger(userId, 1) then
			return failure("INVALID_USER", "User ID is invalid")
		end
		local profile = readContracts(userId)
		if not profile.ok then
			return profile
		end
		return success(serializeContracts(profile.value))
	end

	function service.GetProgress(userId: number, request)
		if type(request) ~= "table" or request.protocolVersion ~= protocolVersion then
			return failure("INVALID_REQUEST", "Contract progress request is malformed")
		end
		if request.contractId ~= nil and not isIdentifier(request.contractId) then
			return failure("INVALID_COMMAND", "Contract ID is malformed")
		end
		local profile = readContracts(userId)
		if not profile.ok then
			return profile
		end
		local contracts = profile.value.contracts
		local instance = nil
		if request.contractId ~= nil then
			instance = contracts.instancesById[request.contractId]
			if instance == nil then
				return failure("CONTRACT_NOT_FOUND", "Contract instance was not found")
			end
		else
			local priority = { ACTIVE = 3, COMPLETED = 2, CLAIMED = 1 }
			local best = 0
			for _, contractId in contracts.instanceOrder do
				local candidate = contracts.instancesById[contractId]
				local score = priority[candidate.status] or 0
				if score > best then
					best = score
					instance = candidate
				end
			end
		end
		if instance == nil then
			return success({ revision = profile.value.revision, contract = nil })
		end
		local definition = instanceDefinition(instance)
		if not definition.ok then
			return definition
		end
		return success({
			revision = profile.value.revision,
			contract = contractDTO(instance, definition.value, false),
		})
	end

	function service.AcceptContract(userId: number, request)
		if not isInteger(userId, 1) then
			return failure("INVALID_USER", "User ID is invalid")
		end
		local requestFailure = validateMutationRequest(request, false)
		if requestFailure ~= nil then
			return requestFailure
		end
		if not isIdentifier(request.definitionId) then
			return failure("INVALID_COMMAND", "Contract definition ID is required")
		end
		local definition = ContractCatalog.validate(request.definitionId, request.definitionVersion)
		if not definition.ok then
			return definition
		end
		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another contract command is running")
		end
		activeMutation[userId] = true
		local ok, result = pcall(function()
			local profile = readContracts(userId)
			if not profile.ok then
				return profile
			end
			local contracts = profile.value.contracts
			local existing = findAcceptCommand(contracts, request.commandId)
			if existing ~= nil then
				if existing.definitionId ~= definition.value.id then
					return failure(
						"COMMAND_ID_CONFLICT",
						"Command ID was used for another contract acceptance"
					)
				end
				local existingDefinition = instanceDefinition(existing)
				if not existingDefinition.ok then
					return existingDefinition
				end
				return success({
					revision = profile.value.revision,
					contract = contractDTO(existing, existingDefinition.value, false),
					duplicate = true,
				})
			end
			if profile.value.revision ~= request.expectedRevision then
				return failure("STALE_REVISION", "Profile revision is stale")
			end
			local outstanding = outstandingContract(contracts, definition.value.id)
			if outstanding ~= nil then
				return failure(
					"CONTRACT_ALREADY_ACTIVE",
					"An outstanding contract already exists for this definition"
				)
			end
			if #contracts.redemptionOrder >= maxRedemptions then
				return failure(
					"CONTRACT_CAPACITY_REACHED",
					"Contract reward capacity has been reached"
				)
			end

			local contractId = `contract:{generateId()}`
			local entitlementId = `entitlement:{generateId()}`
			local acceptedAt = now()
			local baselineBattleId = if deps.activeBattleId ~= nil
				then deps.activeBattleId(userId)
				else nil
			local instance = {
				schemaVersion = 1,
				id = contractId,
				definitionId = definition.value.id,
				definitionVersion = definition.value.version,
				ownerUserId = userId,
				status = "ACTIVE",
				progress = {
					schemaVersion = 1,
					current = 0,
					required = definition.value.requirement.count,
				},
				acceptedAt = acceptedAt,
				acceptCommandId = request.commandId,
				baselineBattleId = baselineBattleId,
				rewardEntitlementId = entitlementId,
			}
			local entitlement = {
				schemaVersion = 1,
				id = entitlementId,
				contractInstanceId = contractId,
				ownerUserId = userId,
				definitionId = definition.value.id,
				definitionVersion = definition.value.version,
				poolId = definition.value.reward.poolId,
				poolVersion = AcquisitionPools.validate(definition.value.reward.poolId).value.version,
				seed = seedFor(entitlementId),
				status = "PENDING",
				createdAt = acceptedAt,
			}

			local mutation = deps.profileService.UpdateProfile(userId, function(candidate)
				local candidateContracts = candidate.contracts
				local raced = findAcceptCommand(candidateContracts, request.commandId)
				if raced ~= nil then
					if raced.definitionId ~= definition.value.id then
						return failure(
							"COMMAND_ID_CONFLICT",
							"Command ID was used for another contract acceptance"
						)
					end
					return success({ duplicate = true, contractId = raced.id })
				end
				if candidate.revision ~= request.expectedRevision then
					return failure("STALE_REVISION", "Profile revision is stale")
				end
				if outstandingContract(candidateContracts, definition.value.id) ~= nil then
					return failure(
						"CONTRACT_ALREADY_ACTIVE",
						"An outstanding contract already exists for this definition"
					)
				end
				if #candidateContracts.redemptionOrder >= maxRedemptions then
					return failure(
						"CONTRACT_CAPACITY_REACHED",
						"Contract reward capacity has been reached"
					)
				end
				pruneClaimed(candidateContracts, maxInstances - 1)
				if #candidateContracts.instanceOrder >= maxInstances then
					return failure(
						"CONTRACT_CAPACITY_REACHED",
						"Contract history capacity has been reached"
					)
				end
				candidateContracts.instancesById[contractId] = clone(instance)
				candidateContracts.entitlementsById[entitlementId] = clone(entitlement)
				table.insert(candidateContracts.instanceOrder, contractId)
				table.insert(candidateContracts.entitlementOrder, entitlementId)
				return success({ duplicate = false, contractId = contractId })
			end)
			if not mutation.ok then
				return mutation
			end
			if mutation.value.duplicate then
				local raced = readContracts(userId)
				if not raced.ok then
					return raced
				end
				local racedInstance = raced.value.contracts.instancesById[mutation.value.contractId]
				if racedInstance == nil then
					return failure(
						"CONTRACT_NOT_FOUND",
						"Contract acceptance could not be reconciled"
					)
				end
				local racedDefinition = instanceDefinition(racedInstance)
				if not racedDefinition.ok then
					return racedDefinition
				end
				return success({
					revision = raced.value.revision,
					contract = contractDTO(racedInstance, racedDefinition.value, false),
					duplicate = true,
				})
			end
			local updated = readContracts(userId)
			if not updated.ok then
				return updated
			end
			local created = updated.value.contracts.instancesById[mutation.value.contractId]
			if created == nil then
				return failure("CONTRACT_INTEGRITY_ERROR", "Accepted contract was not persisted")
			end
			local createdDefinition = instanceDefinition(created)
			if not createdDefinition.ok then
				return createdDefinition
			end
			return success({
				revision = updated.value.revision,
				contract = contractDTO(created, createdDefinition.value, false),
				duplicate = false,
			})
		end)
		activeMutation[userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Contract acceptance failed")
		end
		return result
	end

	function service.RecordBattleCompletion(evidence)
		if
			type(evidence) ~= "table"
			or type(evidence.context) ~= "table"
			or evidence.context.kind ~= "SERVER"
			or evidence.context.source ~= "BATTLE_SERVICE"
		then
			return failure(
				"UNAUTHORIZED_BATTLE_COMPLETION",
				"Server battle authorization is required"
			)
		end
		if
			not isInteger(evidence.userId, 1)
			or evidence.mode ~= "TRAINING"
			or not isIdentifier(evidence.battleId)
			or not isIdentifier(evidence.playerTeamId)
			or not isInteger(evidence.startedAt, 0)
			or not isInteger(evidence.completedAt, 0)
			or evidence.completedAt < evidence.startedAt
			or type(evidence.outcome) ~= "table"
			or type(evidence.outcome.isDraw) ~= "boolean"
		then
			return failure("INVALID_BATTLE_COMPLETION", "Battle completion evidence is malformed")
		end
		local expectedPrefix = `^training:{evidence.userId}:%d+$`
		if string.match(evidence.battleId, expectedPrefix) == nil then
			return failure(
				"INVALID_BATTLE_COMPLETION",
				"Battle completion does not belong to player"
			)
		end
		if evidence.outcome.isDraw or evidence.outcome.winnerTeamId ~= evidence.playerTeamId then
			return success({ ignored = true, reason = "NOT_A_VICTORY" })
		end
		if activeMutation[evidence.userId] then
			return failure("COMMAND_IN_PROGRESS", "Another contract command is running")
		end
		activeMutation[evidence.userId] = true
		local ok, result = pcall(function()
			local profile = readContracts(evidence.userId)
			if not profile.ok then
				return profile
			end
			if profile.value.contracts.battleCompletionsById[evidence.battleId] ~= nil then
				return success({ ignored = true, reason = "DUPLICATE_BATTLE" })
			end
			local instance = outstandingContract(profile.value.contracts, "TRAINING_VICTORY")
			if instance == nil or instance.status ~= "ACTIVE" then
				return success({ ignored = true, reason = "NO_ACTIVE_CONTRACT" })
			end
			if instance.completedBattleId == evidence.battleId then
				return success({ ignored = true, reason = "DUPLICATE_BATTLE" })
			end
			if instance.baselineBattleId == evidence.battleId then
				return success({ ignored = true, reason = "BATTLE_BEFORE_ACCEPTANCE" })
			end
			if evidence.startedAt < instance.acceptedAt then
				return success({ ignored = true, reason = "BATTLE_BEFORE_ACCEPTANCE" })
			end
			local mutation = deps.profileService.UpdateProfile(evidence.userId, function(candidate)
				local candidateContracts = candidate.contracts
				if candidateContracts.battleCompletionsById[evidence.battleId] ~= nil then
					return success({ ignored = true, reason = "DUPLICATE_BATTLE" })
				end
				local candidateInstance = candidateContracts.instancesById[instance.id]
				if candidateInstance == nil or candidateInstance.status ~= "ACTIVE" then
					return success({ ignored = true, reason = "NO_ACTIVE_CONTRACT" })
				end
				if candidateInstance.completedBattleId == evidence.battleId then
					return success({ ignored = true, reason = "DUPLICATE_BATTLE" })
				end
				if candidateInstance.baselineBattleId == evidence.battleId then
					return success({ ignored = true, reason = "BATTLE_BEFORE_ACCEPTANCE" })
				end
				if evidence.startedAt < candidateInstance.acceptedAt then
					return success({ ignored = true, reason = "BATTLE_BEFORE_ACCEPTANCE" })
				end
				if #candidateContracts.battleCompletionOrder >= maxRedemptions then
					return failure(
						"CONTRACT_CAPACITY_REACHED",
						"Battle completion receipt capacity has been reached"
					)
				end
				candidateInstance.status = "COMPLETED"
				candidateInstance.progress.current = candidateInstance.progress.required
				candidateInstance.completedAt = evidence.completedAt
				candidateInstance.completedBattleId = evidence.battleId
				candidateContracts.battleCompletionsById[evidence.battleId] = {
					schemaVersion = 1,
					battleId = evidence.battleId,
					contractInstanceId = candidateInstance.id,
					ownerUserId = evidence.userId,
					completedAt = evidence.completedAt,
				}
				table.insert(candidateContracts.battleCompletionOrder, evidence.battleId)
				return success({ ignored = false })
			end)
			if not mutation.ok then
				return mutation
			end
			if mutation.value.ignored then
				return success({ ignored = true, reason = mutation.value.reason })
			end
			local updated = readContracts(evidence.userId)
			if not updated.ok then
				return updated
			end
			local completed = updated.value.contracts.instancesById[instance.id]
			local definition = if completed ~= nil then instanceDefinition(completed) else nil
			return success({
				ignored = false,
				revision = updated.value.revision,
				contract = if completed ~= nil
						and definition ~= nil
						and definition.ok
					then contractDTO(completed, definition.value, false)
					else nil,
			})
		end)
		activeMutation[evidence.userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Battle completion could not be recorded")
		end
		return result
	end

	function service.ClaimReward(userId: number, request)
		if not isInteger(userId, 1) then
			return failure("INVALID_USER", "User ID is invalid")
		end
		local requestFailure = validateMutationRequest(request, true)
		if requestFailure ~= nil then
			return requestFailure
		end
		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another contract command is running")
		end
		activeMutation[userId] = true
		local ok, result = pcall(function()
			local profile = readContracts(userId)
			if not profile.ok then
				return profile
			end
			local contracts = profile.value.contracts
			local existingRedemption = contracts.redemptionsById[request.contractId]
			if existingRedemption ~= nil then
				if existingRedemption.ownerUserId ~= userId then
					return failure(
						"CONTRACT_NOT_FOUND",
						"Contract reward does not belong to player"
					)
				end
				return claimedResponse(userId, request.contractId, request.commandId, true)
			end
			local instance = contracts.instancesById[request.contractId]
			if instance == nil or instance.ownerUserId ~= userId then
				return failure("CONTRACT_NOT_FOUND", "Contract instance was not found")
			end
			if instance.status == "CLAIMED" then
				return failure(
					"REWARD_INTEGRITY_ERROR",
					"Claimed contract is missing its durable redemption"
				)
			end
			if instance.status ~= "COMPLETED" then
				return failure("CONTRACT_NOT_COMPLETED", "Contract is not completed")
			end
			local entitlement = contracts.entitlementsById[instance.rewardEntitlementId]
			if
				type(entitlement) ~= "table"
				or entitlement.status ~= "PENDING"
				or entitlement.ownerUserId ~= userId
			then
				return failure(
					"REWARD_INTEGRITY_ERROR",
					"Contract reward entitlement is unavailable"
				)
			end
			for _, redemptionId in contracts.redemptionOrder do
				local redemption = contracts.redemptionsById[redemptionId]
				if
					redemption ~= nil
					and redemption.claimCommandId == request.commandId
					and redemption.contractInstanceId ~= request.contractId
				then
					return failure(
						"COMMAND_ID_CONFLICT",
						"Command ID was used for another contract reward"
					)
				end
			end
			if profile.value.revision ~= request.expectedRevision then
				return failure("STALE_REVISION", "Profile revision is stale")
			end
			if #contracts.redemptionOrder >= maxRedemptions then
				return failure(
					"CONTRACT_CAPACITY_REACHED",
					"Contract reward capacity has been reached"
				)
			end
			local pool = AcquisitionPools.validate(entitlement.poolId)
			if not pool.ok then
				return pool
			end
			if pool.value.version ~= entitlement.poolVersion then
				return failure(
					"REWARD_POOL_VERSION_MISMATCH",
					"Stored reward pool version is unavailable"
				)
			end
			local definition = instanceDefinition(instance)
			if not definition.ok then
				return definition
			end
			if definition.value.reward.poolId ~= entitlement.poolId then
				return failure(
					"REWARD_INTEGRITY_ERROR",
					"Contract reward pool does not match entitlement"
				)
			end
			local generated = deps.acquisitionService.GenerateCandidate({
				poolId = entitlement.poolId,
				seed = entitlement.seed,
				context = { kind = "SERVER", source = "CONTRACT_SERVICE" },
			})
			if not generated.ok then
				return generated
			end
			local candidate = generated.value
			local critterId = `critter:{suffixAfterColon(entitlement.id)}`
			local claimedAt = now()
			local factoryResult = deps.factory.Create({
				id = critterId,
				ownerUserId = userId,
				definitionId = candidate.definitionId,
				appearanceGenome = candidate.appearanceGenome,
				abilityGenome = candidate.abilityGenome,
				source = definition.value.reward.source,
				sourceVersion = entitlement.poolVersion,
				acquiredAt = claimedAt,
				tradable = false,
			})
			if not factoryResult.ok then
				return factoryResult
			end
			local critter = factoryResult.value
			local mutation = deps.profileService.UpdateProfile(userId, function(candidateProfile)
				local candidateContracts = candidateProfile.contracts
				local racedRedemption = candidateContracts.redemptionsById[request.contractId]
				if racedRedemption ~= nil then
					return success({
						duplicate = true,
						critterId = racedRedemption.awardedCritterId,
					})
				end
				local candidateInstance = candidateContracts.instancesById[request.contractId]
				if
					candidateInstance == nil
					or candidateInstance.ownerUserId ~= userId
					or candidateInstance.status ~= "COMPLETED"
				then
					return failure(
						"CONTRACT_NOT_COMPLETED",
						"Contract completion state changed before claim"
					)
				end
				local candidateEntitlement =
					candidateContracts.entitlementsById[candidateInstance.rewardEntitlementId]
				if candidateEntitlement == nil or candidateEntitlement.status ~= "PENDING" then
					return failure(
						"REWARD_INTEGRITY_ERROR",
						"Contract entitlement changed before claim"
					)
				end
				for _, redemptionId in candidateContracts.redemptionOrder do
					local redemption = candidateContracts.redemptionsById[redemptionId]
					if
						redemption ~= nil
						and redemption.claimCommandId == request.commandId
						and redemption.contractInstanceId ~= request.contractId
					then
						return failure(
							"COMMAND_ID_CONFLICT",
							"Command ID was used for another contract reward"
						)
					end
				end
				if candidateProfile.revision ~= request.expectedRevision then
					return failure("STALE_REVISION", "Profile revision is stale")
				end
				if #candidateContracts.redemptionOrder >= maxRedemptions then
					return failure(
						"CONTRACT_CAPACITY_REACHED",
						"Contract reward capacity has been reached"
					)
				end
				local existingCritter = candidateProfile.ownedCritters[critterId]
				if existingCritter ~= nil then
					if
						existingCritter.ownerUserId ~= userId
						or existingCritter.definitionId ~= critter.definitionId
						or existingCritter.acquisition.source ~= definition.value.reward.source
					then
						return failure(
							"REWARD_INTEGRITY_ERROR",
							"Deterministic reward Critter ID is already in use"
						)
					end
				else
					candidateProfile.ownedCritters[critterId] = clone(critter)
				end
				candidateInstance.status = "CLAIMED"
				candidateInstance.claimedAt = claimedAt
				candidateEntitlement.status = "CLAIMED"
				candidateEntitlement.claimedAt = claimedAt
				candidateEntitlement.awardedCritterId = critterId
				candidateEntitlement.claimCommandId = request.commandId
				candidateContracts.redemptionsById[request.contractId] = {
					schemaVersion = 1,
					contractInstanceId = request.contractId,
					entitlementId = candidateEntitlement.id,
					ownerUserId = userId,
					definitionId = candidateInstance.definitionId,
					definitionVersion = candidateInstance.definitionVersion,
					poolId = candidateEntitlement.poolId,
					poolVersion = candidateEntitlement.poolVersion,
					awardedCritterId = critterId,
					awardedDefinitionId = critter.definitionId,
					awardedClass = candidate.class,
					claimedAt = claimedAt,
					claimCommandId = request.commandId,
				}
				table.insert(candidateContracts.redemptionOrder, request.contractId)
				return success({ duplicate = false, critterId = critterId })
			end)
			if not mutation.ok then
				return mutation
			end
			if mutation.value.duplicate then
				return claimedResponse(userId, request.contractId, request.commandId, true)
			end
			local updated = readContracts(userId)
			if not updated.ok then
				return updated
			end
			local redemption = updated.value.contracts.redemptionsById[request.contractId]
			local projected = projectReward(updated.value, redemption)
			if not projected.ok then
				return projected
			end
			local claimed = updated.value.contracts.instancesById[request.contractId]
			local claimedDefinition = if claimed ~= nil then instanceDefinition(claimed) else nil
			return success({
				revision = updated.value.revision,
				contract = if claimed ~= nil
						and claimedDefinition ~= nil
						and claimedDefinition.ok
					then contractDTO(claimed, claimedDefinition.value, false)
					else nil,
				critter = projected.value,
				redemption = {
					contractInstanceId = redemption.contractInstanceId,
					entitlementId = redemption.entitlementId,
					critterId = redemption.awardedCritterId,
					class = redemption.awardedClass,
					claimedAt = redemption.claimedAt,
				},
				duplicate = false,
				commandId = request.commandId,
			})
		end)
		activeMutation[userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Contract reward claim failed")
		end
		return result
	end

	local function handleRequest(userId: number, request)
		if type(request) ~= "table" or request.protocolVersion ~= protocolVersion then
			return failure("INVALID_REQUEST", "Contract request is malformed")
		end
		if request.kind == ContractProtocol.RequestKinds.GET_CONTRACTS then
			return service.GetContracts(userId)
		elseif request.kind == ContractProtocol.RequestKinds.GET_CONTRACT_PROGRESS then
			return service.GetProgress(userId, request)
		elseif request.kind == ContractProtocol.RequestKinds.ACCEPT_CONTRACT then
			return service.AcceptContract(userId, request)
		elseif request.kind == ContractProtocol.RequestKinds.CLAIM_CONTRACT_REWARD then
			return service.ClaimReward(userId, request)
		end
		return failure("INVALID_REQUEST_KIND", "Unknown contract request kind")
	end

	function service.removePlayer(userId: number)
		activeMutation[userId] = nil
	end

	service.handleRequest = handleRequest
	return table.freeze(service)
end

ContractService.new = new
ContractService.MaxInstances = MAX_CONTRACT_INSTANCES
ContractService.MaxRedemptions = MAX_REDEMPTIONS
ContractService.SeedFor = seedFor
return table.freeze(ContractService)
