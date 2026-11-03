--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevelopmentLogger = require(Shared.DevelopmentLogger)
local Protocol = require(Shared.Network.Protocol)
local TrainingGrounds = require(Shared.Definitions.TrainingGrounds)
local BattleFactory = require(Shared.Battle.BattleFactory)
local BattlePlan = require(Shared.Battle.BattlePlan)
local RoundResolver = require(Shared.Battle.RoundResolver)
local DeterministicRng = require(Shared.Battle.DeterministicRng)
local Deck = require(Shared.Battle.Deck)
local RoundEconomy = require(Shared.Battle.RoundEconomy)
local StatusEffects = require(Shared.Battle.StatusEffects)
local DomainValidator = require(Shared.Validation.DomainValidator)

local Server = script.Parent
local BattleService = require(Server.Services.BattleService)
local BattleCommandProcessor = require(Server.Services.BattleCommandProcessor)
local BattleProjector = require(Server.Services.BattleProjector)
local TrainingPlanner = require(Server.AI.TrainingPlanner)

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

local battleService = BattleService.new({
	protocolVersion = Protocol.Version,
	content = TrainingGrounds,
	factory = BattleFactory,
	battlePlan = BattlePlan,
	commandProcessor = BattleCommandProcessor,
	projector = BattleProjector,
	resolver = RoundResolver,
	aiPlanner = TrainingPlanner,
	rng = DeterministicRng,
	deck = Deck,
	economy = RoundEconomy,
	statusEffects = StatusEffects,
	validator = DomainValidator,
	drawPerRound = 3,
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

Players.PlayerRemoving:Connect(function(player)
	battleService.removePlayer(player.UserId)
end)

DevelopmentLogger.info("Server initialized")
