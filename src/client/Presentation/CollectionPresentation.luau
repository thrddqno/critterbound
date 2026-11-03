--!strict

local CollectionPresentation = {}

local function join(values): string
	local result = {}
	for key, value in values do
		if key ~= "schemaVersion" then
			table.insert(result, `{tostring(key)}: {tostring(value)}`)
		end
	end
	table.sort(result)
	return if #result == 0 then "None" else table.concat(result, ", ")
end

local function mapCritter(critter)
	local stats = critter.baseStats or {}
	local appearance = critter.appearanceGenome or {}
	local abilities = critter.abilityGenome and critter.abilityGenome.abilityIds or {}
	return {
		id = critter.id,
		definitionId = critter.definitionId,
		displayName = critter.displayName or "Unknown Critter",
		class = critter.class or "Unknown",
		statsText = `HP {stats.maxHealth or 0}  Speed {stats.speed or 0}  Skill {stats.skill or 0}  Resolve {stats.resolve or 0}`,
		appearanceText = join(appearance),
		abilityText = if #abilities == 0 then "None" else table.concat(abilities, ", "),
		equipmentText = if critter.equippedItem == nil
			then "None"
			else critter.equippedItem.displayName,
		acquisitionText = if critter.acquisition == nil
			then "Unknown"
			else critter.acquisition.source,
		breedingText = if critter.breeding and critter.breeding.breedable
			then `Eligible, generation {critter.breeding.generation}`
			else "Restricted",
		tradeText = if critter.tradable then "Tradable" else "Not tradable",
		selectedTeamSlot = critter.selectedTeamSlot,
	}
end

local function map(collection)
	local critters = {}
	for _, critter in collection.critters or {} do
		table.insert(critters, mapCritter(critter))
	end
	return {
		revision = collection.revision,
		selectedTeam = collection.selectedTeam or {},
		critters = critters,
	}
end

CollectionPresentation.map = map
CollectionPresentation.mapCritter = mapCritter
return table.freeze(CollectionPresentation)
