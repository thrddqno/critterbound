--!strict

return function(Harness)
	local Playback = require("../../src/client/Presentation/BattlePlayback")

	local function snapshot()
		return {
			battleState = {
				combatants = {
					{ id = "source", currentHealth = 100, statusEffects = {} },
					{ id = "target", currentHealth = 100, statusEffects = {} },
					{ id = "target.two", currentHealth = 100, statusEffects = {} },
				},
			},
			shieldsByCombatantId = { target = 0, ["target.two"] = 0 },
			initiativeCombatantIds = {},
			cardInstancesById = {
				card = { definitionId = "card.attack" },
			},
			cardDefinitionsById = {
				["card.attack"] = { displayName = "Test Strike" },
			},
		}
	end

	Harness.test("playback applies HP shield status and initiative in event order", function()
		local original = snapshot()
		local state = Playback.new(original)
		state = Playback.apply(state, {
			kind = "INITIATIVE_DETERMINED",
			payload = { initiativeCombatantIds = { "source", "target" } },
			targetCombatantIds = {},
		})
		state = Playback.apply(state, {
			kind = "SHIELD_GRANTED",
			payload = { targetCombatantId = "target", amount = 20 },
			targetCombatantIds = { "target" },
		})
		state = Playback.apply(state, {
			kind = "DAMAGE_APPLIED",
			payload = { targetCombatantId = "target", hpDamage = 15, healthAfter = 85 },
			targetCombatantIds = { "target" },
		})
		state = Playback.apply(state, {
			kind = "STATUS_APPLIED",
			payload = {
				targetCombatantId = "target",
				statusId = "POISON",
				stackCount = 1,
				magnitude = 5,
				expiresAtRound = 2,
			},
			targetCombatantIds = { "target" },
		})
		Harness.equal(original.battleState.combatants[2].currentHealth, 100)
		Harness.equal(state.snapshot.battleState.combatants[2].currentHealth, 85)
		Harness.equal(state.snapshot.shieldsByCombatantId.target, 20)
		Harness.equal(state.snapshot.battleState.combatants[2].statusEffects[1].statusId, "POISON")
		Harness.deepEqual(state.snapshot.initiativeCombatantIds, { "source", "target" })
	end)

	Harness.test("playback does not expose final HP before damage event", function()
		local state = Playback.new(snapshot())
		state = Playback.apply(state, {
			kind = "CARD_PLAYED",
			payload = { cardDefinitionId = "card.attack" },
			targetCombatantIds = { "target" },
		})
		Harness.equal(state.snapshot.battleState.combatants[2].currentHealth, 100)
	end)

	Harness.test("playback distinguishes prepared shields from absorbed shields", function()
		local state = Playback.applyAll(Playback.new(snapshot()), {
			{
				id = "prep.1",
				sequence = 1,
				kind = "SHIELD_PREPARED",
				targetCombatantIds = { "target" },
				payload = { targetCombatantId = "target", amount = 25, preparationOrder = 1 },
			},
			{
				id = "absorb.2",
				sequence = 2,
				kind = "SHIELD_ABSORBED",
				targetCombatantIds = { "target" },
				payload = { targetCombatantId = "target", absorbed = 10 },
			},
		})
		Harness.equal(state.snapshot.shieldsByCombatantId.target, 15)
		Harness.equal(state.logEntries[1].text, "PREP +25 Shield → target")
		Harness.equal(state.logEntries[2].text, "-10 Shield → target")
		Harness.equal(state.feedbackByCombatantId.target.text, "-10 Shield")
	end)

	Harness.test("critical damage uses minimal existing feedback and log conventions", function()
		local state = Playback.apply(Playback.new(snapshot()), {
			id = "critical.1",
			sequence = 1,
			kind = "DAMAGE_APPLIED",
			targetCombatantIds = { "target" },
			payload = {
				targetCombatantId = "target",
				hpDamage = 18,
				healthAfter = 82,
				isCritical = true,
			},
		})
		Harness.equal(state.feedbackByCombatantId.target.kind, "CRITICAL")
		Harness.equal(state.feedbackByCombatantId.target.text, "CRIT -18 HP")
		Harness.equal(state.message, "Critical hit: 18 HP")

		state = Playback.apply(state, {
			id = "critical.2",
			sequence = 2,
			kind = "DAMAGE_APPLIED",
			targetCombatantIds = { "target" },
			payload = {
				targetCombatantId = "target",
				hpDamage = 0,
				shieldAbsorbed = 12,
				healthAfter = 82,
				isCritical = true,
			},
		})
		Harness.equal(state.feedbackByCombatantId.target.text, "CRIT -12 Shield")
		Harness.equal(state.message, "Critical hit: 12 shield")
	end)

	Harness.test("Blood Moon playback is distinct environmental damage", function()
		local state = Playback.apply(Playback.new(snapshot()), {
			id = "blood.1",
			sequence = 1,
			roundNumber = 10,
			kind = "BLOOD_MOON_DAMAGE",
			targetCombatantIds = { "target" },
			payload = {
				source = "BLOOD_MOON",
				targetCombatantId = "target",
				damage = 50,
				hpDamage = 50,
				healthAfter = 50,
				defeated = false,
			},
		})
		Harness.equal(state.snapshot.battleState.combatants[2].currentHealth, 50)
		Harness.equal(state.feedbackByCombatantId.target.kind, "ENVIRONMENT")
		Harness.equal(state.feedbackByCombatantId.target.text, "BLOOD MOON -50 HP")
		Harness.equal(state.message, "Blood Moon: -50 HP")
		Harness.equal(state.logEntries[1].kind, "BLOOD_MOON_DAMAGE")
	end)

	Harness.test("ordered events drive action name log and effect feedback", function()
		local state = Playback.new(snapshot())
		state = Playback.applyAll(state, {
			{
				id = "e1",
				sequence = 1,
				kind = "CARD_PLAYED",
				sourceCombatantId = "source",
				payload = { cardInstanceId = "card" },
			},
			{
				id = "e2",
				sequence = 2,
				kind = "DAMAGE_APPLIED",
				targetCombatantIds = { "target" },
				payload = { targetCombatantId = "target", hpDamage = 12, healthAfter = 88 },
			},
			{
				id = "e3",
				sequence = 3,
				kind = "HEAL_APPLIED",
				targetCombatantIds = { "target.two" },
				payload = { targetCombatantId = "target.two", restored = 7, healthAfter = 100 },
			},
			{
				id = "e4",
				sequence = 4,
				kind = "SHIELD_GRANTED",
				targetCombatantIds = { "target.two" },
				payload = { targetCombatantId = "target.two", amount = 9 },
			},
		})
		Harness.equal(state.currentActionName, "Test Strike")
		Harness.equal(state.snapshot.battleState.combatants[2].currentHealth, 88)
		Harness.equal(state.snapshot.shieldsByCombatantId["target.two"], 9)
		Harness.equal(state.feedbackByCombatantId["target.two"].text, "+9 Shield")
		Harness.equal(#state.logEntries, 4)
	end)

	Harness.test("multiple targets poison defeat and canceled actions stay readable", function()
		local state = Playback.new(snapshot())
		state = Playback.apply(state, {
			id = "e10",
			sequence = 10,
			kind = "TARGET_SELECTED",
			targetCombatantIds = { "target", "target.two" },
			payload = { targetCombatantIds = { "target", "target.two" } },
		})
		Harness.deepEqual(state.activeTargetCombatantIds, { "target", "target.two" })
		state = Playback.applyAll(state, {
			{
				id = "e11",
				sequence = 11,
				kind = "STATUS_TICKED",
				targetCombatantIds = { "target" },
				payload = {
					targetCombatantId = "target",
					statusId = "POISON",
					damage = 5,
					healthAfter = 0,
				},
			},
			{
				id = "e12",
				sequence = 12,
				kind = "CRITTER_DEFEATED",
				payload = { combatantId = "target" },
			},
			{
				id = "e13",
				sequence = 13,
				kind = "ACTION_CANCELED",
				payload = {
					cardInstanceId = "card",
					sourceCombatantId = "source",
					reason = "DEFEATED",
				},
			},
		})
		Harness.equal(state.snapshot.battleState.combatants[2].currentHealth, 0)
		Harness.equal(state.feedbackByCombatantId.source.text, "ACTION CANCELED")
		Harness.equal(state.currentActionName, "Test Strike")
		Harness.expect(string.find(state.message, "canceled", 1, true) ~= nil)
	end)

	Harness.test("round end exposes transition before final snapshot", function()
		local state = Playback.apply(Playback.new(snapshot()), {
			id = "round",
			sequence = 30,
			roundNumber = 2,
			kind = "ROUND_COMPLETED",
			payload = { nextRoundNumber = 3, phase = "PLANNING" },
		})
		Harness.expect(state.roundTransition)
		Harness.equal(state.currentActionName, "Round 2 complete")
		Harness.equal(state.message, "Round complete — preparing round 3")
	end)

	Harness.test("fast-forward preserves order and rejects duplicate or stale events", function()
		local events = {
			{
				id = "ordered.1",
				sequence = 20,
				kind = "SHIELD_GRANTED",
				payload = { targetCombatantId = "target", amount = 10 },
			},
			{
				id = "ordered.2",
				sequence = 21,
				kind = "SHIELD_ABSORBED",
				payload = { targetCombatantId = "target", absorbed = 4 },
			},
		}
		local state = Playback.applyAll(Playback.new(snapshot()), events)
		Harness.equal(state.snapshot.shieldsByCombatantId.target, 6)
		local duplicate = Playback.apply(state, events[2])
		Harness.expect(duplicate == state)
		local stale = Playback.apply(state, {
			id = "stale",
			sequence = 19,
			kind = "SHIELD_GRANTED",
			payload = { targetCombatantId = "target", amount = 99 },
		})
		Harness.expect(stale == state)
	end)

	Harness.test("fresh snapshot playback is isolated from interrupted timeline", function()
		local old = Playback.apply(Playback.new(snapshot()), {
			id = "old",
			sequence = 1,
			kind = "DAMAGE_APPLIED",
			payload = { targetCombatantId = "target", hpDamage = 90, healthAfter = 10 },
		})
		local reconnectedSnapshot = snapshot()
		reconnectedSnapshot.battleState.combatants[2].currentHealth = 72
		local fresh = Playback.new(reconnectedSnapshot)
		Harness.equal(old.snapshot.battleState.combatants[2].currentHealth, 10)
		Harness.equal(fresh.snapshot.battleState.combatants[2].currentHealth, 72)
		Harness.equal(#fresh.logEntries, 0)
	end)
end
