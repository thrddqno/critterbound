--!strict

local PlayerDataService = {}

local MAX_RECEIPTS = 64

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

local function identifier(value: any): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function integer(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value % 1 == 0
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

local function fingerprint(kind: string, payload): string?
	if kind == "SET_TEAM" then
		if type(payload) ~= "table" or arrayLength(payload.critterIds) ~= 3 then
			return nil
		end
		for _, id in payload.critterIds do
			if not identifier(id) then
				return nil
			end
		end
		return `{kind}|{table.concat(payload.critterIds, "|")}`
	elseif kind == "EQUIP_ITEM" then
		if
			type(payload) ~= "table"
			or not identifier(payload.critterId)
			or not identifier(payload.instanceId)
		then
			return nil
		end
		return `{kind}|{payload.critterId}|{payload.instanceId}`
	elseif kind == "UNEQUIP_ITEM" then
		if type(payload) ~= "table" or not identifier(payload.critterId) then
			return nil
		end
		return `{kind}|{payload.critterId}`
	end
	return nil
end

local function new(dependencies)
	local deps = dependencies
	local receiptsByUser = {}
	local receiptOrderByUser = {}
	local lastMutationAt = {}
	local activeMutation = {}
	local service = {}

	local function collection(userId: number)
		local profile = deps.profileService.ReadProfile(userId)
		if not profile.ok then
			return profile
		end
		return {
			ok = true,
			value = deps.projector.collection(profile.value, deps.catalog, deps.itemRegistry),
		}
	end

	local function inventory(userId: number)
		return deps.inventoryService.GetInventory(userId)
	end

	local function mutationResponse(userId: number, receipt, duplicate: boolean)
		local collectionResult = collection(userId)
		if not collectionResult.ok then
			return collectionResult
		end
		local inventoryResult = inventory(userId)
		if not inventoryResult.ok then
			return inventoryResult
		end
		return {
			ok = true,
			value = {
				revision = collectionResult.value.revision,
				receipt = clone(receipt),
				duplicate = duplicate,
				collection = collectionResult.value,
				inventory = inventoryResult.value,
			},
		}
	end

	local function remember(userId: number, commandId: string, commandFingerprint: string, response)
		local receipts = receiptsByUser[userId] or {}
		local order = receiptOrderByUser[userId] or {}
		receiptsByUser[userId] = receipts
		receiptOrderByUser[userId] = order
		while #order >= MAX_RECEIPTS do
			receipts[table.remove(order, 1)] = nil
		end
		receipts[commandId] = { fingerprint = commandFingerprint, response = clone(response) }
		table.insert(order, commandId)
	end

	local function mutate(userId: number, request)
		if not identifier(request.commandId) or not integer(request.expectedRevision) then
			return failure("INVALID_COMMAND", "Command ID and expected revision are required")
		end
		local commandFingerprint = fingerprint(request.kind, request.payload)
		if commandFingerprint == nil then
			return failure("INVALID_COMMAND", "Player data command payload is malformed")
		end
		local previous = receiptsByUser[userId] and receiptsByUser[userId][request.commandId]
		if previous ~= nil then
			if previous.fingerprint ~= commandFingerprint then
				return failure("COMMAND_ID_CONFLICT", "Command ID was used for another mutation")
			end
			return mutationResponse(userId, previous.response.value.receipt, true)
		end
		if activeMutation[userId] then
			return failure("COMMAND_IN_PROGRESS", "Another profile command is running")
		end
		local now = deps.clock()
		local previousTime = lastMutationAt[userId]
		if previousTime ~= nil and now - previousTime < deps.mutationInterval then
			return failure("RATE_LIMITED", "Player data request is rate limited")
		end
		activeMutation[userId] = true
		lastMutationAt[userId] = now
		local ok, result = pcall(function()
			if request.kind == "SET_TEAM" then
				return deps.teamService.SetSelectedTeam(
					userId,
					request.payload.critterIds,
					request.expectedRevision
				)
			elseif request.kind == "EQUIP_ITEM" then
				return deps.equipmentService.EquipItem(
					userId,
					request.payload.critterId,
					request.payload.instanceId,
					request.expectedRevision
				)
			end
			return deps.equipmentService.UnequipItem(
				userId,
				request.payload.critterId,
				request.expectedRevision
			)
		end)
		activeMutation[userId] = nil
		if not ok then
			return failure("INTERNAL_ERROR", "Player data mutation failed")
		end
		if not result.ok then
			return result
		end
		if request.kind == "SET_TEAM" then
			deps.invalidateBattle(userId)
		end
		local response = mutationResponse(userId, result.value, false)
		if response.ok then
			remember(userId, request.commandId, commandFingerprint, response)
		end
		return response
	end

	local function handleRequest(userId: number, request)
		if type(request) ~= "table" or request.protocolVersion ~= deps.protocolVersion then
			return failure("INVALID_REQUEST", "Player data request is malformed")
		end
		if request.kind == "GET_COLLECTION" then
			return collection(userId)
		elseif request.kind == "GET_INVENTORY" then
			return inventory(userId)
		elseif
			request.kind == "SET_TEAM"
			or request.kind == "EQUIP_ITEM"
			or request.kind == "UNEQUIP_ITEM"
		then
			return mutate(userId, request)
		end
		return failure("INVALID_REQUEST_KIND", "Unknown player data request")
	end

	function service.removePlayer(userId: number)
		receiptsByUser[userId] = nil
		receiptOrderByUser[userId] = nil
		lastMutationAt[userId] = nil
		activeMutation[userId] = nil
	end

	service.handleRequest = handleRequest
	service.getCollection = collection
	return table.freeze(service)
end

PlayerDataService.new = new
return table.freeze(PlayerDataService)
