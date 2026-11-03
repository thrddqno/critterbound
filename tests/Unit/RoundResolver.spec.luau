--!strict

return function(Harness)
	local Deck = require("../../src/shared/Battle/Deck")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
	local RoundResolver = require("../../src/shared/Battle/RoundResolver")
	local Fixtures = require("../Fixtures/Run4BFixtures")

	local function definitions(extra)
		local result = Fixtures.clone(Fixtures.CardDefinitionsById)
		for _, value in extra or {} do
			result[value.id] = value
		end
		return result
	end

	local function resolve(state, extra)
		return RoundResolver.resolveRound(state, {
			cardDefinitionsById = definitions(extra),
			deck = Deck,
			economy = RoundEconomy,
			shuffle = DeterministicRng.shuffle,
			drawPerRound = 3,
		})
	end

	local function findEvent(events, kind, predicate)
		for _, event in events do
			if event.kind == kind and (predicate == nil or predicate(event)) then
				return event
			end
		end
		return nil
	end

	local function cardPlayedIds(events)
		local result = {}
		for _, event in events do
			if event.kind == "CARD_PLAYED" then
				table.insert(result, event.payload.cardInstanceId)
			end
		end
		return result
	end

	local function canceledReasons(events)
		local result = {}
		for _, event in events do
			if event.kind == "ACTION_CANCELED" then
				result[event.payload.cardInstanceId] = event.payload.reason
			end
		end
		return result
	end

	local function activeCardIds(teamState)
		local result = {}
		for _, zone in
			{
				teamState.drawPileCardInstanceIds,
				teamState.handCardInstanceIds,
				teamState.discardCardInstanceIds,
			}
		do
			for _, cardId in zone do
				result[cardId] = true
			end
		end
		for _, queued in teamState.queuedCards do
			result[queued.cardInstanceId] = true
		end
		return result
	end

	Harness.test("higher Speed acts first and defeated Critters lose pending actions", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t2:s1").currentHealth = 10
		Fixtures.makeCard(
			state,
			"card.feral.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.makeCard(
			state,
			"card.tide.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t2:s1"
		)
		Fixtures.makeCard(
			state,
			"card.stone.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "card.feral.1", "combatant:t1:s2", { "combatant:t2:s1" })
		Fixtures.queue(state, "team.2", "card.tide.1", "combatant:t2:s1", { "combatant:t1:s1" })
		Fixtures.queue(state, "team.1", "card.stone.1", "combatant:t1:s1", { "combatant:t2:s2" })

		local result = resolve(state)
		Harness.expect(result.ok, "resolution should succeed")
		local events = result.value.events
		local initiative = findEvent(events, "INITIATIVE_DETERMINED")
		Harness.deepEqual(initiative.payload.initiativeCombatantIds, {
			"combatant:t1:s2",
			"combatant:t2:s1",
			"combatant:t1:s1",
		})
		Harness.deepEqual(cardPlayedIds(events), { "card.feral.1", "card.stone.1" })
		Harness.equal(canceledReasons(events)["card.tide.1"], "DEFEATED")
		Harness.equal(
			Fixtures.findCombatant(result.value.state, "combatant:t2:s1").currentHealth,
			0
		)
		Harness.equal(result.value.state.phase, "PLANNING")
	end)

	Harness.test("defeat retires source cards from every active zone before draw", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t2:s1").currentHealth = 10
		Fixtures.makeCard(state, "attacker", Fixtures.CardDefinitions.Attack.id, "combatant:t1:s2")
		Fixtures.queue(state, "team.1", "attacker", "combatant:t1:s2", {})

		local retiredIds = { "dead.draw", "dead.hand", "dead.discard", "dead.queued" }
		for _, cardId in retiredIds do
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Attack.id, "combatant:t2:s1")
		end
		local enemyState = Fixtures.findTeamState(state, "team.2")
		enemyState.drawPileCardInstanceIds = { "survivor.draw", "dead.draw" }
		enemyState.handCardInstanceIds = { "dead.hand", "survivor.hand", "dead.queued" }
		enemyState.discardCardInstanceIds = { "survivor.discard", "dead.discard" }
		Fixtures.queue(state, "team.2", "dead.queued", "combatant:t2:s1", {})

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.equal(canceledReasons(result.value.events)["dead.queued"], "DEFEATED")
		local resolvedEnemyState = Fixtures.findTeamState(result.value.state, "team.2")
		local active = activeCardIds(resolvedEnemyState)
		for _, cardId in retiredIds do
			Harness.expect(not active[cardId])
		end
		Harness.expect(active["survivor.draw"])
		Harness.expect(active["survivor.hand"])
		Harness.expect(active["survivor.discard"])
		Harness.equal(
			#resolvedEnemyState.drawPileCardInstanceIds
				+ #resolvedEnemyState.handCardInstanceIds
				+ #resolvedEnemyState.discardCardInstanceIds,
			3
		)
		Harness.expect(Fixtures.indexById(result.value.state.cardInstances)["dead.draw"] ~= nil)
	end)

	Harness.test("poison defeat retires cards before next-round draw", function()
		local state = Fixtures.createState()
		local target = Fixtures.findCombatant(state, "combatant:t2:s1")
		target.currentHealth = 5
		target.statusEffects = {
			{
				id = "poison.retire",
				statusId = "POISON",
				sourceCombatantId = "combatant:t1:s3",
				targetCombatantId = target.id,
				magnitude = 5,
				duration = 1,
				stackCount = 1,
				appliedRound = 1,
				expiresAtRound = 1,
			},
		}
		Fixtures.makeCard(
			state,
			"poison.dead.card",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t2:s1"
		)
		Fixtures.findTeamState(state, "team.2").drawPileCardInstanceIds = { "poison.dead.card" }

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.expect(
			not activeCardIds(Fixtures.findTeamState(result.value.state, "team.2"))["poison.dead.card"]
		)
	end)

	Harness.test("multiple queued cards execute consecutively in selected order", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"card.feral.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.makeCard(
			state,
			"card.feral.2",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "card.feral.1", "combatant:t1:s2", { "combatant:t2:s1" })
		Fixtures.queue(state, "team.1", "card.feral.2", "combatant:t1:s2", { "combatant:t2:s2" })

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.deepEqual(cardPlayedIds(result.value.events), { "card.feral.1", "card.feral.2" })
		local damageTargets = {}
		for _, event in result.value.events do
			if event.kind == "DAMAGE_APPLIED" then
				table.insert(damageTargets, event.payload.targetCombatantId)
			end
		end
		Harness.deepEqual(damageTargets, { "combatant:t2:s1", "combatant:t2:s1" })
	end)

	Harness.test("Speed changes affect next round initiative, not the current queue", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"card.speed.1",
			Fixtures.CardDefinitions.SpeedUp.id,
			"combatant:t1:s1"
		)
		Fixtures.makeCard(
			state,
			"card.feral.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "card.speed.1", "combatant:t1:s1", {})
		Fixtures.queue(state, "team.1", "card.feral.1", "combatant:t1:s2", { "combatant:t2:s1" })

		local first = resolve(state)
		Harness.expect(first.ok)
		Harness.deepEqual(
			findEvent(first.value.events, "INITIATIVE_DETERMINED").payload.initiativeCombatantIds,
			{ "combatant:t1:s2", "combatant:t1:s1" }
		)
		local stone = Fixtures.findCombatant(first.value.state, "combatant:t1:s1")
		Harness.equal(stone.statusEffects[1].statusId, "SPEED_UP")
		Harness.equal(stone.statusEffects[1].stackCount, 1)

		local second = first.value.state
		Fixtures.makeCard(
			second,
			"card.feral.2",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.makeCard(
			second,
			"card.stone.2",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(second, "team.1", "card.feral.2", "combatant:t1:s2", { "combatant:t2:s1" })
		Fixtures.queue(second, "team.1", "card.stone.2", "combatant:t1:s1", { "combatant:t2:s2" })
		Fixtures.commit(second)

		local resolved = resolve(second)
		Harness.expect(resolved.ok)
		Harness.deepEqual(
			findEvent(resolved.value.events, "INITIATIVE_DETERMINED").payload.initiativeCombatantIds,
			{ "combatant:t1:s1", "combatant:t1:s2" }
		)
	end)

	Harness.test("earlier Speed effects change later automatic ENEMY targeting", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"card.speed.first",
			Fixtures.CardDefinitions.SpeedUp.id,
			"combatant:t2:s1"
		)
		Fixtures.queue(state, "team.2", "card.speed.first", "combatant:t2:s1", {})
		Fixtures.makeCard(
			state,
			"card.attack.second",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "card.attack.second", "combatant:t1:s1", {})

		local result = resolve(state)
		Harness.expect(result.ok)
		local damage = findEvent(result.value.events, "DAMAGE_APPLIED")
		Harness.equal(damage.payload.targetCombatantId, "combatant:t2:s3")
	end)

	Harness.test("last enemy defeat completes the match and cancels remaining actions", function()
		local state = Fixtures.createState()
		for _, combatantId in { "combatant:t2:s1", "combatant:t2:s2", "combatant:t2:s3" } do
			Fixtures.findCombatant(state, combatantId).currentHealth = 10
		end
		for index, targetId in { "combatant:t2:s1", "combatant:t2:s2", "combatant:t2:s3" } do
			local cardId = `card.feral.{index}`
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Attack.id, "combatant:t1:s2")
			Fixtures.queue(state, "team.1", cardId, "combatant:t1:s2", { targetId })
		end
		Fixtures.makeCard(
			state,
			"card.tide.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t2:s1"
		)
		Fixtures.queue(state, "team.2", "card.tide.1", "combatant:t2:s1", { "combatant:t1:s1" })
		Fixtures.makeCard(
			state,
			"card.stone.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "card.stone.1", "combatant:t1:s1", { "combatant:t2:s2" })

		local result = resolve(state)
		Harness.expect(result.ok)
		local outcome = result.value.matchOutcome
		Harness.expect(outcome ~= nil)
		Harness.equal(outcome.isDraw, false)
		Harness.equal(outcome.winnerTeamId, "team.1")
		Harness.equal(outcome.reason, "TEAM_DEFEATED")
		Harness.equal(result.value.state.phase, "COMPLETED")
		Harness.deepEqual(cardPlayedIds(result.value.events), {
			"card.feral.1",
			"card.feral.2",
			"card.feral.3",
		})
		local reasons = canceledReasons(result.value.events)
		Harness.equal(reasons["card.tide.1"], "MATCH_COMPLETED")
		Harness.equal(reasons["card.stone.1"], "MATCH_COMPLETED")
		Harness.equal(findEvent(result.value.events, "ROUND_COMPLETED"), nil)
	end)

	Harness.test("terminal resolution retires every defeated Critter card", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t2:s1").currentHealth = 10
		Fixtures.findCombatant(state, "combatant:t2:s2").currentHealth = 0
		Fixtures.findCombatant(state, "combatant:t2:s3").currentHealth = 0
		Fixtures.makeCard(
			state,
			"terminal.attack",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "terminal.attack", "combatant:t1:s2", {})

		local retiredBySource = {
			{ "terminal.draw", "combatant:t2:s1" },
			{ "terminal.hand", "combatant:t2:s2" },
			{ "terminal.discard", "combatant:t2:s3" },
		}
		for _, value in retiredBySource do
			Fixtures.makeCard(state, value[1], Fixtures.CardDefinitions.Attack.id, value[2])
		end
		local enemyState = Fixtures.findTeamState(state, "team.2")
		enemyState.drawPileCardInstanceIds = { "terminal.draw" }
		enemyState.handCardInstanceIds = { "terminal.hand" }
		enemyState.discardCardInstanceIds = { "terminal.discard" }
		Fixtures.queue(state, "team.2", "terminal.draw", "combatant:t2:s1", {})

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.equal(result.value.state.phase, "COMPLETED")
		local active = activeCardIds(Fixtures.findTeamState(result.value.state, "team.2"))
		for _, value in retiredBySource do
			Harness.expect(not active[value[1]])
		end
		Harness.equal(canceledReasons(result.value.events)["terminal.draw"], "MATCH_COMPLETED")
	end)

	Harness.test("simultaneous poison defeat produces a draw", function()
		local state = Fixtures.createState()
		for _, combatant in state.combatants do
			combatant.currentHealth = 0
		end
		local function poison(combatantId)
			local combatant = Fixtures.findCombatant(state, combatantId)
			combatant.currentHealth = 5
			combatant.statusEffects = {
				{
					id = `status.{combatantId}.1`,
					statusId = "POISON",
					sourceCombatantId = "source",
					targetCombatantId = combatantId,
					magnitude = 5,
					duration = 1,
					stackCount = 1,
					appliedRound = 1,
					expiresAtRound = 1,
				},
			}
		end
		poison("combatant:t1:s1")
		poison("combatant:t2:s1")
		local first = Fixtures.findCombatant(state, "combatant:t1:s1")
		first.shields = {
			{
				id = "shield.terminal",
				sourceCombatantId = "source",
				amount = 10,
				expiresAtRound = 1,
			},
		}

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.expect(result.value.matchOutcome ~= nil)
		Harness.equal(result.value.matchOutcome.isDraw, true)
		Harness.equal(result.value.matchOutcome.reason, "MUTUAL_DESTRUCTION")
		Harness.equal(result.value.state.phase, "COMPLETED")
		local defeats = 0
		for _, event in result.value.events do
			if event.kind == "CRITTER_DEFEATED" then
				defeats += 1
			end
		end
		Harness.equal(defeats, 2)
		Harness.equal(findEvent(result.value.events, "STATUS_EXPIRED"), nil)
		local resolvedFirst = Fixtures.findCombatant(result.value.state, "combatant:t1:s1")
		Harness.equal(#resolvedFirst.statusEffects, 1)
		Harness.equal(#resolvedFirst.shields, 1)
	end)

	Harness.test("identical input produces identical state and events", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"card.feral.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "card.feral.1", "combatant:t1:s2", { "combatant:t2:s1" })
		Fixtures.makeCard(
			state,
			"card.gale.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t2:s2"
		)
		Fixtures.queue(state, "team.2", "card.gale.1", "combatant:t2:s2", { "combatant:t1:s1" })
		local before = Harness.clone(state)

		local first = resolve(state)
		local second = resolve(state)
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first.value.state, second.value.state)
		Harness.deepEqual(first.value.events, second.value.events)
		Harness.deepEqual(state, before)
	end)

	Harness.test("invalid phase, duplicate round, and uncommitted plans are rejected", function()
		local planning = Fixtures.createState({ phase = "PLANNING" })
		Harness.expect(Harness.hasError(resolve(planning), "INVALID_PHASE"))

		local duplicate = Fixtures.createState()
		duplicate.lastResolvedRound = 1
		Harness.expect(Harness.hasError(resolve(duplicate), "ROUND_ALREADY_RESOLVED"))

		local uncommitted = Fixtures.createState()
		Fixtures.findTeamState(uncommitted, "team.2").committed = false
		Harness.expect(Harness.hasError(resolve(uncommitted), "NOT_COMMITTED"))
	end)

	Harness.test("skipped targeting still consumes the card and sends it to discard", function()
		local anyDefinition = {
			schemaVersion = 1,
			id = "card.run4b.any",
			displayName = "Any",
			class = "Feral",
			abilityId = "ability.any",
			energyCost = 1,
			targetingRule = "ANY",
			effects = { { kind = "DAMAGE", amount = 5 } },
		}
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t2:s3").currentHealth = 0
		Fixtures.makeCard(state, "card.any.1", anyDefinition.id, "combatant:t1:s2")
		Fixtures.addHand(state, "team.1", "card.any.1")
		Fixtures.findTeamState(state, "team.1").drawPileCardInstanceIds =
			{ "card.draw.1", "card.draw.2", "card.draw.3" }
		Fixtures.queue(state, "team.1", "card.any.1", "combatant:t1:s2", { "combatant:t2:s3" })

		local result = resolve(state, { Any = anyDefinition })
		Harness.expect(result.ok)
		local targetEvent = findEvent(result.value.events, "TARGET_SELECTED")
		Harness.equal(targetEvent.payload.skipped, true)
		Harness.equal(findEvent(result.value.events, "DAMAGE_APPLIED"), nil)
		local teamState = Fixtures.findTeamState(result.value.state, "team.1")
		Harness.expect(table.find(teamState.discardCardInstanceIds, "card.any.1") ~= nil)
	end)

	Harness.test("a fast shield protects a target from a slower attack", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t2:s2").stats.speed = 5
		Fixtures.findCombatant(state, "combatant:t1:s1").stats.speed = 4
		Fixtures.makeCard(
			state,
			"card.shield.1",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t2:s2"
		)
		Fixtures.queue(state, "team.2", "card.shield.1", "combatant:t2:s2", {})
		Fixtures.makeCard(
			state,
			"card.stone.1",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "card.stone.1", "combatant:t1:s1", { "combatant:t2:s2" })

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.deepEqual(
			findEvent(result.value.events, "INITIATIVE_DETERMINED").payload.initiativeCombatantIds,
			{ "combatant:t2:s2", "combatant:t1:s1" }
		)
		Harness.equal(findEvent(result.value.events, "SHIELD_GRANTED").payload.amount, 20)
		Harness.equal(findEvent(result.value.events, "SHIELD_ABSORBED").payload.absorbed, 20)
		local damage = findEvent(result.value.events, "DAMAGE_APPLIED")
		Harness.equal(damage.payload.hpDamage, 4)
		Harness.equal(
			Fixtures.findCombatant(result.value.state, "combatant:t2:s2").currentHealth,
			96
		)
		Harness.equal(#Fixtures.findCombatant(result.value.state, "combatant:t2:s2").shields, 0)
	end)

	Harness.test("healing clamps to maximum HP and reports restored amount", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t1:s1").currentHealth = 90
		Fixtures.makeCard(state, "card.heal.1", Fixtures.CardDefinitions.Heal.id, "combatant:t1:s3")
		Fixtures.queue(state, "team.1", "card.heal.1", "combatant:t1:s3", { "combatant:t1:s1" })

		local result = resolve(state)
		Harness.expect(result.ok)
		local heal = findEvent(result.value.events, "HEAL_APPLIED")
		Harness.equal(heal.payload.restored, 10)
		Harness.equal(
			Fixtures.findCombatant(result.value.state, "combatant:t1:s1").currentHealth,
			100
		)
	end)
end
