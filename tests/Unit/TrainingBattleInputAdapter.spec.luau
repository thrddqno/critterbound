--!strict

return function(Harness)
	local ProfileFixtures = require("../Fixtures/ProfileFixtures")
	local Run5Fixtures = require("../Fixtures/Run5Fixtures")
	local TrainingGrounds = require("../../src/shared/Definitions/TrainingGrounds")
	local Adapter = require("../../src/server/Services/TrainingBattleInputAdapter")
	local BattleFactory = require("../../src/shared/Battle/BattleFactory")

	Harness.test(
		"Training adapter uses selected owned IDs and isolates battle mutations",
		function()
			local store = ProfileFixtures.MockDataStore.new()
			local service =
				ProfileFixtures.newService(ProfileFixtures.newRepository(store, "job-a"))
			local adapter = Adapter.new({ profileService = service, content = TrainingGrounds })
			local inputResult = adapter.createInput(701, 1)
			Harness.expect(inputResult.ok)
			local selected = service.GetSelectedTeam(701)
			Harness.expect(selected.ok)
			for index, critter in inputResult.value.teams[1].critterInstances do
				Harness.equal(critter.id, selected.value[index].id)
			end
			local deps = Run5Fixtures.dependencies()
			local battle = BattleFactory.create(inputResult.value, {
				rng = deps.rng,
				deck = deps.deck,
				validator = deps.validator,
			})
			Harness.expect(battle.ok)
			battle.value.combatants[1].currentHealth = 0
			battle.value.combatants[1].statusEffects = { { id = "battle-only" } }
			local after = service.GetSelectedTeam(701)
			Harness.expect(after.ok)
			Harness.equal(after.value[1].baseStats.maxHealth, selected.value[1].baseStats.maxHealth)
			Harness.expect(after.value[1].currentHealth == nil)
			Harness.expect(after.value[1].statusEffects == nil)
		end
	)
end
