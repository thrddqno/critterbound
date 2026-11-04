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
		for _, instance in record.profile.ownedCritters do
			local definition = Fixtures.Catalog.getById(instance.definitionId)
			instance.schemaVersion = 1
			instance.baseStats = {
				maxHealth = 100,
				attack = 20,
				defense = 20,
				speed = definition.baseStats.speed,
			}
			instance.appearanceGenome = {
				schemaVersion = 1,
				speciesId = `starter.{string.lower(definition.class)}`,
				bodyVariantId = "placeholder",
				paletteId = "starter",
				patternId = "placeholder",
			}
			instance.abilityGenome = {
				schemaVersion = 1,
				abilityIds = table.clone(definition.abilityIds),
			}
		end
		store.set("player:506", record)
		local migrated = Fixtures.newRepository(store, "migration-target").load(506)
		Harness.expect(migrated.ok)
		Harness.equal(migrated.value.profile.schemaVersion, 8)
		Harness.equal(migrated.value.profile.inventory.schemaVersion, 2)
		Harness.equal(migrated.value.profile.contracts.schemaVersion, 2)
		Harness.deepEqual(ids(migrated.value.profile), originalIds)
	end)

	Harness.test(
		"v7 Critter stats migrate to class Health without reinterpreting maxHealth",
		function()
			local store = Fixtures.MockDataStore.new()
			local sourceRepository = Fixtures.newRepository(store, "stats-source")
			local loaded = sourceRepository.load(507)
			Harness.expect(loaded.ok)
			Harness.expect(sourceRepository.release(loaded.value).ok)

			local record = store.get("player:507")
			record.profile.schemaVersion = 7
			for _, instance in record.profile.ownedCritters do
				instance.schemaVersion = 2
				instance.baseStats = {
					maxHealth = 999,
					attack = 77,
					defense = 66,
					speed = 55,
				}
			end
			store.set("player:507", record)

			local migrated = Fixtures.newRepository(store, "stats-target").load(507)
			Harness.expect(migrated.ok)
			Harness.equal(migrated.value.profile.schemaVersion, 8)
			for _, instance in migrated.value.profile.ownedCritters do
				local definition = Fixtures.Catalog.getById(instance.definitionId)
				Harness.equal(instance.schemaVersion, 3)
				Harness.deepEqual(instance.baseStats, definition.baseStats)
				Harness.expect(instance.baseStats.maxHealth == nil)
			end
		end
	)
end
