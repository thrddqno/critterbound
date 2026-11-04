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
local CardCatalog = requireDefinition("CardCatalog")
local AbilityResolver = {}

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function cardAllowedForGene(definition, card, className: string): boolean
	if card.class == className then
		return true
	end
	return definition.compatibleClasses ~= nil
		and table.find(definition.compatibleClasses, className) ~= nil
		and definition.classes ~= nil
		and table.find(definition.classes, card.class) ~= nil
end

local function compatible(
	definition,
	className: string,
	speciesId: string?,
	slot: string,
	seenAbilities
): (boolean, string?)
	if definition.kind ~= "ABILITY" or definition.slot ~= slot then
		return false, "INCOMPATIBLE_GENE_LOCUS"
	end
	if not GeneRegistry.classExpressible(definition, className) then
		return false, "CLASS_INCOMPATIBLE"
	end
	if not GeneRegistry.speciesExpressible(definition, className, speciesId) then
		return false, "SPECIES_INCOMPATIBLE"
	end
	if definition.abilityId == nil then
		return slot == "traits", if slot == "traits" then nil else "MISSING_ABILITY"
	end
	local card = CardCatalog.getByAbilityId(definition.abilityId)
	if card == nil then
		return false, "MISSING_CARD_DEFINITION"
	end
	if not cardAllowedForGene(definition, card, className) then
		return false, "CARD_CLASS_INCOMPATIBLE"
	end
	if seenAbilities[definition.abilityId] then
		return false, "DUPLICATE_ABILITY"
	end
	return true, nil
end

local function resolveSlot(
	genome,
	className: string,
	speciesId: string?,
	slot: string,
	seenAbilities,
	dominantOnly: boolean?
)
	local triplet = genome.slots[slot]
	local dominantReason = "MISSING_DOMINANT_GENE"
	if type(triplet) == "table" then
		local positions = if dominantOnly then { "D" } else GeneRegistry.Positions
		for _, position in positions do
			local definition = GeneRegistry.get(triplet[position])
			local isCompatible = false
			local reason = "UNKNOWN_GENE"
			if definition ~= nil then
				isCompatible, reason =
					compatible(definition, className, speciesId, slot, seenAbilities)
			end
			if position == "D" then
				dominantReason = reason
			end
			if definition ~= nil and isCompatible then
				return definition, position, false, nil
			end
		end
	end
	for _, definition in GeneRegistry.fallbacks("ABILITY", className, slot) do
		local isCompatible = compatible(definition, className, speciesId, slot, seenAbilities)
		if isCompatible then
			return definition, "FALLBACK", true, dominantReason
		end
	end
	return nil, nil, nil, dominantReason
end

local function resolveInternal(genome, className: string, speciesId: string?, dominantOnly: boolean)
	if type(genome) ~= "table" or genome.schemaVersion ~= 2 or type(genome.slots) ~= "table" then
		return failure("INVALID_ABILITY_GENOME", "Ability genome schema 2 is required")
	end
	local abilityIds = {}
	local cardDefinitionIds = {}
	local cardClassesByAbilityId = {}
	local resolvedGenesBySlot = {}
	local sourcesBySlot = {}
	local fallbackSlots = {}
	local fallbackReasonsBySlot = {}
	local seenAbilities = {}
	for _, slot in GeneRegistry.AbilitySlots do
		local definition, position, usedFallback, fallbackReason =
			resolveSlot(genome, className, speciesId, slot, seenAbilities, dominantOnly)
		if definition == nil then
			return failure(
				"UNRESOLVED_ABILITY_GENE",
				`Ability locus {slot} has no compatible gene`,
				`slots.{slot}`
			)
		end
		resolvedGenesBySlot[slot] = definition.id
		sourcesBySlot[slot] = position
		if usedFallback then
			table.insert(fallbackSlots, slot)
			fallbackReasonsBySlot[slot] = fallbackReason
		end
		if definition.abilityId ~= nil then
			local card = CardCatalog.getByAbilityId(definition.abilityId)
			if card == nil then
				return failure(
					"MISSING_CARD_DEFINITION",
					"Ability gene has no card definition",
					definition.id
				)
			end
			seenAbilities[definition.abilityId] = true
			table.insert(abilityIds, definition.abilityId)
			table.insert(cardDefinitionIds, card.id)
			cardClassesByAbilityId[definition.abilityId] = card.class
		end
	end
	if #abilityIds ~= 4 then
		return failure(
			"INVALID_ABILITY_COUNT",
			"Ability genome must resolve exactly four abilities"
		)
	end
	return {
		ok = true,
		value = {
			abilityIds = abilityIds,
			cardDefinitionIds = cardDefinitionIds,
			cardClassesByAbilityId = cardClassesByAbilityId,
			resolvedGenesBySlot = resolvedGenesBySlot,
			sourcesBySlot = sourcesBySlot,
			fallbackSlots = fallbackSlots,
			fallbackReasonsBySlot = fallbackReasonsBySlot,
		},
	}
end

local function resolve(genome, className: string, speciesId: string?)
	return resolveInternal(genome, className, speciesId, false)
end

local function resolveDominant(genome, className: string, speciesId: string?)
	return resolveInternal(genome, className, speciesId, true)
end

local abilityGenesByAbilityId = {}
for _, definition in GeneRegistry.allById() do
	if definition.kind == "ABILITY" and definition.abilityId ~= nil then
		local list = abilityGenesByAbilityId[definition.abilityId] or {}
		table.insert(list, definition)
		abilityGenesByAbilityId[definition.abilityId] = list
	end
end

local function cardClassFor(abilityId: string, className: string): string?
	local card = CardCatalog.getByAbilityId(abilityId)
	if card == nil then
		return nil
	end
	for _, definition in abilityGenesByAbilityId[abilityId] or {} do
		if
			GeneRegistry.classExpressible(definition, className)
			and definition.classes ~= nil
			and table.find(definition.classes, card.class) ~= nil
		then
			return card.class
		end
	end
	return nil
end

AbilityResolver.resolve = resolve
AbilityResolver.resolveDominant = resolveDominant
AbilityResolver.cardClassFor = cardClassFor
return table.freeze(AbilityResolver)
