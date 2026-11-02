--!strict

local DomainFixtures = require("./DomainFixtures")

local function clone(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[clone(key)] = clone(child)
	end
	return result
end

local definitionsById = {}
local cardDefinitionsById = {}
for _, definition in DomainFixtures.Definitions do
	definitionsById[definition.id] = clone(definition)
	for index, abilityId in definition.abilityIds do
		local id = `card.{abilityId}`
		local targetingRule = if index == 1
			then (if definition.class == "Feral"
				then "ENEMY"
				elseif definition.class == "Verdant" then "ALLY"
				else "SELF")
			else "ANY"
		cardDefinitionsById[id] = {
			schemaVersion = 1,
			id = id,
			displayName = abilityId,
			class = definition.class,
			abilityId = abilityId,
			energyCost = if index == 2 then 2 else 1,
			targetingRule = targetingRule,
		}
	end
end

local function teamInstances(ownerUserId: number, suffix: string)
	local values = {}
	for _, source in
		{
			DomainFixtures.Instances.Stone,
			DomainFixtures.Instances.Feral,
			DomainFixtures.Instances.Verdant,
		}
	do
		local instance = clone(source)
		instance.id = `{source.id}.{suffix}`
		instance.ownerUserId = ownerUserId
		table.insert(values, instance)
	end
	return values
end

local function createInput()
	return {
		battleId = "battle.run4.fixture",
		rngSeed = 3001,
		teams = {
			{ id = "team.2", ownerUserId = 202, critterInstances = teamInstances(202, "team2") },
			{ id = "team.1", ownerUserId = 101, critterInstances = teamInstances(101, "team1") },
		},
		critterDefinitionsById = clone(definitionsById),
		cardDefinitionsById = clone(cardDefinitionsById),
	}
end

local function indexById(values)
	local result = {}
	for _, value in values do
		result[value.id] = value
	end
	return result
end

return {
	createInput = createInput,
	definitionsById = definitionsById,
	cardDefinitionsById = cardDefinitionsById,
	indexById = indexById,
	clone = clone,
}
