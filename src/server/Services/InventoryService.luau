--!strict

local InventoryService = {}

local function clone<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[clone(key)] = clone(child)
	end
	return result :: any
end

local function failure(code: string, message: string)
	return { ok = false, errors = { { code = code, message = message } } }
end

local function positiveInteger(value: any): boolean
	return type(value) == "number" and value == value and value >= 1 and value % 1 == 0
end

local function identifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function projectInventory(profile, registry)
	local stacks = {}
	for definitionId, quantity in profile.inventory.stacksByDefinitionId do
		local definition = registry.getById(definitionId)
		table.insert(stacks, {
			definitionId = definitionId,
			quantity = quantity,
			displayName = definition.displayName,
			description = definition.description,
			category = definition.category,
			rarity = definition.rarity,
			maxStack = definition.maxStack,
			tradeable = definition.tradeable,
		})
	end
	table.sort(stacks, function(a, b)
		return a.definitionId < b.definitionId
	end)
	local uniqueItems = {}
	for _, item in profile.inventory.uniqueItemsById do
		local definition = registry.getById(item.definitionId)
		table.insert(uniqueItems, {
			instanceId = item.instanceId,
			definitionId = item.definitionId,
			displayName = definition.displayName,
			description = definition.description,
			category = definition.category,
			rarity = definition.rarity,
			equipmentSlot = definition.equipmentSlot,
			modifiers = clone(definition.modifiers),
			tradeable = definition.tradeable,
			metadata = clone(item.metadata),
			equippedCritterId = item.equipment.equippedCritterId,
		})
	end
	table.sort(uniqueItems, function(a, b)
		return a.instanceId < b.instanceId
	end)
	return {
		schemaVersion = 1,
		revision = profile.revision,
		stacks = stacks,
		uniqueItems = uniqueItems,
	}
end

local function new(dependencies)
	local deps = dependencies
	local service = {}

	local function validateInventory(userId: number)
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		return deps.validator.validateInventory(
			snapshot.value.inventory,
			userId,
			snapshot.value.ownedCritters,
			deps.registry
		)
	end

	local function getInventory(userId: number)
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		return { ok = true, value = projectInventory(snapshot.value, deps.registry) }
	end

	local function addItem(userId: number, request)
		if
			type(request) ~= "table"
			or not identifier(request.definitionId)
			or not positiveInteger(request.quantity)
			or not identifier(request.operationId)
			or not identifier(request.source)
		then
			return failure("INVALID_ITEM_GRANT", "Item grant request is malformed")
		end
		local definition = deps.registry.getById(request.definitionId)
		if definition == nil then
			return failure("UNKNOWN_ITEM_DEFINITION", "Item definition does not exist")
		end
		if not definition.stackable and request.quantity > deps.maxUniqueBatch then
			return failure("INVALID_ITEM_QUANTITY", "Unique item grant exceeds batch limit")
		end
		local preparedIds = {}
		if not definition.stackable then
			for _ = 1, request.quantity do
				table.insert(preparedIds, `item:{deps.generateId()}`)
			end
		end
		local acquiredAt = deps.clock()
		return deps.profileService.UpdateProfile(userId, function(profile)
			local inventory = profile.inventory
			local previous = inventory.operationsById[request.operationId]
			if previous ~= nil then
				if
					previous.definitionId ~= request.definitionId
					or previous.quantity ~= request.quantity
				then
					return failure(
						"OPERATION_ID_CONFLICT",
						"Operation ID was used for another grant"
					)
				end
				return { ok = true, value = clone(previous) }
			end

			if definition.stackable then
				local current = inventory.stacksByDefinitionId[definition.id] or 0
				if current + request.quantity > definition.maxStack then
					return failure("STACK_LIMIT_EXCEEDED", "Item stack would exceed maxStack")
				end
				inventory.stacksByDefinitionId[definition.id] = current + request.quantity
			else
				for _, instanceId in preparedIds do
					if inventory.uniqueItemsById[instanceId] ~= nil then
						return failure(
							"DUPLICATE_UNIQUE_ITEM",
							"Generated unique item ID already exists"
						)
					end
					inventory.uniqueItemsById[instanceId] = {
						schemaVersion = 1,
						instanceId = instanceId,
						definitionId = definition.id,
						ownerUserId = userId,
						metadata = { source = request.source, acquiredAt = acquiredAt },
						equipment = { equippedCritterId = nil },
					}
				end
			end

			while #inventory.operationOrder >= deps.validator.MaxOperations do
				local expiredId = table.remove(inventory.operationOrder, 1)
				inventory.operationsById[expiredId] = nil
			end
			local receipt = {
				kind = "ADD_ITEM",
				definitionId = definition.id,
				quantity = request.quantity,
				instanceIds = clone(preparedIds),
			}
			inventory.operationsById[request.operationId] = receipt
			table.insert(inventory.operationOrder, request.operationId)
			return { ok = true, value = clone(receipt) }
		end)
	end

	local function removeItem(userId: number, request)
		if type(request) ~= "table" then
			return failure("INVALID_ITEM_REMOVAL", "Item removal request is malformed")
		end
		if request.instanceId ~= nil then
			if
				not identifier(request.instanceId)
				or request.definitionId ~= nil
				or request.quantity ~= nil
			then
				return failure("INVALID_ITEM_REMOVAL", "Unique removal requires only instanceId")
			end
			return deps.profileService.UpdateProfile(userId, function(profile)
				local item = profile.inventory.uniqueItemsById[request.instanceId]
				if item == nil or item.ownerUserId ~= userId then
					return failure("ITEM_NOT_OWNED", "Unique item is not owned")
				end
				if item.equipment.equippedCritterId ~= nil then
					return failure("ITEM_EQUIPPED", "Equipped item cannot be removed")
				end
				profile.inventory.uniqueItemsById[request.instanceId] = nil
				return { ok = true, value = { removed = true, instanceId = request.instanceId } }
			end)
		end
		if not identifier(request.definitionId) or not positiveInteger(request.quantity) then
			return failure(
				"INVALID_ITEM_REMOVAL",
				"Stack removal requires definitionId and positive quantity"
			)
		end
		local definition = deps.registry.getById(request.definitionId)
		if definition == nil then
			return failure("UNKNOWN_ITEM_DEFINITION", "Item definition does not exist")
		end
		if not definition.stackable then
			return failure("INVALID_ITEM_REMOVAL", "Unique items require instanceId removal")
		end
		return deps.profileService.UpdateProfile(userId, function(profile)
			local current = profile.inventory.stacksByDefinitionId[definition.id] or 0
			if current < request.quantity then
				return failure("INSUFFICIENT_ITEM_QUANTITY", "Inventory has insufficient quantity")
			end
			local remaining = current - request.quantity
			profile.inventory.stacksByDefinitionId[definition.id] = if remaining == 0
				then nil
				else remaining
			return {
				ok = true,
				value = { definitionId = definition.id, quantity = request.quantity },
			}
		end)
	end

	local function hasItem(userId: number, request)
		if type(request) ~= "table" then
			return failure("INVALID_ITEM_QUERY", "Item query is malformed")
		end
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		if request.instanceId ~= nil then
			local item = snapshot.value.inventory.uniqueItemsById[request.instanceId]
			return { ok = true, value = item ~= nil and item.ownerUserId == userId }
		end
		if not identifier(request.definitionId) or not positiveInteger(request.quantity) then
			return failure(
				"INVALID_ITEM_QUERY",
				"Stack query requires definitionId and positive quantity"
			)
		end
		local definition = deps.registry.getById(request.definitionId)
		if definition == nil or not definition.stackable then
			return failure("UNKNOWN_ITEM_DEFINITION", "Stackable item definition does not exist")
		end
		return {
			ok = true,
			value = (snapshot.value.inventory.stacksByDefinitionId[request.definitionId] or 0)
				>= request.quantity,
		}
	end

	service.AddItem = addItem
	service.RemoveItem = removeItem
	service.GetInventory = getInventory
	service.HasItem = hasItem
	service.ValidateInventory = validateInventory
	return table.freeze(service)
end

InventoryService.new = new
return table.freeze(InventoryService)
