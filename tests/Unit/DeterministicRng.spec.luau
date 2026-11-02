--!strict

return function(Harness)
	local Rng = require("../../src/shared/Battle/DeterministicRng")

	Harness.test("deterministic RNG locks golden vector", function()
		local created = Rng.new(1)
		Harness.expect(created.ok)
		local state, first = Rng.next(created.value)
		state, first = Rng.next(state)
		Harness.equal(first, 282475249)
		Harness.equal(state.drawCount, 2)
	end)

	Harness.test("deterministic shuffle copies input", function()
		local values = { "a", "b", "c", "d", "e" }
		local before = Harness.clone(values)
		local created = Rng.new(42)
		local stateA, shuffledA = Rng.shuffle(created.value, values)
		local stateB, shuffledB = Rng.shuffle(created.value, values)
		Harness.deepEqual(shuffledA, shuffledB)
		Harness.deepEqual(stateA, stateB)
		Harness.deepEqual(values, before)
	end)

	Harness.test("deterministic RNG rejects invalid seeds", function()
		Harness.expect(not Rng.new(0).ok)
		Harness.expect(not Rng.new(-1).ok)
		Harness.expect(not Rng.new(1.5).ok)
	end)
end
