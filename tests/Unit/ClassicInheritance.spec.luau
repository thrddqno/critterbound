--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local GenomeValidator = require("../../src/shared/Genetics/GenomeValidator")
	local ClassicInheritance = require("../../src/server/Genetics/ClassicInheritancePolicy")
	local ClassInheritance = require("../../src/server/Genetics/ClassInheritancePolicy")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")
	local DeckBuilder = require("../../src/shared/Battle/DeckBuilder")
	local DeckRules = require("../../src/shared/Battle/DeckRules")

	local function parent(className: string)
		local genomes = GeneRegistry.defaultGenomes(className)
		return {
			class = className,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
		}
	end

	Harness.test("Classic policy is deterministic and traces all 36 inherited positions", function()
		local first = ClassicInheritance.inherit(parent("Stone"), parent("Feral"), "Stone", 4107)
		local second = InheritanceEngine.inheritWithPolicy(
			"CLASSIC_INHERITANCE_V1",
			parent("Stone"),
			parent("Feral"),
			"Stone",
			4107
		)
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first, second)
		Harness.equal(first.value.trace.algorithm, "CLASSIC_INHERITANCE_V1")
		Harness.equal(first.value.trace.contentVersion, GeneRegistry.ContentVersion)
		Harness.equal(#first.value.trace.selections, 36)
		Harness.equal(first.value.rng.drawCount, 72)
		Harness.equal(first.value.appearanceGenome.schemaVersion, 2)
		Harness.equal(first.value.abilityGenome.schemaVersion, 2)
		Harness.expect(
			GenomeValidator.validate(
				first.value.appearanceGenome,
				first.value.abilityGenome,
				"Stone",
				GeneRegistry.ContentVersion
			).ok
		)
	end)

	Harness.test("Classic policy chooses both parents and transmits hidden positions", function()
		local result = ClassicInheritance.inherit(parent("Stone"), parent("Feral"), "Stone", 901)
		Harness.expect(result.ok)
		local parents = { A = 0, B = 0 }
		local positions = { D = 0, R1 = 0, R2 = 0 }
		for _, selection in result.value.trace.selections do
			parents[selection.parent] += 1
			positions[selection.parentPosition] += 1
		end
		Harness.expect(parents.A > 0 and parents.B > 0)
		Harness.expect(positions.R1 > 0 and positions.R2 > 0)
	end)

	Harness.test("Classic dominant source distribution matches 37.5 9.375 3.125 weights", function()
		local rng = { algorithm = "PARK_MILLER_V1", state = 12345, drawCount = 0 }
		local counts = {
			["A:D"] = 0,
			["A:R1"] = 0,
			["A:R2"] = 0,
			["B:D"] = 0,
			["B:R1"] = 0,
			["B:R2"] = 0,
		}
		local samples = 0
		for _ = 1, 3_000 do
			local result =
				ClassicInheritance.inherit(parent("Stone"), parent("Stone"), "Stone", rng)
			Harness.expect(result.ok)
			rng = result.value.rng
			for _, selection in result.value.trace.selections do
				if selection.childPosition == "D" then
					counts[`{selection.parent}:{selection.parentPosition}`] += 1
					samples += 1
				end
			end
		end
		local expected = {
			["A:D"] = 0.375,
			["A:R1"] = 0.09375,
			["A:R2"] = 0.03125,
			["B:D"] = 0.375,
			["B:R1"] = 0.09375,
			["B:R2"] = 0.03125,
		}
		for source, probability in expected do
			local observed = counts[source] / samples
			Harness.expect(
				math.abs(observed - probability) < 0.012,
				`{source}: expected {probability}, observed {observed}`
			)
		end
	end)

	Harness.test("hidden carrier can emerge as dominant over two generations", function()
		local carrier = parent("Stone")
		local ordinary = parent("Stone")
		local hiddenId = "gene.appearance.eyes.universal.bright"
		carrier.appearanceGenome.slots.eyes.R1 = hiddenId
		local firstGeneration = nil
		for seed = 1, 200 do
			local result = ClassicInheritance.inherit(carrier, ordinary, "Stone", seed)
			Harness.expect(result.ok)
			local eyes = result.value.appearanceGenome.slots.eyes
			if eyes.R1 == hiddenId or eyes.R2 == hiddenId then
				firstGeneration = {
					class = "Stone",
					appearanceGenome = result.value.appearanceGenome,
					abilityGenome = result.value.abilityGenome,
				}
				break
			end
		end
		Harness.expect(firstGeneration ~= nil)
		local emerged = false
		for seed = 201, 600 do
			local result = ClassicInheritance.inherit(firstGeneration, ordinary, "Stone", seed)
			Harness.expect(result.ok)
			if result.value.appearanceGenome.slots.eyes.D == hiddenId then
				emerged = true
				break
			end
		end
		Harness.expect(emerged)
	end)

	Harness.test("class policy preserves same class and samples either mixed parent", function()
		local same = ClassInheritance.resolve("Tide", "Tide", 99)
		Harness.expect(same.ok)
		Harness.equal(same.value.class, "Tide")
		Harness.equal(same.value.parent, "SHARED")
		Harness.equal(same.value.rng.drawCount, 0)

		local counts = { Tide = 0, Gale = 0 }
		local rng = { algorithm = "PARK_MILLER_V1", state = 77, drawCount = 0 }
		for _ = 1, 2_000 do
			local result = ClassInheritance.resolve("Tide", "Gale", rng)
			Harness.expect(result.ok)
			counts[result.value.class] += 1
			rng = result.value.rng
		end
		Harness.expect(math.abs(counts.Tide / 2_000 - 0.5) < 0.04)
		Harness.expect(counts.Tide > 0 and counts.Gale > 0)
	end)

	Harness.test(
		"Classic fallback repairs phenotype without rewriting inherited genotype",
		function()
			local result =
				ClassicInheritance.inherit(parent("Feral"), parent("Feral"), "Stone", 5150)
			Harness.expect(result.ok)
			local appearanceBefore = Harness.clone(result.value.appearanceGenome)
			local abilityBefore = Harness.clone(result.value.abilityGenome)
			Harness.expect(#result.value.trace.fallbacks > 0)
			Harness.equal(
				result.value.appearanceGenome.slots.body.D,
				"gene.appearance.body.feral.default"
			)
			Harness.equal(
				result.value.phenotype.appearance.bodyGeneId,
				"gene.appearance.body.stone.default"
			)
			Harness.deepEqual(result.value.appearanceGenome, appearanceBefore)
			Harness.deepEqual(result.value.abilityGenome, abilityBefore)
			Harness.equal(#result.value.phenotype.abilities.abilityIds, 4)
			Harness.equal(#result.value.phenotype.abilities.cardDefinitionIds, 4)
		end
	)

	Harness.test("Classic abilities retain eight-card Critter and 24-card team decks", function()
		local result = ClassicInheritance.inherit(parent("Tide"), parent("Gale"), "Tide", 8080)
		Harness.expect(result.ok)
		local definitionIds = result.value.phenotype.abilities.cardDefinitionIds
		Harness.equal(#definitionIds, 4)

		local one = DeckBuilder.build(1, {
			{ sourceCritterInstanceId = "child:1", definitionIds = definitionIds },
		}, {
			AbilitiesPerCritter = 4,
			CopiesPerCard = 2,
			TeamDeckSize = 8,
		})
		Harness.expect(one.ok)
		Harness.equal(#one.value.cardInstances, 8)

		local team = DeckBuilder.build(1, {
			{ sourceCritterInstanceId = "child:1", definitionIds = definitionIds },
			{ sourceCritterInstanceId = "child:2", definitionIds = definitionIds },
			{ sourceCritterInstanceId = "child:3", definitionIds = definitionIds },
		}, DeckRules.Default)
		Harness.expect(team.ok)
		Harness.equal(#team.value.cardInstances, 24)
	end)

	Harness.test("Classic policy rejects invalid genes versions and policy IDs", function()
		local invalid = parent("Stone")
		invalid.appearanceGenome.slots.eyes.D = "gene.missing"
		Harness.expect(
			Harness.hasError(
				ClassicInheritance.inherit(parent("Stone"), parent("Stone"), "Stone", 1, true),
				"INVALID_INHERITANCE_DEPENDENCIES"
			)
		)
		Harness.expect(
			Harness.hasError(
				ClassicInheritance.inherit(invalid, parent("Stone"), "Stone", 1),
				"UNKNOWN_GENE"
			)
		)
		Harness.expect(
			Harness.hasError(
				ClassicInheritance.inherit(parent("Stone"), parent("Stone"), "Stone", 1, {
					contentVersion = 2,
				}),
				"UNSUPPORTED_GENE_CONTENT_VERSION"
			)
		)
		Harness.expect(
			Harness.hasError(
				InheritanceEngine.inheritWithPolicy(
					"UNKNOWN",
					parent("Stone"),
					parent("Stone"),
					"Stone",
					1
				),
				"UNKNOWN_INHERITANCE_POLICY"
			)
		)
	end)
end
