--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local PlayerDataService = require("../../src/server/Services/PlayerDataService")
	local ProfileProjector = require("../../src/server/Persistence/ProfileProjector")

	local function setup(userId: number)
		local store = Fixtures.MockDataStore.new()
		local profile = Fixtures.newService(Fixtures.newRepository(store, `player-data-{userId}`))
		Harness.expect(profile.LoadProfile(userId).ok)
		local inventory = Fixtures.newInventoryService(profile)
		local invalidations = 0
		local service = PlayerDataService.new({
			protocolVersion = 2,
			profileService = profile,
			inventoryService = inventory,
			equipmentService = Fixtures.newEquipmentService(profile),
			teamService = Fixtures.newTeamService(profile),
			projector = ProfileProjector,
			catalog = Fixtures.Catalog,
			itemRegistry = Fixtures.ItemRegistry,
			clock = function()
				return 10
			end,
			mutationInterval = 0,
			invalidateBattle = function()
				invalidations += 1
			end,
		})
		return store, profile, inventory, service, function()
			return invalidations
		end
	end

	local function request(kind: string, fields)
		local result = { protocolVersion = 2, kind = kind }
		for key, value in fields or {} do
			result[key] = value
		end
		return result
	end

	Harness.test("collection DTO exposes owned details without private profile state", function()
		local _, _, _, service = setup(831)
		local result = service.handleRequest(831, request("GET_COLLECTION", nil))
		Harness.expect(result.ok)
		Harness.equal(#result.value.critters, 3)
		Harness.equal(#result.value.selectedTeam, 3)
		Harness.expect(result.value.critters[1].displayName ~= nil)
		Harness.expect(result.value.critters[1].baseStats.health > 0)
		Harness.expect(#result.value.critters[1].resolvedAbilityIds, 4)
		Harness.expect(result.value.sessionLock == nil)
		Harness.expect(result.value.inventory == nil)
		Harness.expect(result.value.operationsById == nil)
		Harness.expect(result.value.critters[1].ownerUserId == nil)
		Harness.expect(result.value.critters[1].equipmentIds == nil)
	end)

	Harness.test(
		"player data mutation advances revision and invalidates battle after team save",
		function()
			local _, _, _, service, invalidations = setup(832)
			local before = service.handleRequest(832, request("GET_COLLECTION", nil)).value
			local team = { before.selectedTeam[3], before.selectedTeam[1], before.selectedTeam[2] }
			local response = service.handleRequest(
				832,
				request("SET_TEAM", {
					commandId = "team.command.1",
					expectedRevision = before.revision,
					payload = { critterIds = team },
				})
			)
			Harness.expect(response.ok)
			Harness.equal(response.value.revision, before.revision + 1)
			Harness.deepEqual(response.value.collection.selectedTeam, team)
			Harness.equal(invalidations(), 1)
		end
	)

	Harness.test("duplicate command precedes stale check and conflicting reuse rejects", function()
		local _, _, _, service, invalidations = setup(833)
		local before = service.handleRequest(833, request("GET_COLLECTION", nil)).value
		local team = { before.selectedTeam[2], before.selectedTeam[3], before.selectedTeam[1] }
		local command = request("SET_TEAM", {
			commandId = "team.command.duplicate",
			expectedRevision = before.revision,
			payload = { critterIds = team },
		})
		Harness.expect(service.handleRequest(833, command).ok)
		local duplicate = service.handleRequest(833, command)
		Harness.expect(duplicate.ok and duplicate.value.duplicate)
		Harness.equal(invalidations(), 1)
		command.payload = { critterIds = { team[3], team[2], team[1] } }
		Harness.expect(Harness.hasError(service.handleRequest(833, command), "COMMAND_ID_CONFLICT"))
	end)

	Harness.test("duplicate receipt returns current DTO after later mutation", function()
		local _, _, _, service = setup(837)
		local before = service.handleRequest(837, request("GET_COLLECTION", nil)).value
		local firstTeam = { before.selectedTeam[2], before.selectedTeam[3], before.selectedTeam[1] }
		local first = request("SET_TEAM", {
			commandId = "team.command.first",
			expectedRevision = before.revision,
			payload = { critterIds = firstTeam },
		})
		local firstResponse = service.handleRequest(837, first)
		Harness.expect(firstResponse.ok)
		local secondTeam = { firstTeam[2], firstTeam[3], firstTeam[1] }
		Harness.expect(service.handleRequest(
			837,
			request("SET_TEAM", {
				commandId = "team.command.second",
				expectedRevision = firstResponse.value.revision,
				payload = { critterIds = secondTeam },
			})
		).ok)
		local duplicate = service.handleRequest(837, first)
		Harness.expect(duplicate.ok and duplicate.value.duplicate)
		Harness.deepEqual(duplicate.value.collection.selectedTeam, secondTeam)
	end)

	Harness.test("stale malformed and invalid commands never mutate profile", function()
		local _, profile, _, service = setup(834)
		local before = profile.ReadProfile(834).value
		local stale = service.handleRequest(
			834,
			request("SET_TEAM", {
				commandId = "team.command.stale",
				expectedRevision = before.revision + 1,
				payload = { critterIds = table.clone(before.selectedTeam) },
			})
		)
		Harness.expect(Harness.hasError(stale, "STALE_PROFILE"))
		local malformed = service.handleRequest(
			834,
			request("EQUIP_ITEM", {
				commandId = "equip.command.bad",
				expectedRevision = before.revision,
				payload = { critterId = before.selectedTeam[1] },
			})
		)
		Harness.expect(Harness.hasError(malformed, "INVALID_COMMAND"))
		Harness.deepEqual(profile.ReadProfile(834).value, before)
	end)

	Harness.test(
		"inventory DTO lists descriptions and equipment mutations refresh both DTOs",
		function()
			local _, profile, inventory, service = setup(835)
			local itemId = inventory.AddItem(835, {
				definitionId = "equipment.training_charm",
				quantity = 1,
				operationId = "grant.player-data.charm",
				source = "TEST",
			}).value.instanceIds[1]
			local iron = inventory.AddItem(835, {
				definitionId = "material.iron_shard",
				quantity = 4,
				operationId = "grant.player-data.iron",
				source = "TEST",
			})
			Harness.expect(iron.ok)
			local dto = service.handleRequest(835, request("GET_INVENTORY", nil)).value
			Harness.equal(dto.stacks[1].quantity, 4)
			Harness.expect(#dto.stacks[1].description > 0)
			Harness.expect(#dto.uniqueItems[1].description > 0)
			local current = service.handleRequest(835, request("GET_COLLECTION", nil)).value
			local critterId = profile.ReadProfile(835).value.selectedTeam[1]
			local equipped = service.handleRequest(
				835,
				request("EQUIP_ITEM", {
					commandId = "equip.command.1",
					expectedRevision = current.revision,
					payload = { critterId = critterId, instanceId = itemId },
				})
			)
			Harness.expect(equipped.ok)
			Harness.equal(equipped.value.inventory.uniqueItems[1].equippedCritterId, critterId)
			Harness.equal(equipped.value.collection.critters[1].equippedItem.instanceId, itemId)
			local unequipped = service.handleRequest(
				835,
				request("UNEQUIP_ITEM", {
					commandId = "unequip.command.1",
					expectedRevision = equipped.value.revision,
					payload = { critterId = critterId },
				})
			)
			Harness.expect(unequipped.ok)
			Harness.expect(unequipped.value.inventory.uniqueItems[1].equippedCritterId == nil)
		end
	)

	Harness.test("failed profile load blocks player data reads and writes", function()
		local store = Fixtures.MockDataStore.new()
		store.failNext(3)
		local profile = Fixtures.newService(Fixtures.newRepository(store, "player-data-failed"))
		Harness.expect(not profile.LoadProfile(836).ok)
		local service = PlayerDataService.new({
			protocolVersion = 2,
			profileService = profile,
			inventoryService = Fixtures.newInventoryService(profile),
			equipmentService = Fixtures.newEquipmentService(profile),
			teamService = Fixtures.newTeamService(profile),
			projector = ProfileProjector,
			catalog = Fixtures.Catalog,
			itemRegistry = Fixtures.ItemRegistry,
			clock = function()
				return 0
			end,
			mutationInterval = 0,
			invalidateBattle = function() end,
		})
		Harness.expect(
			Harness.hasError(
				service.handleRequest(836, request("GET_COLLECTION", nil)),
				"PROFILE_NOT_READY"
			)
		)
	end)
end
