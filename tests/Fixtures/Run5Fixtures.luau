--!strict

local BattleFactory = require("../../src/shared/Battle/BattleFactory")
local BattlePlan = require("../../src/shared/Battle/BattlePlan")
local RoundResolver = require("../../src/shared/Battle/RoundResolver")
local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
local Deck = require("../../src/shared/Battle/Deck")
local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
local StatusEffects = require("../../src/shared/Battle/StatusEffects")
local DomainValidator = require("../../src/shared/Validation/DomainValidator")
local Protocol = require("../../src/shared/Network/Protocol")
local TrainingGrounds = require("../../src/shared/Definitions/TrainingGrounds")
local TrainingPlanner = require("../../src/server/AI/TrainingPlanner")
local BattleService = require("../../src/server/Services/BattleService")
local BattleCommandProcessor = require("../../src/server/Services/BattleCommandProcessor")
local BattleProjector = require("../../src/server/Services/BattleProjector")

local function dependencies()
	return {
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
	}
end

local function createService()
	return BattleService.new(dependencies())
end

local function start(service, userId: number)
	local result = service.startBattle(userId)
	assert(result.ok, "Run 5 fixture battle must start")
	return result.value.snapshot
end

local function command(snapshot, id: string, commandType: string, payload)
	return {
		protocolVersion = Protocol.Version,
		matchId = snapshot.battleState.id,
		teamId = snapshot.viewerTeamId,
		commandId = id,
		expectedStateVersion = snapshot.revision,
		expectedPlanVersion = snapshot.planVersion,
		commandType = commandType,
		payload = payload or {},
	}
end

return {
	dependencies = dependencies,
	createService = createService,
	start = start,
	command = command,
}
