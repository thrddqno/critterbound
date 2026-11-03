--!strict

local function requireGenetics(name: string)
	if script ~= nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage.Shared.Genetics[name])
	end
	return require(`../../shared/Genetics/{name}`)
end

local GeneRegistry = requireGenetics("GeneRegistry")

local CollectionPresentation = {}
local APPEARANCE_ORDER = { "body", "eyes", "wings", "tail", "color", "markings", "accessories" }

local function titleCase(value: string): string
	local words = {}
	for word in string.gmatch(string.gsub(value, "_", " "), "%S+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(words, " ")
end

local function readableIdentifier(value: string): string
	local definition = GeneRegistry.get(value)
	if definition ~= nil and type(definition.displayName) == "string" then
		return definition.displayName
	end
	local parts = string.split(value, ".")
	if parts[1] == "gene" and parts[2] == "appearance" then
		local classOrFamily = parts[4] or ""
		local variant = parts[5] or ""
		return titleCase(`{classOrFamily} {variant}`)
	end
	return titleCase(table.concat(parts, " "))
end

local function selectedGene(value): string
	if type(value) == "string" then
		return readableIdentifier(value)
	end
	if type(value) == "table" then
		local id = value.D or value.R1 or value.R2
		if type(id) == "string" then
			return readableIdentifier(id)
		end
	end
	return "Unknown"
end

local function appearanceText(values): string
	local lines = {}
	for _, slot in APPEARANCE_ORDER do
		if values[slot] ~= nil then
			table.insert(lines, `{titleCase(slot)}: {selectedGene(values[slot])}`)
		end
	end
	return if #lines == 0 then "None" else table.concat(lines, "\n")
end

local function abilityText(values): string
	local labels = {}
	for _, value in values do
		table.insert(labels, readableIdentifier(value))
	end
	return if #labels == 0 then "None" else table.concat(labels, ", ")
end

local function mapCritter(critter)
	local stats = critter.baseStats or {}
	local appearance = critter.resolvedAppearance and critter.resolvedAppearance.resolvedGenesBySlot
		or critter.appearanceGenome and critter.appearanceGenome.slots
		or {}
	local abilities = critter.resolvedAbilityIds or {}
	local acquisitionText = if critter.acquisition == nil
		then "Unknown"
		else critter.acquisition.source
	local breedingText = if critter.breeding and critter.breeding.breedable
		then `Eligible, generation {critter.breeding.generation}`
		else "Restricted"
	local tradeText = if critter.tradable then "Tradable" else "Not tradable"
	return {
		id = critter.id,
		definitionId = critter.definitionId,
		displayName = critter.displayName or "Unknown Critter",
		class = critter.class or "Unknown",
		appearanceGenome = critter.appearanceGenome,
		statsText = `HP {stats.maxHealth or 0}  Speed {stats.speed or 0}  Skill {stats.skill or 0}  Resolve {stats.resolve or 0}`,
		appearanceText = appearanceText(appearance),
		abilityText = abilityText(abilities),
		equipmentText = if critter.equippedItem == nil
			then "None"
			else critter.equippedItem.displayName,
		acquisitionText = acquisitionText,
		breeding = critter.breeding,
		breedingText = breedingText,
		tradeText = tradeText,
		restrictionsText = `Acquisition: {acquisitionText}\nBreeding: {breedingText}\nTrading: {tradeText}`,
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
CollectionPresentation.readableIdentifier = readableIdentifier
return table.freeze(CollectionPresentation)
