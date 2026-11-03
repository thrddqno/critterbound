--!strict

local MockDataStore = require("./MockDataStore")
local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
local ItemRegistry = require("../../src/shared/Items/ItemRegistry")
local InventoryValidator = require("../../src/shared/Validation/InventoryValidator")
local TeamValidator = require("../../src/shared/Validation/TeamValidator")
local ProfileSchema = require("../../src/server/Persistence/ProfileSchema")
local ProfileMigrations = require("../../src/server/Persistence/ProfileMigrations")
local StarterGrant = require("../../src/server/Persistence/StarterGrant")
local ProfileRepository = require("../../src/server/Persistence/ProfileRepository")
local ProfileProjector = require("../../src/server/Persistence/ProfileProjector")
local ProfileService = require("../../src/server/Services/ProfileService")
local InventoryService = require("../../src/server/Services/InventoryService")
local EquipmentService = require("../../src/server/Services/EquipmentService")
local TeamService = require("../../src/server/Services/TeamService")

local function newRepository(store, jobId: string, options)
	local idCounter = 0
	local now = if options and options.now then options.now else 1_700_000_000
	return ProfileRepository.new({
		store = store,
		schema = ProfileSchema,
		migrations = ProfileMigrations,
		migrationHooks = if options and options.migrationHooks
			then options.migrationHooks
			else ProfileMigrations.DefaultHooks,
		starterGrant = StarterGrant,
		catalog = CritterCatalog,
		clock = function()
			return now
		end,
		generateId = function()
			idCounter += 1
			return `{jobId}-{idCounter}`
		end,
		wait = function() end,
		jitter = function()
			return 0
		end,
		log = function() end,
		jobId = jobId,
		leaseSeconds = 180,
		maxAttempts = 3,
		baseDelay = 0,
		maxDelay = 0,
	})
end

local function newService(repository, options)
	return ProfileService.new({
		repository = repository,
		projector = ProfileProjector,
		catalog = CritterCatalog,
		wait = if options and options.wait then options.wait else function() end,
		loadWaitSeconds = 1,
		loadPollSeconds = 0.1,
	})
end

local itemIdCounter = 0
local function newInventoryService(profileService)
	return InventoryService.new({
		profileService = profileService,
		registry = ItemRegistry,
		validator = InventoryValidator,
		generateId = function()
			itemIdCounter += 1
			return `fixture-item-{itemIdCounter}`
		end,
		clock = function()
			return 1_700_000_000
		end,
		maxUniqueBatch = 20,
	})
end

local function newEquipmentService(profileService)
	return EquipmentService.new({
		profileService = profileService,
		registry = ItemRegistry,
		validator = InventoryValidator,
	})
end

local function newTeamService(profileService)
	return TeamService.new({
		profileService = profileService,
		validator = TeamValidator,
		catalog = CritterCatalog,
	})
end

return {
	MockDataStore = MockDataStore,
	Catalog = CritterCatalog,
	ItemRegistry = ItemRegistry,
	InventoryValidator = InventoryValidator,
	TeamValidator = TeamValidator,
	Schema = ProfileSchema,
	Migrations = ProfileMigrations,
	StarterGrant = StarterGrant,
	newRepository = newRepository,
	newService = newService,
	newInventoryService = newInventoryService,
	newEquipmentService = newEquipmentService,
	newTeamService = newTeamService,
}
