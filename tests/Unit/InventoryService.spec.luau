--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")

	local function setup(userId: number, replay: boolean?)
		local store = Fixtures.MockDataStore.new()
		store.replay(replay == true)
		local profileService =
			Fixtures.newService(Fixtures.newRepository(store, `inventory-{userId}`))
		Harness.expect(profileService.LoadProfile(userId).ok)
		return store, profileService, Fixtures.newInventoryService(profileService)
	end

	Harness.test("InventoryService adds and removes stackable materials", function()
		local _, _, service = setup(801)
		local added = service.AddItem(801, {
			definitionId = "material.iron_shard",
			quantity = 10,
			operationId = "grant.material.1",
			source = "TEST",
		})
		Harness.expect(added.ok)
		Harness.expect(
			service.HasItem(801, { definitionId = "material.iron_shard", quantity = 10 }).value
		)
		Harness.expect(
			service.RemoveItem(801, { definitionId = "material.iron_shard", quantity = 4 }).ok
		)
		local inventory = service.GetInventory(801)
		Harness.expect(inventory.ok)
		Harness.equal(inventory.value.stacks[1].quantity, 6)
	end)

	Harness.test(
		"InventoryService rejects invalid quantities stack overflow and insufficient removal",
		function()
			local _, _, service = setup(802)
			local request = {
				definitionId = "consumable.training_tonic",
				quantity = 20,
				operationId = "grant.tonic.max",
				source = "TEST",
			}
			Harness.expect(service.AddItem(802, request).ok)
			request.operationId = "grant.tonic.overflow"
			request.quantity = 1
			Harness.expect(Harness.hasError(service.AddItem(802, request), "STACK_LIMIT_EXCEEDED"))
			request.operationId = "grant.tonic.zero"
			request.quantity = 0
			Harness.expect(Harness.hasError(service.AddItem(802, request), "INVALID_ITEM_GRANT"))
			Harness.expect(
				Harness.hasError(
					service.RemoveItem(
						802,
						{ definitionId = "consumable.training_tonic", quantity = 21 }
					),
					"INSUFFICIENT_ITEM_QUANTITY"
				)
			)
		end
	)

	Harness.test("unique grants create immutable IDs and replay idempotently", function()
		local _, _, service = setup(803, true)
		local request = {
			definitionId = "equipment.training_charm",
			quantity = 1,
			operationId = "grant.charm.once",
			source = "TEST",
		}
		local first = service.AddItem(803, request)
		local duplicate = service.AddItem(803, request)
		Harness.expect(first.ok and duplicate.ok)
		Harness.deepEqual(first.value, duplicate.value)
		Harness.equal(#first.value.instanceIds, 1)
		local inventory = service.GetInventory(803)
		Harness.equal(#inventory.value.uniqueItems, 1)
		Harness.equal(inventory.value.uniqueItems[1].instanceId, first.value.instanceIds[1])
		local conflict = service.AddItem(803, {
			definitionId = "collectible.training_relic",
			quantity = 1,
			operationId = "grant.charm.once",
			source = "TEST",
		})
		Harness.expect(Harness.hasError(conflict, "OPERATION_ID_CONFLICT"))
	end)

	Harness.test("InventoryService rejects unknown item definitions", function()
		local _, _, service = setup(804)
		local result = service.AddItem(804, {
			definitionId = "item.missing",
			quantity = 1,
			operationId = "grant.missing",
			source = "TEST",
		})
		Harness.expect(Harness.hasError(result, "UNKNOWN_ITEM_DEFINITION"))
	end)

	Harness.test("failed DataStore mutation preserves cached and stored inventory", function()
		local store, _, service = setup(805)
		Harness.expect(service.AddItem(805, {
			definitionId = "material.iron_shard",
			quantity = 2,
			operationId = "grant.before.outage",
			source = "TEST",
		}).ok)
		local before = store.get("player:805")
		store.failNext(3)
		local failed = service.AddItem(805, {
			definitionId = "material.iron_shard",
			quantity = 3,
			operationId = "grant.during.outage",
			source = "TEST",
		})
		Harness.expect(Harness.hasError(failed, "DATASTORE_UNAVAILABLE"))
		Harness.deepEqual(store.get("player:805"), before)
		Harness.equal(service.GetInventory(805).value.stacks[1].quantity, 2)
	end)

	Harness.test("inventory persists through release and reload", function()
		local store, profileService, service = setup(806)
		Harness.expect(service.AddItem(806, {
			definitionId = "material.iron_shard",
			quantity = 7,
			operationId = "grant.persist",
			source = "TEST",
		}).ok)
		Harness.expect(profileService.ReleaseProfile(806).ok)
		local reloadedProfile =
			Fixtures.newService(Fixtures.newRepository(store, "inventory-reload"))
		Harness.expect(reloadedProfile.LoadProfile(806).ok)
		local reloadedInventory = Fixtures.newInventoryService(reloadedProfile).GetInventory(806)
		Harness.equal(reloadedInventory.value.stacks[1].quantity, 7)
	end)

	Harness.test("fixture ItemRegistry passes static validation", function()
		Harness.expect(Fixtures.InventoryValidator.validateRegistry(Fixtures.ItemRegistry).ok)
		Harness.expect(Harness.hasError(
			Fixtures.InventoryValidator.validateDefinition({
				schemaVersion = 1,
				id = "broken.item",
				displayName = "Broken",
				description = "Invalid test definition.",
				category = "MATERIAL",
				rarity = "COMMON",
				stackable = true,
				maxStack = 0,
				modifiers = {},
				tradeable = false,
			}),
			"INVALID_ITEM_DEFINITION"
		))
	end)

	Harness.test("concurrent inventory mutations serialize without lost quantities", function()
		local store = Fixtures.MockDataStore.new()
		local profile = Fixtures.newService(Fixtures.newRepository(store, "inventory-concurrent"), {
			wait = coroutine.yield,
		})
		Harness.expect(profile.LoadProfile(807).ok)
		store.yieldOnUpdate(true, coroutine.yield)
		local service = Fixtures.newInventoryService(profile)
		local results = {}
		local workers = {}
		for index, quantity in { 2, 3 } do
			workers[index] = coroutine.create(function()
				results[index] = service.AddItem(807, {
					definitionId = "material.iron_shard",
					quantity = quantity,
					operationId = `grant.concurrent.{index}`,
					source = "TEST",
				})
			end)
		end
		Harness.expect(coroutine.resume(workers[1]))
		Harness.expect(coroutine.resume(workers[2]))
		Harness.expect(coroutine.resume(workers[1]))
		Harness.expect(coroutine.resume(workers[2]))
		Harness.expect(coroutine.resume(workers[2]))
		Harness.equal(coroutine.status(workers[1]), "dead")
		Harness.equal(coroutine.status(workers[2]), "dead")
		Harness.expect(results[1].ok and results[2].ok)
		Harness.equal(service.GetInventory(807).value.stacks[1].quantity, 5)
	end)
end
