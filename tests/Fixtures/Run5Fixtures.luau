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

local function createTiming()
	local timing = { time = 1_000, scheduled = {} }
	function timing.now()
		return timing.time
	end
	function timing.schedule(delaySeconds, callback)
		local handle = {
			at = timing.time + delaySeconds,
			callback = callback,
			cancelled = false,
		}
		table.insert(timing.scheduled, handle)
		return handle
	end
	function timing.cancel(handle)
		handle.cancelled = true
	end
	function timing.advance(seconds)
		timing.time += seconds
		while true do
			local due = nil
			for _, handle in timing.scheduled do
				if not handle.cancelled and handle.at <= timing.time then
					due = handle
					break
				end
			end
			if due == nil then
				break
			end
			due.cancelled = true
			due.callback()
		end
	end
	return timing
end

local function dependencies(overrides)
	local timing = if overrides ~= nil and overrides.timing ~= nil
		then overrides.timing
		else createTiming()
	local result = {
		protocolVersion = Protocol.Version,
		content = TrainingGrounds,
		factory = BattleFactory,
		battlePlan = BattlePlan,
		commandProcessor = BattleCommandProcessor,
		projector = BattleProjector,
		resolver = RoundResolver,
		aiPlanner = TrainingPlanner,
		rng = DeterministicRng,
		criticalRngSeed = function(userId, generation)
			return (userId * 97 + generation * 193) % 2147483646 + 1
		end,
		deck = Deck,
		economy = RoundEconomy,
		statusEffects = StatusEffects,
		validator = DomainValidator,
		drawPerRound = 3,
		planningNow = timing.now,
		planningSeconds = 45,
		schedule = timing.schedule,
		cancelScheduled = timing.cancel,
	}
	for key, value in overrides or {} do
		if key ~= "timing" then
			result[key] = value
		end
	end
	return result
end

local function createService()
	return BattleService.new(dependencies())
end

local function createTimedService(overrides)
	local timing = createTiming()
	local options = overrides or {}
	options.timing = timing
	return BattleService.new(dependencies(options)), timing
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
	createTimedService = createTimedService,
	createTiming = createTiming,
	start = start,
	command = command,
}
