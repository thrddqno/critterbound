--!strict

return function(Harness)
	local GeneRegistry = require("../../src/shared/Genetics/GeneRegistry")
	local InheritanceEngine = require("../../src/server/Genetics/InheritanceEngine")

	local function parent(className: string)
		local genomes = GeneRegistry.defaultGenomes(className)
		return {
			class = className,
			appearanceGenome = genomes.appearanceGenome,
			abilityGenome = genomes.abilityGenome,
		}
	end

	Harness.test("inheritance is deterministic and consumes exactly 72 draws by default", function()
		local first = InheritanceEngine.inherit(parent("Stone"), parent("Feral"), "Stone", 4107)
		local second = InheritanceEngine.inherit(parent("Stone"), parent("Feral"), "Stone", 4107)
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first.value, second.value)
		Harness.equal(first.value.rng.drawCount, 72)
		Harness.equal(#first.value.trace.selections, 36)
		Harness.equal(#first.value.trace.mutations, 0)
	end)

	Harness.test("inheritance chooses both parents independently", function()
		local result = InheritanceEngine.inherit(parent("Stone"), parent("Feral"), "Stone", 901)
		Harness.expect(result.ok)
		local counts = { A = 0, B = 0 }
		for _, selection in result.value.trace.selections do
			counts[selection.parent] += 1
		end
		Harness.expect(counts.A > 0 and counts.B > 0)
	end)

	Harness.test("seeded inheritance follows provisional 75 20 5 allele weights", function()
		local rng = { algorithm = "PARK_MILLER_V1", state = 12345, drawCount = 0 }
		local counts = { D = 0, R1 = 0, R2 = 0 }
		for _ = 1, 300 do
			local result = InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", rng)
			Harness.expect(result.ok)
			rng = result.value.rng
			for _, selection in result.value.trace.selections do
				counts[selection.parentPosition] += 1
			end
		end
		local total = counts.D + counts.R1 + counts.R2
		Harness.expect(counts.D / total > 0.72 and counts.D / total < 0.78)
		Harness.expect(counts.R1 / total > 0.17 and counts.R1 / total < 0.23)
		Harness.expect(counts.R2 / total > 0.035 and counts.R2 / total < 0.065)
	end)

	Harness.test("compatibility fallback replaces dominant and preserves carriers", function()
		local found = nil
		for seed = 1, 30 do
			local result =
				InheritanceEngine.inherit(parent("Feral"), parent("Feral"), "Stone", seed)
			Harness.expect(result.ok)
			if #result.value.trace.fallbacks > 0 then
				found = result
				break
			end
		end
		Harness.expect(found ~= nil)
		for _, fallback in found.value.trace.fallbacks do
			local genome = if fallback.genome == "APPEARANCE"
				then found.value.appearanceGenome
				else found.value.abilityGenome
			Harness.equal(genome.slots[fallback.slot].D, fallback.toGeneId)
			Harness.expect(genome.slots[fallback.slot].R1 ~= nil)
			Harness.expect(genome.slots[fallback.slot].R2 ~= nil)
		end
	end)

	Harness.test("mutation disabled consumes no extra draws and changes no inheritance", function()
		local implicit = InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 8080)
		local explicit =
			InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 8080, {
				mutation = { enabled = false, chancePerTenThousand = 10_000 },
			})
		Harness.expect(implicit.ok and explicit.ok)
		Harness.deepEqual(implicit.value, explicit.value)
		Harness.equal(explicit.value.rng.drawCount, 72)
	end)

	Harness.test("enabled mutation is deterministic and bounded", function()
		local options = { mutation = { enabled = true, chancePerTenThousand = 10_000 } }
		local first =
			InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 5150, options)
		local second =
			InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 5150, options)
		Harness.expect(first.ok and second.ok)
		Harness.deepEqual(first.value, second.value)
		Harness.expect(#first.value.trace.mutations > 0)
		Harness.expect(#first.value.trace.mutations <= 36)
		Harness.equal(first.value.rng.drawCount, 108 + #first.value.trace.mutations)
	end)

	Harness.test("invalid mutation rate and parent genome reject structurally", function()
		local invalidRate =
			InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 1, {
				mutation = { enabled = true, chancePerTenThousand = 10_001 },
			})
		Harness.expect(Harness.hasError(invalidRate, "INVALID_MUTATION_RATE"))
		local invalidParent = parent("Stone")
		invalidParent.abilityGenome.slots.mouth.D = "unknown"
		Harness.expect(
			Harness.hasError(
				InheritanceEngine.inherit(invalidParent, parent("Stone"), "Stone", 1),
				"UNKNOWN_GENE"
			)
		)
		Harness.expect(
			Harness.hasError(
				InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Unknown", 1),
				"INVALID_OFFSPRING_CLASS"
			)
		)
		Harness.expect(
			Harness.hasError(
				InheritanceEngine.inherit(parent("Stone"), parent("Stone"), "Stone", 1, true),
				"INVALID_INHERITANCE_OPTIONS"
			)
		)
	end)
end
