--!strict

local function requireCritterCatalog()
	if script ~= nil then
		return require(script.Parent.Parent.Definitions.CritterCatalog)
	end
	return require("../Definitions/CritterCatalog")
end

local CritterCatalog = requireCritterCatalog()
local APPEARANCE_SLOTS = { "body", "eyes", "wings", "tail", "color", "markings", "accessories" }
local ABILITY_SLOTS = { "mouth", "horn", "back", "tail", "traits" }
local POSITIONS = { "D", "R1", "R2" }
local CLASSES = { "Stone", "Feral", "Verdant", "Tide", "Gale", "Shade" }
local RIGS = {
	Stone = "heavy",
	Verdant = "round",
	Tide = "round",
	Feral = "agile",
	Gale = "agile",
	Shade = "agile",
}
local LAYER_ORDER = { tail = 5, wings = 8, color = 15, markings = 20, eyes = 50, accessories = 70 }
local ABILITY_SLOT_BY_INDEX = { "mouth", "horn", "back", "tail" }
local BODY_BASE_TAGS = {
	Stone = { "tail:stub", "wing:plate", "attachment:shoulder", "markings:stone" },
	Feral = { "tail:long", "wing:small", "attachment:crest", "markings:feral" },
	Verdant = { "tail:leaf", "wing:leaf", "markings:verdant" },
	Tide = { "tail:fin", "wing:fin", "markings:tide" },
	Gale = { "tail:feather", "wing:feather", "attachment:crest", "markings:gale" },
	Shade = { "tail:wisp", "wing:wisp", "attachment:wisp", "markings:shade" },
}

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

local function bodyTags(className: string, shape: string)
	local lower = string.lower(className)
	local tags = {
		`class:{lower}`,
		`rig:{RIGS[className]}`,
		`shape:{shape}`,
	}
	for _, tag in BODY_BASE_TAGS[className] do
		table.insert(tags, tag)
	end
	return tags
end

local definitions = {}
local fallbackByClassAndSlot = {}

local function add(definition)
	assert(definitions[definition.id] == nil, `Duplicate gene {definition.id}`)
	definitions[definition.id] = definition
	if definition.fallbackPriority ~= nil then
		for _, className in definition.classes or CLASSES do
			local key = `{definition.kind}|{className}|{definition.slot}`
			local list = fallbackByClassAndSlot[key] or {}
			table.insert(list, definition)
			fallbackByClassAndSlot[key] = list
		end
	end
end

for _, className in CLASSES do
	local lower = string.lower(className)
	local rig = RIGS[className]
	add({
		id = `gene.appearance.body.{lower}.default`,
		kind = "APPEARANCE",
		slot = "body",
		classes = { className },
		speciesId = `critter.{lower}`,
		bodyRigFamily = rig,
		bodyShape = "standard",
		providesTags = bodyTags(className, "standard"),
		spriteRigId = lower,
		assetId = `creature.{lower}.default`,
		displayName = `{className} Body`,
		fallbackPriority = 1,
		anchorKey = `anchor.body.{rig}`,
		pivotKey = `pivot.body.{rig}`,
	})
	for _, slot in APPEARANCE_SLOTS do
		if slot ~= "body" then
			add({
				id = `gene.appearance.{slot}.{lower}.default`,
				kind = "APPEARANCE",
				slot = slot,
				classes = { className },
				speciesIds = { `critter.{lower}` },
				bodyRigFamilies = { rig },
				assetId = `creature.layer.{slot}.{lower}.default`,
				displayName = `{className} {string.upper(string.sub(slot, 1, 1))}{string.sub(
					slot,
					2
				)}`,
				layerOrder = LAYER_ORDER[slot],
				fallbackPriority = 1,
				anchorKey = `anchor.{slot}.{rig}`,
				pivotKey = `pivot.{slot}.{rig}`,
				attachmentKey = if slot == "accessories"
					then `attachment.accessories.{rig}`
					else nil,
			})
		end
	end
	local definition = CritterCatalog.getByClass(className)
	assert(definition ~= nil, `Missing Critter definition {className}`)
	for index, abilityId in definition.abilityIds do
		local slot = ABILITY_SLOT_BY_INDEX[index]
		add({
			id = `gene.ability.{slot}.{abilityId}`,
			kind = "ABILITY",
			slot = slot,
			classes = { className },
			speciesIds = { `critter.{lower}` },
			abilityId = abilityId,
			fallbackPriority = 1,
		})
	end
	add({
		id = `gene.ability.traits.{lower}.neutral`,
		kind = "ABILITY",
		slot = "traits",
		classes = { className },
		speciesIds = { `critter.{lower}` },
		abilityId = nil,
		fallbackPriority = 1,
	})
end

add({
	id = "gene.appearance.eyes.universal.bright",
	kind = "APPEARANCE",
	slot = "eyes",
	bodyRigFamilies = { "heavy", "round", "agile" },
	assetId = "creature.layer.eyes.bright",
	displayName = "Bright Eyes",
	layerOrder = 50,
	anchorKey = "anchor.eyes.universal",
	pivotKey = "pivot.eyes.universal",
})

local bodyVariants = {
	{
		className = "Stone",
		variant = "armored",
		displayName = "Armored Stone Body",
		shape = "armored",
	},
	{
		className = "Feral",
		variant = "spiked",
		displayName = "Spiked Feral Body",
		shape = "spiked",
	},
	{
		className = "Verdant",
		variant = "compact",
		displayName = "Compact Verdant Body",
		shape = "compact",
	},
	{
		className = "Tide",
		variant = "streamlined",
		displayName = "Streamlined Tide Body",
		shape = "streamlined",
	},
	{
		className = "Gale",
		variant = "plumed",
		displayName = "Plumed Gale Body",
		shape = "feathered",
	},
	{
		className = "Shade",
		variant = "wispy",
		displayName = "Wispy Shade Body",
		shape = "wispy",
	},
}

for _, variant in bodyVariants do
	local lower = string.lower(variant.className)
	local rig = RIGS[variant.className]
	add({
		id = `gene.appearance.body.{lower}.{variant.variant}`,
		kind = "APPEARANCE",
		slot = "body",
		classes = { variant.className },
		speciesId = `critter.{lower}`,
		bodyRigFamily = rig,
		bodyShape = variant.shape,
		providesTags = bodyTags(variant.className, variant.shape),
		spriteRigId = lower,
		assetId = `creature.{lower}.{variant.variant}`,
		displayName = variant.displayName,
		anchorKey = `anchor.body.{rig}`,
		pivotKey = `pivot.body.{rig}`,
	})
end

local layerVariants = {
	{
		className = "Verdant",
		slot = "eyes",
		variant = "wide",
		displayName = "Verdant Wide Eyes",
		order = 50,
		shapes = { "standard", "compact" },
	},
	{
		className = "Stone",
		slot = "eyes",
		variant = "foreign_species",
		displayName = "Stone Crystal Eyes",
		order = 50,
		shapes = { "standard", "armored" },
	},
	{
		className = "Feral",
		slot = "eyes",
		variant = "slit",
		displayName = "Feral Slit Eyes",
		order = 50,
		shapes = { "standard", "spiked" },
	},
	{
		className = "Tide",
		slot = "eyes",
		variant = "deep",
		displayName = "Tide Deep Eyes",
		order = 50,
		shapes = { "standard", "streamlined" },
	},
	{
		className = "Gale",
		slot = "eyes",
		variant = "keen",
		displayName = "Gale Keen Eyes",
		order = 50,
		shapes = { "standard", "feathered" },
	},
	{
		className = "Shade",
		slot = "eyes",
		variant = "glow",
		displayName = "Shade Glow Eyes",
		order = 50,
		shapes = { "standard", "wispy" },
	},
	{
		className = "Verdant",
		slot = "tail",
		variant = "leafy",
		displayName = "Verdant Leafy Tail",
		order = 5,
		shapes = { "standard", "compact" },
		requiresAnyTags = { "tail:leaf" },
	},
	{
		className = "Stone",
		slot = "tail",
		variant = "crystal",
		displayName = "Stone Crystal Tail",
		order = 5,
		shapes = { "standard", "armored" },
		requiresAnyTags = { "tail:stub" },
	},
	{
		className = "Feral",
		slot = "tail",
		variant = "flame",
		displayName = "Feral Flame Tail",
		order = 5,
		shapes = { "standard", "spiked" },
		requiresAnyTags = { "tail:long" },
	},
	{
		className = "Tide",
		slot = "tail",
		variant = "fin",
		displayName = "Tide Fin Tail",
		order = 5,
		shapes = { "standard", "streamlined" },
		requiresAnyTags = { "tail:fin" },
	},
	{
		className = "Gale",
		slot = "tail",
		variant = "feather",
		displayName = "Gale Feather Tail",
		order = 5,
		shapes = { "standard", "feathered", "streamlined" },
		rigs = { "agile", "round" },
		compatibleClasses = { "Tide" },
		requiresAnyTags = { "tail:feather", "tail:fin" },
	},
	{
		className = "Shade",
		slot = "tail",
		variant = "wisp",
		displayName = "Shade Wisp Tail",
		order = 5,
		shapes = { "standard", "wispy" },
		requiresAnyTags = { "tail:wisp" },
	},
	{
		className = "Verdant",
		slot = "markings",
		variant = "speckled",
		displayName = "Verdant Speckled Markings",
		order = 20,
		shapes = { "standard", "compact", "armored" },
		rigs = { "round", "heavy" },
		compatibleClasses = { "Stone" },
		requiresAnyTags = { "markings:verdant", "markings:stone" },
	},
	{
		className = "Stone",
		slot = "markings",
		variant = "crystal",
		displayName = "Stone Crystal Markings",
		order = 20,
		shapes = { "standard", "armored" },
		requiresAnyTags = { "markings:stone" },
	},
	{
		className = "Feral",
		slot = "markings",
		variant = "scar",
		displayName = "Feral Scar Markings",
		order = 20,
		shapes = { "standard", "spiked" },
		requiresAnyTags = { "markings:feral" },
	},
	{
		className = "Tide",
		slot = "markings",
		variant = "current",
		displayName = "Tide Current Markings",
		order = 20,
		shapes = { "standard", "streamlined" },
		requiresAnyTags = { "markings:tide" },
	},
	{
		className = "Gale",
		slot = "markings",
		variant = "wind",
		displayName = "Gale Wind Markings",
		order = 20,
		shapes = { "standard", "feathered" },
		requiresAnyTags = { "markings:gale" },
	},
	{
		className = "Shade",
		slot = "markings",
		variant = "veil",
		displayName = "Shade Veil Markings",
		order = 20,
		shapes = { "standard", "wispy" },
		requiresAnyTags = { "markings:shade" },
	},
	{
		className = "Gale",
		slot = "wings",
		variant = "feathered",
		displayName = "Feathered Wings",
		order = 8,
		shapes = { "standard", "feathered", "streamlined" },
		rigs = { "agile", "round" },
		compatibleClasses = { "Tide" },
		requiresAnyTags = { "wing:feather", "wing:fin" },
	},
	{
		className = "Verdant",
		slot = "accessories",
		variant = "sprout",
		displayName = "Verdant Sprout",
		order = 70,
		shapes = { "standard", "compact" },
	},
	{
		className = "Stone",
		slot = "accessories",
		variant = "crystal",
		displayName = "Stone Crystal Crown",
		order = 70,
		shapes = { "standard", "armored" },
		requiresTags = { "attachment:shoulder" },
	},
	{
		className = "Feral",
		slot = "accessories",
		variant = "fang",
		displayName = "Feral Fang Charm",
		order = 70,
		shapes = { "standard", "spiked" },
		requiresTags = { "attachment:crest" },
	},
	{
		className = "Tide",
		slot = "accessories",
		variant = "shell",
		displayName = "Tide Shell Charm",
		order = 70,
		shapes = { "standard", "streamlined" },
		requiresAnyTags = { "tail:fin" },
	},
	{
		className = "Gale",
		slot = "accessories",
		variant = "crest",
		displayName = "Gale Feather Crest",
		order = 70,
		shapes = { "standard", "feathered", "streamlined" },
		rigs = { "agile", "round" },
		compatibleClasses = { "Tide" },
		requiresAnyTags = { "wing:feather", "wing:fin" },
	},
	{
		className = "Shade",
		slot = "accessories",
		variant = "veil",
		displayName = "Shade Veil Fragment",
		order = 70,
		shapes = { "standard", "wispy" },
		requiresAnyTags = { "tail:wisp" },
	},
}

for _, variant in layerVariants do
	local lower = string.lower(variant.className)
	local rig = RIGS[variant.className]
	add({
		id = `gene.appearance.{variant.slot}.{lower}.{variant.variant}`,
		kind = "APPEARANCE",
		slot = variant.slot,
		classes = { variant.className },
		speciesIds = { `critter.{lower}` },
		compatibleClasses = variant.compatibleClasses,
		bodyRigFamilies = variant.rigs or { rig },
		bodyShapes = variant.shapes,
		requiresTags = variant.requiresTags,
		requiresAnyTags = variant.requiresAnyTags,
		assetId = `creature.layer.{variant.slot}.{lower}.{variant.variant}`,
		displayName = variant.displayName,
		layerOrder = variant.order,
		anchorKey = `anchor.{variant.slot}.{rig}`,
		pivotKey = `pivot.{variant.slot}.{rig}`,
		attachmentKey = if variant.slot == "accessories"
			then `attachment.accessories.{rig}`
			else nil,
	})
end

local abilityVariants = {
	{ className = "Stone", slot = "mouth", abilityId = "stone.rampart" },
	{ className = "Stone", slot = "back", abilityId = "stone.crush" },
	{ className = "Feral", slot = "mouth", abilityId = "feral.maul" },
	{ className = "Feral", slot = "tail", abilityId = "feral.fury" },
	{
		className = "Verdant",
		slot = "horn",
		abilityId = "verdant.bloom",
		compatibleClasses = { "Stone", "Tide" },
	},
	{ className = "Verdant", slot = "tail", abilityId = "verdant.bramble" },
	{ className = "Tide", slot = "mouth", abilityId = "tide.torrent" },
	{ className = "Tide", slot = "horn", abilityId = "tide.purge" },
	{ className = "Gale", slot = "mouth", abilityId = "gale.squall" },
	{
		className = "Gale",
		slot = "back",
		abilityId = "gale.tailwind",
		compatibleClasses = { "Feral" },
	},
	{ className = "Shade", slot = "horn", abilityId = "shade.curse" },
	{ className = "Shade", slot = "back", abilityId = "shade.terror" },
}

for _, variant in abilityVariants do
	local lower = string.lower(variant.className)
	add({
		id = `gene.ability.{variant.slot}.{variant.abilityId}`,
		kind = "ABILITY",
		slot = variant.slot,
		classes = { variant.className },
		speciesIds = { `critter.{lower}` },
		compatibleClasses = variant.compatibleClasses,
		abilityId = variant.abilityId,
	})
end

for _, list in fallbackByClassAndSlot do
	table.sort(list, function(a, b)
		if a.fallbackPriority ~= b.fallbackPriority then
			return a.fallbackPriority < b.fallbackPriority
		end
		return a.id < b.id
	end)
end

local function triplet(id: string)
	return { D = id, R1 = id, R2 = id }
end

local function defaultGenomes(className: string)
	local definition = CritterCatalog.getByClass(className)
	if definition == nil then
		return nil
	end
	local lower = string.lower(className)
	local appearanceSlots = {}
	for _, slot in APPEARANCE_SLOTS do
		appearanceSlots[slot] = triplet(`gene.appearance.{slot}.{lower}.default`)
	end
	local abilitySlots = {}
	for index, abilityId in definition.abilityIds do
		local slot = ABILITY_SLOT_BY_INDEX[index]
		abilitySlots[slot] = triplet(`gene.ability.{slot}.{abilityId}`)
	end
	abilitySlots.traits = triplet(`gene.ability.traits.{lower}.neutral`)
	return {
		appearanceGenome = { schemaVersion = 2, slots = appearanceSlots },
		abilityGenome = { schemaVersion = 2, slots = abilitySlots },
	}
end

local founderAppearance = {
	Stone = {
		body = "gene.appearance.body.stone.armored",
		eyes = "gene.appearance.eyes.stone.foreign_species",
		tail = "gene.appearance.tail.stone.crystal",
		markings = "gene.appearance.markings.stone.crystal",
		accessories = "gene.appearance.accessories.stone.crystal",
	},
	Feral = {
		body = "gene.appearance.body.feral.spiked",
		eyes = "gene.appearance.eyes.feral.slit",
		tail = "gene.appearance.tail.feral.flame",
		markings = "gene.appearance.markings.feral.scar",
		accessories = "gene.appearance.accessories.feral.fang",
	},
	Verdant = {
		body = "gene.appearance.body.verdant.compact",
		eyes = "gene.appearance.eyes.verdant.wide",
		tail = "gene.appearance.tail.verdant.leafy",
		markings = "gene.appearance.markings.verdant.speckled",
		accessories = "gene.appearance.accessories.verdant.sprout",
	},
	Tide = {
		body = "gene.appearance.body.tide.streamlined",
		eyes = "gene.appearance.eyes.tide.deep",
		wings = "gene.appearance.wings.gale.feathered",
		tail = "gene.appearance.tail.tide.fin",
		markings = "gene.appearance.markings.tide.current",
		accessories = "gene.appearance.accessories.tide.shell",
	},
	Gale = {
		body = "gene.appearance.body.gale.plumed",
		eyes = "gene.appearance.eyes.gale.keen",
		tail = "gene.appearance.tail.gale.feather",
		markings = "gene.appearance.markings.gale.wind",
		accessories = "gene.appearance.accessories.gale.crest",
	},
	Shade = {
		body = "gene.appearance.body.shade.wispy",
		eyes = "gene.appearance.eyes.shade.glow",
		tail = "gene.appearance.tail.shade.wisp",
		markings = "gene.appearance.markings.shade.veil",
		accessories = "gene.appearance.accessories.shade.veil",
	},
}

local founderAbility = {
	Stone = {
		mouth = "gene.ability.mouth.stone.rampart",
		horn = "gene.ability.horn.verdant.bloom",
	},
	Feral = {
		mouth = "gene.ability.mouth.feral.maul",
		back = "gene.ability.back.gale.tailwind",
	},
	Verdant = {
		horn = "gene.ability.horn.verdant.bloom",
	},
	Tide = {
		horn = "gene.ability.horn.tide.purge",
	},
	Gale = {
		mouth = "gene.ability.mouth.gale.squall",
	},
	Shade = {
		horn = "gene.ability.horn.shade.curse",
	},
}

local function applyFounderVariants(genome, preset)
	for slot, geneId in preset do
		local previous = genome.slots[slot]
		genome.slots[slot] = {
			D = geneId,
			R1 = previous.D,
			R2 = previous.D,
		}
	end
end

local function founderGenomes(className: string)
	local genomes = defaultGenomes(className)
	if genomes == nil then
		return nil
	end
	applyFounderVariants(genomes.appearanceGenome, founderAppearance[className] or {})
	applyFounderVariants(genomes.abilityGenome, founderAbility[className] or {})
	return genomes
end

local function classAllowed(definition, className: string): boolean
	return definition.classes == nil or table.find(definition.classes, className) ~= nil
end

local function classExpressible(definition, className: string): boolean
	if classAllowed(definition, className) then
		return true
	end
	return definition.compatibleClasses ~= nil
		and table.find(definition.compatibleClasses, className) ~= nil
end

local function speciesExpressible(definition, className: string, speciesId: string?): boolean
	if speciesId == nil or definition.speciesIds == nil then
		return true
	end
	if table.find(definition.speciesIds, speciesId) ~= nil then
		return true
	end
	return definition.compatibleClasses ~= nil
		and table.find(definition.compatibleClasses, className) ~= nil
end

local function rigAllowed(definition, rigFamily: string?): boolean
	return definition.bodyRigFamilies == nil
		or (rigFamily ~= nil and table.find(definition.bodyRigFamilies, rigFamily) ~= nil)
end

local function providedTags(definition): { [string]: boolean }
	local result = {}
	for _, tag in definition.providesTags or {} do
		result[tag] = true
	end
	return result
end

local function tagsAllowed(definition, tagSet: { [string]: boolean }?): boolean
	if definition.requiresTags ~= nil then
		for _, tag in definition.requiresTags do
			if tagSet == nil or tagSet[tag] ~= true then
				return false
			end
		end
	end
	if definition.requiresAnyTags ~= nil then
		local found = false
		for _, tag in definition.requiresAnyTags do
			if tagSet ~= nil and tagSet[tag] == true then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

local function appearanceExpressible(
	definition,
	className: string,
	rigFamily: string?,
	bodyShape: string?,
	tagSet: { [string]: boolean }?
): boolean
	if not classExpressible(definition, className) or not rigAllowed(definition, rigFamily) then
		return false
	end
	if
		definition.bodyShapes ~= nil
		and (bodyShape == nil or table.find(definition.bodyShapes, bodyShape) == nil)
	then
		return false
	end
	return tagsAllowed(definition, tagSet)
end

return table.freeze({
	AppearanceSlots = table.freeze(APPEARANCE_SLOTS),
	AbilitySlots = table.freeze(ABILITY_SLOTS),
	Positions = table.freeze(POSITIONS),
	get = function(id: string)
		return if definitions[id] == nil then nil else clone(definitions[id])
	end,
	allById = function()
		return clone(definitions)
	end,
	classAllowed = classAllowed,
	classExpressible = classExpressible,
	speciesExpressible = speciesExpressible,
	rigAllowed = rigAllowed,
	bodyTags = bodyTags,
	providedTags = providedTags,
	appearanceExpressible = appearanceExpressible,
	fallbacks = function(kind: string, className: string, slot: string)
		return clone(fallbackByClassAndSlot[`{kind}|{className}|{slot}`] or {})
	end,
	defaultGenomes = defaultGenomes,
	founderGenomes = founderGenomes,
})
