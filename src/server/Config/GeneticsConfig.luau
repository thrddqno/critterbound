--!strict

-- Server-owned rollout configuration. Production remains on legacy inheritance until this
-- module is deliberately changed or an equivalent trusted server configuration is injected.
local LEGACY_INHERITANCE = "LEGACY_INHERITANCE"
local CLASSIC_INHERITANCE_V1 = "CLASSIC_INHERITANCE_V1"

local function classic(mutationEnabled: boolean)
	return {
		mode = CLASSIC_INHERITANCE_V1,
		classInheritancePolicyVersion = 1,
		inheritancePolicyVersion = 1,
		mutationPolicyVersion = 1,
		mutationEnabled = mutationEnabled,
		mutationProbabilityNumerator = 2,
		mutationProbabilityDenominator = 100,
		geneContentVersion = 1,
		expressionVersion = 1,
	}
end

local function validate(config)
	if type(config) ~= "table" then
		return false
	end
	if config.mode == LEGACY_INHERITANCE then
		return true
	end
	return config.mode == CLASSIC_INHERITANCE_V1
		and config.classInheritancePolicyVersion == 1
		and config.inheritancePolicyVersion == 1
		and config.mutationPolicyVersion == 1
		and type(config.mutationEnabled) == "boolean"
		and config.mutationProbabilityNumerator == 2
		and config.mutationProbabilityDenominator == 100
		and config.geneContentVersion == 1
		and config.expressionVersion == 1
end

return table.freeze({
	LegacyMode = LEGACY_INHERITANCE,
	ClassicMode = CLASSIC_INHERITANCE_V1,
	Default = table.freeze({ mode = LEGACY_INHERITANCE }),
	ClassicV1 = table.freeze(classic(false)),
	classic = classic,
	validate = validate,
})
