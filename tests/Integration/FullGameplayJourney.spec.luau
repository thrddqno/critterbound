--!strict

return function(Harness)
	local ProfileFixtures = require("../Fixtures/ProfileFixtures")
	local ContractFixtures = require("../Fixtures/ContractFixtures")
	local Run5Fixtures = require("../Fixtures/Run5Fixtures")
	local TrainingBattleInputAdapter =
		require("../../src/server/Services/TrainingBattleInputAdapter")
	local BreedingService = require("../../src/server/Services/BreedingService")
	local EggService = require("../../src/server/Services/EggService")
	local ContractProtocol = require("../../src/shared/Network/ContractProtocol")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local BreedingValidator = require("../../src/server/Services/BreedingValidator")

	local function count(map): number
		local total = 0
		for _ in map do
			total += 1
		end
		return total
	end

	local function viewerRoundState(snapshot)
		for _, state in snapshot.battleState.teamRoundStates do
			if state.teamId == snapshot.viewerTeamId then
				return state
			end
		end
		error("Missing viewer round state")
	end

	local function legalAttack(snapshot)
		local roundState = viewerRoundState(snapshot)
		local queued = {}
		for _, value in snapshot.visibleQueuedCards do
			queued[value.cardInstanceId] = true
		end
		for _, cardId in roundState.handCardInstanceIds do
			if not queued[cardId] then
				local instance = snapshot.cardInstancesById[cardId]
				local definition = snapshot.cardDefinitionsById[instance.definitionId]
				if definition.energyCost <= roundState.energy then
					local source = nil
					for _, combatant in snapshot.battleState.combatants do
						if combatant.critterInstanceId == instance.sourceCritterInstanceId then
							source = combatant
							break
						end
					end
					if source ~= nil and source.currentHealth > 0 then
						local targets = {}
						if definition.targetingRule == "ANY" then
							for _, combatant in snapshot.battleState.combatants do
								if
									combatant.teamId ~= source.teamId
									and combatant.currentHealth > 0
								then
									targets = { combatant.id }
									break
								end
							end
						elseif definition.targetingRule == "ALLY" then
							for _, combatant in snapshot.battleState.combatants do
								if
									combatant.teamId == source.teamId
									and combatant.id ~= source.id
									and combatant.currentHealth > 0
								then
									targets = { combatant.id }
									break
								end
							end
						end
						if definition.targetingRule ~= "ANY" or #targets > 0 then
							return {
								cardInstanceId = cardId,
								sourceCombatantId = source.id,
								targetCombatantIds = targets,
							},
								definition
						end
					end
				end
			end
		end
		return nil
	end

	local function send(service, userId: number, snapshot, commandId: string, kind: string, payload)
		return service.processCommand(
			userId,
			Run5Fixtures.command(snapshot, commandId, kind, payload)
		)
	end

	local function winBattle(service, userId: number, snapshot, prefix: string)
		local sequence = 0
		local rounds = 0
		while snapshot.matchOutcome == nil and rounds < 60 do
			rounds += 1
			local spent = 0
			local energy = viewerRoundState(snapshot).energy
			while spent < energy do
				local payload, definition = legalAttack(snapshot)
				if payload == nil or spent + definition.energyCost > energy then
					break
				end
				sequence += 1
				local queued = send(
					service,
					userId,
					snapshot,
					`{prefix}.queue.{sequence}`,
					"QUEUE_CARD",
					payload
				)
				Harness.expect(queued.ok)
				snapshot = queued.value.snapshot
				spent += definition.energyCost
			end
			sequence += 1
			local committed =
				send(service, userId, snapshot, `{prefix}.commit.{sequence}`, "COMMIT_PLAN", {})
			Harness.expect(committed.ok)
			snapshot = committed.value.snapshot
		end
		Harness.expect(snapshot.matchOutcome ~= nil)
		Harness.equal(snapshot.matchOutcome.winnerTeamId, "team.player")
		return snapshot
	end

	local function newBattle(env)
		local base = Run5Fixtures.dependencies()
		local adapter = TrainingBattleInputAdapter.new({
			profileService = env.profileService,
			content = base.content,
		})
		local controlledAdapter = {
			createInput = function(userId: number, generation: number)
				local produced = adapter.createInput(userId, generation)
				if not produced.ok then
					return produced
				end
				for _, team in produced.value.teams do
					if team.ownerUserId == userId then
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
				return produced
			end,
		}
		return env.createBattleService(env.contractService, {
			inputFactory = controlledAdapter,
		})
	end

	Harness.test("full gameplay journey persists from starters through offspring battle", function()
		local userId = 9001
		local env = ContractFixtures.new()
		env.load(userId)
		local initial = env.read(userId)
		Harness.equal(count(initial.ownedCritters), 3)
		Harness.equal(#initial.selectedTeam, 3)
		for _, critter in initial.ownedCritters do
			Harness.expect(not critter.breeding.breedable)
		end

		local battleService = newBattle(env)
		local acceptedOne = ContractFixtures.accept(env, userId, {
			commandId = "journey.accept.1",
		})
		Harness.expect(acceptedOne.ok)
		env.advance(1)
		local startedOne = battleService.startBattle(userId)
		Harness.expect(startedOne.ok)
		local firstRound = viewerRoundState(startedOne.value.snapshot)
		Harness.equal(#firstRound.handCardInstanceIds, 6)
		Harness.equal(firstRound.handCount + firstRound.drawPileCount + firstRound.discardCount, 24)
		winBattle(battleService, userId, startedOne.value.snapshot, "journey.first")
		local completedOne = env.read(userId).contracts.instancesById[acceptedOne.value.contract.id]
		Harness.equal(completedOne.status, "COMPLETED")

		local claimOne = env.contractService.ClaimReward(userId, {
			protocolVersion = ContractProtocol.Version,
			kind = ContractProtocol.RequestKinds.CLAIM_CONTRACT_REWARD,
			commandId = "journey.claim.1",
			expectedRevision = env.read(userId).revision,
			contractId = acceptedOne.value.contract.id,
		})
		Harness.expect(claimOne.ok)
		local rewardOneId = claimOne.value.critter.id
		Harness.expect(env.read(userId).ownedCritters[rewardOneId] ~= nil)

		local inventory = ProfileFixtures.newInventoryService(env.profileService)
		local equipment = ProfileFixtures.newEquipmentService(env.profileService)
		local grantedItem = inventory.AddItem(userId, {
			definitionId = "equipment.training_charm",
			quantity = 1,
			operationId = "journey.item",
			source = "INTEGRATION_TEST",
		})
		Harness.expect(grantedItem.ok)
		Harness.expect(
			equipment.EquipItem(userId, rewardOneId, grantedItem.value.instanceIds[1]).ok
		)

		local acceptedTwo = ContractFixtures.accept(env, userId, {
			commandId = "journey.accept.2",
		})
		Harness.expect(acceptedTwo.ok)
		env.advance(1)
		local restarted = battleService.restartBattle(userId, "journey.restart.2")
		Harness.expect(restarted.ok)
		winBattle(battleService, userId, restarted.value.snapshot, "journey.second")
		local claimTwo = env.contractService.ClaimReward(userId, {
			protocolVersion = ContractProtocol.Version,
			kind = ContractProtocol.RequestKinds.CLAIM_CONTRACT_REWARD,
			commandId = "journey.claim.2",
			expectedRevision = env.read(userId).revision,
			contractId = acceptedTwo.value.contract.id,
		})
		Harness.expect(claimTwo.ok)
		local rewardTwoId = claimTwo.value.critter.id
		Harness.expect(rewardOneId ~= rewardTwoId)

		local starterId = initial.selectedTeam[1]
		local teamService = ProfileFixtures.newTeamService(env.profileService)
		Harness.expect(
			teamService.SetSelectedTeam(
				userId,
				{ rewardOneId, initial.selectedTeam[2], initial.selectedTeam[3] },
				env.read(userId).revision
			).ok
		)
		battleService.invalidateBattle(userId)
		local rewardBattle = battleService.startBattle(userId)
		Harness.expect(rewardBattle.ok)
		local rewardPresent = false
		for _, combatant in rewardBattle.value.snapshot.battleState.combatants do
			if combatant.critterInstanceId == rewardOneId then
				rewardPresent = true
			end
		end
		Harness.expect(rewardPresent)

		local generatedId = 0
		local breeding = BreedingService.new({
			protocolVersion = 1,
			profileService = env.profileService,
			validator = BreedingValidator,
			catalog = ProfileFixtures.Catalog,
			genomeValidator = GenomeValidator,
			inheritanceEngine = InheritanceEngine,
			rng = DeterministicRng,
			rngSeed = function()
				return 7654321
			end,
			generateId = function()
				generatedId += 1
				return `journey-{generatedId}`
			end,
			now = function()
				return env.now
			end,
			incubationSeconds = 60,
		})
		local bred = breeding.Breed(
			userId,
			rewardOneId,
			rewardTwoId,
			"journey.breed",
			env.read(userId).revision
		)
		Harness.expect(bred.ok)
		local eggId = bred.value.egg.eggId
		local afterBreed = env.read(userId)
		Harness.equal(count(afterBreed.eggs), 1)
		Harness.equal(afterBreed.ownedCritters[rewardOneId].breeding.successfulBreedCount, 1)

		local eggService = EggService.new({
			protocolVersion = 1,
			profileService = env.profileService,
			catalog = ProfileFixtures.Catalog,
			genomeValidator = GenomeValidator,
			generateId = function()
				generatedId += 1
				return `journey-{generatedId}`
			end,
			now = function()
				return env.now
			end,
		})
		Harness.equal(eggService.GetEggStatus(userId, eggId).value.status, "INCUBATING")
		env.advance(60)
		Harness.equal(eggService.GetEggStatus(userId, eggId).value.status, "READY")
		local hatched =
			eggService.HatchEgg(userId, eggId, "journey.hatch", env.read(userId).revision)
		Harness.expect(hatched.ok)
		local offspringId = hatched.value.offspring.id
		local history = eggService.GetEggs(userId)
		Harness.equal(#history.value.eggs, 1)
		Harness.equal(history.value.eggs[1].status, "HATCHED")
		Harness.equal(history.value.eggs[1].offspringId, offspringId)
		local storedEgg = env.read(userId).eggs[eggId]
		local storedOffspring = env.read(userId).ownedCritters[offspringId]
		Harness.deepEqual(storedOffspring.appearanceGenome, storedEgg.offspringAppearanceGenome)
		Harness.deepEqual(storedOffspring.abilityGenome, storedEgg.offspringAbilityGenome)
		Harness.equal(storedOffspring.breeding.generation, storedEgg.generation)

		Harness.expect(
			teamService.SetSelectedTeam(
				userId,
				{ offspringId, rewardOneId, rewardTwoId },
				env.read(userId).revision
			).ok
		)
		battleService.invalidateBattle(userId)
		local offspringBattle = battleService.startBattle(userId)
		Harness.expect(offspringBattle.ok)
		local offspringPresent = false
		for _, combatant in offspringBattle.value.snapshot.battleState.combatants do
			if combatant.critterInstanceId == offspringId then
				offspringPresent = true
			end
		end
		Harness.expect(offspringPresent)
		Harness.expect(env.profileService.ReleaseProfile(userId).ok)

		local reloaded = ProfileFixtures.newService(
			ProfileFixtures.newRepository(env.store, "journey-rejoin", { now = env.now })
		)
		Harness.expect(reloaded.LoadProfile(userId).ok)
		local persisted = reloaded.ReadProfile(userId).value
		Harness.equal(count(persisted.ownedCritters), 6)
		Harness.equal(persisted.eggs[eggId].status, "HATCHED")
		Harness.equal(persisted.eggs[eggId].offspringId, offspringId)
		Harness.deepEqual(persisted.selectedTeam, { offspringId, rewardOneId, rewardTwoId })
		Harness.equal(
			persisted.ownedCritters[rewardOneId].equipmentIds[1],
			grantedItem.value.instanceIds[1]
		)
		Harness.expect(persisted.ownedCritters[starterId] ~= nil)
		Harness.equal(
			persisted.contracts.redemptionsById[acceptedOne.value.contract.id].awardedCritterId,
			rewardOneId
		)
		Harness.equal(
			persisted.contracts.redemptionsById[acceptedTwo.value.contract.id].awardedCritterId,
			rewardTwoId
		)
	end)
end
