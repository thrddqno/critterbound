--!strict

local StarterGrant = {}

local function requireGeneRegistry()
	if script ~= nil then
		return require(game:GetService("ReplicatedStorage").Shared.Genetics.GeneRegistry)
	end
	return require("../../shared/Genetics/GeneRegistry")
end

local GeneRegistry = requireGeneRegistry()

local GRANT_VERSION = 1
local STARTER_CLASSES = { "Stone", "Feral", "Verdant" }

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

local function prepare(userId: number, now: number, generateId, catalog)
	local critters = {}
	for _, className in STARTER_CLASSES do
		local definition = catalog.getByClass(className)
		assert(definition ~= nil, `Missing starter definition {className}`)
		local genomes = GeneRegistry.defaultGenomes(className)
		assert(genomes ~= nil, `Missing starter genomes {className}`)
		local id = `critter:{generateId()}`
		table.insert(critters, {
			schemaVersion = 2,
			id = id,
			definitionId = definition.id,
			ownerUserId = userId,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
			baseStats = clone(definition.baseStats),
			acquisition = { source = "STARTER", acquiredAt = now, sourceVersion = GRANT_VERSION },
			breeding = {
				breedable = false,
				generation = 0,
				parentIds = {},
				successfulBreedCount = 0,
			},
			tradable = false,
			equipmentIds = {},
		})
	end
	return critters
end

local function apply(profile, preparedCritters)
	if profile.starterGrantVersion >= GRANT_VERSION then
		return { ok = true, value = profile, granted = false }
	end
	for _, critter in preparedCritters do
		if profile.ownedCritters[critter.id] ~= nil then
			return {
				ok = false,
				errors = {
					{
						code = "STARTER_ID_COLLISION",
						message = "Starter Critter ID already exists",
					},
				},
			}
		end
	end
	local selectedWasEmpty = #profile.selectedTeam == 0
	for _, critter in preparedCritters do
		profile.ownedCritters[critter.id] = clone(critter)
	end
	if selectedWasEmpty then
		profile.selectedTeam = {
			preparedCritters[1].id,
			preparedCritters[2].id,
			preparedCritters[3].id,
		}
	end
	profile.starterGrantVersion = GRANT_VERSION
	profile.revision += 1
	return { ok = true, value = profile, granted = true }
end

StarterGrant.Version = GRANT_VERSION
StarterGrant.prepare = prepare
StarterGrant.apply = apply
return table.freeze(StarterGrant)
