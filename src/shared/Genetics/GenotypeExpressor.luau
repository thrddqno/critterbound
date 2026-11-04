--!strict

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local function requireDefinition(name: string)
	if script ~= nil then
		return require(script.Parent.Parent.Definitions[name])
	end
	return require(`../Definitions/{name}`)
end

local GeneRegistry = requireGenetics("GeneRegistry")
local GenomeValidator = requireGenetics("GenomeValidator")
local AppearanceResolver = requireGenetics("AppearanceResolver")
local AbilityResolver = requireGenetics("AbilityResolver")
local CritterCatalog = requireDefinition("CritterCatalog")
local GenotypeExpressor = {}

local ACTIVE_ABILITY_SLOTS = { "mouth", "horn", "back", "tail" }

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function traceEntry(kind: string, slot: string, genome, resolution, contentVersion: number)
	local source = resolution.sourcesBySlot[slot]
	local usedFallback = source == "FALLBACK"
	return {
		genome = kind,
		locus = slot,
		inheritedDominantGene = genome.slots[slot].D,
		expressedGene = resolution.resolvedGenesBySlot[slot],
		compatibilityDecision = if usedFallback then "PHENOTYPE_FALLBACK" else "DOMINANT_EXPRESSED",
		fallbackReason = if usedFallback then resolution.fallbackReasonsBySlot[slot] else nil,
		geneContentVersion = contentVersion,
	}
end

local function express(
	appearanceGenome,
	abilityGenome,
	authoritativeClass: string,
	geneContentVersion: number?
)
	local contentVersion = geneContentVersion or GeneRegistry.ContentVersion
	if
		type(authoritativeClass) ~= "string"
		or CritterCatalog.getByClass(authoritativeClass) == nil
	then
		return failure("INVALID_CRITTER_CLASS", "Authoritative Critter class is unknown", "class")
	end

	local validation = GenomeValidator.validate(
		appearanceGenome,
		abilityGenome,
		authoritativeClass,
		contentVersion
	)
	if not validation.ok then
		return validation
	end

	local appearance = AppearanceResolver.resolveDominant(appearanceGenome, authoritativeClass)
	if not appearance.ok then
		return appearance
	end
	local abilities = AbilityResolver.resolveDominant(
		abilityGenome,
		authoritativeClass,
		appearance.value.speciesId
	)
	if not abilities.ok then
		return abilities
	end

	local seenAbilities = {}
	if #abilities.value.abilityIds ~= #ACTIVE_ABILITY_SLOTS then
		return failure("INVALID_ABILITY_COUNT", "Phenotype must contain exactly four abilities")
	end
	for _, abilityId in abilities.value.abilityIds do
		if seenAbilities[abilityId] then
			return failure("DUPLICATE_ABILITY_ID", "Phenotype abilities must be unique")
		end
		seenAbilities[abilityId] = true
	end

	local entries = {}
	for _, slot in GeneRegistry.AppearanceSlots do
		table.insert(
			entries,
			traceEntry("APPEARANCE", slot, appearanceGenome, appearance.value, contentVersion)
		)
	end
	for _, slot in ACTIVE_ABILITY_SLOTS do
		table.insert(
			entries,
			traceEntry("ABILITY", slot, abilityGenome, abilities.value, contentVersion)
		)
	end

	return {
		ok = true,
		value = {
			class = authoritativeClass,
			geneContentVersion = contentVersion,
			phenotype = {
				appearance = appearance.value,
				abilities = abilities.value,
			},
			trace = {
				geneContentVersion = contentVersion,
				entries = entries,
			},
		},
	}
end

GenotypeExpressor.express = express

return table.freeze(GenotypeExpressor)
