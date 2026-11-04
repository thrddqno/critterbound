--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local ContractFixtures = require("../Fixtures/ContractFixtures")
	local DomainFixtures = require("../Fixtures/DomainFixtures")
	local ProfileMigrations = require("../../src/server/Persistence/ProfileMigrations")
	local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")
	local ContractCatalog = require("../../src/shared/Definitions/ContractCatalog")
	local AcquisitionPools = require("../../src/shared/Definitions/AcquisitionPools")
	local ContractProtocol = require("../../src/shared/Network/ContractProtocol")
	local ContractPresentation = require("../../src/client/Presentation/ContractPresentation")
	local Run5Fixtures = require("../Fixtures/Run5Fixtures")

	local function setup(userId: number, options)
		local env = ContractFixtures.new(options)
		env.load(userId)
		return env
	end

	local function controlledVictoryInputFactory(firstBuffedGeneration: number)
		local content = Run5Fixtures.dependencies().content
		return {
			createInput = function(userId: number, generation: number)
				local input = content.createInput(userId, generation)
				if generation >= firstBuffedGeneration then
					for _, team in input.teams do
						if team.id == "team.player" then
							for _, critter in team.critterInstances do
								critter.baseStats = {
									health = 500,
									speed = 100,
									skill = 100,
									morale = 100,
								}
							end
						end
					end
				end
				return input
			end,
		}
	end

	local function ownedCount(env, userId: number): number
		return ContractFixtures.count(env.read(userId).ownedCritters)
	end

	local function redeem(env, userId: number, contractId: string, overrides)
		local request = ContractFixtures.claimRequest(env, userId, contractId, overrides)
		local result = env.contractService.ClaimReward(userId, request)
		return result, request
	end

	local function acceptCompleteClaim(env, userId: number, battleSuffix: number)
		local accepted, acceptRequest = ContractFixtures.accept(env, userId, {
			commandId = `accept.{userId}.{battleSuffix}`,
		})
		Harness.expect(accepted.ok)
		env.advance(1)
		local completed =
			ContractFixtures.completeRequest(env, userId, `training:{userId}:{battleSuffix}`)
		local completedResult = env.contractService.RecordBattleCompletion(completed)
		Harness.expect(completedResult.ok)
		env.advance(1)
		local claimRequest =
			ContractFixtures.claimRequest(env, userId, accepted.value.contract.id, {
				commandId = `claim.{userId}.{battleSuffix}`,
				expectedRevision = env.read(userId).revision,
			})
		local claimed = env.contractService.ClaimReward(userId, claimRequest)
		Harness.expect(claimed.ok)
		return {
			env = env,
			accepted = accepted.value.contract,
			acceptRequest = acceptRequest,
			claimRequest = claimRequest,
			claimed = claimed.value,
		}
	end

	local function viewerRoundState(snapshot)
		for _, roundState in snapshot.battleState.teamRoundStates do
			if roundState.teamId == snapshot.viewerTeamId then
				return roundState
			end
		end
		error("Missing viewer round state")
	end

	local function legalPayload(snapshot, cardId)
		local instance = snapshot.cardInstancesById[cardId]
		local definition = instance and snapshot.cardDefinitionsById[instance.definitionId]
		if definition == nil then
			return nil
		end
		local source = nil
		for _, combatant in snapshot.battleState.combatants do
			if combatant.critterInstanceId == instance.sourceCritterInstanceId then
				source = combatant
				break
			end
		end
		if source == nil or source.currentHealth <= 0 then
			return nil
		end
		local targetIds = {}
		if definition.targetingRule == "ALLY" then
			for _, combatant in snapshot.battleState.combatants do
				if
					combatant.teamId == source.teamId
					and combatant.id ~= source.id
					and combatant.currentHealth > 0
				then
					targetIds = { combatant.id }
					break
				end
			end
			if #targetIds == 0 then
				return nil
			end
		elseif definition.targetingRule == "ANY" then
			local candidates = {}
			for _, combatant in snapshot.battleState.combatants do
				if combatant.teamId ~= source.teamId and combatant.currentHealth > 0 then
					table.insert(candidates, combatant)
				end
			end
			table.sort(candidates, function(a, b)
				if a.currentHealth ~= b.currentHealth then
					return a.currentHealth < b.currentHealth
				end
				return a.id < b.id
			end)
			if candidates[1] == nil then
				return nil
			end
			targetIds = { candidates[1].id }
		end
		return {
			cardInstanceId = cardId,
			sourceCombatantId = source.id,
			targetCombatantIds = targetIds,
		},
			definition
	end

	local function chooseAttackCard(snapshot)
		local roundState = viewerRoundState(snapshot)
		local queued = {}
		for _, value in snapshot.visibleQueuedCards do
			queued[value.cardInstanceId] = true
		end
		for _, cardId in roundState.handCardInstanceIds do
			if not queued[cardId] then
				local payload, definition = legalPayload(snapshot, cardId)
				if payload ~= nil and definition.energyCost <= roundState.energy then
					return payload, definition
				end
			end
		end
		return nil
	end

	local function send(service, userId: number, snapshot, id: string, commandType: string, payload)
		return service.processCommand(
			userId,
			require("../Fixtures/Run5Fixtures").command(snapshot, id, commandType, payload)
		)
	end

	local function playVictory(service, userId: number, snapshot)
		local rounds = 0
		local sequence = 0
		while snapshot.matchOutcome == nil and rounds < 60 do
			rounds += 1
			local energy = viewerRoundState(snapshot).energy
			local spent = 0
			while spent < energy do
				local payload, definition = chooseAttackCard(snapshot)
				if payload == nil then
					break
				end
				if spent + definition.energyCost > energy then
					break
				end
				sequence += 1
				local queued = send(
					service,
					userId,
					snapshot,
					`contract.queue.{sequence}`,
					"QUEUE_CARD",
					payload
				)
				Harness.expect(queued.ok)
				snapshot = queued.value.snapshot
				spent += definition.energyCost
			end
			sequence += 1
			local committed =
				send(service, userId, snapshot, `contract.commit.{sequence}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			Harness.expect(committed.value.resolution ~= nil)
			snapshot = committed.value.snapshot
		end
		Harness.expect(snapshot.matchOutcome ~= nil)
		Harness.equal(snapshot.matchOutcome.winnerTeamId, "team.player")
		return snapshot
	end

	local function playLoss(service, userId: number, snapshot)
		local rounds = 0
		while snapshot.matchOutcome == nil and rounds < 30 do
			rounds += 1
			local committed =
				send(service, userId, snapshot, `contract.idle.{rounds}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			snapshot = committed.value.snapshot
		end
		Harness.expect(snapshot.matchOutcome ~= nil)
		Harness.equal(snapshot.matchOutcome.winnerTeamId, "team.training")
		return snapshot
	end

	Harness.test(
		"contract catalog exposes one valid repeatable Training Victory contract",
		function()
			local definition = ContractCatalog.validate("TRAINING_VICTORY", 1)
			Harness.expect(definition.ok)
			Harness.equal(definition.value.requirement.kind, "TRAINING_PVE_WINS")
			Harness.equal(definition.value.requirement.count, 1)
			Harness.equal(definition.value.reward.poolId, "COMMON_FOUNDERS")
			Harness.equal(definition.value.repeatable, true)
			Harness.equal(definition.value.maxActivePerDefinition, 1)
			local pool = AcquisitionPools.validate(definition.value.reward.poolId)
			Harness.expect(pool.ok)
			Harness.equal(pool.value.version, 1)
			Harness.expect(
				Harness.hasError(ContractCatalog.validate("UNKNOWN"), "UNKNOWN_CONTRACT")
			)
		end
	)

	Harness.test("accept creates one outstanding contract and durable entitlement", function()
		local env = setup(701)
		local accepted, request = ContractFixtures.accept(env, 701)
		Harness.expect(accepted.ok)
		Harness.expect(accepted.value.duplicate == false)
		Harness.equal(accepted.value.contract.status, "ACTIVE")
		Harness.equal(accepted.value.contract.progressCurrent, 0)
		Harness.equal(accepted.value.contract.progressRequired, 1)
		local profile = env.read(701)
		local contracts = profile.contracts
		Harness.equal(#contracts.instanceOrder, 1)
		Harness.equal(#contracts.entitlementOrder, 1)
		local instance = contracts.instancesById[accepted.value.contract.id]
		Harness.expect(instance ~= nil)
		Harness.equal(instance.acceptCommandId, request.commandId)
		local entitlement = contracts.entitlementsById[instance.rewardEntitlementId]
		Harness.expect(entitlement ~= nil)
		Harness.equal(entitlement.status, "PENDING")
		Harness.equal(entitlement.poolId, "COMMON_FOUNDERS")
		Harness.equal(entitlement.poolVersion, 1)
		Harness.expect(type(entitlement.seed) == "number" and entitlement.seed >= 1)

		local duplicate = env.contractService.AcceptContract(701, request)
		Harness.expect(duplicate.ok)
		Harness.expect(duplicate.value.duplicate == true)
		Harness.equal(duplicate.value.contract.id, accepted.value.contract.id)
		Harness.equal(#env.read(701).contracts.instanceOrder, 1)

		local blocked = ContractFixtures.accept(env, 701)
		Harness.expect(Harness.hasError(blocked, "CONTRACT_ALREADY_ACTIVE"))
		Harness.equal(#env.read(701).contracts.instanceOrder, 1)
	end)

	Harness.test("pre-acceptance, lost, drawn, and duplicate battles never complete", function()
		local env = setup(702)
		local accepted = ContractFixtures.accept(env, 702)
		Harness.expect(accepted.ok)
		local contractId = accepted.value.contract.id
		local baseline = env.read(702).contracts.instancesById[contractId].baselineBattleId

		local before = ContractFixtures.completeRequest(env, 702, `training:702:1`, {
			startedAt = env.now - 10,
			completedAt = env.now - 5,
		})
		local beforeResult = env.contractService.RecordBattleCompletion(before)
		Harness.expect(beforeResult.ok)
		Harness.expect(beforeResult.value.ignored)
		Harness.equal(beforeResult.value.reason, "BATTLE_BEFORE_ACCEPTANCE")

		if baseline ~= nil then
			local same = ContractFixtures.completeRequest(env, 702, baseline)
			local sameResult = env.contractService.RecordBattleCompletion(same)
			Harness.expect(sameResult.value.ignored)
			Harness.equal(sameResult.value.reason, "BATTLE_BEFORE_ACCEPTANCE")
		end

		local loss = ContractFixtures.completeRequest(env, 702, "training:702:2", {
			outcome = { isDraw = false, winnerTeamId = "team.training" },
		})
		local lossResult = env.contractService.RecordBattleCompletion(loss)
		Harness.expect(lossResult.ok)
		Harness.expect(lossResult.value.ignored)
		Harness.equal(lossResult.value.reason, "NOT_A_VICTORY")

		local draw = ContractFixtures.completeRequest(env, 702, "training:702:3", {
			outcome = { isDraw = true, winnerTeamId = nil },
		})
		local drawResult = env.contractService.RecordBattleCompletion(draw)
		Harness.expect(drawResult.ok)
		Harness.expect(drawResult.value.ignored)

		env.advance(1)
		local win = ContractFixtures.completeRequest(env, 702, "training:702:4")
		local winResult = env.contractService.RecordBattleCompletion(win)
		Harness.expect(winResult.ok)
		Harness.expect(winResult.value.ignored == false)
		Harness.equal(winResult.value.contract.status, "COMPLETED")

		local duplicate = env.contractService.RecordBattleCompletion(win)
		Harness.expect(duplicate.ok)
		Harness.expect(duplicate.value.ignored)
		Harness.equal(env.read(702).contracts.instancesById[contractId].status, "COMPLETED")
	end)

	Harness.test("battle completion requires server authorization and matching player", function()
		local env = setup(703)
		local accepted = ContractFixtures.accept(env, 703)
		Harness.expect(accepted.ok)

		local clientContext = ContractFixtures.completeRequest(env, 703, "training:703:1", {
			context = { kind = "CLIENT", source = "BATTLE_SERVICE" },
		})
		Harness.expect(
			Harness.hasError(
				env.contractService.RecordBattleCompletion(clientContext),
				"UNAUTHORIZED_BATTLE_COMPLETION"
			)
		)
		local clientSource = ContractFixtures.completeRequest(env, 703, "training:703:1", {
			context = { kind = "SERVER", source = "CLIENT" },
		})
		Harness.expect(
			Harness.hasError(
				env.contractService.RecordBattleCompletion(clientSource),
				"UNAUTHORIZED_BATTLE_COMPLETION"
			)
		)
		local otherPlayer = ContractFixtures.completeRequest(env, 703, "training:704:1")
		Harness.expect(
			Harness.hasError(
				env.contractService.RecordBattleCompletion(otherPlayer),
				"INVALID_BATTLE_COMPLETION"
			)
		)
		local clientRequest = {
			protocolVersion = ContractProtocol.Version,
			kind = "RECORD_BATTLE_COMPLETION",
			userId = 703,
			battleId = "training:703:9",
			outcome = { isDraw = false, winnerTeamId = "team.player" },
		}
		Harness.expect(
			Harness.hasError(
				env.contractService.handleRequest(703, clientRequest),
				"INVALID_REQUEST_KIND"
			)
		)
		Harness.equal(
			env.read(703).contracts.instancesById[accepted.value.contract.id].status,
			"ACTIVE"
		)
	end)

	Harness.test("real Training Grounds victory completes a contract", function()
		local env = setup(704)
		local battleService = env.createBattleService(nil, {
			inputFactory = controlledVictoryInputFactory(1),
		})
		local accepted = ContractFixtures.accept(env, 704)
		Harness.expect(accepted.ok)
		env.advance(5)
		local started = battleService.startBattle(704)
		Harness.expect(started.ok)
		local snapshot = playVictory(battleService, 704, started.value.snapshot)
		Harness.equal(snapshot.battleState.phase, "FINISHED")
		local contract = env.read(704).contracts.instancesById[accepted.value.contract.id]
		Harness.equal(contract.status, "COMPLETED")
		Harness.equal(contract.progress.current, 1)
		Harness.equal(contract.completedBattleId, snapshot.battleState.id)
		Harness.equal(battleService.hasPendingCompletion(704), false)
	end)

	Harness.test("a real Training Grounds loss does not complete a contract", function()
		local env = setup(705)
		local battleService = env.createBattleService(nil, {
			inputFactory = controlledVictoryInputFactory(2),
		})
		local accepted = ContractFixtures.accept(env, 705)
		Harness.expect(accepted.ok)
		env.advance(5)
		local started = battleService.startBattle(705)
		Harness.expect(started.ok)
		playLoss(battleService, 705, started.value.snapshot)
		local contract = env.read(705).contracts.instancesById[accepted.value.contract.id]
		Harness.equal(contract.status, "ACTIVE")
		Harness.equal(contract.progress.current, 0)

		env.advance(5)
		local restarted = battleService.restartBattle(705, "restart.after.loss")
		Harness.expect(restarted.ok)
		playVictory(battleService, 705, restarted.value.snapshot)
		Harness.equal(
			env.read(705).contracts.instancesById[accepted.value.contract.id].status,
			"COMPLETED"
		)
	end)

	Harness.test("claim grants exactly one persisted Critter and retries idempotently", function()
		local env = setup(706)
		local accepted = ContractFixtures.accept(env, 706)
		Harness.expect(accepted.ok)
		env.advance(2)
		local win = ContractFixtures.completeRequest(env, 706, "training:706:1")
		Harness.expect(env.contractService.RecordBattleCompletion(win).ok)
		env.advance(2)
		local before = ownedCount(env, 706)
		local claimed, request = redeem(env, 706, accepted.value.contract.id)
		Harness.expect(claimed.ok)
		Harness.expect(claimed.value.duplicate == false)
		Harness.equal(ownedCount(env, 706), before + 1)
		local critter = claimed.value.critter
		Harness.equal(critter.id, claimed.value.redemption.critterId)
		Harness.equal(critter.acquisition.source, "CONTRACT.TRAINING_VICTORY")
		Harness.equal(critter.breeding.breedable, true)
		Harness.equal(critter.tradable, false)

		local profile = env.read(706)
		local contract = profile.contracts.instancesById[accepted.value.contract.id]
		Harness.equal(contract.status, "CLAIMED")
		local entitlement = profile.contracts.entitlementsById[contract.rewardEntitlementId]
		Harness.equal(entitlement.status, "CLAIMED")
		Harness.equal(entitlement.awardedCritterId, critter.id)
		Harness.equal(entitlement.claimCommandId, request.commandId)
		local redemption = profile.contracts.redemptionsById[accepted.value.contract.id]
		Harness.expect(redemption ~= nil)
		Harness.equal(redemption.awardedCritterId, critter.id)
		Harness.equal(redemption.awardedClass, critter.class)
		Harness.equal(redemption.poolId, "COMMON_FOUNDERS")
		Harness.equal(redemption.poolVersion, 1)

		local stored = profile.ownedCritters[critter.id]
		Harness.expect(stored ~= nil)
		local candidate = env.acquisitionService.GenerateCandidate({
			poolId = entitlement.poolId,
			seed = entitlement.seed,
			context = { kind = "SERVER", source = "CONTRACT_SERVICE" },
		})
		Harness.expect(candidate.ok)
		Harness.deepEqual(stored.appearanceGenome, candidate.value.appearanceGenome)
		Harness.deepEqual(stored.abilityGenome, candidate.value.abilityGenome)

		local duplicate = env.contractService.ClaimReward(706, request)
		Harness.expect(duplicate.ok)
		Harness.expect(duplicate.value.duplicate == true)
		Harness.equal(duplicate.value.critter.id, critter.id)
		Harness.equal(ownedCount(env, 706), before + 1)

		local newCommand = ContractFixtures.claimRequest(env, 706, accepted.value.contract.id, {
			commandId = "claim.new.command",
			expectedRevision = profile.revision + 10,
		})
		local alias = env.contractService.ClaimReward(706, newCommand)
		Harness.expect(alias.ok)
		Harness.expect(alias.value.duplicate == true)
		Harness.equal(alias.value.critter.id, critter.id)
		Harness.equal(ownedCount(env, 706), before + 1)
	end)

	Harness.test("claim is atomic on save failure and rejects stale revisions", function()
		local env = setup(707)
		local accepted = ContractFixtures.accept(env, 707)
		Harness.expect(accepted.ok)
		env.advance(2)
		Harness.expect(
			env.contractService.RecordBattleCompletion(
				ContractFixtures.completeRequest(env, 707, "training:707:1")
			).ok
		)
		env.advance(2)
		local before = ownedCount(env, 707)

		local stale = ContractFixtures.claimRequest(env, 707, accepted.value.contract.id, {
			commandId = "claim.stale",
			expectedRevision = env.read(707).revision - 1,
		})
		Harness.expect(
			Harness.hasError(env.contractService.ClaimReward(707, stale), "STALE_REVISION")
		)
		Harness.equal(ownedCount(env, 707), before)

		-- Repository retries failed DataStore writes three times before surfacing
		-- failure. Exhaust every attempt to verify the profile remains atomic.
		env.store.failNext(3)
		local failed = ContractFixtures.claimRequest(env, 707, accepted.value.contract.id, {
			commandId = "claim.save.failure",
		})
		local failedResult = env.contractService.ClaimReward(707, failed)
		Harness.expect(not failedResult.ok)
		Harness.equal(ownedCount(env, 707), before)
		local afterFailure = env.read(707)
		Harness.equal(
			afterFailure.contracts.instancesById[accepted.value.contract.id].status,
			"COMPLETED"
		)
		Harness.equal(afterFailure.contracts.redemptionsById[accepted.value.contract.id], nil)

		local retried = env.contractService.ClaimReward(707, failed)
		Harness.expect(retried.ok)
		Harness.equal(ownedCount(env, 707), before + 1)
		Harness.expect(Fixtures.Schema.validate(env.read(707), 707, CritterCatalog.allById()).ok)
	end)

	Harness.test("missing awarded Critter reports an integrity error", function()
		local env = setup(708)
		local result = acceptCompleteClaim(env, 708, 1)
		local realProfileService = env.profileService
		local critterId = result.claimed.critter.id
		local tampered = {
			ReadProfile = function(userId)
				local profile = realProfileService.ReadProfile(userId)
				if not profile.ok then
					return profile
				end
				local value = Harness.clone(profile.value)
				value.ownedCritters[critterId] = nil
				return { ok = true, value = value }
			end,
			UpdateProfile = realProfileService.UpdateProfile,
		}
		local service = env.newContractService(tampered)
		local retried = ContractFixtures.claim(
			env,
			708,
			result.accepted.id,
			{ commandId = result.claimRequest.commandId },
			service
		)
		Harness.expect(Harness.hasError(retried, "REWARD_INTEGRITY_ERROR"))
	end)

	Harness.test("reward command IDs cannot be reused for another entitlement", function()
		local env = setup(709)
		local first = acceptCompleteClaim(env, 709, 1)
		local before = ownedCount(env, 709)

		local secondAccepted = ContractFixtures.accept(env, 709)
		Harness.expect(secondAccepted.ok)
		env.advance(1)
		Harness.expect(
			env.contractService.RecordBattleCompletion(
				ContractFixtures.completeRequest(env, 709, "training:709:2")
			).ok
		)
		env.advance(1)
		local conflict = ContractFixtures.claimRequest(env, 709, secondAccepted.value.contract.id, {
			commandId = first.claimRequest.commandId,
			expectedRevision = env.read(709).revision,
		})
		Harness.expect(
			Harness.hasError(env.contractService.ClaimReward(709, conflict), "COMMAND_ID_CONFLICT")
		)
		Harness.equal(ownedCount(env, 709), before)
		Harness.equal(
			env.read(709).contracts.instancesById[secondAccepted.value.contract.id].status,
			"COMPLETED"
		)
	end)

	Harness.test("pruned contract history retains lifetime reward idempotency", function()
		local env = setup(710, { maxInstances = 2, maxRedemptions = 10 })
		local first = acceptCompleteClaim(env, 710, 1)
		env.advance(1)
		local second = acceptCompleteClaim(env, 710, 2)
		env.advance(1)
		local thirdAccepted = ContractFixtures.accept(env, 710, {
			commandId = "accept.third",
		})
		Harness.expect(thirdAccepted.ok)

		local profile = env.read(710)
		Harness.equal(profile.contracts.instancesById[first.accepted.id], nil)
		Harness.equal(
			profile.contracts.entitlementsById[first.claimed.redemption.entitlementId],
			nil
		)
		local redemption = profile.contracts.redemptionsById[first.accepted.id]
		Harness.expect(redemption ~= nil)
		Harness.equal(redemption.awardedCritterId, first.claimed.critter.id)
		Harness.expect(Fixtures.Schema.validate(profile, 710, CritterCatalog.allById()).ok)

		local before = ownedCount(env, 710)
		local retried = env.contractService.ClaimReward(710, first.claimRequest)
		Harness.expect(retried.ok)
		Harness.expect(retried.value.duplicate == true)
		Harness.equal(retried.value.critter.id, first.claimed.critter.id)
		Harness.equal(retried.value.contract, nil)
		Harness.equal(ownedCount(env, 710), before)

		local newCommand = ContractFixtures.claimRequest(env, 710, first.accepted.id, {
			commandId = "claim.pruned.new",
		})
		local alias = env.contractService.ClaimReward(710, newCommand)
		Harness.expect(alias.ok)
		Harness.equal(alias.value.critter.id, first.claimed.critter.id)
		Harness.equal(ownedCount(env, 710), before)
		Harness.expect(second.claimed ~= nil)
	end)

	Harness.test("redemption capacity stops new contracts without pruning rewards", function()
		local env = setup(711, { maxInstances = 8, maxRedemptions = 1 })
		local first = acceptCompleteClaim(env, 711, 1)
		local before = ownedCount(env, 711)
		local blocked = ContractFixtures.accept(env, 711)
		Harness.expect(Harness.hasError(blocked, "CONTRACT_CAPACITY_REACHED"))
		local profile = env.read(711)
		Harness.equal(#profile.contracts.instanceOrder, 1)
		Harness.equal(#profile.contracts.redemptionOrder, 1)
		local retried = env.contractService.ClaimReward(711, first.claimRequest)
		Harness.expect(retried.ok)
		Harness.equal(retried.value.critter.id, first.claimed.critter.id)
		Harness.equal(ownedCount(env, 711), before)
	end)

	Harness.test("battle completion is only acknowledged after the profile write", function()
		local env = setup(712)
		local failWrites = false
		local flaky = {
			ReadProfile = env.profileService.ReadProfile,
			UpdateProfile = function(userId, mutator)
				if failWrites then
					return {
						ok = false,
						errors = {
							{ code = "DATASTORE_ERROR", message = "simulated save failure" },
						},
					}
				end
				return env.profileService.UpdateProfile(userId, mutator)
			end,
		}
		local service = env.newContractService(flaky)
		local accepted = ContractFixtures.accept(env, 712, {
			commandId = "accept.flaky",
		}, service)
		Harness.expect(accepted.ok)
		env.advance(2)

		failWrites = true
		local evidence = ContractFixtures.complete(env, 712, "training:712:1", nil, service)
		Harness.expect(Harness.hasError(evidence, "DATASTORE_ERROR"))
		Harness.equal(
			env.read(712).contracts.instancesById[accepted.value.contract.id].status,
			"ACTIVE"
		)

		failWrites = false
		local retried = ContractFixtures.complete(env, 712, "training:712:1", nil, service)
		Harness.expect(retried.ok)
		Harness.expect(retried.value.ignored == false)
		Harness.equal(
			env.read(712).contracts.instancesById[accepted.value.contract.id].status,
			"COMPLETED"
		)
	end)

	Harness.test("BattleService withholds victory until a retry persists completion", function()
		local env = setup(713)
		local failWrites = false
		local flaky = {
			ReadProfile = env.profileService.ReadProfile,
			UpdateProfile = function(userId, mutator)
				if failWrites then
					return {
						ok = false,
						errors = {
							{ code = "DATASTORE_ERROR", message = "simulated save failure" },
						},
					}
				end
				return env.profileService.UpdateProfile(userId, mutator)
			end,
		}
		local service = env.newContractService(flaky)
		local accepted = ContractFixtures.accept(env, 713, {
			commandId = "accept.pending",
		}, service)
		Harness.expect(accepted.ok)
		local battleService = env.createBattleService(service, {
			inputFactory = controlledVictoryInputFactory(1),
		})
		env.advance(5)
		local started = battleService.startBattle(713)
		Harness.expect(started.ok)

		failWrites = true
		local snapshot = started.value.snapshot
		local rounds = 0
		local sequence = 0
		local failedEnvelope = nil
		while snapshot.matchOutcome == nil and rounds < 60 do
			rounds += 1
			local energy = viewerRoundState(snapshot).energy
			local spent = 0
			while spent < energy do
				local payload, definition = chooseAttackCard(snapshot)
				if payload == nil then
					break
				end
				if spent + definition.energyCost > energy then
					break
				end
				sequence += 1
				local queued = send(
					battleService,
					713,
					snapshot,
					`pending.queue.{sequence}`,
					"QUEUE_CARD",
					payload
				)
				Harness.expect(queued.ok)
				snapshot = queued.value.snapshot
				spent += definition.energyCost
			end
			sequence += 1
			local envelope =
				Run5Fixtures.command(snapshot, `pending.commit.{sequence}`, "COMMIT_PLAN", {})
			local committed = battleService.processCommand(713, envelope)
			if not committed.ok then
				Harness.expect(Harness.hasError(committed, "COMPLETION_PENDING"))
				failedEnvelope = envelope
				break
			end
			snapshot = committed.value.snapshot
		end
		Harness.expect(failedEnvelope ~= nil)
		Harness.equal(battleService.hasPendingCompletion(713), true)
		Harness.equal(
			env.read(713).contracts.instancesById[accepted.value.contract.id].status,
			"ACTIVE"
		)

		failWrites = false
		local flushed = battleService.processCommand(713, failedEnvelope)
		Harness.expect(flushed.ok)
		Harness.expect(flushed.value.snapshot.matchOutcome ~= nil)
		Harness.equal(flushed.value.snapshot.matchOutcome.winnerTeamId, "team.player")
		Harness.equal(battleService.hasPendingCompletion(713), false)
		Harness.equal(
			env.read(713).contracts.instancesById[accepted.value.contract.id].status,
			"COMPLETED"
		)
	end)

	Harness.test("acknowledged completion survives release and rejoin", function()
		local env = setup(715)
		local accepted = ContractFixtures.accept(env, 715)
		Harness.expect(accepted.ok)
		env.advance(1)
		local evidence = ContractFixtures.completeRequest(env, 715, "training:715:1")
		local completed = env.contractService.RecordBattleCompletion(evidence)
		Harness.expect(completed.ok)
		Harness.expect(completed.value.ignored == false)
		Harness.expect(env.profileService.ReleaseProfile(715).ok)

		local rejoined = ContractFixtures.new({ store = env.store, jobId = "contract-rejoin" })
		rejoined.load(715)
		local profile = rejoined.read(715)
		Harness.equal(
			profile.contracts.instancesById[accepted.value.contract.id].status,
			"COMPLETED"
		)
		Harness.equal(
			profile.contracts.battleCompletionsById[evidence.battleId].contractInstanceId,
			accepted.value.contract.id
		)
	end)

	Harness.test("durable battle receipts reject duplicates across repeat contracts", function()
		local env = setup(716)
		local first = acceptCompleteClaim(env, 716, 1)
		local second = ContractFixtures.accept(env, 716, { commandId = "accept.second" })
		Harness.expect(second.ok)
		env.advance(1)

		local duplicate = env.contractService.RecordBattleCompletion(
			ContractFixtures.completeRequest(env, 716, "training:716:1")
		)
		Harness.expect(duplicate.ok)
		Harness.equal(duplicate.value.reason, "DUPLICATE_BATTLE")
		Harness.equal(
			env.read(716).contracts.instancesById[second.value.contract.id].status,
			"ACTIVE"
		)
		Harness.expect(first.claimed ~= nil)
	end)

	Harness.test("concurrent claims reject the second command without duplication", function()
		local env = setup(714)
		local accepted = ContractFixtures.accept(env, 714)
		Harness.expect(accepted.ok)
		env.advance(2)
		Harness.expect(
			env.contractService.RecordBattleCompletion(
				ContractFixtures.completeRequest(env, 714, "training:714:1")
			).ok
		)
		env.advance(2)
		local before = ownedCount(env, 714)
		env.store.yieldOnUpdate(true, coroutine.yield)
		local results = {}
		local workers = {}
		for index, commandId in { "claim.concurrent.1", "claim.concurrent.2" } do
			workers[index] = coroutine.create(function()
				local request =
					ContractFixtures.claimRequest(env, 714, accepted.value.contract.id, {
						commandId = commandId,
					})
				results[index] = env.contractService.ClaimReward(714, request)
			end)
		end
		Harness.expect(coroutine.resume(workers[1]))
		Harness.expect(coroutine.resume(workers[2]))
		for _ = 1, 10 do
			if coroutine.status(workers[1]) ~= "dead" then
				coroutine.resume(workers[1])
			end
			if coroutine.status(workers[2]) ~= "dead" then
				coroutine.resume(workers[2])
			end
		end
		env.store.yieldOnUpdate(false, nil)
		Harness.equal(coroutine.status(workers[1]), "dead")
		Harness.equal(coroutine.status(workers[2]), "dead")
		local successes = 0
		local conflicts = 0
		for _, result in results do
			if result.ok then
				successes += 1
			elseif Harness.hasError(result, "COMMAND_IN_PROGRESS") then
				conflicts += 1
			end
		end
		Harness.equal(successes, 1)
		Harness.equal(conflicts, 1)
		Harness.equal(ownedCount(env, 714), before + 1)
	end)

	Harness.test("schema 5 profiles migrate to v7 with durable completion receipts", function()
		local migrated = ProfileMigrations.migrate(
			{ schemaVersion = 5, ownedCritters = {} },
			7,
			ProfileMigrations.DefaultHooks
		)
		Harness.expect(migrated.ok)
		Harness.equal(migrated.value.schemaVersion, 7)
		Harness.equal(migrated.value.contracts.schemaVersion, 2)
		Harness.equal(next(migrated.value.contracts.instancesById), nil)
		Harness.equal(next(migrated.value.contracts.entitlementsById), nil)
		Harness.equal(next(migrated.value.contracts.redemptionsById), nil)
		Harness.equal(next(migrated.value.contracts.battleCompletionsById), nil)
	end)

	Harness.test("schema 6 migration preserves existing completion evidence", function()
		local env = setup(717)
		local accepted = ContractFixtures.accept(env, 717)
		Harness.expect(accepted.ok)
		env.advance(1)
		local battleId = "training:717:1"
		Harness.expect(
			env.contractService.RecordBattleCompletion(
				ContractFixtures.completeRequest(env, 717, battleId)
			).ok
		)
		local legacy = Harness.clone(env.read(717))
		legacy.schemaVersion = 6
		legacy.contracts.schemaVersion = 1
		legacy.contracts.battleCompletionsById = nil
		legacy.contracts.battleCompletionOrder = nil

		local migrated = ProfileMigrations.migrate(legacy, 7, ProfileMigrations.DefaultHooks)
		Harness.expect(migrated.ok)
		local receipt = migrated.value.contracts.battleCompletionsById[battleId]
		Harness.equal(receipt.contractInstanceId, accepted.value.contract.id)
		Harness.equal(receipt.ownerUserId, 717)
		Harness.equal(#migrated.value.contracts.battleCompletionOrder, 1)
	end)

	Harness.test(
		"contract presentation maps statuses progress rewards and reward Critters",
		function()
			local response = ContractPresentation.map({
				revision = 1,
				contracts = {
					{
						id = "contract:one",
						definitionId = "TRAINING_VICTORY",
						definitionVersion = 1,
						displayName = "Training Victory",
						description = "Win a Training Grounds PvE battle.",
						status = "COMPLETED",
						progressCurrent = 1,
						progressRequired = 1,
						canClaim = true,
						canAccept = false,
						rewardPoolId = "COMMON_FOUNDERS",
					},
				},
				availableDefinitions = {
					{
						id = "TRAINING_VICTORY",
						version = 1,
						displayName = "Training Victory",
						description = "Win a Training Grounds PvE battle.",
						requirementKind = "TRAINING_PVE_WINS",
						requirementCount = 1,
						rewardPoolId = "COMMON_FOUNDERS",
						rewardCount = 1,
					},
				},
				capacityAvailable = true,
			})
			Harness.equal(#response.contracts, 1)
			Harness.equal(response.contracts[1].statusText, "Completed - reward ready")
			Harness.equal(response.contracts[1].progressText, "Progress: 1/1")
			Harness.expect(response.contracts[1].canClaim)
			Harness.equal(#response.availableDefinitions, 1)
			Harness.equal(response.availableDefinitions[1].statusText, "Available")
			Harness.expect(response.availableDefinitions[1].canAccept)

			local reward = ContractPresentation.mapReward({
				critter = (function()
					local critter = Harness.clone(DomainFixtures.Instances.Stone)
					critter.class = "Stone"
					return critter
				end)(),
				redemption = { critterId = "owned.stone.1", class = "Stone" },
				duplicate = false,
			})
			Harness.expect(reward ~= nil)
			Harness.equal(reward.critter.id, "owned.stone.1")
			Harness.equal(reward.critter.class, "Stone")
			Harness.equal(reward.duplicate, false)
		end
	)
end
