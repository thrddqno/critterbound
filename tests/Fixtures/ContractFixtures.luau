--!strict

-- Shared setup for Run 7E.3 contract tests.

local ProfileFixtures = require("./ProfileFixtures")
local AcquisitionFixtures = require("./AcquisitionFixtures")
local Run5Fixtures = require("./Run5Fixtures")
local ContractService = require("../../src/server/Services/ContractService")
local CritterInstanceFactory = require("../../src/server/Persistence/CritterInstanceFactory")
local ProfileProjector = require("../../src/server/Persistence/ProfileProjector")
local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
local ContractCatalog = require("../../src/shared/Definitions/ContractCatalog")
local ContractProtocol = require("../../src/shared/Network/ContractProtocol")
local BattleService = require("../../src/server/Services/BattleService")

local ContractFixtures = {}

ContractFixtures.NOW = 1_700_000_000
ContractFixtures.SERVER_CONTEXT = { kind = "SERVER", source = "BATTLE_SERVICE" }

local function new(options)
	local settings = options or {}
	local store = settings.store or ProfileFixtures.MockDataStore.new()
	local now = settings.now or ContractFixtures.NOW
	local repository =
		ProfileFixtures.newRepository(store, settings.jobId or "contract-job", { now = now })
	local profileService = settings.profileService or ProfileFixtures.newService(repository)
	local acquisitionService = settings.acquisitionService
		or AcquisitionFixtures.new({ store = store, profileService = profileService }).service
	local env = {
		store = store,
		repository = repository,
		profileService = profileService,
		acquisitionService = acquisitionService,
		now = now,
		battleService = nil,
		idCounter = 0,
	}

	local function newContractService(serviceProfileService)
		return ContractService.new({
			protocolVersion = ContractProtocol.Version,
			profileService = serviceProfileService or env.profileService,
			acquisitionService = env.acquisitionService,
			factory = CritterInstanceFactory.new(),
			projector = ProfileProjector,
			catalog = CritterCatalog,
			generateId = function()
				env.idCounter += 1
				return `contract-id-{env.idCounter}`
			end,
			now = function()
				return env.now
			end,
			activeBattleId = function(userId)
				if env.battleService == nil then
					return nil
				end
				return env.battleService.getActiveBattleId(userId)
			end,
			maxInstances = settings.maxInstances,
			maxRedemptions = settings.maxRedemptions,
		})
	end

	env.newContractService = newContractService
	env.contractService = newContractService()

	function env.createBattleService(serviceOverride, battleOptions)
		local deps = Run5Fixtures.dependencies()
		deps.now = function()
			return env.now
		end
		deps.onBattleCompleted = function(evidence)
			return (serviceOverride or env.contractService).RecordBattleCompletion(evidence)
		end
		for key, value in battleOptions or {} do
			deps[key] = value
		end
		env.battleService = BattleService.new(deps)
		return env.battleService
	end

	function env.advance(seconds: number)
		env.now += seconds
	end

	function env.load(userId: number)
		local loaded = env.profileService.LoadProfile(userId)
		assert(loaded.ok, "profile load failed")
		return loaded.value
	end

	function env.read(userId: number)
		local profile = env.profileService.ReadProfile(userId)
		assert(profile.ok, "profile read failed")
		return profile.value
	end

	return env
end

function ContractFixtures.acceptRequest(env, overrides)
	local value = {
		protocolVersion = ContractProtocol.Version,
		kind = ContractProtocol.RequestKinds.ACCEPT_CONTRACT,
		commandId = `accept.command.{env.idCounter + 1}`,
		expectedRevision = 0,
		definitionId = "TRAINING_VICTORY",
		definitionVersion = 1,
	}
	for key, replacement in overrides or {} do
		value[key] = replacement
	end
	return value
end

function ContractFixtures.accept(env, userId: number, overrides, service)
	local request = ContractFixtures.acceptRequest(env, overrides)
	request.expectedRevision = env.read(userId).revision
	return (service or env.contractService).AcceptContract(userId, request), request
end

function ContractFixtures.completeRequest(env, userId: number, battleId: string, overrides)
	local value = {
		context = ContractFixtures.SERVER_CONTEXT,
		userId = userId,
		mode = "TRAINING",
		battleId = battleId,
		playerTeamId = "team.player",
		startedAt = env.now,
		completedAt = env.now,
		outcome = {
			isDraw = false,
			winnerTeamId = "team.player",
		},
	}
	for key, replacement in overrides or {} do
		value[key] = replacement
	end
	return value
end

function ContractFixtures.complete(env, userId: number, battleId: string, overrides, service)
	return (service or env.contractService).RecordBattleCompletion(
		ContractFixtures.completeRequest(env, userId, battleId, overrides)
	)
end

function ContractFixtures.claimRequest(env, userId: number, contractId: string, overrides)
	local value = {
		protocolVersion = ContractProtocol.Version,
		kind = ContractProtocol.RequestKinds.CLAIM_CONTRACT_REWARD,
		commandId = `claim.command.{env.idCounter + 1}`,
		expectedRevision = env.read(userId).revision,
		contractId = contractId,
	}
	for key, replacement in overrides or {} do
		value[key] = replacement
	end
	return value
end

function ContractFixtures.claim(env, userId: number, contractId: string, overrides, service)
	local request = ContractFixtures.claimRequest(env, userId, contractId, overrides)
	return (service or env.contractService).ClaimReward(userId, request), request
end

function ContractFixtures.outstanding(env, userId: number, definitionId: string?)
	local contracts = env.read(userId).contracts
	for _, contractId in contracts.instanceOrder do
		local instance = contracts.instancesById[contractId]
		if
			(definitionId == nil or instance.definitionId == definitionId)
			and (instance.status == "ACTIVE" or instance.status == "COMPLETED")
		then
			return instance
		end
	end
	return nil
end

function ContractFixtures.count(value): number
	local total = 0
	for _ in value do
		total += 1
	end
	return total
end

ContractFixtures.Catalog = ContractCatalog
ContractFixtures.Protocol = ContractProtocol
ContractFixtures.new = new
return ContractFixtures
