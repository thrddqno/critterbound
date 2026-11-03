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

local function allowedForCandidate(
	definition,
	className: string,
	slot: string,
	rigFamily: string?,
	speciesId: string?,
	bodyShape: string?,
	tagSet: { [string]: boolean }?
): boolean
	return definition.kind == "APPEARANCE"
		and definition.slot == slot
		and GeneRegistry.speciesExpressible(definition, className, speciesId)
		and GeneRegistry.appearanceExpressible(definition, className, rigFamily, bodyShape, tagSet)
end

local function candidateForSlot(
	genome,
	className: string,
	slot: string,
	rigFamily: string?,
	speciesId: string?,
	bodyShape: string?,
	tagSet: { [string]: boolean }?
)
	local triplet = genome.slots[slot]
	if type(triplet) == "table" then
		for _, position in GeneRegistry.Positions do
			local definition = GeneRegistry.get(triplet[position])
			if
				definition ~= nil
				and allowedForCandidate(
					definition,
					className,
					slot,
					rigFamily,
					speciesId,
					bodyShape,
					tagSet
				)
			then
				return definition, position, false
			end
		end
	end
	for _, definition in GeneRegistry.fallbacks("APPEARANCE", className, slot) do
		if
			allowedForCandidate(
				definition,
				className,
				slot,
				rigFamily,
				speciesId,
				bodyShape,
				tagSet
			)
		then
			return definition, "FALLBACK", true
		end
	end
	return nil, nil, nil
end

local function resolve(genome, className: string)
	if type(genome) ~= "table" or genome.schemaVersion ~= 2 or type(genome.slots) ~= "table" then
		return failure("INVALID_APPEARANCE_GENOME", "Appearance genome schema 2 is required")
	end
	local body, bodyPosition, bodyFallback = candidateForSlot(genome, className, "body")
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
	for _, slot in GeneRegistry.AppearanceSlots do
		if slot ~= "body" then
			local definition, position, usedFallback = candidateForSlot(
				genome,
				className,
				slot,
				body.bodyRigFamily,
				body.speciesId,
				bodyShape,
				tagSet
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
		},
	}
end

AppearanceResolver.resolve = resolve
return table.freeze(AppearanceResolver)
