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
): boolean
	if
		definition.kind ~= "ABILITY"
		or definition.slot ~= slot
		or not GeneRegistry.classExpressible(definition, className)
		or not GeneRegistry.speciesExpressible(definition, className, speciesId)
	then
		return false
	end
	if definition.abilityId == nil then
		return slot == "traits"
	end
	local card = CardCatalog.getByAbilityId(definition.abilityId)
	return card ~= nil
		and cardAllowedForGene(definition, card, className)
		and not seenAbilities[definition.abilityId]
end

local function resolveSlot(
	genome,
	className: string,
	speciesId: string?,
	slot: string,
	seenAbilities
)
	local triplet = genome.slots[slot]
	if type(triplet) == "table" then
		for _, position in GeneRegistry.Positions do
			local definition = GeneRegistry.get(triplet[position])
			if
				definition ~= nil
				and compatible(definition, className, speciesId, slot, seenAbilities)
			then
				return definition, position, false
			end
		end
	end
	for _, definition in GeneRegistry.fallbacks("ABILITY", className, slot) do
		if compatible(definition, className, speciesId, slot, seenAbilities) then
			return definition, "FALLBACK", true
		end
	end
	return nil, nil, nil
end

local function resolve(genome, className: string, speciesId: string?)
	if type(genome) ~= "table" or genome.schemaVersion ~= 2 or type(genome.slots) ~= "table" then
		return failure("INVALID_ABILITY_GENOME", "Ability genome schema 2 is required")
	end
	local abilityIds = {}
	local cardDefinitionIds = {}
	local cardClassesByAbilityId = {}
	local resolvedGenesBySlot = {}
	local sourcesBySlot = {}
	local fallbackSlots = {}
	local seenAbilities = {}
	for _, slot in GeneRegistry.AbilitySlots do
		local definition, position, usedFallback =
			resolveSlot(genome, className, speciesId, slot, seenAbilities)
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
		},
	}
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
AbilityResolver.cardClassFor = cardClassFor
return table.freeze(AbilityResolver)
