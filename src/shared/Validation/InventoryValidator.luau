--!strict

local InventoryValidator = {}

local MAX_OPERATIONS = 128
local VALID_CATEGORIES = {
	MATERIAL = true,
	CATALYST = true,
	CONSUMABLE = true,
	EQUIPMENT = true,
	COLLECTIBLE = true,
}
local VALID_RARITIES = { COMMON = true, UNCOMMON = true, RARE = true, EPIC = true }

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function isInteger(value: any, minimum: number): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= minimum
		and value % 1 == 0
end

local function isIdentifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function arrayLength(value: any): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	local maximum = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil
		end
		count += 1
		maximum = math.max(maximum, key)
	end
	return if count == maximum then count else nil
end

local function validateDefinition(definition: any)
	if type(definition) ~= "table" or definition.schemaVersion ~= 1 then
		return failure("INVALID_ITEM_DEFINITION", "Item definition is malformed", nil)
	end
	if
		not isIdentifier(definition.id)
		or type(definition.displayName) ~= "string"
		or #definition.displayName < 1
		or #definition.displayName > 48
		or type(definition.description) ~= "string"
		or #definition.description < 1
		or #definition.description > 240
		or not VALID_CATEGORIES[definition.category]
		or not VALID_RARITIES[definition.rarity]
		or type(definition.stackable) ~= "boolean"
		or not isInteger(definition.maxStack, 1)
		or type(definition.modifiers) ~= "table"
		or type(definition.tradeable) ~= "boolean"
	then
		return failure(
			"INVALID_ITEM_DEFINITION",
			"Item definition fields are invalid",
			definition.id
		)
	end
	if
		definition.stackable
		and (definition.equipmentSlot ~= nil or next(definition.modifiers) ~= nil)
	then
		return failure(
			"INVALID_ITEM_DEFINITION",
			"Stackable items cannot be equipment",
			definition.id
		)
	end
	if definition.category == "EQUIPMENT" then
		if definition.stackable or definition.equipmentSlot ~= "CRITTER" then
			return failure(
				"INVALID_ITEM_DEFINITION",
				"Equipment must use CRITTER slot",
				definition.id
			)
		end
	elseif definition.equipmentSlot ~= nil then
		return failure(
			"INVALID_ITEM_DEFINITION",
			"Non-equipment item has equipment slot",
			definition.id
		)
	end
	for modifier, value in definition.modifiers do
		if
			not isIdentifier(modifier)
			or type(value) ~= "number"
			or value ~= value
			or value == math.huge
			or value == -math.huge
		then
			return failure("INVALID_ITEM_MODIFIER", "Item modifier is invalid", definition.id)
		end
	end
	return { ok = true, value = true }
end

local function validateRegistry(registry)
	local definitions = registry.allById()
	for id, definition in definitions do
		if id ~= definition.id then
			return failure("INVALID_ITEM_DEFINITION", "Registry key does not match definition", id)
		end
		local result = validateDefinition(definition)
		if not result.ok then
			return result
		end
	end
	return { ok = true, value = true }
end

local function validateInventory(inventory: any, userId: number, ownedCritters: any, registry)
	if
		type(inventory) ~= "table"
		or inventory.schemaVersion ~= 2
		or type(inventory.stacksByDefinitionId) ~= "table"
		or type(inventory.uniqueItemsById) ~= "table"
		or type(inventory.operationsById) ~= "table"
	then
		return failure("INVALID_INVENTORY", "Inventory schema is malformed", "inventory")
	end
	local operationCount = arrayLength(inventory.operationOrder)
	if operationCount == nil or operationCount > MAX_OPERATIONS then
		return failure(
			"INVALID_INVENTORY_OPERATIONS",
			"Inventory operation order is invalid",
			"inventory.operationOrder"
		)
	end

	for definitionId, quantity in inventory.stacksByDefinitionId do
		local definition = registry.getById(definitionId)
		if definition == nil or not definition.stackable then
			return failure(
				"INVALID_ITEM_DEFINITION",
				"Stack references non-stackable definition",
				`inventory.stacksByDefinitionId.{tostring(definitionId)}`
			)
		end
		if not isInteger(quantity, 1) or quantity > definition.maxStack then
			return failure(
				"INVALID_ITEM_QUANTITY",
				"Stack quantity is outside definition limits",
				`inventory.stacksByDefinitionId.{definitionId}`
			)
		end
	end

	for instanceId, item in inventory.uniqueItemsById do
		if type(item) ~= "table" or item.schemaVersion ~= 1 or item.instanceId ~= instanceId then
			return failure(
				"INVALID_UNIQUE_ITEM",
				"Unique item record is malformed",
				`inventory.uniqueItemsById.{tostring(instanceId)}`
			)
		end
		local definition = registry.getById(item.definitionId)
		if
			not isIdentifier(instanceId)
			or definition == nil
			or definition.stackable
			or item.ownerUserId ~= userId
		then
			return failure(
				"INVALID_UNIQUE_ITEM",
				"Unique item identity or owner is invalid",
				`inventory.uniqueItemsById.{instanceId}`
			)
		end
		local metadata = item.metadata
		if
			type(metadata) ~= "table"
			or not isIdentifier(metadata.source)
			or not isInteger(metadata.acquiredAt, 0)
		then
			return failure(
				"INVALID_ITEM_METADATA",
				"Unique item metadata is invalid",
				`inventory.uniqueItemsById.{instanceId}.metadata`
			)
		end
		local equipment = item.equipment
		if type(equipment) ~= "table" then
			return failure(
				"INVALID_EQUIPMENT_STATE",
				"Equipment state is missing",
				`inventory.uniqueItemsById.{instanceId}.equipment`
			)
		end
		local critterId = equipment.equippedCritterId
		if critterId ~= nil then
			local critter = ownedCritters[critterId]
			if
				definition.equipmentSlot ~= "CRITTER"
				or critter == nil
				or critter.ownerUserId ~= userId
			then
				return failure(
					"INVALID_EQUIPMENT_STATE",
					"Equipped item references invalid Critter",
					`inventory.uniqueItemsById.{instanceId}.equipment`
				)
			end
			if #critter.equipmentIds ~= 1 or critter.equipmentIds[1] ~= instanceId then
				return failure(
					"ORPHAN_EQUIPMENT_REFERENCE",
					"Equipment references are not bidirectional",
					instanceId
				)
			end
		end
	end

	for critterId, critter in ownedCritters do
		local equipmentCount = arrayLength(critter.equipmentIds)
		if equipmentCount == nil or equipmentCount > 1 then
			return failure(
				"INVALID_EQUIPMENT_STATE",
				"Critter supports at most one equipment item",
				`ownedCritters.{critterId}.equipmentIds`
			)
		end
		if equipmentCount == 1 then
			local item = inventory.uniqueItemsById[critter.equipmentIds[1]]
			if item == nil or item.equipment.equippedCritterId ~= critterId then
				return failure(
					"ORPHAN_EQUIPMENT_REFERENCE",
					"Critter equipment reference is orphaned",
					`ownedCritters.{critterId}.equipmentIds[1]`
				)
			end
		end
	end

	local seenOperations = {}
	for index, operationId in inventory.operationOrder do
		if
			not isIdentifier(operationId)
			or seenOperations[operationId]
			or inventory.operationsById[operationId] == nil
		then
			return failure(
				"INVALID_INVENTORY_OPERATIONS",
				"Operation order contains invalid receipt",
				`inventory.operationOrder[{index}]`
			)
		end
		seenOperations[operationId] = true
	end
	for operationId, receipt in inventory.operationsById do
		local receiptDefinition = if type(receipt) == "table"
			then registry.getById(receipt.definitionId)
			else nil
		local receiptInstanceCount = if type(receipt) == "table"
			then arrayLength(receipt.instanceIds)
			else nil
		if
			not seenOperations[operationId]
			or type(receipt) ~= "table"
			or receipt.kind ~= "ADD_ITEM"
			or not isIdentifier(receipt.definitionId)
			or receiptDefinition == nil
			or not isInteger(receipt.quantity, 1)
			or receiptInstanceCount == nil
			or (receiptDefinition.stackable and receiptInstanceCount ~= 0)
			or (not receiptDefinition.stackable and receiptInstanceCount ~= receipt.quantity)
		then
			return failure(
				"INVALID_INVENTORY_OPERATIONS",
				"Inventory receipt is malformed",
				`inventory.operationsById.{tostring(operationId)}`
			)
		end
		for index, instanceId in receipt.instanceIds do
			if not isIdentifier(instanceId) then
				return failure(
					"INVALID_INVENTORY_OPERATIONS",
					"Inventory receipt instance ID is invalid",
					`inventory.operationsById.{operationId}.instanceIds[{index}]`
				)
			end
		end
	end
	return { ok = true, value = true }
end

InventoryValidator.MaxOperations = MAX_OPERATIONS
InventoryValidator.validateDefinition = validateDefinition
InventoryValidator.validateRegistry = validateRegistry
InventoryValidator.validateInventory = validateInventory
return table.freeze(InventoryValidator)
