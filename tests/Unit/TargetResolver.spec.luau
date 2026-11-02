--!strict

return function(Harness)
	local TargetResolver = require("../../src/shared/Battle/TargetResolver")

	local function combatant(id, teamId, slot, health)
		return {
			id = id,
			teamId = teamId,
			slot = slot,
			currentHealth = health or 100,
		}
	end

	local combatants = {
		combatant("t1s1", "team.1", 1),
		combatant("t1s2", "team.1", 2),
		combatant("t1s3", "team.1", 3),
		combatant("t2s1", "team.2", 1),
		combatant("t2s2", "team.2", 2),
		combatant("t2s3", "team.2", 3, 0),
	}
	local byId = {}
	for _, value in combatants do
		byId[value.id] = value
	end
	local source = byId.t1s1

	Harness.test("SELF ignores submitted targets", function()
		local result = TargetResolver.resolve("SELF", source, { "t2s1" }, byId)
		Harness.equal(#result.targetIds, 1)
		Harness.equal(result.targetIds[1], "t1s1")
		Harness.expect(not result.skipped)
	end)

	Harness.test("ALLY accepts a living ally and never self", function()
		local result = TargetResolver.resolve("ALLY", source, { "t1s2" }, byId)
		Harness.equal(result.targetIds[1], "t1s2")
		Harness.expect(not result.retargeted)

		local selfTarget = TargetResolver.resolve("ALLY", source, { "t1s1" }, byId)
		Harness.expect(selfTarget.retargeted)
		Harness.equal(selfTarget.targetIds[1], "t1s2")
	end)

	Harness.test("ALLY retargets to lowest-slot living ally when invalid", function()
		byId.t1s2.currentHealth = 0
		local result = TargetResolver.resolve("ALLY", source, { "t2s1" }, byId)
		Harness.equal(result.targetIds[1], "t1s3")
		Harness.expect(result.retargeted)
		byId.t1s2.currentHealth = 100
	end)

	Harness.test("ENEMY retargets to lowest-slot living enemy when invalid", function()
		local result = TargetResolver.resolve("ENEMY", source, { "t2s3" }, byId)
		Harness.equal(result.targetIds[1], "t2s1")
		Harness.expect(result.retargeted)

		local accepted = TargetResolver.resolve("ENEMY", source, { "t2s2" }, byId)
		Harness.equal(accepted.targetIds[1], "t2s2")
		Harness.expect(not accepted.retargeted)
	end)

	Harness.test("FRONT_ENEMY derives the closest living frontline enemy", function()
		local result = TargetResolver.resolve("FRONT_ENEMY", source, { "t2s2" }, byId)
		Harness.equal(#result.targetIds, 1)
		Harness.equal(result.targetIds[1], "t2s1")
		Harness.expect(result.retargeted)
	end)

	Harness.test("ALL_ALLIES and ALL_ENEMIES return slot-ordered living targets", function()
		local allies = TargetResolver.resolve("ALL_ALLIES", source, {}, byId)
		Harness.deepEqual(allies.targetIds, { "t1s1", "t1s2", "t1s3" })

		local enemies = TargetResolver.resolve("ALL_ENEMIES", source, {}, byId)
		Harness.deepEqual(enemies.targetIds, { "t2s1", "t2s2" })
	end)

	Harness.test("ANY skips invalid targets and defeated sources skip everything", function()
		local invalid = TargetResolver.resolve("ANY", source, { "t2s3" }, byId)
		Harness.expect(invalid.skipped)
		Harness.equal(#invalid.targetIds, 0)

		byId.t1s1.currentHealth = 0
		local deadSource = TargetResolver.resolve("SELF", source, {}, byId)
		Harness.expect(deadSource.skipped)
		byId.t1s1.currentHealth = 100
	end)

	Harness.test("target resolution is deterministic", function()
		local first = TargetResolver.resolve("ENEMY", source, { "missing" }, byId)
		local second = TargetResolver.resolve("ENEMY", source, { "missing" }, byId)
		Harness.deepEqual(first, second)
	end)
end
