--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")

	local function ids(profile)
		local result = {}
		for _, id in profile.selectedTeam do
			table.insert(result, id)
		end
		return result
	end

	Harness.test("new profile atomically receives one starter team", function()
		local store = Fixtures.MockDataStore.new()
		local repository = Fixtures.newRepository(store, "job-a")
		local loaded = repository.load(101)
		Harness.expect(loaded.ok)
		local profile = loaded.value.profile
		Harness.equal(profile.starterGrantVersion, 1)
		Harness.equal(#profile.selectedTeam, 3)
		local count = 0
		for _, critter in profile.ownedCritters do
			count += 1
			Harness.expect(not critter.tradable)
			Harness.expect(not critter.breeding.breedable)
		end
		Harness.equal(count, 3)
	end)

	Harness.test("rejoin preserves starter IDs and duplicate grants stay blocked", function()
		local store = Fixtures.MockDataStore.new()
		store.replay(true)
		local firstRepository = Fixtures.newRepository(store, "job-a")
		local first = firstRepository.load(101)
		Harness.expect(first.ok)
		local originalIds = ids(first.value.profile)
		Harness.expect(firstRepository.release(first.value).ok)
		local second = Fixtures.newRepository(store, "job-b").load(101)
		Harness.expect(second.ok)
		Harness.deepEqual(ids(second.value.profile), originalIds)
		local count = 0
		for _ in second.value.profile.ownedCritters do
			count += 1
		end
		Harness.equal(count, 3)
	end)

	Harness.test("invalid team and corrupt profile fail without repair or starter grant", function()
		local store = Fixtures.MockDataStore.new()
		local repository = Fixtures.newRepository(store, "job-a")
		local loaded = repository.load(202)
		Harness.expect(loaded.ok)
		Harness.expect(repository.release(loaded.value).ok)
		local record = store.get("player:202")
		record.profile.selectedTeam[2] = record.profile.selectedTeam[1]
		record.profile.starterGrantVersion = 0
		store.set("player:202", record)
		local before = store.get("player:202")
		local rejected = Fixtures.newRepository(store, "job-b").load(202)
		Harness.expect(Harness.hasError(rejected, "INVALID_SELECTED_TEAM"))
		Harness.deepEqual(store.get("player:202"), before)
	end)

	Harness.test("DataStore outage never overwrites existing profile", function()
		local store = Fixtures.MockDataStore.new()
		local repository = Fixtures.newRepository(store, "job-a")
		local loaded = repository.load(303)
		Harness.expect(loaded.ok)
		Harness.expect(repository.release(loaded.value).ok)
		local before = store.get("player:303")
		store.failNext(3)
		local failed = Fixtures.newRepository(store, "job-b").load(303)
		Harness.expect(Harness.hasError(failed, "DATASTORE_UNAVAILABLE"))
		Harness.deepEqual(store.get("player:303"), before)
	end)

	Harness.test("session lock rejects concurrent owner and allows released owner", function()
		local store = Fixtures.MockDataStore.new()
		local firstRepository = Fixtures.newRepository(store, "job-a")
		local first = firstRepository.load(404)
		Harness.expect(first.ok)
		local concurrent = Fixtures.newRepository(store, "job-b").load(404)
		Harness.expect(Harness.hasError(concurrent, "PROFILE_SESSION_ACTIVE"))
		Harness.expect(firstRepository.release(first.value).ok)
		Harness.expect(Fixtures.newRepository(store, "job-b").load(404).ok)
	end)

	Harness.test("expired session lock can be reclaimed", function()
		local store = Fixtures.MockDataStore.new()
		local firstRepository = Fixtures.newRepository(store, "job-a", { now = 100 })
		local first = firstRepository.load(405)
		Harness.expect(first.ok)
		local reclaimed = Fixtures.newRepository(store, "job-b", { now = 500 }).load(405)
		Harness.expect(reclaimed.ok)
		Harness.expect(Harness.hasError(firstRepository.save(first.value), "PROFILE_LOCK_LOST"))
	end)

	Harness.test("save release and reload preserve profile data", function()
		local store = Fixtures.MockDataStore.new()
		local firstRepository = Fixtures.newRepository(store, "job-a")
		local first = firstRepository.load(505)
		Harness.expect(first.ok)
		local firstRevision = first.value.profile.revision
		Harness.expect(firstRepository.save(first.value).ok)
		Harness.expect(first.value.profile.revision > firstRevision)
		local savedIds = ids(first.value.profile)
		Harness.expect(firstRepository.release(first.value).ok)
		local reloaded = Fixtures.newRepository(store, "job-b").load(505)
		Harness.expect(reloaded.ok)
		Harness.deepEqual(ids(reloaded.value.profile), savedIds)
	end)

	Harness.test("migration pipeline applies sequential hook and rejects future schema", function()
		local migrated = Fixtures.Migrations.migrate({ schemaVersion = 0, value = 7 }, 1, {
			[0] = function(profile)
				return { schemaVersion = 1, value = profile.value }
			end,
		})
		Harness.expect(migrated.ok)
		Harness.equal(migrated.value.value, 7)
		local future = Fixtures.Migrations.migrate({ schemaVersion = 2 }, 1, {})
		Harness.expect(Harness.hasError(future, "FUTURE_PROFILE_SCHEMA"))
	end)

	Harness.test("Run 6A profile migrates to inventory schema 2 without ownership loss", function()
		local store = Fixtures.MockDataStore.new()
		local firstRepository = Fixtures.newRepository(store, "migration-source")
		local loaded = firstRepository.load(506)
		Harness.expect(loaded.ok)
		local originalIds = ids(loaded.value.profile)
		Harness.expect(firstRepository.release(loaded.value).ok)
		local record = store.get("player:506")
		record.profile.schemaVersion = 1
		record.profile.inventory = { schemaVersion = 1, itemsById = {} }
		store.set("player:506", record)
		local migrated = Fixtures.newRepository(store, "migration-target").load(506)
		Harness.expect(migrated.ok)
		Harness.equal(migrated.value.profile.schemaVersion, 2)
		Harness.equal(migrated.value.profile.inventory.schemaVersion, 2)
		Harness.deepEqual(ids(migrated.value.profile), originalIds)
	end)
end
