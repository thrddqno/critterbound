--!strict

return function(Harness)
	local Mapper = require("../../src/client/Presentation/BattlePresentationMapper")
	local MockBattleSession = require("../../src/client/Development/MockBattleSession")
	local DomainFixtures = require("../Fixtures/DomainFixtures")

	Harness.test("maps six Critters and six card instances", function()
		local snapshot = MockBattleSession.createSnapshot()
		snapshot.critterDefinitionsById[DomainFixtures.Definitions.Stone.id] =
			DomainFixtures.Definitions.Stone
		local result = Mapper.map(snapshot)
		Harness.expect(result.ok)
		Harness.equal(#result.value.teams, 2)
		Harness.equal(#result.value.critters, 6)
		Harness.equal(#result.value.hand, 6)
		Harness.equal(result.value.teams[1].side, "ALLY")
		Harness.equal(
			result.value.teams[1].critters[1].displayName,
			DomainFixtures.Definitions.Stone.displayName
		)
	end)

	Harness.test("preserves card identity and authoritative initiative order", function()
		local snapshot = MockBattleSession.createSnapshot()
		local result = Mapper.map(snapshot)
		Harness.expect(result.ok)
		local seen = {}
		for _, card in result.value.hand do
			Harness.expect(not seen[card.id])
			seen[card.id] = true
		end
		Harness.equal(result.value.initiative[1].combatantId, snapshot.initiativeCombatantIds[1])
		Harness.equal(result.value.initiative[6].combatantId, snapshot.initiativeCombatantIds[6])
		for index, entry in result.value.initiative do
			Harness.equal(entry.position, index)
			Harness.equal(entry.combatantId, snapshot.initiativeCombatantIds[index])
			Harness.expect(entry.teamId == "team.1" or entry.teamId == "team.2")
			Harness.equal(
				entry.side,
				if entry.teamId == snapshot.viewerTeamId then "ALLY" else "ENEMY"
			)
		end
	end)

	Harness.test("duplicate names retain unique combatant initiative identity", function()
		local result = Mapper.map(MockBattleSession.createSnapshot())
		Harness.expect(result.ok)
		Harness.equal(
			result.value.initiative[1].displayName,
			result.value.initiative[2].displayName
		)
		Harness.expect(
			result.value.initiative[1].combatantId ~= result.value.initiative[2].combatantId
		)
		Harness.expect(result.value.initiative[1].side ~= result.value.initiative[2].side)
	end)

	Harness.test(
		"maps long optional card descriptions without changing domain definitions",
		function()
			local snapshot = MockBattleSession.createSnapshot()
			local description =
				"A deliberately long presentation description that must wrap inside its card."
			snapshot.cardDefinitionsById["card.stone.guard"].description = description
			local result = Mapper.map(snapshot)
			Harness.expect(result.ok)
			Harness.equal(result.value.hand[1].description, description)
		end
	)

	Harness.test("maps HP shields Speed energy and phase", function()
		local result = Mapper.map(MockBattleSession.createSnapshot())
		Harness.expect(result.ok)
		local stone = result.value.teams[1].critters[1]
		Harness.equal(stone.health, 120)
		Harness.equal(stone.shield, 12)
		Harness.equal(stone.speed, 10)
		Harness.equal(result.value.energy.available, 3)
		Harness.equal(result.value.phase, "PLANNING")
	end)

	Harness.test("presentation mapper reports missing references", function()
		local snapshot = MockBattleSession.createSnapshot()
		snapshot.critterInstancesById["owned.team1.stone"] = nil
		local result = Mapper.map(snapshot)
		Harness.expect(not result.ok)
		Harness.expect(Harness.hasError(result, "MISSING_CRITTER_REFERENCE"))
	end)

	Harness.test("presentation mapping is deterministic and nonmutating", function()
		local snapshot = MockBattleSession.createSnapshot()
		local before = Harness.clone(snapshot)
		local first = Mapper.map(snapshot)
		local second = Mapper.map(snapshot)
		Harness.deepEqual(first, second)
		Harness.deepEqual(snapshot, before)
	end)
end
