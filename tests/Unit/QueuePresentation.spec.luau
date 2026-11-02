--!strict

return function(Harness)
	local QueuePresentation = require("../../src/client/Presentation/QueuePresentation")

	local critters = {
		{ id = "combatant.player.stone", displayName = "Bastion", slot = 1 },
		{ id = "combatant.player.feral", displayName = "Ravager", slot = 2 },
		{ id = "combatant.player.verdant", displayName = "Bloom", slot = 3 },
	}

	local function entry(id, sourceId, sourceOrder)
		return {
			card = { id = id, sourceCombatantId = sourceId },
			sourceOrder = sourceOrder,
		}
	end

	Harness.test("queue presentation groups by exact combatant identity", function()
		local groups = QueuePresentation.group({
			entry("feral.2", critters[2].id, 2),
			entry("stone.1", critters[1].id, 1),
			entry("feral.1", critters[2].id, 1),
		}, critters)
		Harness.equal(#groups, 2)
		Harness.equal(groups[1].sourceCombatantId, critters[1].id)
		Harness.equal(groups[2].sourceCombatantId, critters[2].id)
		Harness.equal(groups[2].entries[1].card.id, "feral.1")
		Harness.equal(groups[2].entries[2].card.id, "feral.2")
	end)

	Harness.test("queue presentation keeps duplicate names distinct", function()
		local sameNames = {
			{ id = "combatant.player.one", displayName = "Ravager", slot = 1 },
			{ id = "combatant.player.two", displayName = "Ravager", slot = 2 },
		}
		local groups = QueuePresentation.group({
			entry("one", sameNames[1].id, 1),
			entry("two", sameNames[2].id, 1),
		}, sameNames)
		Harness.equal(#groups, 2)
		Harness.equal(groups[1].sourceCombatantId, sameNames[1].id)
		Harness.equal(groups[2].sourceCombatantId, sameNames[2].id)
	end)

	Harness.test("queue presentation preserves unknown sources deterministically", function()
		local groups = QueuePresentation.group({
			entry("z", "missing.z", 1),
			entry("a", "missing.a", 1),
		}, critters)
		Harness.equal(#groups, 2)
		Harness.expect(not groups[1].knownSource)
		Harness.equal(groups[1].sourceCombatantId, "missing.a")
		Harness.equal(groups[2].sourceCombatantId, "missing.z")
	end)

	Harness.test("queue presentation handles empty queue without mutation", function()
		local entries = {}
		local beforeCritters = Harness.clone(critters)
		local groups = QueuePresentation.group(entries, critters)
		Harness.equal(#groups, 0)
		Harness.equal(#entries, 0)
		Harness.deepEqual(critters, beforeCritters)
	end)

	Harness.test("queue presentation never mutates entries", function()
		local entries = {
			entry("second", critters[1].id, 2),
			entry("first", critters[1].id, 1),
		}
		local before = Harness.clone(entries)
		QueuePresentation.group(entries, critters)
		Harness.deepEqual(entries, before)
	end)
end
