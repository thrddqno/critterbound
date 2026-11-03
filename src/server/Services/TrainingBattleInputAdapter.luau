--!strict

local TrainingBattleInputAdapter = {}

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
	local adapter = {}

	function adapter.createInput(userId: number, generation: number)
		local loaded = deps.profileService.LoadProfile(userId)
		if not loaded.ok then
			return loaded
		end
		local selected = deps.profileService.GetSelectedTeam(userId)
		if not selected.ok then
			return selected
		end
		if #selected.value ~= 3 then
			return failure(
				"INVALID_SELECTED_TEAM",
				"Training Grounds requires three owned Critters"
			)
		end
		local input = deps.content.createInput(userId, generation)
		local replaced = false
		for _, team in input.teams do
			if team.ownerUserId == userId then
				team.critterInstances = clone(selected.value)
				replaced = true
				break
			end
		end
		if not replaced then
			return failure("PLAYER_TEAM_MISSING", "Training Grounds player team is missing")
		end
		return { ok = true, value = input }
	end

	return table.freeze(adapter)
end

TrainingBattleInputAdapter.new = new
return table.freeze(TrainingBattleInputAdapter)
