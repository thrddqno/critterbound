--!strict

-- Replaceable Training Grounds content. Runtime state is always built by BattleFactory.
local function requireSibling(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent.Parent.Genetics[name])
	end
	return require(`../Genetics/{name}`)
end

local CritterCatalog = requireSibling("CritterCatalog")
local CardCatalog = requireSibling("CardCatalog")
local GeneRegistry = requireGenetics("GeneRegistry")

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

local critters = {
	Stone = CritterCatalog.getByClass("Stone"),
	Feral = CritterCatalog.getByClass("Feral"),
	Verdant = CritterCatalog.getByClass("Verdant"),
	Tide = CritterCatalog.getByClass("Tide"),
	Gale = CritterCatalog.getByClass("Gale"),
	Shade = CritterCatalog.getByClass("Shade"),
}

local function makeInstance(definition, ownerUserId: number, suffix: string, founder: boolean?)
	local genomes = if founder
		then GeneRegistry.founderGenomes(definition.class)
		else GeneRegistry.defaultGenomes(definition.class)
	assert(genomes ~= nil, `Missing genomes for {definition.class}`)
	return {
		schemaVersion = 2,
		id = `owned.training.{string.lower(definition.class)}.{suffix}`,
		definitionId = definition.id,
		ownerUserId = ownerUserId,
		appearanceGenome = genomes.appearanceGenome,
		abilityGenome = genomes.abilityGenome,
		baseStats = clone(definition.baseStats),
		acquisition = { source = "TRAINING", acquiredAt = 0, sourceVersion = 1 },
		breeding = { breedable = false, generation = 0, parentIds = {}, successfulBreedCount = 0 },
		tradable = false,
		equipmentIds = {},
	}
end

local function createInput(playerUserId: number, generation: number)
	local aiOwnerUserId = 1_000_000_000_000 + playerUserId
	local playerInstances = {
		makeInstance(critters.Stone, playerUserId, `player.{generation}`),
		makeInstance(critters.Feral, playerUserId, `player.{generation}`),
		makeInstance(critters.Verdant, playerUserId, `player.{generation}`),
	}
	local aiInstances = {
		makeInstance(critters.Tide, aiOwnerUserId, `ai.{generation}`, true),
		makeInstance(critters.Gale, aiOwnerUserId, `ai.{generation}`, true),
		makeInstance(critters.Shade, aiOwnerUserId, `ai.{generation}`, true),
	}
	return {
		battleId = `training:{playerUserId}:{generation}`,
		rngSeed = ((playerUserId % 2_000_000_000) + generation * 7919) % 2_147_483_646 + 1,
		teams = {
			{ id = "team.player", ownerUserId = playerUserId, critterInstances = playerInstances },
			{ id = "team.training", ownerUserId = aiOwnerUserId, critterInstances = aiInstances },
		},
		critterDefinitionsById = CritterCatalog.allById(),
		cardDefinitionsById = CardCatalog.allById(),
		playerTeamId = "team.player",
		aiTeamId = "team.training",
		aiOwnerUserId = aiOwnerUserId,
	}
end

return table.freeze({ createInput = createInput })
