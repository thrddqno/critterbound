--!strict

local TeamValidator = {}

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
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

local function validateTeam(
	team: any,
	userId: number,
	ownedCritters: any,
	definitionsById: any,
	allowEmpty: boolean?
)
	local length = arrayLength(team)
	if allowEmpty and length == 0 then
		return { ok = true, value = true }
	end
	if length ~= 3 then
		return failure(
			"INVALID_SELECTED_TEAM",
			"Selected team requires exactly three Critters",
			"selectedTeam"
		)
	end
	local seen = {}
	for index, critterId in team do
		local critter = if type(critterId) == "string" then ownedCritters[critterId] else nil
		if type(critterId) ~= "string" or seen[critterId] then
			return failure(
				"INVALID_SELECTED_TEAM",
				"Selected Critter IDs must be unique",
				`selectedTeam[{index}]`
			)
		end
		if critter == nil then
			return failure(
				"CRITTER_NOT_OWNED",
				"Selected Critter is not owned",
				`selectedTeam[{index}]`
			)
		end
		if critter.ownerUserId ~= userId or definitionsById[critter.definitionId] == nil then
			return failure(
				"CRITTER_INELIGIBLE",
				"Selected Critter is not battle eligible",
				`selectedTeam[{index}]`
			)
		end
		seen[critterId] = true
	end
	return { ok = true, value = true }
end

TeamValidator.validateTeam = validateTeam
return table.freeze(TeamValidator)
