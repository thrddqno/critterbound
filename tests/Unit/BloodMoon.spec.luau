--!strict

return function(Harness)
	local BattleEvents = require("../../src/shared/Battle/BattleEvents")
	local BloodMoon = require("../../src/shared/Battle/BloodMoon")
	local Deck = require("../../src/shared/Battle/Deck")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")
	local RoundEconomy = require("../../src/shared/Battle/RoundEconomy")
	local RoundResolver = require("../../src/shared/Battle/RoundResolver")
	local Fixtures = require("../Fixtures/Run4BFixtures")

	local CONFIG = {
		Enabled = true,
		StartingRound = 10,
		InitialDamage = 50,
		DamageIncrement = 30,
		BypassesShields = true,
	}

	local function resolve(state)
		return RoundResolver.resolveRound(state, {
			cardDefinitionsById = Fixtures.clone(Fixtures.CardDefinitionsById),
			deck = Deck,
			economy = RoundEconomy,
			shuffle = DeterministicRng.shuffle,
			drawPerRound = 3,
			bloodMoonConfig = CONFIG,
		})
	end

	local function eventsOfKind(events, kind: string)
		local result = {}
		for _, event in events do
			if event.kind == kind then
				table.insert(result, event)
			end
		end
		return result
	end

	Harness.test("Blood Moon damage starts at 50 and escalates by 30", function()
		Harness.equal(BloodMoon.damageForRound(CONFIG, 9), nil)
		Harness.equal(BloodMoon.damageForRound(CONFIG, 10), 50)
		Harness.equal(BloodMoon.damageForRound(CONFIG, 11), 80)
		Harness.equal(BloodMoon.damageForRound(CONFIG, 12), 110)
		Harness.equal(BloodMoon.damageForRound(CONFIG, 25), 500)
		local disabled = Fixtures.clone(CONFIG)
		disabled.Enabled = false
		Harness.equal(BloodMoon.damageForRound(disabled, 25), nil)
	end)

	Harness.test(
		"Blood Moon damages every living Critter in stable order and skips defeated",
		function()
			local state = Fixtures.createState({ roundNumber = 10 })
			local skipped = Fixtures.findCombatant(state, "combatant:t1:s2")
			skipped.currentHealth = 0
			local shielded = Fixtures.findCombatant(state, "combatant:t1:s1")
			shielded.shields = {
				{
					id = "shield.test",
					sourceCombatantId = shielded.id,
					amount = 100,
					expiresAtRound = 10,
				},
			}
			local events = {}
			local applied = BloodMoon.apply(
				state,
				state.combatants,
				10,
				CONFIG,
				BattleEvents.create(state.id, 0),
				events
			)
			Harness.expect(applied.applied)
			Harness.equal(#events, 5)
			Harness.deepEqual(events[1].targetCombatantIds, { "combatant:t1:s1" })
			Harness.deepEqual(events[2].targetCombatantIds, { "combatant:t1:s3" })
			Harness.deepEqual(events[3].targetCombatantIds, { "combatant:t2:s1" })
			Harness.equal(events[1].payload.source, "BLOOD_MOON")
			Harness.equal(events[1].payload.roundNumber, 10)
			Harness.equal(events[1].payload.damage, 50)
			Harness.equal(events[1].payload.healthBefore, 100)
			Harness.equal(events[1].payload.healthAfter, 50)
			Harness.equal(events[1].payload.defeated, false)
			Harness.equal(shielded.shields[1].amount, 100)
			Harness.equal(skipped.currentHealth, 0)
		end
	)

	Harness.test("Blood Moon clamps lethal damage and cannot execute twice", function()
		local state = Fixtures.createState({ roundNumber = 12 })
		for _, combatant in state.combatants do
			combatant.currentHealth = 40
		end
		local events = {}
		local factory = BattleEvents.create(state.id, 0)
		local first = BloodMoon.apply(state, state.combatants, 12, CONFIG, factory, events)
		Harness.equal(#first.defeatedCombatantIds, 6)
		Harness.equal(#events, 6)
		Harness.equal(events[1].payload.hpDamage, 40)
		Harness.equal(events[1].payload.healthAfter, 0)
		Harness.equal(events[1].payload.defeated, true)
		local second = BloodMoon.apply(state, state.combatants, 12, CONFIG, factory, events)
		Harness.expect(not second.applied)
		Harness.equal(#events, 6)
		Harness.equal(state.lastBloodMoonRound, 12)
	end)

	Harness.test("round resolution heals before Blood Moon and preserves shields", function()
		local state = Fixtures.createState({ roundNumber = 10 })
		local target = Fixtures.findCombatant(state, "combatant:t1:s1")
		target.currentHealth = 40
		target.shields = {
			{
				id = "shield.persist",
				sourceCombatantId = target.id,
				amount = 75,
				expiresAtRound = 10,
			},
		}
		Fixtures.makeCard(state, "moon.heal", Fixtures.CardDefinitions.Heal.id, "combatant:t1:s3")
		Fixtures.queue(state, "team.1", "moon.heal", "combatant:t1:s3", { target.id })
		local result = resolve(state)
		Harness.expect(result.ok)
		local healIndex = nil
		local moonIndex = nil
		for index, event in result.value.events do
			if event.kind == "HEAL_APPLIED" then
				healIndex = index
			elseif
				event.kind == "BLOOD_MOON_DAMAGE"
				and event.payload.targetCombatantId == target.id
			then
				moonIndex = index
				Harness.equal(event.payload.healthBefore, 70)
				Harness.equal(event.payload.healthAfter, 20)
				Harness.equal(event.payload.shieldAbsorbed, 0)
			end
		end
		Harness.expect(healIndex ~= nil and moonIndex ~= nil and healIndex < moonIndex)
	end)

	Harness.test(
		"Blood Moon leaves critical and deck RNG unchanged when transition needs no shuffle",
		function()
			local state = Fixtures.createState({ roundNumber = 10 })
			local deckBefore = Fixtures.clone(state.rng)
			local criticalBefore = Fixtures.clone(state.criticalRng)
			local result = resolve(state)
			Harness.expect(result.ok)
			Harness.deepEqual(result.value.state.rng, deckBefore)
			Harness.deepEqual(result.value.state.criticalRng, criticalBefore)
			Harness.equal(#eventsOfKind(result.value.events, "BLOOD_MOON_DAMAGE"), 6)
		end
	)

	Harness.test("simultaneous Blood Moon defeat produces mutual destruction", function()
		local state = Fixtures.createState({ roundNumber = 10 })
		for _, combatant in state.combatants do
			combatant.currentHealth = 50
			local cardId = `moon.card.{combatant.id}`
			Fixtures.makeCard(state, cardId, Fixtures.CardDefinitions.Attack.id, combatant.id)
			table.insert(
				Fixtures.findTeamState(state, combatant.teamId).drawPileCardInstanceIds,
				cardId
			)
		end
		local result = resolve(state)
		Harness.expect(result.ok)
		Harness.expect(result.value.matchOutcome.isDraw)
		Harness.equal(result.value.matchOutcome.reason, "MUTUAL_DESTRUCTION")
		Harness.equal(#eventsOfKind(result.value.events, "BLOOD_MOON_DAMAGE"), 6)
		Harness.equal(#eventsOfKind(result.value.events, "CRITTER_DEFEATED"), 6)
		for _, roundState in result.value.state.teamRoundStates do
			Harness.equal(#roundState.drawPileCardInstanceIds, 0)
			Harness.equal(#roundState.removedCardInstanceIds, 3)
		end
	end)

	Harness.test("Blood Moon resolution is replay deterministic", function()
		local state = Fixtures.createState({ roundNumber = 11 })
		local first = resolve(state)
		local second = resolve(state)
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first.value.events, second.value.events)
		Harness.deepEqual(first.value.state, second.value.state)
		local moonEvents = eventsOfKind(first.value.events, "BLOOD_MOON_DAMAGE")
		Harness.equal(#moonEvents, 6)
		Harness.equal(moonEvents[1].payload.damage, 80)
	end)

	Harness.test("card victory prevents later Blood Moon damage", function()
		local lethal = Fixtures.clone(Fixtures.CardDefinitions.Attack)
		lethal.id = "card.bloodmoon.lethal"
		lethal.effects = { { kind = "DAMAGE", amount = 10_000 } }
		local state = Fixtures.createState({ roundNumber = 10 })
		for _, combatant in state.combatants do
			if combatant.teamId == "team.2" then
				combatant.currentHealth = 1
			end
		end
		lethal.targetingRule = "ALL_ENEMIES"
		Fixtures.makeCard(state, "moon.lethal", lethal.id, "combatant:t1:s2")
		Fixtures.queue(state, "team.1", "moon.lethal", "combatant:t1:s2", {})
		local definitions = Fixtures.clone(Fixtures.CardDefinitionsById)
		definitions[lethal.id] = lethal
		local result = RoundResolver.resolveRound(state, {
			cardDefinitionsById = definitions,
			deck = Deck,
			economy = RoundEconomy,
			shuffle = DeterministicRng.shuffle,
			bloodMoonConfig = CONFIG,
		})
		Harness.expect(result.ok)
		Harness.equal(#eventsOfKind(result.value.events, "BLOOD_MOON_DAMAGE"), 0)
		Harness.equal(result.value.matchOutcome.winnerTeamId, "team.1")
	end)
end
