--!strict

return function(Harness)
	local Initiative = require("../../src/shared/Battle/Initiative")

	local function card(id, sourceId, queueIndex)
		return {
			cardInstanceId = id,
			sourceCombatantId = sourceId,
			targetCombatantIds = { sourceId },
			queueIndex = queueIndex,
		}
	end

	Harness.test("higher Speed resolves first and idle Critters excluded", function()
		local entries = {
			{
				combatantId = "slow",
				teamIndex = 1,
				slot = 1,
				speed = 10,
				queuedCards = { card("a", "slow", 1) },
			},
			{
				combatantId = "fast",
				teamIndex = 2,
				slot = 1,
				speed = 30,
				queuedCards = { card("b", "fast", 1) },
			},
			{ combatantId = "idle", teamIndex = 1, slot = 2, speed = 99, queuedCards = {} },
		}
		local ordered = Initiative.order(entries, 1)
		Harness.equal(#ordered, 2)
		Harness.equal(ordered[1].combatantId, "fast")
		Harness.equal(ordered[2].combatantId, "slow")
	end)

	Harness.test("equal Speed alternates team priority by round", function()
		local entries = {
			{
				combatantId = "team1",
				teamIndex = 1,
				slot = 1,
				speed = 20,
				queuedCards = { card("a", "team1", 1) },
			},
			{
				combatantId = "team2",
				teamIndex = 2,
				slot = 1,
				speed = 20,
				queuedCards = { card("b", "team2", 1) },
			},
		}
		Harness.equal(Initiative.order(entries, 1)[1].combatantId, "team1")
		Harness.equal(Initiative.order(entries, 2)[1].combatantId, "team2")
	end)

	Harness.test("equal Speed uses slot then identifier", function()
		local entries = {
			{
				combatantId = "z",
				teamIndex = 1,
				slot = 2,
				speed = 20,
				queuedCards = { card("a", "z", 1) },
			},
			{
				combatantId = "b",
				teamIndex = 1,
				slot = 1,
				speed = 20,
				queuedCards = { card("b", "b", 1) },
			},
			{
				combatantId = "a",
				teamIndex = 1,
				slot = 1,
				speed = 20,
				queuedCards = { card("c", "a", 1) },
			},
		}
		local ordered = Initiative.order(entries, 1)
		Harness.equal(ordered[1].combatantId, "a")
		Harness.equal(ordered[2].combatantId, "b")
		Harness.equal(ordered[3].combatantId, "z")
	end)

	Harness.test("per-Critter card order preserved", function()
		local queue =
			{ card("first", "actor", 1), card("second", "actor", 2), card("third", "actor", 3) }
		local entries =
			{ { combatantId = "actor", teamIndex = 1, slot = 1, speed = 20, queuedCards = queue } }
		local ordered = Initiative.order(entries, 1)
		Harness.equal(ordered[1].queuedCards[1].cardInstanceId, "first")
		Harness.equal(ordered[1].queuedCards[2].cardInstanceId, "second")
		Harness.equal(ordered[1].queuedCards[3].cardInstanceId, "third")
	end)

	Harness.test("initiative ordering is deterministic and nonmutating", function()
		local entries = {
			{
				combatantId = "second",
				teamIndex = 1,
				slot = 2,
				speed = 20,
				queuedCards = { card("a", "second", 1) },
			},
			{
				combatantId = "first",
				teamIndex = 1,
				slot = 1,
				speed = 20,
				queuedCards = { card("b", "first", 1) },
			},
		}
		local before = Harness.clone(entries)
		local one = Initiative.order(entries, 1)
		local two = Initiative.order(entries, 1)
		Harness.deepEqual(one, two)
		Harness.deepEqual(entries, before)
	end)
end
