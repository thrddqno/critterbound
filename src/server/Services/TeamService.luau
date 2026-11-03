--!strict

local TeamService = {}

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

local function new(dependencies)
	local deps = dependencies
	local service = {}

	local function getSelectedTeam(userId: number)
		return deps.profileService.GetSelectedTeam(userId)
	end

	local function validateTeam(userId: number, team)
		local snapshot = deps.profileService.ReadProfile(userId)
		if not snapshot.ok then
			return snapshot
		end
		return deps.validator.validateTeam(
			team,
			userId,
			snapshot.value.ownedCritters,
			deps.catalog.allById()
		)
	end

	local function setSelectedTeam(userId: number, team, expectedRevision: number?)
		return deps.profileService.UpdateProfile(userId, function(profile)
			if expectedRevision ~= nil and profile.revision ~= expectedRevision then
				return {
					ok = false,
					errors = { { code = "STALE_PROFILE", message = "Collection state is stale" } },
				}
			end
			local validation = deps.validator.validateTeam(
				team,
				userId,
				profile.ownedCritters,
				deps.catalog.allById()
			)
			if not validation.ok then
				return validation
			end
			profile.selectedTeam = clone(team)
			return { ok = true, value = { selectedTeam = clone(team) } }
		end)
	end

	service.GetSelectedTeam = getSelectedTeam
	service.SetSelectedTeam = setSelectedTeam
	service.ValidateTeam = validateTeam
	return table.freeze(service)
end

TeamService.new = new
return table.freeze(TeamService)
