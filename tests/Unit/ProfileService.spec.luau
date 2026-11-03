--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")

	Harness.test("ProfileService returns detached sanitized DTOs", function()
		local store = Fixtures.MockDataStore.new()
		local service = Fixtures.newService(Fixtures.newRepository(store, "job-a"))
		Harness.expect(service.LoadProfile(601).ok)
		local first = service.GetProfile(601)
		Harness.expect(first.ok)
		Harness.expect(first.value.sessionLock == nil)
		first.value.ownedCritters[1].baseStats.maxHealth = 1
		first.value.selectedTeam[1] = "forged"
		local second = service.GetProfile(601)
		Harness.expect(second.ok)
		Harness.expect(second.value.ownedCritters[1].baseStats.maxHealth > 1)
		Harness.expect(second.value.selectedTeam[1] ~= "forged")
	end)

	Harness.test("ProfileService selected team contains owned stable instances", function()
		local store = Fixtures.MockDataStore.new()
		local service = Fixtures.newService(Fixtures.newRepository(store, "job-a"))
		Harness.expect(service.LoadProfile(602).ok)
		local selected = service.GetSelectedTeam(602)
		Harness.expect(selected.ok)
		Harness.equal(#selected.value, 3)
		for _, critter in selected.value do
			Harness.equal(critter.ownerUserId, 602)
		end
	end)

	Harness.test("failed profile load exposes no writable guest fallback", function()
		local store = Fixtures.MockDataStore.new()
		store.failNext(3)
		local service = Fixtures.newService(Fixtures.newRepository(store, "job-a"))
		local loaded = service.LoadProfile(603)
		Harness.expect(Harness.hasError(loaded, "DATASTORE_UNAVAILABLE"))
		Harness.expect(Harness.hasError(service.GetProfile(603), "PROFILE_NOT_READY"))
		Harness.expect(store.get("player:603") == nil)
	end)
end
