--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")

	local function setup(userId: number)
		local store = Fixtures.MockDataStore.new()
		local profile = Fixtures.newService(Fixtures.newRepository(store, `equipment-{userId}`))
		Harness.expect(profile.LoadProfile(userId).ok)
		return store,
			profile,
			Fixtures.newInventoryService(profile),
			Fixtures.newEquipmentService(profile)
	end

	local function grant(service, userId: number, operationId: string)
		local result = service.AddItem(userId, {
			definitionId = "equipment.training_charm",
			quantity = 1,
			operationId = operationId,
			source = "TEST",
		})
		assert(result.ok, "Fixture equipment grant must succeed")
		return result.value.instanceIds[1]
	end

	Harness.test("EquipmentService equips and unequips owned unique item", function()
		local _, profile, inventory, equipment = setup(811)
		local critterId = profile.GetProfile(811).value.selectedTeam[1]
		local itemId = grant(inventory, 811, "grant.equip.1")
		Harness.expect(equipment.EquipItem(811, critterId, itemId).ok)
		Harness.equal(equipment.GetEquipment(811).value[1].instanceId, itemId)
		Harness.expect(equipment.UnequipItem(811, critterId).ok)
		Harness.equal(#equipment.GetEquipment(811).value, 0)
	end)

	Harness.test("occupied Critter slot atomically swaps equipment", function()
		local _, profile, inventory, equipment = setup(812)
		local critterId = profile.GetProfile(812).value.selectedTeam[1]
		local firstId = grant(inventory, 812, "grant.swap.1")
		local secondId = grant(inventory, 812, "grant.swap.2")
		Harness.expect(equipment.EquipItem(812, critterId, firstId).ok)
		local swapped = equipment.EquipItem(812, critterId, secondId)
		Harness.expect(swapped.ok)
		Harness.equal(swapped.value.swappedInstanceId, firstId)
		local dto = inventory.GetInventory(812).value
		local states = {}
		for _, item in dto.uniqueItems do
			states[item.instanceId] = item.equippedCritterId
		end
		Harness.expect(states[firstId] == nil)
		Harness.equal(states[secondId], critterId)
	end)

	Harness.test("same item cannot equip to multiple Critters", function()
		local _, profile, inventory, equipment = setup(813)
		local team = profile.GetProfile(813).value.selectedTeam
		local itemId = grant(inventory, 813, "grant.double")
		Harness.expect(equipment.EquipItem(813, team[1], itemId).ok)
		Harness.expect(
			Harness.hasError(equipment.EquipItem(813, team[2], itemId), "ITEM_ALREADY_EQUIPPED")
		)
	end)

	Harness.test("equipped unique item cannot be removed", function()
		local _, profile, inventory, equipment = setup(814)
		local critterId = profile.GetProfile(814).value.selectedTeam[1]
		local itemId = grant(inventory, 814, "grant.remove.block")
		Harness.expect(equipment.EquipItem(814, critterId, itemId).ok)
		Harness.expect(
			Harness.hasError(inventory.RemoveItem(814, { instanceId = itemId }), "ITEM_EQUIPPED")
		)
	end)

	Harness.test("non-equipment and foreign ownership are rejected", function()
		local _, profile, inventory, equipment = setup(815)
		local critterId = profile.GetProfile(815).value.selectedTeam[1]
		local relic = inventory.AddItem(815, {
			definitionId = "collectible.training_relic",
			quantity = 1,
			operationId = "grant.relic",
			source = "TEST",
		}).value.instanceIds[1]
		Harness.expect(
			Harness.hasError(equipment.EquipItem(815, critterId, relic), "ITEM_NOT_EQUIPMENT")
		)
		Harness.expect(
			Harness.hasError(
				equipment.EquipItem(815, "foreign-critter", relic),
				"CRITTER_NOT_OWNED"
			)
		)
		Harness.expect(
			Harness.hasError(equipment.EquipItem(815, critterId, "foreign-item"), "ITEM_NOT_OWNED")
		)
	end)

	Harness.test("equipment persists through profile release and reload", function()
		local store, profile, inventory, equipment = setup(816)
		local critterId = profile.GetProfile(816).value.selectedTeam[1]
		local itemId = grant(inventory, 816, "grant.persist.equipment")
		Harness.expect(equipment.EquipItem(816, critterId, itemId).ok)
		Harness.expect(profile.ReleaseProfile(816).ok)
		local reloadedProfile =
			Fixtures.newService(Fixtures.newRepository(store, "equipment-reload"))
		Harness.expect(reloadedProfile.LoadProfile(816).ok)
		local reloaded = Fixtures.newEquipmentService(reloadedProfile).GetEquipment(816)
		Harness.expect(reloaded.ok)
		Harness.equal(reloaded.value[1].instanceId, itemId)
		Harness.equal(reloaded.value[1].critterId, critterId)
	end)
end
