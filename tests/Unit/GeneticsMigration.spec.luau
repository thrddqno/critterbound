--!strict

return function(Harness)
	local Migrations = require("../../src/server/Persistence/ProfileMigrations")
	local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")

	local function legacyProfile()
		local definition = CritterCatalog.getByClass("Stone")
		return {
			schemaVersion = 2,
			userId = 42,
			revision = 9,
			ownedCritters = {
				["critter:legacy"] = {
					schemaVersion = 1,
					id = "critter:legacy",
					definitionId = definition.id,
					ownerUserId = 42,
					appearanceGenome = {
						schemaVersion = 1,
						speciesId = "starter.stone",
						bodyVariantId = "placeholder",
						paletteId = "starter",
						patternId = "placeholder",
					},
					abilityGenome = {
						schemaVersion = 1,
						abilityIds = table.clone(definition.abilityIds),
					},
					baseStats = { maxHealth = 120, attack = 22, defense = 34, speed = 10 },
					acquisition = { source = "STARTER", acquiredAt = 1, sourceVersion = 1 },
					breeding = {
						breedable = false,
						generation = 0,
						parentIds = {},
						successfulBreedCount = 0,
					},
					tradable = false,
					equipmentIds = { "item:charm" },
				},
			},
			selectedTeam = { "critter:legacy" },
			inventory = { schemaVersion = 2, uniqueItemsById = { keep = true } },
		}
	end

	Harness.test("legacy starter migration changes only schema and genomes", function()
		local source = legacyProfile()
		local before = Harness.clone(source)
		local result = Migrations.migrate(source, 3, Migrations.DefaultHooks)
		Harness.expect(result.ok)
		Harness.deepEqual(source, before)
		Harness.equal(result.value.schemaVersion, 3)
		local migrated = result.value.ownedCritters["critter:legacy"]
		Harness.equal(migrated.schemaVersion, 2)
		Harness.equal(migrated.appearanceGenome.schemaVersion, 2)
		Harness.equal(migrated.abilityGenome.schemaVersion, 2)
		Harness.equal(migrated.id, "critter:legacy")
		Harness.equal(migrated.ownerUserId, 42)
		Harness.deepEqual(migrated.baseStats, before.ownedCritters["critter:legacy"].baseStats)
		Harness.deepEqual(migrated.equipmentIds, { "item:charm" })
		Harness.deepEqual(result.value.selectedTeam, { "critter:legacy" })
		Harness.deepEqual(result.value.inventory, before.inventory)
		Harness.equal(result.value.revision, 9)
	end)

	Harness.test("unknown legacy combinations fail closed without input mutation", function()
		local source = legacyProfile()
		source.ownedCritters["critter:legacy"].appearanceGenome.paletteId = "unknown"
		local before = Harness.clone(source)
		local result = Migrations.migrate(source, 3, Migrations.DefaultHooks)
		Harness.expect(Harness.hasError(result, "PROFILE_MIGRATION_FAILED"))
		Harness.deepEqual(source, before)
	end)

	Harness.test("schema 8 migration preserves existing Critters and legacy eggs", function()
		local Schema = require("../../src/server/Persistence/ProfileSchema")
		local source = Schema.create(42, 100)
		source.schemaVersion = 8
		source.eggs["egg:legacy"] = {
			schemaVersion = 1,
			eggId = "egg:legacy",
			marker = "unchanged",
		}
		local before = Harness.clone(source)
		local result = Migrations.migrate(source, 9, Migrations.DefaultHooks)
		Harness.expect(result.ok)
		Harness.deepEqual(source, before)
		Harness.equal(result.value.schemaVersion, 9)
		Harness.deepEqual(result.value.eggs, before.eggs)
		Harness.deepEqual(result.value.ownedCritters, before.ownedCritters)
	end)
end
