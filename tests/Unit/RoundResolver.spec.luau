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

	local function resolve(state, extra, overrides)
		local dependencies = {
			cardDefinitionsById = definitions(extra),
			deck = Deck,
			economy = RoundEconomy,
			shuffle = DeterministicRng.shuffle,
			drawPerRound = 3,
		}
		for key, value in overrides or {} do
			dependencies[key] = value
		end
		return RoundResolver.resolveRound(state, dependencies)
	end

	local function findEvent(events, kind, predicate)
		for _, event in events do
			if event.kind == kind and (predicate == nil or predicate(event)) then
				return event
			end
		end
		return nil
	end

	local function eventsOfKind(events, kind)
		local result = {}
		for _, event in events do
			if event.kind == kind then
				table.insert(result, event)
			end
		end
		return result
	end

	local function eventIndex(events, kind): number?
		for index, event in events do
			if event.kind == kind then
				return index
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

	local function comboDamageEvents(cardCount: number, splitLastCard: boolean?)
		local state = Fixtures.createState()
		local target = Fixtures.findCombatant(state, "combatant:t2:s1")
		target.currentHealth = 500
		target.stats.maxHealth = 500
		for index = 1, cardCount do
			local cardId = `card.combo.{index}`
			local sourceId = if splitLastCard and index == cardCount
				then "combatant:t1:s1"
				else "combatant:t1:s2"
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Attack.id, sourceId)
			Fixtures.queue(state, "team.1", cardId, sourceId, { target.id })
		end
		local result = resolve(state)
		Harness.expect(result.ok)
		local events = {}
		for _, event in result.value.events do
			if event.kind == "DAMAGE_APPLIED" then
				table.insert(events, event)
			end
		end
		return events
	end

	Harness.test("two-card queues do not activate Skill combo", function()
		local events = comboDamageEvents(2)
		Harness.equal(#events, 2)
		for _, event in events do
			Harness.equal(event.payload.skillMultiplier, 1.0)
		end
	end)

	Harness.test("three-card queues activate Skill combo for every direct-damage card", function()
		local events = comboDamageEvents(3)
		Harness.equal(#events, 3)
		for _, event in events do
			Harness.equal(event.payload.skillMultiplier, 1.06)
		end
	end)

	Harness.test("four-card queues use same Skill combo without extra threshold bonus", function()
		local events = comboDamageEvents(4)
		Harness.equal(#events, 4)
		for _, event in events do
			Harness.equal(event.payload.skillMultiplier, 1.06)
		end
	end)

	Harness.test("cards from different Critters never combine into a Skill combo", function()
		local events = comboDamageEvents(3, true)
		Harness.equal(#events, 3)
		for _, event in events do
			Harness.equal(event.payload.skillMultiplier, 1.0)
		end
	end)

	Harness.test("cross-class cards count toward their owning Critter's Skill combo", function()
		local state = Fixtures.createState()
		local target = Fixtures.findCombatant(state, "combatant:t2:s1")
		target.currentHealth = 500
		target.stats.maxHealth = 500
		local crossClass = {
			schemaVersion = 1,
			id = "card.combo.cross-class",
			displayName = "Cross Class Combo",
			class = "Stone",
			abilityId = "ability.combo.cross-class",
			energyCost = 1,
			targetingRule = "ENEMY",
			effects = { { kind = "DAMAGE", amount = 30 } },
		}
		for index = 1, 3 do
			local cardId = `card.cross-combo.{index}`
			local definitionId = if index == 3
				then crossClass.id
				else Fixtures.CardDefinitions.Attack.id
			Fixtures.makeCard(state, cardId, definitionId, "combatant:t1:s2")
			Fixtures.queue(state, "team.1", cardId, "combatant:t1:s2", { target.id })
		end

		local result = resolve(state, { crossClass })
		Harness.expect(result.ok)
		local damageCount = 0
		for _, event in result.value.events do
			if event.kind == "DAMAGE_APPLIED" then
				damageCount += 1
				Harness.equal(event.payload.skillMultiplier, 1.06)
			end
		end
		Harness.equal(damageCount, 3)
	end)

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
		Harness.equal(result.value.state.criticalRng.drawCount, 2)
	end)

	Harness.test("area damage rolls independently once per living target", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"card.area.critical",
			Fixtures.CardDefinitions.AllEnemies.id,
			"combatant:t1:s3"
		)
		Fixtures.queue(state, "team.1", "card.area.critical", "combatant:t1:s3", {})
		local fakeRng = {
			Modulus = 101,
			next = function(rngState)
				local drawCount = rngState.drawCount + 1
				return {
					algorithm = rngState.algorithm,
					state = drawCount,
					drawCount = drawCount,
				},
					if drawCount % 2 == 1 then 1 else 100
			end,
		}
		local result = resolve(state, nil, { criticalRng = fakeRng })
		Harness.expect(result.ok)
		local outcomes = {}
		for _, event in result.value.events do
			if event.kind == "DAMAGE_APPLIED" then
				table.insert(outcomes, event.payload.isCritical)
			end
		end
		Harness.deepEqual(outcomes, { true, false, true })
		Harness.equal(result.value.state.criticalRng.drawCount, 3)
	end)

	Harness.test("canceled and skipped cards consume no critical rolls", function()
		local canceled = Fixtures.createState()
		Fixtures.makeCard(canceled, "card.missing", "definition.missing", "combatant:t1:s1")
		Fixtures.queue(canceled, "team.1", "card.missing", "combatant:t1:s1", {})
		local canceledResult = resolve(canceled)
		Harness.expect(canceledResult.ok)
		Harness.equal(canceledResult.value.state.criticalRng.drawCount, 0)
		Harness.equal(
			canceledReasons(canceledResult.value.events)["card.missing"],
			"MISSING_DEFINITION"
		)

		local skipped = Fixtures.createState()
		local anyDamage = {
			schemaVersion = 1,
			id = "card.any.damage",
			displayName = "Any Damage",
			class = "Stone",
			abilityId = "ability.any.damage",
			energyCost = 1,
			targetingRule = "ANY",
			effects = { { kind = "DAMAGE", amount = 10 } },
		}
		Fixtures.makeCard(skipped, "card.skipped", anyDamage.id, "combatant:t1:s1")
		Fixtures.queue(skipped, "team.1", "card.skipped", "combatant:t1:s1", { "missing" })
		local skippedResult = resolve(skipped, { anyDamage })
		Harness.expect(skippedResult.ok)
		Harness.equal(skippedResult.value.state.criticalRng.drawCount, 0)
		local selected = findEvent(skippedResult.value.events, "TARGET_SELECTED")
		Harness.expect(selected.payload.skipped)
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
			Harness.expect(table.find(resolvedEnemyState.removedCardInstanceIds, cardId) ~= nil)
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
		Harness.equal(result.value.state.phase, "FINISHED")
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
		Harness.equal(result.value.state.phase, "FINISHED")
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
		Harness.equal(result.value.state.phase, "FINISHED")
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

	Harness.test("a slow Stone shield prepares before a fast attack", function()
		local state = Fixtures.createState()
		Fixtures.findCombatant(state, "combatant:t1:s1").stats.speed = 1
		Fixtures.findCombatant(state, "combatant:t2:s2").stats.speed = 50
		Fixtures.makeCard(
			state,
			"card.shield.1",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "card.shield.1", "combatant:t1:s1", {})
		Fixtures.makeCard(
			state,
			"card.attack.fast",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t2:s2"
		)
		Fixtures.queue(state, "team.2", "card.attack.fast", "combatant:t2:s2", {})

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.deepEqual(
			findEvent(result.value.events, "INITIATIVE_DETERMINED").payload.initiativeCombatantIds,
			{ "combatant:t2:s2", "combatant:t1:s1" }
		)
		local prepared = findEvent(result.value.events, "SHIELD_PREPARED")
		Harness.equal(prepared.payload.amount, 22)
		Harness.expect(
			eventIndex(result.value.events, "SHIELD_PREPARED")
				< eventIndex(result.value.events, "INITIATIVE_DETERMINED")
		)
		Harness.equal(findEvent(result.value.events, "SHIELD_ABSORBED").payload.absorbed, 22)
		Harness.equal(#eventsOfKind(result.value.events, "SHIELD_PREPARED"), 1)
	end)

	Harness.test("both teams prepare shields before initiative and damage", function()
		local state = Fixtures.createState()
		for _, spec in
			{
				{ "team.1", "shield.team.1", "combatant:t1:s1" },
				{ "team.2", "shield.team.2", "combatant:t2:s2" },
			}
		do
			Fixtures.makeCard(state, spec[2], Fixtures.CardDefinitions.Shield.id, spec[3])
			Fixtures.queue(state, spec[1], spec[2], spec[3], {})
		end
		Fixtures.makeCard(
			state,
			"attack.after.prep",
			Fixtures.CardDefinitions.Attack.id,
			"combatant:t1:s2"
		)
		Fixtures.queue(state, "team.1", "attack.after.prep", "combatant:t1:s2", {})

		local result = resolve(state)
		Harness.expect(result.ok)
		local prepared = eventsOfKind(result.value.events, "SHIELD_PREPARED")
		Harness.equal(#prepared, 2)
		Harness.equal(prepared[1].payload.preparationOrder, 1)
		Harness.equal(prepared[2].payload.preparationOrder, 2)
		local initiativeIndex = eventIndex(result.value.events, "INITIATIVE_DETERMINED")
		local damageIndex = eventIndex(result.value.events, "DAMAGE_APPLIED")
		Harness.expect(prepared[2].sequence < result.value.events[initiativeIndex].sequence)
		Harness.expect(initiativeIndex < damageIndex)
	end)

	Harness.test("multiple prepared shields stack and expire at round end", function()
		local state = Fixtures.createState()
		for index = 1, 2 do
			local cardId = `shield.stack.{index}`
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Shield.id, "combatant:t1:s1")
			Fixtures.queue(state, "team.1", cardId, "combatant:t1:s1", {})
		end
		local result = resolve(state)
		Harness.expect(result.ok)
		local prepared = eventsOfKind(result.value.events, "SHIELD_PREPARED")
		Harness.equal(#prepared, 2)
		Harness.equal(prepared[1].payload.amount, 22)
		Harness.equal(prepared[2].payload.amount, 22)
		Harness.equal(prepared[2].payload.shieldCount, 2)
		local expired = eventsOfKind(result.value.events, "STATUS_EXPIRED")
		Harness.equal(#expired, 2)
		Harness.equal(#Fixtures.findCombatant(result.value.state, "combatant:t1:s1").shields, 0)
		Harness.equal(result.value.state.criticalRng.drawCount, 0)
	end)

	Harness.test("mixed card prepares shield once and heals during normal action", function()
		local mixed = {
			schemaVersion = 1,
			id = "card.mixed.support",
			displayName = "Mixed Support",
			class = "Tide",
			abilityId = "ability.mixed.support",
			energyCost = 1,
			targetingRule = "ALLY",
			effects = {
				{ kind = "HEAL", amount = 45 },
				{ kind = "SHIELD", amount = 15 },
			},
		}
		local state = Fixtures.createState()
		local target = Fixtures.findCombatant(state, "combatant:t2:s2")
		target.currentHealth = 40
		Fixtures.makeCard(state, "mixed.support", mixed.id, "combatant:t2:s1")
		Fixtures.queue(state, "team.2", "mixed.support", "combatant:t2:s1", { target.id })
		Fixtures.findTeamState(state, "team.2").drawPileCardInstanceIds = {
			"mixed.draw.1",
			"mixed.draw.2",
			"mixed.draw.3",
		}

		local result = resolve(state, { mixed })
		Harness.expect(result.ok)
		local prepared = eventsOfKind(result.value.events, "SHIELD_PREPARED")
		Harness.equal(#prepared, 1)
		Harness.equal(prepared[1].payload.amount, 16)
		Harness.expect(
			prepared[1].sequence < findEvent(result.value.events, "INITIATIVE_DETERMINED").sequence
		)
		local heal = findEvent(result.value.events, "HEAL_APPLIED")
		Harness.equal(heal.payload.restored, 45)
		Harness.expect(heal.sequence > findEvent(result.value.events, "CARD_PLAYED").sequence)
		Harness.equal(findEvent(result.value.events, "SHIELD_GRANTED"), nil)
		local teamState = Fixtures.findTeamState(result.value.state, "team.2")
		local copies = 0
		for _, zone in
			{
				teamState.drawPileCardInstanceIds,
				teamState.handCardInstanceIds,
				teamState.discardCardInstanceIds,
				teamState.removedCardInstanceIds,
			}
		do
			for _, cardId in zone do
				if cardId == "mixed.support" then
					copies += 1
				end
			end
		end
		Harness.equal(copies, 1)
		Harness.expect(table.find(teamState.discardCardInstanceIds, "mixed.support") ~= nil)
	end)

	Harness.test(
		"prepared shield remains when its source is defeated and action cancels",
		function()
			local allyShield = {
				schemaVersion = 1,
				id = "card.ally.preparation",
				displayName = "Ally Preparation",
				class = "Stone",
				abilityId = "ability.ally.preparation",
				energyCost = 1,
				targetingRule = "ALLY",
				effects = { { kind = "SHIELD", amount = 20 } },
			}
			local lethal = {
				schemaVersion = 1,
				id = "card.lethal.preparation",
				displayName = "Lethal Preparation",
				class = "Feral",
				abilityId = "ability.lethal.preparation",
				energyCost = 1,
				targetingRule = "ENEMY",
				effects = { { kind = "DAMAGE", amount = 1000 } },
			}
			local state = Fixtures.createState()
			local shieldSource = Fixtures.findCombatant(state, "combatant:t1:s1")
			local shieldTarget = Fixtures.findCombatant(state, "combatant:t1:s3")
			shieldSource.stats.speed = 1
			Fixtures.findCombatant(state, "combatant:t2:s2").stats.speed = 50
			Fixtures.findCombatant(state, "combatant:t2:s3").stats.speed = 40
			Fixtures.makeCard(state, "ally.preparation", allyShield.id, shieldSource.id)
			Fixtures.queue(
				state,
				"team.1",
				"ally.preparation",
				shieldSource.id,
				{ shieldTarget.id }
			)
			Fixtures.makeCard(state, "kill.shield.source", lethal.id, "combatant:t2:s2")
			Fixtures.queue(state, "team.2", "kill.shield.source", "combatant:t2:s2", {})
			Fixtures.makeCard(
				state,
				"attack.shield.target",
				Fixtures.CardDefinitions.Attack.id,
				"combatant:t2:s3"
			)
			Fixtures.queue(state, "team.2", "attack.shield.target", "combatant:t2:s3", {})

			local result = resolve(state, { allyShield, lethal })
			Harness.expect(result.ok)
			local prepared = findEvent(result.value.events, "SHIELD_PREPARED")
			Harness.equal(prepared.payload.targetCombatantId, shieldTarget.id)
			local canceled = findEvent(result.value.events, "ACTION_CANCELED", function(event)
				return event.payload.cardInstanceId == "ally.preparation"
			end)
			Harness.equal(canceled.payload.reason, "DEFEATED")
			local absorbed = findEvent(result.value.events, "SHIELD_ABSORBED", function(event)
				return event.payload.targetCombatantId == shieldTarget.id
			end)
			Harness.equal(absorbed.payload.absorbed, 22)
		end
	)

	Harness.test("repeated resolution cannot reapply prepared shields", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"shield.once",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "shield.once", "combatant:t1:s1", {})
		local first = resolve(state)
		Harness.expect(first.ok)
		Harness.equal(#eventsOfKind(first.value.events, "SHIELD_PREPARED"), 1)
		local repeated = resolve(first.value.state)
		Harness.expect(Harness.hasError(repeated, "INVALID_PHASE"))
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

	Harness.test(
		"shield preparation follows team, slot, queue, effect, then target order",
		function()
			local multi = {
				schemaVersion = 1,
				id = "card.order.multi",
				displayName = "Order Multi",
				class = "Stone",
				abilityId = "ability.order.multi",
				energyCost = 2,
				targetingRule = "ALL_ALLIES",
				effects = {
					{ kind = "SHIELD", amount = 10 },
					{ kind = "SHIELD", amount = 5 },
				},
			}
			local state = Fixtures.createState()
			Fixtures.makeCard(state, "order.multi", multi.id, "combatant:t1:s1")
			Fixtures.queue(state, "team.1", "order.multi", "combatant:t1:s1", {})
			Fixtures.makeCard(
				state,
				"order.queue.second",
				Fixtures.CardDefinitions.Shield.id,
				"combatant:t1:s1"
			)
			Fixtures.queue(state, "team.1", "order.queue.second", "combatant:t1:s1", {})
			Fixtures.makeCard(
				state,
				"order.slot.two",
				Fixtures.CardDefinitions.Shield.id,
				"combatant:t1:s2"
			)
			Fixtures.queue(state, "team.1", "order.slot.two", "combatant:t1:s2", {})
			Fixtures.makeCard(
				state,
				"order.team.two",
				Fixtures.CardDefinitions.Shield.id,
				"combatant:t2:s1"
			)
			Fixtures.queue(state, "team.2", "order.team.two", "combatant:t2:s1", {})

			local result = resolve(state, { multi })
			Harness.expect(result.ok)
			local prepared = eventsOfKind(result.value.events, "SHIELD_PREPARED")
			Harness.equal(#prepared, 9)
			local expected = {
				{ "order.multi", 1, "combatant:t1:s1" },
				{ "order.multi", 1, "combatant:t1:s2" },
				{ "order.multi", 1, "combatant:t1:s3" },
				{ "order.multi", 2, "combatant:t1:s1" },
				{ "order.multi", 2, "combatant:t1:s2" },
				{ "order.multi", 2, "combatant:t1:s3" },
				{ "order.queue.second", 1, "combatant:t1:s1" },
				{ "order.slot.two", 1, "combatant:t1:s2" },
				{ "order.team.two", 1, "combatant:t2:s1" },
			}
			for index, expectation in expected do
				local event = prepared[index]
				Harness.equal(event.payload.preparationOrder, index)
				Harness.equal(event.payload.cardInstanceId, expectation[1])
				Harness.equal(event.payload.effectIndex, expectation[2])
				Harness.equal(event.payload.targetCombatantId, expectation[3])
			end
			local initiativeIndex = eventIndex(result.value.events, "INITIATIVE_DETERMINED")
			Harness.expect(
				prepared[#prepared].sequence < result.value.events[initiativeIndex].sequence
			)
		end
	)

	Harness.test("partially consumed shield expires with its remaining amount", function()
		local smallHit = {
			schemaVersion = 1,
			id = "card.partial.hit",
			displayName = "Partial Hit",
			class = "Stone",
			abilityId = "ability.partial.hit",
			energyCost = 1,
			targetingRule = "ANY",
			effects = { { kind = "DAMAGE", amount = 5 } },
		}
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"partial.shield",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "partial.shield", "combatant:t1:s1", {})
		Fixtures.makeCard(state, "partial.hit", smallHit.id, "combatant:t2:s1")
		Fixtures.queue(state, "team.2", "partial.hit", "combatant:t2:s1", { "combatant:t1:s1" })

		local result = resolve(state, { smallHit })
		Harness.expect(result.ok)
		local absorbed = findEvent(result.value.events, "SHIELD_ABSORBED")
		Harness.expect(absorbed ~= nil)
		Harness.expect(absorbed.payload.absorbed > 0)
		Harness.expect(absorbed.payload.absorbed < 22)
		local expired = findEvent(result.value.events, "STATUS_EXPIRED", function(event)
			return event.payload.statusId == "SHIELD"
		end)
		Harness.expect(expired ~= nil)
		Harness.equal(expired.payload.remainingAmount, 22 - absorbed.payload.absorbed)
		Harness.equal(#Fixtures.findCombatant(result.value.state, "combatant:t1:s1").shields, 0)
	end)

	Harness.test("fully consumed shield emits no expiry event", function()
		local heavyHit = {
			schemaVersion = 1,
			id = "card.full.hit",
			displayName = "Full Hit",
			class = "Stone",
			abilityId = "ability.full.hit",
			energyCost = 1,
			targetingRule = "ANY",
			effects = { { kind = "DAMAGE", amount = 100 } },
		}
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"full.shield",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "full.shield", "combatant:t1:s1", {})
		Fixtures.makeCard(state, "full.hit", heavyHit.id, "combatant:t2:s1")
		Fixtures.queue(state, "team.2", "full.hit", "combatant:t2:s1", { "combatant:t1:s1" })

		local result = resolve(state, { heavyHit })
		Harness.expect(result.ok)
		local absorbed = findEvent(result.value.events, "SHIELD_ABSORBED")
		Harness.equal(absorbed.payload.absorbed, 22)
		local expired = findEvent(result.value.events, "STATUS_EXPIRED", function(event)
			return event.payload.statusId == "SHIELD"
		end)
		Harness.equal(expired, nil)
		Harness.equal(#Fixtures.findCombatant(result.value.state, "combatant:t1:s1").shields, 0)
	end)

	Harness.test("shield-only card prepares once and discards once", function()
		local state = Fixtures.createState()
		Fixtures.makeCard(
			state,
			"shield.only",
			Fixtures.CardDefinitions.Shield.id,
			"combatant:t1:s1"
		)
		Fixtures.queue(state, "team.1", "shield.only", "combatant:t1:s1", {})
		Fixtures.findTeamState(state, "team.1").drawPileCardInstanceIds = {
			"shield.draw.1",
			"shield.draw.2",
			"shield.draw.3",
		}

		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.equal(#eventsOfKind(result.value.events, "SHIELD_PREPARED"), 1)
		Harness.equal(#eventsOfKind(result.value.events, "CARD_PLAYED"), 1)
		Harness.equal(findEvent(result.value.events, "SHIELD_GRANTED"), nil)

		local teamState = Fixtures.findTeamState(result.value.state, "team.1")
		local copies = 0
		for _, zone in
			{
				teamState.drawPileCardInstanceIds,
				teamState.handCardInstanceIds,
				teamState.discardCardInstanceIds,
				teamState.removedCardInstanceIds,
			}
		do
			for _, cardId in zone do
				if cardId == "shield.only" then
					copies += 1
				end
			end
		end
		Harness.equal(copies, 1)
		Harness.expect(table.find(teamState.discardCardInstanceIds, "shield.only") ~= nil)
	end)
end
