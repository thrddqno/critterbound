--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevelopmentLogger = require(Shared.DevelopmentLogger)
local Protocol = require(Shared.Network.Protocol)
local PlayerDataProtocol = require(Shared.Network.PlayerDataProtocol)
local BreedingProtocol = require(Shared.Network.BreedingProtocol)
local EggProtocol = require(Shared.Network.EggProtocol)
local ContractProtocol = require(Shared.Network.ContractProtocol)
local TrainingGrounds = require(Shared.Definitions.TrainingGrounds)
local CritterCatalog = require(Shared.Definitions.CritterCatalog)
local ItemRegistry = require(Shared.Items.ItemRegistry)
local InventoryValidator = require(Shared.Validation.InventoryValidator)
local TeamValidator = require(Shared.Validation.TeamValidator)
local BattleFactory = require(Shared.Battle.BattleFactory)
local BattlePlan = require(Shared.Battle.BattlePlan)
local RoundResolver = require(Shared.Battle.RoundResolver)
local DeterministicRng = require(Shared.Battle.DeterministicRng)
local Deck = require(Shared.Battle.Deck)
local DeckBuilder = require(Shared.Battle.DeckBuilder)
local DeckRules = require(Shared.Battle.DeckRules)
local DeckShuffler = require(Shared.Battle.DeckShuffler)
local RoundEconomy = require(Shared.Battle.RoundEconomy)
local StatusEffects = require(Shared.Battle.StatusEffects)
local DomainValidator = require(Shared.Validation.DomainValidator)
local Server = script.Parent
local GenomeValidator = require(Shared.Genetics.GenomeValidator)
local GenotypeExpressor = require(Shared.Genetics.GenotypeExpressor)
local InheritanceEngine = require(Server.Genetics.InheritanceEngine)
local ClassInheritancePolicy = require(Server.Genetics.ClassInheritancePolicy)
local MutationEngine = require(Server.Genetics.MutationEngine)
local MutationPolicy = require(Server.Genetics.MutationPolicy)
local ConceptionRng = require(Server.Genetics.ConceptionRng)
local BreedingValidator = require(Server.Services.BreedingValidator)

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[clone(key)] = clone(child)
	end
	return result
end
local BattleService = require(Server.Services.BattleService)
local ProfileService = require(Server.Services.ProfileService)
local TrainingBattleInputAdapter = require(Server.Services.TrainingBattleInputAdapter)
local InventoryService = require(Server.Services.InventoryService)
local EquipmentService = require(Server.Services.EquipmentService)
local TeamService = require(Server.Services.TeamService)
local BreedingService = require(Server.Services.BreedingService)
local EggService = require(Server.Services.EggService)
local CritterAcquisitionService = require(Server.Services.CritterAcquisitionService)
local ContractService = require(Server.Services.ContractService)
local CritterInstanceFactory = require(Server.Persistence.CritterInstanceFactory)
local PlayerDataService = require(Server.Services.PlayerDataService)
local BattleCommandProcessor = require(Server.Services.BattleCommandProcessor)
local BattleProjector = require(Server.Services.BattleProjector)
local TrainingPlanner = require(Server.AI.TrainingPlanner)
local ProfileSchema = require(Server.Persistence.ProfileSchema)
local ProfileMigrations = require(Server.Persistence.ProfileMigrations)
local StarterGrant = require(Server.Persistence.StarterGrant)
local ProfileRepository = require(Server.Persistence.ProfileRepository)
local ProfileProjector = require(Server.Persistence.ProfileProjector)
local DevelopmentConfig = require(Server.Config.DevelopmentConfig)
local CombatConfig = require(Server.Config.CombatConfig)
local GeneticsConfig = require(Server.Config.GeneticsConfig)
local StudioAcquisitionFixtures = require(Server.Config.StudioAcquisitionFixtures)
local GeneRegistry = require(Shared.Genetics.GeneRegistry)

local storeOk, storeOrError = pcall(function()
	return DataStoreService:GetDataStore("CritterboundPlayerProfiles_v1")
end)
local profileStore = storeOrError
if not storeOk then
	DevelopmentLogger.warn(`Profile DataStore initialization failed: {tostring(storeOrError)}`)
	profileStore = {
		UpdateAsync = function()
			error("Profile DataStore is unavailable")
		end,
	}
end
local jitterRandom = Random.new()
local profileRepository = ProfileRepository.new({
	store = profileStore,
	schema = ProfileSchema,
	migrations = ProfileMigrations,
	migrationHooks = ProfileMigrations.DefaultHooks,
	starterGrant = StarterGrant,
	catalog = CritterCatalog,
	clock = os.time,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	wait = task.wait,
	jitter = function()
		return jitterRandom:NextNumber(0, 0.25)
	end,
	log = DevelopmentLogger.warn,
	jobId = game.JobId,
	leaseSeconds = 180,
	maxAttempts = 5,
	baseDelay = 0.5,
	maxDelay = 4,
})
local profileService = ProfileService.new({
	repository = profileRepository,
	projector = ProfileProjector,
	catalog = CritterCatalog,
	wait = task.wait,
	loadWaitSeconds = 20,
	loadPollSeconds = 0.05,
})
local trainingInputAdapter = TrainingBattleInputAdapter.new({
	profileService = profileService,
	content = TrainingGrounds,
})
local inventoryService = InventoryService.new({
	profileService = profileService,
	registry = ItemRegistry,
	validator = InventoryValidator,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	clock = os.time,
	maxUniqueBatch = 20,
})
local equipmentService = EquipmentService.new({
	profileService = profileService,
	registry = ItemRegistry,
	validator = InventoryValidator,
})
local teamService = TeamService.new({
	profileService = profileService,
	validator = TeamValidator,
	catalog = CritterCatalog,
})

local eggService = EggService.new({
	protocolVersion = EggProtocol.Version,
	profileService = profileService,
	catalog = CritterCatalog,
	projector = ProfileProjector,
	genomeValidator = GenomeValidator,
	genotypeExpressor = GenotypeExpressor,
	conceptionRng = ConceptionRng,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	now = os.time,
})

local activeGeneticsConfig = GeneticsConfig.Default
if RunService:IsStudio() and DevelopmentConfig.EnableStudioClassicGeneticsAcceptance then
	activeGeneticsConfig = GeneticsConfig.classic(true)
end

local breedingService = BreedingService.new({
	protocolVersion = BreedingProtocol.Version,
	profileService = profileService,
	validator = BreedingValidator,
	catalog = CritterCatalog,
	genomeValidator = GenomeValidator,
	inheritanceEngine = InheritanceEngine,
	classInheritancePolicy = ClassInheritancePolicy,
	mutationEngine = MutationEngine,
	mutationPolicy = MutationPolicy,
	genotypeExpressor = GenotypeExpressor,
	conceptionRng = ConceptionRng,
	geneticsConfig = activeGeneticsConfig,
	rng = DeterministicRng,
	rngSeed = function()
		return ConceptionRng.hashParts({ HttpService:GenerateGUID(false), "LEGACY_BREEDING" })
	end,
	conceptionSeed = function()
		return ConceptionRng.hashParts({ HttpService:GenerateGUID(false), "CLASSIC_CONCEPTION_V1" })
	end,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	now = os.time,
	incubationSeconds = BreedingProtocol.IncubationSeconds,
})

DevelopmentLogger.info(
	`Genetics policy={activeGeneticsConfig.mode} mutation={tostring(
		activeGeneticsConfig.mutationEnabled == true
	)} rate={tostring(activeGeneticsConfig.mutationProbabilityNumerator or 0)}/{tostring(
		activeGeneticsConfig.mutationProbabilityDenominator or 1
	)}`
)

local acquisitionService = CritterAcquisitionService.new({
	profileService = profileService,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	now = os.time,
})

local remotes = ReplicatedStorage:FindFirstChild(Protocol.RemoteFolderName)
if remotes == nil then
	remotes = Instance.new("Folder")
	remotes.Name = Protocol.RemoteFolderName
	remotes.Parent = ReplicatedStorage
end

local battleRequest = remotes:FindFirstChild(Protocol.BattleRequestName)
if battleRequest == nil then
	battleRequest = Instance.new("RemoteFunction")
	battleRequest.Name = Protocol.BattleRequestName
	battleRequest.Parent = remotes
end

local playerDataRequest = remotes:FindFirstChild(PlayerDataProtocol.RemoteName)
if playerDataRequest == nil then
	playerDataRequest = Instance.new("RemoteFunction")
	playerDataRequest.Name = PlayerDataProtocol.RemoteName
	playerDataRequest.Parent = remotes
end

local breedingRequest = remotes:FindFirstChild(BreedingProtocol.RemoteName)
if breedingRequest == nil then
	breedingRequest = Instance.new("RemoteFunction")
	breedingRequest.Name = BreedingProtocol.RemoteName
	breedingRequest.Parent = remotes
end

local eggRequest = remotes:FindFirstChild(EggProtocol.RemoteName)
if eggRequest == nil then
	eggRequest = Instance.new("RemoteFunction")
	eggRequest.Name = EggProtocol.RemoteName
	eggRequest.Parent = remotes
end

local contractRequest = remotes:FindFirstChild(ContractProtocol.RemoteName)
if contractRequest == nil then
	contractRequest = Instance.new("RemoteFunction")
	contractRequest.Name = ContractProtocol.RemoteName
	contractRequest.Parent = remotes
end

local contractService
local battleService = BattleService.new({
	protocolVersion = Protocol.Version,
	content = TrainingGrounds,
	inputFactory = trainingInputAdapter,
	factory = BattleFactory,
	battlePlan = BattlePlan,
	commandProcessor = BattleCommandProcessor,
	projector = BattleProjector,
	resolver = RoundResolver,
	aiPlanner = TrainingPlanner,
	rng = DeterministicRng,
	criticalRngSeed = function()
		local material = HttpService:GenerateGUID(false)
		local value = 1
		for index = 1, #material do
			value = (value * 131 + string.byte(material, index)) % 2147483646
		end
		return value + 1
	end,
	deck = Deck,
	deckBuilder = DeckBuilder,
	deckRules = DeckRules.Default,
	deckShuffler = DeckShuffler,
	economy = RoundEconomy,
	statusEffects = StatusEffects,
	bloodMoonConfig = CombatConfig.BloodMoon,
	validator = DomainValidator,
	now = os.time,
	planningNow = function()
		return Workspace:GetServerTimeNow()
	end,
	planningSeconds = 45,
	schedule = task.delay,
	cancelScheduled = task.cancel,
	onBattleCompleted = function(evidence)
		if contractService == nil then
			return {
				ok = false,
				errors = {
					{
						code = "CONTRACT_SERVICE_UNAVAILABLE",
						message = "Contract service is unavailable",
					},
				},
			}
		end
		return contractService.RecordBattleCompletion(evidence)
	end,
})
contractService = ContractService.new({
	protocolVersion = ContractProtocol.Version,
	profileService = profileService,
	acquisitionService = acquisitionService,
	factory = CritterInstanceFactory.new(),
	projector = ProfileProjector,
	catalog = CritterCatalog,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
	now = os.time,
	activeBattleId = function(userId)
		return battleService.getActiveBattleId(userId)
	end,
})
local playerDataService = PlayerDataService.new({
	protocolVersion = PlayerDataProtocol.Version,
	profileService = profileService,
	inventoryService = inventoryService,
	equipmentService = equipmentService,
	teamService = teamService,
	projector = ProfileProjector,
	catalog = CritterCatalog,
	itemRegistry = ItemRegistry,
	clock = os.clock,
	mutationInterval = 0.25,
	invalidateBattle = battleService.invalidateBattle,
})

local battleRequestRemote = battleRequest :: RemoteFunction
battleRequestRemote.OnServerInvoke = function(player: Player, request)
	local ok, response = pcall(function()
		return battleService.handleRequest(player.UserId, request)
	end)
	if not ok then
		DevelopmentLogger.warn(`Battle request failed: {response}`)
		return {
			ok = false,
			errors = { { code = "INTERNAL_ERROR", message = "Battle request failed" } },
		}
	end
	return response
end

local playerDataRequestRemote = playerDataRequest :: RemoteFunction
playerDataRequestRemote.OnServerInvoke = function(player: Player, request)
	local ok, response = pcall(function()
		return playerDataService.handleRequest(player.UserId, request)
	end)
	if not ok then
		DevelopmentLogger.warn(`Player data request failed: {response}`)
		return {
			ok = false,
			errors = { { code = "INTERNAL_ERROR", message = "Player data request failed" } },
		}
	end
	return response
end

local breedingRequestRemote = breedingRequest :: RemoteFunction
breedingRequestRemote.OnServerInvoke = function(player: Player, request)
	local ok, response = pcall(function()
		return breedingService.handleRequest(player.UserId, request)
	end)
	if not ok then
		DevelopmentLogger.warn(`Breeding request failed: {response}`)
		return {
			ok = false,
			errors = { { code = "INTERNAL_ERROR", message = "Breeding request failed" } },
		}
	end
	return response
end

local eggRequestRemote = eggRequest :: RemoteFunction
eggRequestRemote.OnServerInvoke = function(player: Player, request)
	local ok, response = pcall(function()
		return eggService.handleRequest(player.UserId, request)
	end)
	if not ok then
		DevelopmentLogger.warn(`Egg request failed: {response}`)
		return {
			ok = false,
			errors = { { code = "INTERNAL_ERROR", message = "Egg request failed" } },
		}
	end
	return response
end

local contractRequestRemote = contractRequest :: RemoteFunction
contractRequestRemote.OnServerInvoke = function(player: Player, request)
	local ok, response = pcall(function()
		return contractService.handleRequest(player.UserId, request)
	end)
	if not ok then
		DevelopmentLogger.warn(`Contract request failed: {response}`)
		return {
			ok = false,
			errors = { { code = "INTERNAL_ERROR", message = "Contract request failed" } },
		}
	end
	return response
end

Players.PlayerRemoving:Connect(function(player)
	battleService.playerDisconnected(player.UserId)
	playerDataService.removePlayer(player.UserId)
	breedingService.removePlayer(player.UserId)
	eggService.removePlayer(player.UserId)
	acquisitionService.removePlayer(player.UserId)
	contractService.removePlayer(player.UserId)
	local released = profileService.ReleaseProfile(player.UserId)
	if not released.ok then
		DevelopmentLogger.warn(
			`Final profile save failed for user {player.UserId}: {released.errors[1].code}`
		)
	end
end)

local function loadPlayer(player: Player)
	local result = profileService.LoadProfile(player.UserId)
	if not result.ok and player.Parent == Players then
		DevelopmentLogger.warn(
			`Profile load failed for user {player.UserId}: {result.errors[1].code}`
		)
		player:Kick("Player data is temporarily unavailable. Please rejoin.")
	elseif
		result.ok
		and RunService:IsStudio()
		and DevelopmentConfig.EnableStudioInventoryFixture
	then
		local currentInventory = inventoryService.GetInventory(player.UserId)
		local ownedDefinitions = {}
		if currentInventory.ok then
			for _, stack in currentInventory.value.stacks do
				ownedDefinitions[stack.definitionId] = true
			end
			for _, item in currentInventory.value.uniqueItems do
				ownedDefinitions[item.definitionId] = true
			end
		end
		for _, fixture in
			{
				{
					definitionId = "material.iron_shard",
					quantity = 8,
					operationId = "studio.run6c.iron",
				},
				{
					definitionId = "equipment.training_charm",
					quantity = 1,
					operationId = "studio.run6c.charm",
				},
			}
		do
			if ownedDefinitions[fixture.definitionId] then
				continue
			end
			local granted = inventoryService.AddItem(player.UserId, {
				definitionId = fixture.definitionId,
				quantity = fixture.quantity,
				operationId = fixture.operationId,
				source = "STUDIO_FIXTURE",
			})
			if not granted.ok then
				DevelopmentLogger.warn(
					`Studio fixture failed for user {player.UserId}: {granted.errors[1].code}`
				)
			end
		end
	end
	if result.ok and RunService:IsStudio() and DevelopmentConfig.EnableStudioBreedingFixture then
		local profile = profileService.ReadProfile(player.UserId)
		local hasBreedable = false
		if profile.ok then
			for _, critter in profile.value.ownedCritters do
				if critter.breeding and critter.breeding.breedable then
					hasBreedable = true
					break
				end
			end
		end
		if not hasBreedable then
			local now = os.time()
			local grantedCritters = {}
			for _, className in { "Tide", "Gale" } do
				local definition = CritterCatalog.getByClass(className)
				local genomes = GeneRegistry.founderGenomes(className)
				if definition ~= nil and genomes ~= nil then
					table.insert(grantedCritters, {
						schemaVersion = 3,
						id = `critter:{HttpService:GenerateGUID(false)}`,
						definitionId = definition.id,
						ownerUserId = player.UserId,
						appearanceGenome = clone(genomes.appearanceGenome),
						abilityGenome = clone(genomes.abilityGenome),
						baseStats = clone(definition.baseStats),
						acquisition = {
							source = "STUDIO_FIXTURE",
							acquiredAt = now,
							sourceVersion = 1,
						},
						breeding = {
							breedable = true,
							generation = 0,
							parentIds = {},
							successfulBreedCount = 0,
						},
						tradable = false,
						equipmentIds = {},
					})
				end
			end
			local update = profileService.UpdateProfile(player.UserId, function(candidate)
				for _, critter in grantedCritters do
					candidate.ownedCritters[critter.id] = clone(critter)
				end
				return { ok = true, value = true }
			end)
			if not update.ok then
				DevelopmentLogger.warn(
					`Studio breeding fixture failed for user {player.UserId}: {update.errors[1].code}`
				)
			end
		end
	end
	if result.ok and RunService:IsStudio() and DevelopmentConfig.EnableStudioAcquisitionFixture then
		local fixtureOk, fixtureError = pcall(function()
			StudioAcquisitionFixtures.run(player, acquisitionService)
		end)
		if not fixtureOk then
			DevelopmentLogger.warn(
				`Studio acquisition fixture failed for user {player.UserId}: {tostring(fixtureError)}`
			)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)

for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end

local shuttingDown = false
task.spawn(function()
	while not shuttingDown do
		task.wait(60)
		if shuttingDown then
			break
		end
		for _, userId in profileService.loadedUserIds() do
			task.spawn(function()
				local saved = profileService.SaveProfile(userId)
				if not saved.ok then
					DevelopmentLogger.warn(
						`Autosave failed for user {userId}: {saved.errors[1].code}`
					)
				end
			end)
		end
	end
end)

game:BindToClose(function()
	shuttingDown = true
	profileService.beginShutdown()
	local pending = 0
	for _, userId in profileService.loadedUserIds() do
		pending += 1
		task.spawn(function()
			local released = profileService.ReleaseProfile(userId)
			if not released.ok then
				DevelopmentLogger.warn(
					`Shutdown profile save failed for user {userId}: {released.errors[1].code}`
				)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	if pending > 0 then
		DevelopmentLogger.warn(`Shutdown ended with {pending} profile save(s) pending`)
	end
end)

DevelopmentLogger.info("Server initialized")
