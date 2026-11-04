--!strict

return function(Harness)
	local CriticalHits = require("../../src/shared/Battle/CriticalHits")
	local DeterministicRng = require("../../src/shared/Battle/DeterministicRng")

	Harness.test("Morale maps to capped critical chance", function()
		for morale, expected in { [0] = 0.05, [5] = 0.15, [10] = 0.25, [15] = 0.35 } do
			Harness.expect(math.abs(CriticalHits.chance(morale) - expected) < 1e-12)
		end
		Harness.equal(CriticalHits.chance(100), 0.35)
	end)

	Harness.test("fixed critical RNG seed reproduces identical outcomes", function()
		local first = DeterministicRng.new(12345).value
		local second = DeterministicRng.new(12345).value
		local firstOutcomes = {}
		local secondOutcomes = {}
		for _ = 1, 12 do
			local firstCritical
			local secondCritical
			first, firstCritical = CriticalHits.roll(first, 10, DeterministicRng)
			second, secondCritical = CriticalHits.roll(second, 10, DeterministicRng)
			table.insert(firstOutcomes, firstCritical)
			table.insert(secondOutcomes, secondCritical)
		end
		Harness.deepEqual(firstOutcomes, secondOutcomes)
		Harness.deepEqual(first, second)
		Harness.equal(first.drawCount, 12)
	end)
end
