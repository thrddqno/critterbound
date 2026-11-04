--!strict

local ProfileService = {}

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

local function isIdentifier(value): boolean
	return type(value) == "string"
		and #value >= 1
		and #value <= 96
		and string.match(value, "^[%w][%w_.:%-]*$") ~= nil
end

local function new(dependencies)
	local deps = dependencies
	local entries = {}
	local locksByCritterId = {}
	local locksByToken = {}
	local lockCounter = 0
	local service = {}
	local shuttingDown = false
	local clock = deps.clock or os.time
	local ownershipLockSeconds = deps.ownershipLockSeconds or 30

	local function releaseLockRecord(record)
		locksByToken[record.token] = nil
		for _, critterId in record.critterIds do
			if locksByCritterId[critterId] == record then
				locksByCritterId[critterId] = nil
			end
		end
	end

	local function cleanupExpiredLocks()
		local now = clock()
		local expired = {}
		for _, record in locksByToken do
			if record.expiresAt <= now then
				table.insert(expired, record)
			end
		end
		for _, record in expired do
			releaseLockRecord(record)
		end
		return #expired
	end

	local function releaseUserLocks(userId: number)
		local owned = {}
		for _, record in locksByToken do
			if record.ownerUserId == userId then
				table.insert(owned, record)
			end
		end
		for _, record in owned do
			releaseLockRecord(record)
		end
	end

	local function loadProfile(userId: number)
		local entry = entries[userId]
		if entry ~= nil then
			if entry.state == "READY" then
				return {
					ok = true,
					value = deps.projector.project(entry.handle.profile, deps.catalog),
				}
			elseif entry.state == "FAILED" or entry.state == "RELEASED" then
				return entry.failure
					or failure("PROFILE_UNAVAILABLE", "Player profile is unavailable")
			elseif entry.state == "LOADING" then
				local waited = 0
				while entry.state == "LOADING" and waited < deps.loadWaitSeconds do
					deps.wait(deps.loadPollSeconds)
					waited += deps.loadPollSeconds
				end
				if entry.state == "READY" then
					return {
						ok = true,
						value = deps.projector.project(entry.handle.profile, deps.catalog),
					}
				end
				return entry.failure
					or failure("PROFILE_LOAD_TIMEOUT", "Player profile load timed out")
			end
		end
		if shuttingDown then
			return failure("SERVER_SHUTTING_DOWN", "Server is shutting down")
		end
		entry = { state = "LOADING", handle = nil, failure = nil, saving = false }
		entries[userId] = entry
		local loaded = deps.repository.load(userId)
		if not loaded.ok then
			entry.state = "FAILED"
			entry.failure = loaded
			return loaded
		end
		entry.handle = loaded.value
		entry.state = "READY"
		return { ok = true, value = deps.projector.project(entry.handle.profile, deps.catalog) }
	end

	local function readyEntry(userId: number)
		local entry = entries[userId]
		if entry == nil or entry.state ~= "READY" then
			return nil, failure("PROFILE_NOT_READY", "Player profile is not ready")
		end
		return entry, nil
	end

	local function getProfile(userId: number)
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		return { ok = true, value = deps.projector.project(entry.handle.profile, deps.catalog) }
	end

	local function readProfile(userId: number)
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		return { ok = true, value = clone(entry.handle.profile) }
	end

	local function getOwnedCritters(userId: number)
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		return {
			ok = true,
			value = deps.projector.ownedCritters(entry.handle.profile, deps.catalog),
		}
	end

	local function getSelectedTeam(userId: number)
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		local selected = deps.projector.selectedTeam(entry.handle.profile, deps.catalog)
		if selected == nil or #selected ~= 3 then
			return failure("INVALID_SELECTED_TEAM", "Selected team is unavailable")
		end
		return { ok = true, value = selected }
	end

	local function waitForWriter(entry)
		local waited = 0
		while entry.saving and waited < deps.loadWaitSeconds do
			deps.wait(deps.loadPollSeconds)
			waited += deps.loadPollSeconds
		end
		if entry.saving then
			return failure("PROFILE_SAVE_IN_PROGRESS", "Timed out waiting for profile mutation")
		end
		if entry.state ~= "READY" then
			return entry.failure or failure("PROFILE_NOT_READY", "Player profile is not ready")
		end
		return nil
	end

	local function recordSaveFailure(entry, result)
		if not result.ok and result.errors[1] and result.errors[1].code == "PROFILE_LOCK_LOST" then
			entry.state = "FAILED"
			entry.failure = result
		end
	end

	local function saveProfile(userId: number)
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		local waitFailure = waitForWriter(entry)
		if waitFailure ~= nil then
			return waitFailure
		end
		entry.saving = true
		local saved = deps.repository.save(entry.handle)
		entry.saving = false
		recordSaveFailure(entry, saved)
		return saved
	end

	local function updateProfile(userId: number, mutator)
		if type(mutator) ~= "function" then
			return failure("INVALID_PROFILE_MUTATOR", "Profile mutator must be a function")
		end
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		local waitFailure = waitForWriter(entry)
		if waitFailure ~= nil then
			return waitFailure
		end
		entry.saving = true
		local candidate = clone(entry.handle.profile)
		local ok, mutation = pcall(mutator, candidate)
		if not ok then
			entry.saving = false
			return failure("PROFILE_MUTATION_FAILED", "Profile mutation raised an error")
		end
		if type(mutation) ~= "table" or mutation.ok == nil then
			entry.saving = false
			return failure("INVALID_PROFILE_MUTATION", "Profile mutation returned invalid result")
		end
		if not mutation.ok then
			entry.saving = false
			return mutation
		end
		local saved = deps.repository.save(entry.handle, candidate)
		entry.saving = false
		if not saved.ok then
			recordSaveFailure(entry, saved)
			return saved
		end
		return { ok = true, value = clone(mutation.value) }
	end

	local function releaseProfile(userId: number)
		local entry = entries[userId]
		if entry == nil then
			releaseUserLocks(userId)
			return { ok = true, value = true }
		end
		local waited = 0
		while entry.saving and waited < deps.loadWaitSeconds do
			deps.wait(deps.loadPollSeconds)
			waited += deps.loadPollSeconds
		end
		entry = entries[userId]
		if entry == nil then
			return { ok = true, value = true }
		end
		if entry.saving then
			return failure("PROFILE_SAVE_IN_PROGRESS", "Timed out waiting for profile save")
		end
		if entry.state ~= "READY" then
			entries[userId] = nil
			releaseUserLocks(userId)
			return entry.failure or { ok = true, value = true }
		end
		entry.saving = true
		local released = deps.repository.release(entry.handle)
		entry.saving = false
		entry.state = "RELEASED"
		entries[userId] = nil
		releaseUserLocks(userId)
		return released
	end

	local function acquireOwnershipLocks(userId: number, critterIds, operationType)
		if operationType ~= "BREEDING" and operationType ~= "TRANSFER" then
			return failure("INVALID_LOCK_OPERATION", "Ownership lock operation is invalid")
		end
		if type(critterIds) ~= "table" or #critterIds < 1 or #critterIds > 16 then
			return failure("INVALID_CRITTER_IDS", "Ownership lock requires Critter IDs")
		end
		local entry, problem = readyEntry(userId)
		if entry == nil then
			return problem
		end
		cleanupExpiredLocks()
		local seen = {}
		for _, critterId in critterIds do
			if not isIdentifier(critterId) or seen[critterId] then
				return failure("INVALID_CRITTER_IDS", "Ownership lock Critter IDs are malformed")
			end
			seen[critterId] = true
			local critter = entry.handle.profile.ownedCritters[critterId]
			if critter == nil or critter.ownerUserId ~= userId then
				return failure("CRITTER_NOT_OWNED", "Critter is not owned by this player")
			end
			if locksByCritterId[critterId] ~= nil then
				return failure("OWNERSHIP_LOCK_CONFLICT", "Critter is already locked")
			end
		end

		lockCounter += 1
		local token = `ownership-lock:{userId}:{lockCounter}`
		local record = {
			token = token,
			ownerUserId = userId,
			operationType = operationType,
			critterIds = clone(critterIds),
			expiresAt = clock() + ownershipLockSeconds,
		}
		locksByToken[token] = record
		for _, critterId in critterIds do
			locksByCritterId[critterId] = record
		end
		return { ok = true, value = clone(record) }
	end

	local function getOwnershipLock(critterId)
		if not isIdentifier(critterId) then
			return nil
		end
		cleanupExpiredLocks()
		local record = locksByCritterId[critterId]
		return if record == nil then nil else clone(record)
	end

	local function releaseOwnershipLocks(userId: number, token)
		if not isIdentifier(token) then
			return failure("INVALID_LOCK_TOKEN", "Ownership lock token is malformed")
		end
		cleanupExpiredLocks()
		local record = locksByToken[token]
		if record == nil then
			return { ok = true, value = false }
		end
		if record.ownerUserId ~= userId then
			return failure("LOCK_NOT_OWNED", "Ownership lock belongs to another player")
		end
		releaseLockRecord(record)
		return { ok = true, value = true }
	end

	function service.beginShutdown()
		shuttingDown = true
	end

	function service.loadedUserIds()
		local userIds = {}
		for userId, entry in entries do
			if entry.state == "READY" then
				table.insert(userIds, userId)
			end
		end
		return userIds
	end

	service.LoadProfile = loadProfile
	service.GetProfile = getProfile
	service.ReadProfile = readProfile
	service.GetOwnedCritters = getOwnedCritters
	service.GetSelectedTeam = getSelectedTeam
	service.SaveProfile = saveProfile
	service.UpdateProfile = updateProfile
	service.ReleaseProfile = releaseProfile
	service.AcquireOwnershipLocks = acquireOwnershipLocks
	service.GetOwnershipLock = getOwnershipLock
	service.ReleaseOwnershipLocks = releaseOwnershipLocks
	service.CleanupExpiredOwnershipLocks = cleanupExpiredLocks
	return table.freeze(service)
end

ProfileService.new = new
return table.freeze(ProfileService)
