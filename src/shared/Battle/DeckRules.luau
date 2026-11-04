--!strict

local DEFAULTS = table.freeze({
	CrittersPerTeam = 3,
	AbilitiesPerCritter = 4,
	CopiesPerCard = 2,
	OpeningHandSize = 6,
	DrawsPerRound = 3,
	MaxHandSize = 9,
	DefeatPolicy = "REMOVE_IMMEDIATELY",
})

local function resolve(overrides)
	local rules = table.clone(DEFAULTS)
	for key, value in overrides or {} do
		rules[key] = value
	end
	rules.TeamDeckSize = rules.CrittersPerTeam * rules.AbilitiesPerCritter * rules.CopiesPerCard
	return table.freeze(rules)
end

return table.freeze({
	Default = resolve(nil),
	resolve = resolve,
})
