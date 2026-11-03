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

local function new(dependencies)
	local deps = dependencies
	local entries = {}
	local service = {}
	local shuttingDown = false

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
			return entry.failure or { ok = true, value = true }
		end
		entry.saving = true
		local released = deps.repository.release(entry.handle)
		entry.saving = false
		entry.state = "RELEASED"
		entries[userId] = nil
		return released
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
	return table.freeze(service)
end

ProfileService.new = new
return table.freeze(ProfileService)
