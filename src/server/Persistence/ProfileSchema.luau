--!strict

local ProfileSchema = {}

local function requireShared(folder: string, name: string)
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared[folder][name])
	end
	return require(`../../shared/{folder}/{name}`)
end

local InventoryValidator = requireShared("Validation", "InventoryValidator")
local TeamValidator = requireShared("Validation", "TeamValidator")
local ItemRegistry = requireShared("Items", "ItemRegistry")
local GenomeValidator = requireShared("Genetics", "GenomeValidator")
local ContractCatalog = requireShared("Definitions", "ContractCatalog")
local AcquisitionPools = requireShared("Definitions", "AcquisitionPools")

local CURRENT_VERSION = 8
local MAX_OWNED_CRITTERS = 500
local MAX_ACQUISITION_OPERATIONS = 128
local MAX_ACQUISITION_SEED = 2147483646
local MAX_CONTRACT_INSTANCES = 128
local MAX_CONTRACT_ENTITLEMENTS = 128
local MAX_CONTRACT_REDEMPTIONS = 2048
local MAX_BATTLE_COMPLETIONS = 2048
local CRITTER_CLASSES = { "Verdant", "Tide", "Feral", "Gale", "Shade", "Stone" }

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

local function arrayLength(value: any): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	local maximum = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	return if count == maximum then count else nil
end

local function validStats(stats: any): boolean
	if type(stats) ~= "table" then
		return false
	end
	for _, field in { "health", "speed", "skill", "morale" } do
		local value = stats[field]
		if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
			return false
		end
	end
	for _, field in { "maxHealth", "attack", "defense", "resolve" } do
		if stats[field] ~= nil then
			return false
		end
	end
	return true
end

local function validateInstance(instance: any, id: string, userId: number, definitionsById: any)
	if type(instance) ~= "table" or instance.schemaVersion ~= 3 or instance.id ~= id then
		return failure(
			"INVALID_CRITTER_INSTANCE",
			"Owned Critter record is malformed",
			`ownedCritters.{id}`
		)
	end
	if
		not isIdentifier(id)
		or instance.ownerUserId ~= userId
		or not isIdentifier(instance.definitionId)
	then
		return failure(
			"INVALID_CRITTER_OWNERSHIP",
			"Owned Critter identity or owner is invalid",
			`ownedCritters.{id}`
		)
	end
	local definition = definitionsById[instance.definitionId]
	if definition == nil then
		return failure(
			"UNKNOWN_CRITTER_DEFINITION",
			"Owned Critter definition is unknown",
			`ownedCritters.{id}.definitionId`
		)
	end
	if not validStats(instance.baseStats) then
		return failure(
			"INVALID_CRITTER_STATS",
			"Owned Critter base stats are invalid",
			`ownedCritters.{id}.baseStats`
		)
	end
	local genomeValidation = GenomeValidator.validate(
		instance.appearanceGenome,
		instance.abilityGenome,
		definition.class
	)
	if not genomeValidation.ok then
		local genomeError = genomeValidation.errors[1]
		return failure(
			genomeError.code,
			genomeError.message,
			if genomeError.path == nil
				then `ownedCritters.{id}`
				else `ownedCritters.{id}.{genomeError.path}`
		)
	end
	local acquisition = instance.acquisition
	if
		type(acquisition) ~= "table"
		or not isIdentifier(acquisition.source)
		or not isInteger(acquisition.acquiredAt, 0)
		or not isInteger(acquisition.sourceVersion, 1)
	then
		return failure(
			"INVALID_ACQUISITION",
			"Acquisition metadata is malformed",
			`ownedCritters.{id}.acquisition`
		)
	end
	local breeding = instance.breeding
	local parentCount = if type(breeding) == "table" then arrayLength(breeding.parentIds) else nil
	if
		type(breeding) ~= "table"
		or type(breeding.breedable) ~= "boolean"
		or not isInteger(breeding.generation, 0)
		or not isInteger(breeding.successfulBreedCount, 0)
		or parentCount == nil
		or parentCount > 2
	then
		return failure(
			"INVALID_BREEDING_FLAGS",
			"Breeding flags are malformed",
			`ownedCritters.{id}.breeding`
		)
	end
	for index, parentId in breeding.parentIds do
		if not isIdentifier(parentId) then
			return failure(
				"INVALID_BREEDING_FLAGS",
				"Breeding parent reference is invalid",
				`ownedCritters.{id}.breeding.parentIds[{index}]`
			)
		end
	end
	local equipmentCount = arrayLength(instance.equipmentIds)
	if type(instance.tradable) ~= "boolean" or equipmentCount == nil or equipmentCount > 1 then
		return failure(
			"INVALID_CRITTER_REFERENCES",
			"Trading or equipment references are malformed",
			`ownedCritters.{id}`
		)
	end
	for index, equipmentId in instance.equipmentIds do
		if not isIdentifier(equipmentId) then
			return failure(
				"INVALID_EQUIPMENT_REFERENCE",
				"Equipment reference is invalid",
				`ownedCritters.{id}.equipmentIds[{index}]`
			)
		end
	end
	return { ok = true, value = true }
end

local function validateContracts(profile: any, userId: number, definitionsById: any)
	local contracts = profile.contracts
	if
		type(contracts) ~= "table"
		or contracts.schemaVersion ~= 2
		or type(contracts.instancesById) ~= "table"
		or type(contracts.instanceOrder) ~= "table"
		or type(contracts.entitlementsById) ~= "table"
		or type(contracts.entitlementOrder) ~= "table"
		or type(contracts.redemptionsById) ~= "table"
		or type(contracts.redemptionOrder) ~= "table"
		or type(contracts.battleCompletionsById) ~= "table"
		or type(contracts.battleCompletionOrder) ~= "table"
	then
		return failure("CORRUPT_PROFILE", "Contract state is malformed", "contracts")
	end
	local function tableCount(value): number
		local count = 0
		for _ in value do
			count += 1
		end
		return count
	end
	local function orderMatches(order, byId, maximum: number, label: string)
		local count = arrayLength(order)
		if count == nil or count ~= tableCount(byId) or count > maximum then
			return failure(
				"CORRUPT_PROFILE",
				`{label} order is malformed`,
				`contracts.{label}Order`
			)
		end
		local seen = {}
		for index, id in order do
			if type(id) ~= "string" or not isIdentifier(id) or seen[id] then
				return failure(
					"CORRUPT_PROFILE",
					`{label} order is invalid`,
					`contracts.{label}Order[{index}]`
				)
			end
			seen[id] = true
		end
		return nil
	end
	local orderFailure = orderMatches(
		contracts.instanceOrder,
		contracts.instancesById,
		MAX_CONTRACT_INSTANCES,
		"instance"
	)
	if orderFailure ~= nil then
		return orderFailure
	end
	orderFailure = orderMatches(
		contracts.entitlementOrder,
		contracts.entitlementsById,
		MAX_CONTRACT_ENTITLEMENTS,
		"entitlement"
	)
	if orderFailure ~= nil then
		return orderFailure
	end
	orderFailure = orderMatches(
		contracts.redemptionOrder,
		contracts.redemptionsById,
		MAX_CONTRACT_REDEMPTIONS,
		"redemption"
	)
	if orderFailure ~= nil then
		return orderFailure
	end
	orderFailure = orderMatches(
		contracts.battleCompletionOrder,
		contracts.battleCompletionsById,
		MAX_BATTLE_COMPLETIONS,
		"battleCompletion"
	)
	if orderFailure ~= nil then
		return orderFailure
	end
	for _, battleId in contracts.battleCompletionOrder do
		local receipt = contracts.battleCompletionsById[battleId]
		if
			type(receipt) ~= "table"
			or receipt.schemaVersion ~= 1
			or receipt.battleId ~= battleId
			or receipt.ownerUserId ~= userId
			or not isIdentifier(receipt.contractInstanceId)
			or not isInteger(receipt.completedAt, 0)
		then
			return failure(
				"INVALID_BATTLE_COMPLETION_RECEIPT",
				"Battle completion receipt is malformed",
				`contracts.battleCompletionsById.{battleId}`
			)
		end
	end
	local function classValid(className): boolean
		for _, candidate in CRITTER_CLASSES do
			if candidate == className then
				return true
			end
		end
		return false
	end
	local function validateRedemption(redemptionId: string, redemption: any)
		if
			type(redemption) ~= "table"
			or redemption.schemaVersion ~= 1
			or redemption.contractInstanceId ~= redemptionId
			or redemption.ownerUserId ~= userId
			or not isIdentifier(redemption.entitlementId)
			or not isIdentifier(redemption.definitionId)
			or not isInteger(redemption.definitionVersion, 1)
			or not isIdentifier(redemption.poolId)
			or not isInteger(redemption.poolVersion, 1)
			or not isIdentifier(redemption.awardedCritterId)
			or not isIdentifier(redemption.awardedDefinitionId)
			or not classValid(redemption.awardedClass)
			or not isInteger(redemption.claimedAt, 0)
			or not isIdentifier(redemption.claimCommandId)
		then
			return failure(
				"INVALID_CONTRACT_REDEMPTION",
				"Contract reward redemption is malformed",
				`contracts.redemptionsById.{redemptionId}`
			)
		end
		local definition =
			ContractCatalog.validate(redemption.definitionId, redemption.definitionVersion)
		if not definition.ok then
			return failure(
				"INVALID_CONTRACT_REDEMPTION",
				"Contract reward definition is unavailable",
				`contracts.redemptionsById.{redemptionId}.definitionId`
			)
		end
		local pool = AcquisitionPools.validate(redemption.poolId)
		if not pool.ok or pool.value.version ~= redemption.poolVersion then
			return failure(
				"INVALID_CONTRACT_REDEMPTION",
				"Contract reward pool version is unavailable",
				`contracts.redemptionsById.{redemptionId}.poolVersion`
			)
		end
		local critter = profile.ownedCritters[redemption.awardedCritterId]
		local critterDefinition = if critter ~= nil
			then definitionsById[critter.definitionId]
			else nil
		if
			type(critter) ~= "table"
			or critter.ownerUserId ~= userId
			or critter.definitionId ~= redemption.awardedDefinitionId
			or critterDefinition == nil
			or critterDefinition.class ~= redemption.awardedClass
			or type(critter.acquisition) ~= "table"
			or critter.acquisition.source ~= definition.value.reward.source
		then
			return failure(
				"INVALID_CONTRACT_REDEMPTION",
				"Contract reward Critter is missing or inconsistent",
				`contracts.redemptionsById.{redemptionId}.awardedCritterId`
			)
		end
		return nil
	end
	for _, redemptionId in contracts.redemptionOrder do
		local redemptionFailure =
			validateRedemption(redemptionId, contracts.redemptionsById[redemptionId])
		if redemptionFailure ~= nil then
			return redemptionFailure
		end
	end
	for _, contractId in contracts.instanceOrder do
		local instance = contracts.instancesById[contractId]
		if
			type(instance) ~= "table"
			or instance.schemaVersion ~= 1
			or instance.id ~= contractId
			or instance.ownerUserId ~= userId
			or not isIdentifier(instance.definitionId)
			or not isInteger(instance.definitionVersion, 1)
			or not isIdentifier(instance.acceptCommandId)
			or not isIdentifier(instance.rewardEntitlementId)
			or not isInteger(instance.acceptedAt, 0)
			or (instance.baselineBattleId ~= nil and not isIdentifier(instance.baselineBattleId))
			or (
				instance.status ~= "ACTIVE"
				and instance.status ~= "COMPLETED"
				and instance.status ~= "CLAIMED"
			)
		then
			return failure(
				"INVALID_CONTRACT_INSTANCE",
				"Contract instance is malformed",
				`contracts.instancesById.{contractId}`
			)
		end
		local definition =
			ContractCatalog.validate(instance.definitionId, instance.definitionVersion)
		if not definition.ok then
			return failure(
				"INVALID_CONTRACT_INSTANCE",
				"Contract definition is unavailable",
				`contracts.instancesById.{contractId}.definitionId`
			)
		end
		local progress = instance.progress
		if
			type(progress) ~= "table"
			or progress.schemaVersion ~= 1
			or not isInteger(progress.current, 0)
			or not isInteger(progress.required, 1)
			or progress.required ~= definition.value.requirement.count
			or progress.current > progress.required
		then
			return failure(
				"INVALID_CONTRACT_PROGRESS",
				"Contract progress is malformed",
				`contracts.instancesById.{contractId}.progress`
			)
		end
		local entitlement = contracts.entitlementsById[instance.rewardEntitlementId]
		if
			type(entitlement) ~= "table"
			or entitlement.id ~= instance.rewardEntitlementId
			or entitlement.contractInstanceId ~= contractId
			or entitlement.ownerUserId ~= userId
		then
			return failure(
				"INVALID_CONTRACT_ENTITLEMENT",
				"Contract entitlement link is malformed",
				`contracts.instancesById.{contractId}.rewardEntitlementId`
			)
		end
		if instance.status == "ACTIVE" then
			if
				instance.completedAt ~= nil
				or instance.completedBattleId ~= nil
				or instance.claimedAt ~= nil
				or progress.current ~= 0
			then
				return failure(
					"INVALID_CONTRACT_INSTANCE",
					"Active contract contains completion state",
					`contracts.instancesById.{contractId}`
				)
			end
		else
			if
				not isInteger(instance.completedAt, 0)
				or instance.completedAt < instance.acceptedAt
				or not isIdentifier(instance.completedBattleId)
				or progress.current ~= progress.required
			then
				return failure(
					"INVALID_CONTRACT_INSTANCE",
					"Completed contract evidence is malformed",
					`contracts.instancesById.{contractId}`
				)
			end
			if instance.status == "COMPLETED" then
				if instance.claimedAt ~= nil then
					return failure(
						"INVALID_CONTRACT_INSTANCE",
						"Unclaimed contract contains claim state",
						`contracts.instancesById.{contractId}`
					)
				end
			else
				if
					not isInteger(instance.claimedAt, 0)
					or instance.claimedAt < instance.completedAt
				then
					return failure(
						"INVALID_CONTRACT_INSTANCE",
						"Claimed contract timestamp is invalid",
						`contracts.instancesById.{contractId}.claimedAt`
					)
				end
				local redemption = contracts.redemptionsById[contractId]
				if
					type(redemption) ~= "table"
					or redemption.entitlementId ~= instance.rewardEntitlementId
					or redemption.claimedAt ~= instance.claimedAt
				then
					return failure(
						"INVALID_CONTRACT_REDEMPTION",
						"Claimed contract is missing its durable redemption",
						`contracts.instancesById.{contractId}`
					)
				end
			end
			local completionReceipt = contracts.battleCompletionsById[instance.completedBattleId]
			if
				type(completionReceipt) ~= "table"
				or completionReceipt.contractInstanceId ~= contractId
				or completionReceipt.completedAt ~= instance.completedAt
			then
				return failure(
					"INVALID_BATTLE_COMPLETION_RECEIPT",
					"Completed contract is missing its durable battle receipt",
					`contracts.instancesById.{contractId}.completedBattleId`
				)
			end
		end
	end
	for _, entitlementId in contracts.entitlementOrder do
		local entitlement = contracts.entitlementsById[entitlementId]
		if
			type(entitlement) ~= "table"
			or entitlement.schemaVersion ~= 1
			or entitlement.id ~= entitlementId
			or entitlement.ownerUserId ~= userId
			or not isIdentifier(entitlement.contractInstanceId)
			or not isIdentifier(entitlement.definitionId)
			or not isInteger(entitlement.definitionVersion, 1)
			or not isIdentifier(entitlement.poolId)
			or not isInteger(entitlement.poolVersion, 1)
			or not isInteger(entitlement.seed, 1)
			or entitlement.seed > MAX_ACQUISITION_SEED
			or not isInteger(entitlement.createdAt, 0)
			or (entitlement.status ~= "PENDING" and entitlement.status ~= "CLAIMED")
		then
			return failure(
				"INVALID_CONTRACT_ENTITLEMENT",
				"Contract entitlement is malformed",
				`contracts.entitlementsById.{entitlementId}`
			)
		end
		local definition =
			ContractCatalog.validate(entitlement.definitionId, entitlement.definitionVersion)
		if not definition.ok then
			return failure(
				"INVALID_CONTRACT_ENTITLEMENT",
				"Contract entitlement definition is unavailable",
				`contracts.entitlementsById.{entitlementId}.definitionId`
			)
		end
		local pool = AcquisitionPools.validate(entitlement.poolId)
		if not pool.ok or pool.value.version ~= entitlement.poolVersion then
			return failure(
				"INVALID_CONTRACT_ENTITLEMENT",
				"Contract entitlement pool version is unavailable",
				`contracts.entitlementsById.{entitlementId}.poolVersion`
			)
		end
		local contract = contracts.instancesById[entitlement.contractInstanceId]
		if
			type(contract) ~= "table"
			or contract.rewardEntitlementId ~= entitlementId
			or contract.ownerUserId ~= userId
			or contract.definitionId ~= entitlement.definitionId
			or contract.definitionVersion ~= entitlement.definitionVersion
		then
			return failure(
				"INVALID_CONTRACT_ENTITLEMENT",
				"Contract entitlement ownership link is invalid",
				`contracts.entitlementsById.{entitlementId}.contractInstanceId`
			)
		end
		if entitlement.status == "PENDING" then
			if
				entitlement.claimedAt ~= nil
				or entitlement.awardedCritterId ~= nil
				or entitlement.claimCommandId ~= nil
				or contract.status == "CLAIMED"
			then
				return failure(
					"INVALID_CONTRACT_ENTITLEMENT",
					"Pending entitlement contains claim state",
					`contracts.entitlementsById.{entitlementId}`
				)
			end
		else
			if
				not isInteger(entitlement.claimedAt, 0)
				or not isIdentifier(entitlement.awardedCritterId)
				or not isIdentifier(entitlement.claimCommandId)
				or contract.status ~= "CLAIMED"
			then
				return failure(
					"INVALID_CONTRACT_ENTITLEMENT",
					"Claimed entitlement is malformed",
					`contracts.entitlementsById.{entitlementId}`
				)
			end
			local redemption = contracts.redemptionsById[contract.id]
			if
				type(redemption) ~= "table"
				or redemption.entitlementId ~= entitlementId
				or redemption.awardedCritterId ~= entitlement.awardedCritterId
				or redemption.claimCommandId ~= entitlement.claimCommandId
				or redemption.claimedAt ~= entitlement.claimedAt
			then
				return failure(
					"INVALID_CONTRACT_ENTITLEMENT",
					"Claimed entitlement does not match its redemption",
					`contracts.entitlementsById.{entitlementId}`
				)
			end
		end
	end
	return nil
end

local function create(userId: number, now: number)
	return {
		schemaVersion = CURRENT_VERSION,
		userId = userId,
		revision = 0,
		createdAt = now,
		updatedAt = now,
		starterGrantVersion = 0,
		ownedCritters = {},
		selectedTeam = {},
		eggs = {},
		breedingOperationsById = {},
		breedingOperationOrder = {},
		acquisitionOperationsById = {},
		acquisitionOperationOrder = {},
		contracts = {
			schemaVersion = 2,
			instancesById = {},
			instanceOrder = {},
			entitlementsById = {},
			entitlementOrder = {},
			redemptionsById = {},
			redemptionOrder = {},
			battleCompletionsById = {},
			battleCompletionOrder = {},
		},
		inventory = {
			schemaVersion = 2,
			stacksByDefinitionId = {},
			uniqueItemsById = {},
			operationsById = {},
			operationOrder = {},
		},
		progression = { schemaVersion = 1, flags = {}, counters = {} },
	}
end

local function validate(
	profile: any,
	expectedUserId: number,
	definitionsById: any,
	allowEmptyTeam: boolean?
)
	if type(profile) ~= "table" then
		return failure("CORRUPT_PROFILE", "Profile must be a table", nil)
	end
	if profile.schemaVersion ~= CURRENT_VERSION then
		return failure(
			"UNSUPPORTED_PROFILE_SCHEMA",
			"Profile schema version is unsupported",
			"schemaVersion"
		)
	end
	if profile.userId ~= expectedUserId or not isInteger(profile.userId, 1) then
		return failure(
			"PROFILE_USER_MISMATCH",
			"Profile user does not match DataStore key",
			"userId"
		)
	end
	for _, field in { "revision", "createdAt", "updatedAt", "starterGrantVersion" } do
		if not isInteger(profile[field], 0) then
			return failure("CORRUPT_PROFILE", `Profile {field} is invalid`, field)
		end
	end
	if type(profile.ownedCritters) ~= "table" then
		return failure("CORRUPT_PROFILE", "ownedCritters must be a table", "ownedCritters")
	end
	local ownedCount = 0
	for id, instance in profile.ownedCritters do
		ownedCount += 1
		if ownedCount > MAX_OWNED_CRITTERS then
			return failure(
				"CRITTER_LIMIT_EXCEEDED",
				"Owned Critter limit exceeded",
				"ownedCritters"
			)
		end
		if type(id) ~= "string" then
			return failure(
				"INVALID_CRITTER_INSTANCE",
				"Owned Critter keys must be strings",
				"ownedCritters"
			)
		end
		local result = validateInstance(instance, id, expectedUserId, definitionsById)
		if not result.ok then
			return result
		end
	end
	if type(profile.eggs) ~= "table" then
		return failure("CORRUPT_PROFILE", "eggs must be a table", "eggs")
	end
	local eggCount = 0
	for eggId, egg in profile.eggs do
		eggCount += 1
		if eggCount > MAX_OWNED_CRITTERS then
			return failure("EGG_LIMIT_EXCEEDED", "Egg limit exceeded", "eggs")
		end
		if type(eggId) ~= "string" or not isIdentifier(eggId) then
			return failure("INVALID_EGG", "Egg key is invalid", "eggs")
		end
		if
			type(egg) ~= "table"
			or egg.schemaVersion ~= 1
			or egg.eggId ~= eggId
			or egg.ownerUserId ~= expectedUserId
			or not isIdentifier(egg.parentAId)
			or not isIdentifier(egg.parentBId)
			or egg.parentAId == egg.parentBId
			or type(egg.offspringClass) ~= "string"
			or not isInteger(egg.generation, 0)
			or not isInteger(egg.createdAt, 0)
			or not isInteger(egg.hatchAt, 0)
			or egg.hatchAt < egg.createdAt
			or (egg.status ~= "INCUBATING" and egg.status ~= "READY" and egg.status ~= "HATCHED")
			or not isIdentifier(egg.breedingCommandId)
		then
			return failure("INVALID_EGG", "Egg record is malformed", `eggs.{eggId}`)
		end
		local classValid = false
		for _, className in { "Verdant", "Tide", "Feral", "Gale", "Shade", "Stone" } do
			if egg.offspringClass == className then
				classValid = true
				break
			end
		end
		if not classValid then
			return failure(
				"INVALID_EGG",
				"Egg offspring class is invalid",
				`eggs.{eggId}.offspringClass`
			)
		end
		local genomeValidation = GenomeValidator.validate(
			egg.offspringAppearanceGenome,
			egg.offspringAbilityGenome,
			egg.offspringClass
		)
		if not genomeValidation.ok then
			local genomeError = genomeValidation.errors[1]
			return failure(
				genomeError.code,
				genomeError.message,
				if genomeError.path == nil
					then `eggs.{eggId}`
					else `eggs.{eggId}.{genomeError.path}`
			)
		end
		if
			egg.hatchedAt ~= nil
			and (not isInteger(egg.hatchedAt, 0) or egg.hatchedAt < egg.hatchAt)
		then
			return failure(
				"INVALID_EGG",
				"Egg hatch timestamp is invalid",
				`eggs.{eggId}.hatchedAt`
			)
		end
		for _, field in { "hatchOperationId", "hatchedCommandId", "offspringId" } do
			local value = egg[field]
			if value ~= nil and not isIdentifier(value) then
				return failure(
					"INVALID_EGG",
					"Egg hatch reference is invalid",
					`eggs.{eggId}.{field}`
				)
			end
		end
		if egg.status == "HATCHED" then
			if
				egg.hatchedAt == nil
				or egg.hatchOperationId == nil
				or egg.hatchedCommandId == nil
				or egg.offspringId == nil
			then
				return failure(
					"INVALID_EGG",
					"Hatched egg is missing result references",
					`eggs.{eggId}`
				)
			end
		end
	end
	if type(profile.breedingOperationsById) ~= "table" then
		return failure(
			"CORRUPT_PROFILE",
			"breedingOperationsById must be a table",
			"breedingOperationsById"
		)
	end
	if type(profile.breedingOperationOrder) ~= "table" then
		return failure(
			"CORRUPT_PROFILE",
			"breedingOperationOrder must be a table",
			"breedingOperationOrder"
		)
	end
	local operationCount = arrayLength(profile.breedingOperationOrder)
	if
		operationCount == nil
		or operationCount
			~= (function()
				local count = 0
				for _ in profile.breedingOperationsById do
					count += 1
				end
				return count
			end)()
	then
		return failure(
			"CORRUPT_PROFILE",
			"Breeding operation order is malformed",
			"breedingOperationOrder"
		)
	end
	for index, commandId in profile.breedingOperationOrder do
		if type(commandId) ~= "string" or not isIdentifier(commandId) then
			return failure(
				"INVALID_BREEDING_OPERATION",
				"Breeding operation ID is invalid",
				`breedingOperationOrder[{index}]`
			)
		end
		local operation = profile.breedingOperationsById[commandId]
		if
			type(operation) ~= "table"
			or operation.schemaVersion ~= 1
			or operation.commandId ~= commandId
			or not isIdentifier(operation.parentAId)
			or not isIdentifier(operation.parentBId)
			or not isIdentifier(operation.eggId)
			or not isInteger(operation.createdAt, 0)
			or profile.eggs[operation.eggId] == nil
		then
			return failure(
				"INVALID_BREEDING_OPERATION",
				"Breeding operation record is malformed",
				`breedingOperationsById.{commandId}`
			)
		end
	end
	if type(profile.acquisitionOperationsById) ~= "table" then
		return failure(
			"CORRUPT_PROFILE",
			"acquisitionOperationsById must be a table",
			"acquisitionOperationsById"
		)
	end
	if type(profile.acquisitionOperationOrder) ~= "table" then
		return failure(
			"CORRUPT_PROFILE",
			"acquisitionOperationOrder must be a table",
			"acquisitionOperationOrder"
		)
	end
	local acquisitionCount = arrayLength(profile.acquisitionOperationOrder)
	local acquisitionRecordCount = 0
	for _ in profile.acquisitionOperationsById do
		acquisitionRecordCount += 1
	end
	if
		acquisitionCount == nil
		or acquisitionCount ~= acquisitionRecordCount
		or acquisitionCount > MAX_ACQUISITION_OPERATIONS
	then
		return failure(
			"CORRUPT_PROFILE",
			"Acquisition operation order is malformed",
			"acquisitionOperationOrder"
		)
	end
	for index, commandId in profile.acquisitionOperationOrder do
		if type(commandId) ~= "string" or not isIdentifier(commandId) then
			return failure(
				"INVALID_ACQUISITION_OPERATION",
				"Acquisition operation ID is invalid",
				`acquisitionOperationOrder[{index}]`
			)
		end
		local operation = profile.acquisitionOperationsById[commandId]
		if
			type(operation) ~= "table"
			or operation.schemaVersion ~= 1
			or operation.commandId ~= commandId
			or not isIdentifier(operation.grantId)
			or not isIdentifier(operation.critterId)
			or not isIdentifier(operation.poolId)
			or not isInteger(operation.poolVersion, 1)
			or not isInteger(operation.configVersion, 1)
			or not isIdentifier(operation.source)
			or not isIdentifier(operation.grantedBy)
			or not isInteger(operation.seed, 1)
			or operation.seed > MAX_ACQUISITION_SEED
			or not isInteger(operation.createdAt, 0)
			or profile.ownedCritters[operation.critterId] == nil
		then
			return failure(
				"INVALID_ACQUISITION_OPERATION",
				"Acquisition operation record is malformed",
				`acquisitionOperationsById.{commandId}`
			)
		end
		local classValid = false
		for _, className in CRITTER_CLASSES do
			if operation.class == className then
				classValid = true
				break
			end
		end
		if not classValid then
			return failure(
				"INVALID_ACQUISITION_OPERATION",
				"Acquisition operation class is invalid",
				`acquisitionOperationsById.{commandId}.class`
			)
		end
	end
	local contractFailure = validateContracts(profile, expectedUserId, definitionsById)
	if contractFailure ~= nil then
		return contractFailure
	end
	local teamValidation = TeamValidator.validateTeam(
		profile.selectedTeam,
		expectedUserId,
		profile.ownedCritters,
		definitionsById,
		allowEmptyTeam
	)
	if not teamValidation.ok then
		return teamValidation
	end
	local inventoryValidation = InventoryValidator.validateInventory(
		profile.inventory,
		expectedUserId,
		profile.ownedCritters,
		ItemRegistry
	)
	if not inventoryValidation.ok then
		return inventoryValidation
	end
	if
		type(profile.progression) ~= "table"
		or profile.progression.schemaVersion ~= 1
		or type(profile.progression.flags) ~= "table"
		or type(profile.progression.counters) ~= "table"
		or next(profile.progression.flags) ~= nil
		or next(profile.progression.counters) ~= nil
	then
		return failure(
			"INVALID_PROGRESSION_PLACEHOLDER",
			"Progression placeholder is malformed",
			"progression"
		)
	end
	return { ok = true, value = true }
end

ProfileSchema.CurrentVersion = CURRENT_VERSION
ProfileSchema.clone = clone
ProfileSchema.create = create
ProfileSchema.validate = validate
return table.freeze(ProfileSchema)
