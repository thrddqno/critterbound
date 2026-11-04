--!strict

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local GeneRegistry = requireGenetics("GeneRegistry")
local AppearanceResolver = {}

local function failure(code: string, message: string, path: string?)
	return { ok = false, errors = { { code = code, message = message, path = path } } }
end

local function compatibilityReason(
	definition,
	className: string,
	slot: string,
	rigFamily: string?,
	speciesId: string?,
	bodyShape: string?,
	tagSet: { [string]: boolean }?
): string?
	if definition == nil then
		return "UNKNOWN_GENE"
	end
	if definition.kind ~= "APPEARANCE" or definition.slot ~= slot then
		return "INCOMPATIBLE_GENE_LOCUS"
	end
	if not GeneRegistry.speciesExpressible(definition, className, speciesId) then
		return "SPECIES_INCOMPATIBLE"
	end
	if
		not GeneRegistry.appearanceExpressible(definition, className, rigFamily, bodyShape, tagSet)
	then
		return "APPEARANCE_INCOMPATIBLE"
	end
	return nil
end

local function candidateForSlot(
	genome,
	className: string,
	slot: string,
	rigFamily: string?,
	speciesId: string?,
	bodyShape: string?,
	tagSet: { [string]: boolean }?,
	dominantOnly: boolean?
)
	local triplet = genome.slots[slot]
	local dominantReason = "MISSING_DOMINANT_GENE"
	if type(triplet) == "table" then
		local positions = if dominantOnly then { "D" } else GeneRegistry.Positions
		for _, position in positions do
			local definition = GeneRegistry.get(triplet[position])
			local reason = compatibilityReason(
				definition,
				className,
				slot,
				rigFamily,
				speciesId,
				bodyShape,
				tagSet
			)
			if position == "D" then
				dominantReason = reason
			end
			if definition ~= nil and reason == nil then
				return definition, position, false, nil
			end
		end
	end
	for _, definition in GeneRegistry.fallbacks("APPEARANCE", className, slot) do
		if
			compatibilityReason(
				definition,
				className,
				slot,
				rigFamily,
				speciesId,
				bodyShape,
				tagSet
			) == nil
		then
			return definition, "FALLBACK", true, dominantReason
		end
	end
	return nil, nil, nil, dominantReason
end

local function resolveInternal(genome, className: string, dominantOnly: boolean)
	if type(genome) ~= "table" or genome.schemaVersion ~= 2 or type(genome.slots) ~= "table" then
		return failure("INVALID_APPEARANCE_GENOME", "Appearance genome schema 2 is required")
	end
	local body, bodyPosition, bodyFallback, bodyFallbackReason =
		candidateForSlot(genome, className, "body", nil, nil, nil, nil, dominantOnly)
	if body == nil or body.bodyRigFamily == nil then
		return failure(
			"UNRESOLVED_APPEARANCE_GENE",
			"Body locus has no compatible gene",
			"slots.body"
		)
	end
	local bodyShape = body.bodyShape or "standard"
	local tagSet = GeneRegistry.providedTags(body)
	local layers = {}
	local resolvedGenesBySlot = { body = body.id }
	local sourcesBySlot = { body = bodyPosition }
	local fallbackSlots = if bodyFallback then { "body" } else {}
	local fallbackReasonsBySlot = if bodyFallback then { body = bodyFallbackReason } else {}
	for _, slot in GeneRegistry.AppearanceSlots do
		if slot ~= "body" then
			local definition, position, usedFallback, fallbackReason = candidateForSlot(
				genome,
				className,
				slot,
				body.bodyRigFamily,
				body.speciesId,
				bodyShape,
				tagSet,
				dominantOnly
			)
			if definition == nil then
				return failure(
					"UNRESOLVED_APPEARANCE_GENE",
					`Appearance locus {slot} has no compatible gene`,
					`slots.{slot}`
				)
			end
			resolvedGenesBySlot[slot] = definition.id
			sourcesBySlot[slot] = position
			if usedFallback then
				table.insert(fallbackSlots, slot)
				fallbackReasonsBySlot[slot] = fallbackReason
			end
			table.insert(layers, {
				slot = slot,
				geneId = definition.id,
				assetId = definition.assetId,
				order = definition.layerOrder,
				anchorKey = definition.anchorKey,
				pivotKey = definition.pivotKey,
				attachmentKey = definition.attachmentKey,
			})
		end
	end
	table.sort(layers, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.geneId < b.geneId
	end)
	return {
		ok = true,
		value = {
			bodyGeneId = body.id,
			speciesId = body.speciesId,
			bodyRigFamily = body.bodyRigFamily,
			bodyShape = bodyShape,
			spriteRigId = body.spriteRigId or string.lower(className),
			baseAssetId = body.assetId,
			anchorKey = body.anchorKey,
			pivotKey = body.pivotKey,
			layers = layers,
			resolvedGenesBySlot = resolvedGenesBySlot,
			sourcesBySlot = sourcesBySlot,
			fallbackSlots = fallbackSlots,
			fallbackReasonsBySlot = fallbackReasonsBySlot,
		},
	}
end

local function resolve(genome, className: string)
	return resolveInternal(genome, className, false)
end

local function resolveDominant(genome, className: string)
	return resolveInternal(genome, className, true)
end

AppearanceResolver.resolve = resolve
AppearanceResolver.resolveDominant = resolveDominant
return table.freeze(AppearanceResolver)
