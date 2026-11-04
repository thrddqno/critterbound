--!strict

local POLICY_VERSION = "MUTATION_POLICY_V1"

-- Production remains disabled. Tests may clone this policy and opt in explicitly.
local DEFAULT = table.freeze({
	version = POLICY_VERSION,
	enabled = false,
	probabilityNumerator = 2,
	probabilityDenominator = 100,
})

return table.freeze({
	Version = POLICY_VERSION,
	Default = DEFAULT,
})
