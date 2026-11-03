--!strict

-- Shared setup for Run 7E.2 acquisition tests.

local ProfileFixtures = require("./ProfileFixtures")
local CritterAcquisitionService = require("../../src/server/Services/CritterAcquisitionService")
local CritterInstanceFactory = require("../../src/server/Persistence/CritterInstanceFactory")

local AcquisitionFixtures = {}

AcquisitionFixtures.NOW = 1_700_000_000
AcquisitionFixtures.SERVER_CONTEXT = { kind = "SERVER", source = "TEST_HARNESS" }

function AcquisitionFixtures.new(options)
	local settings = options or {}
	local store = settings.store or ProfileFixtures.MockDataStore.new()
	local repository = ProfileFixtures.newRepository(
		store,
		settings.jobId or "acquisition-job",
		{ now = AcquisitionFixtures.NOW }
	)
	local profileService = ProfileFixtures.newService(repository)
	local counter = 0
	local service = CritterAcquisitionService.new({
		profileService = settings.profileService or profileService,
		generateId = function()
			counter += 1
			return `acquisition-{counter}`
		end,
		now = function()
			return AcquisitionFixtures.NOW
		end,
		authorizeGrant = settings.authorizeGrant,
		maxOperationRecords = settings.maxOperationRecords,
	})
	return {
		store = store,
		repository = repository,
		profileService = profileService,
		service = service,
		factory = CritterInstanceFactory.new(),
		nextId = function()
			counter += 1
			return `acquisition-{counter}`
		end,
	}
end

function AcquisitionFixtures.request(poolId: string, seed: number, overrides)
	local value = {
		commandId = `cmd.{poolId}.{seed}`,
		grantId = `grant.{poolId}.{seed}`,
		poolId = poolId,
		seed = seed,
		class = nil,
		context = AcquisitionFixtures.SERVER_CONTEXT,
	}
	for key, replacement in overrides or {} do
		value[key] = replacement
	end
	return value
end

function AcquisitionFixtures.load(env, userId: number)
	local loaded = env.profileService.LoadProfile(userId)
	assert(loaded.ok, "profile load failed")
	return loaded.value
end

function AcquisitionFixtures.grant(env, userId: number, poolId: string, seed: number, overrides)
	local request = AcquisitionFixtures.request(poolId, seed, overrides)
	local result = env.service.GrantCritter(userId, request)
	return result, request
end

function AcquisitionFixtures.reload(env, userId: number)
	local released = env.profileService.ReleaseProfile(userId)
	assert(released.ok, "profile release failed")
	local reloaded =
		ProfileFixtures.newService(ProfileFixtures.newRepository(env.store, "acquisition-reload", {
			now = AcquisitionFixtures.NOW,
		}))
	return reloaded
end

return AcquisitionFixtures
