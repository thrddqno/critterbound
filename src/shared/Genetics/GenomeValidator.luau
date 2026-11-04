--!strict

local function requireGenetics(name: string)
	if script ~= nil then
		return require(script.Parent[name])
	end
	return require(`./{name}`)
end

local GeneRegistry = requireGenetics("GeneRegistry")
local AppearanceResolver = requireGenetics("AppearanceResolver")
local AbilityResolver = requireGenetics("AbilityResolver")
local GenomeValidator = {}

local function addError(errors, code: string, message: string, path: string?)
	table.insert(errors, { code = code, message = message, path = path })
end

local function exactKeys(value, expected): boolean
	local count = 0
	for key in value do
		if not expected[key] then
			return false
		end
		count += 1
	end
	local expectedCount = 0
	for _ in expected do
		expectedCount += 1
	end
	return count == expectedCount
end

local function validateShape(genome, kind: string, slots, contentVersion: number?)
	local errors = {}
	local label = if kind == "APPEARANCE" then "appearance" else "ability"
	local registryVersion = contentVersion or GeneRegistry.ContentVersion
	if registryVersion ~= GeneRegistry.ContentVersion then
		addError(
			errors,
			"UNSUPPORTED_GENE_CONTENT_VERSION",
			`Gene content version {tostring(registryVersion)} is not registered`,
			"contentVersion"
		)
		return errors
	end
	if type(genome) ~= "table" then
		addError(errors, `INVALID_{string.upper(label)}_GENOME`, `Expected {label} genome table`)
		return errors
	end
	if genome.schemaVersion ~= 2 then
		addError(
			errors,
			"UNSUPPORTED_SCHEMA",
			`{label} genome schemaVersion must be 2`,
			"schemaVersion"
		)
	end
	if not exactKeys(genome, { schemaVersion = true, slots = true }) then
		addError(errors, "INVALID_GENOME_SHAPE", "Genome fields must match schema exactly", nil)
	end
	if type(genome.slots) ~= "table" then
		addError(errors, "INVALID_GENOME_SLOTS", "Expected named genome slots", "slots")
		return errors
	end
	local expectedSlots = {}
	for _, slot in slots do
		expectedSlots[slot] = true
	end
	if not exactKeys(genome.slots, expectedSlots) then
		addError(
			errors,
			"INVALID_GENOME_SLOTS",
			"Genome slots must match required loci exactly",
			"slots"
		)
	end
	local expectedPositions = { D = true, R1 = true, R2 = true }
	for _, slot in slots do
		local triplet = genome.slots[slot]
		if type(triplet) ~= "table" or not exactKeys(triplet, expectedPositions) then
			addError(
				errors,
				"INVALID_ALLELE_TRIPLET",
				"Locus requires exact D, R1, and R2 alleles",
				`slots.{slot}`
			)
			continue
		end
		for _, position in GeneRegistry.Positions do
			local geneId = triplet[position]
			local definition = if type(geneId) == "string"
				then GeneRegistry.getAtVersion(registryVersion, geneId)
				else nil
			if definition == nil then
				addError(
					errors,
					"UNKNOWN_GENE",
					"Allele references unknown gene",
					`slots.{slot}.{position}`
				)
			elseif definition.kind ~= kind or definition.slot ~= slot then
				addError(
					errors,
					"INCOMPATIBLE_GENE_SLOT",
					"Gene kind or locus is incompatible",
					`slots.{slot}.{position}`
				)
			end
		end
	end
	return errors
end

local function append(errors, result, prefix: string)
	if result.ok then
		return
	end
	for _, nested in result.errors do
		addError(
			errors,
			nested.code,
			nested.message,
			if prefix == ""
				then nested.path
				elseif nested.path == nil then prefix
				else `{prefix}.{nested.path}`
		)
	end
end

local function validate(appearanceGenome, abilityGenome, className: string, contentVersion: number?)
	local errors = {}
	append(
		errors,
		GenomeValidator.validateAppearance(appearanceGenome, className, contentVersion),
		"appearanceGenome"
	)
	append(
		errors,
		GenomeValidator.validateAbility(abilityGenome, className, contentVersion),
		"abilityGenome"
	)
	if #errors == 0 then
		local appearance = AppearanceResolver.resolve(appearanceGenome, className)
		if appearance.ok then
			append(
				errors,
				AbilityResolver.resolve(abilityGenome, className, appearance.value.speciesId),
				"abilityGenome"
			)
		end
	end
	return if #errors == 0 then { ok = true, value = true } else { ok = false, errors = errors }
end

GenomeValidator.validateAppearance = function(genome, className: string, contentVersion: number?)
	local errors = validateShape(genome, "APPEARANCE", GeneRegistry.AppearanceSlots, contentVersion)
	if #errors == 0 then
		append(errors, AppearanceResolver.resolve(genome, className), "")
	end
	return if #errors == 0 then { ok = true, value = true } else { ok = false, errors = errors }
end
GenomeValidator.validateAbility = function(genome, className: string, contentVersion: number?)
	local errors = validateShape(genome, "ABILITY", GeneRegistry.AbilitySlots, contentVersion)
	if #errors == 0 then
		append(errors, AbilityResolver.resolve(genome, className), "")
	end
	return if #errors == 0 then { ok = true, value = true } else { ok = false, errors = errors }
end
GenomeValidator.validate = validate

return table.freeze(GenomeValidator)
