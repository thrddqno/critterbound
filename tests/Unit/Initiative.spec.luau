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

	local function combatEntry(id, speed, health, skill, resolve, queue)
		return {
			combatantId = id,
			teamIndex = 1,
			slot = 1,
			speed = speed,
			currentHealth = health,
			skill = skill,
			resolve = resolve,
			queuedCards = queue or { card(`card.{id}`, id, 1) },
		}
	end

	Harness.test("combat initiative uses speed, health, skill, resolve, then id", function()
		local speedFirst = Initiative.orderCombat({
			combatEntry("slow", 10, 50, 9, 9),
			combatEntry("fast", 30, 100, 1, 1),
		})
		Harness.equal(speedFirst[1].combatantId, "fast")

		local healthFirst = Initiative.orderCombat({
			combatEntry("healthy", 20, 100, 9, 9),
			combatEntry("wounded", 20, 25, 1, 1),
		})
		Harness.equal(healthFirst[1].combatantId, "wounded")

		local skillFirst = Initiative.orderCombat({
			combatEntry("lowSkill", 20, 100, 1, 9),
			combatEntry("highSkill", 20, 100, 5, 1),
		})
		Harness.equal(skillFirst[1].combatantId, "highSkill")

		local resolveFirst = Initiative.orderCombat({
			combatEntry("lowResolve", 20, 100, 5, 1),
			combatEntry("highResolve", 20, 100, 5, 5),
		})
		Harness.equal(resolveFirst[1].combatantId, "highResolve")

		local idFirst = Initiative.orderCombat({
			combatEntry("zulu", 20, 100, 5, 5),
			combatEntry("alpha", 20, 100, 5, 5),
		})
		Harness.equal(idFirst[1].combatantId, "alpha")
	end)

	Harness.test("combat initiative skips idle Critters and preserves card order", function()
		local ordered = Initiative.orderCombat({
			combatEntry("actor", 20, 100, 1, 1, {
				card("first", "actor", 1),
				card("second", "actor", 2),
			}),
			combatEntry("idle", 99, 100, 1, 1, {}),
		})
		Harness.equal(#ordered, 1)
		Harness.equal(ordered[1].queuedCards[1].cardInstanceId, "first")
		Harness.equal(ordered[1].queuedCards[2].cardInstanceId, "second")
	end)

	Harness.test("combat initiative is deterministic and nonmutating", function()
		local entries = {
			combatEntry("beta", 20, 100, 1, 1),
			combatEntry("alpha", 20, 100, 1, 1),
		}
		local before = Harness.clone(entries)
		local first = Initiative.orderCombat(entries)
		local second = Initiative.orderCombat(entries)
		Harness.deepEqual(first, second)
		Harness.deepEqual(entries, before)
	end)
end
