--!strict

return function(Harness)
	local CardCatalog = require("../../src/shared/Definitions/CardCatalog")

	local function effect(abilityId: string, kind: string)
		local definition = CardCatalog.getByAbilityId(abilityId)
		Harness.expect(definition ~= nil, `Missing card {abilityId}`)
		for _, candidate in definition.effects do
			if candidate.kind == kind then
				return candidate, definition
			end
		end
		error(`Missing {kind} effect on {abilityId}`)
	end

	Harness.test("Run 4 healing values preserve costs and targeting", function()
		local expected = {
			["verdant.mend"] = { 55, 1, "ALLY" },
			["verdant.renew"] = { 48, 1, "SELF" },
			["verdant.grove"] = { 30, 2, "ALL_ALLIES" },
			["verdant.bloom"] = { 35, 2, "ALL_ALLIES" },
			["tide.mend"] = { 50, 1, "ALLY" },
			["tide.renew"] = { 44, 1, "SELF" },
			["tide.purge"] = { 45, 1, "ALLY" },
		}
		for abilityId, values in expected do
			local heal, definition = effect(abilityId, "HEAL")
			Harness.equal(heal.amount, values[1])
			Harness.equal(definition.energyCost, values[2])
			Harness.equal(definition.targetingRule, values[3])
		end
	end)

	Harness.test("Run 4 shield values preserve costs and targeting", function()
		local expected = {
			["stone.guard"] = { 50, 1, "SELF" },
			["stone.bulwark"] = { 25, 2, "ALL_ALLIES" },
			["stone.rampart"] = { 30, 2, "ALL_ALLIES" },
			["tide.barrier"] = { 22, 2, "ALL_ALLIES" },
			["gale.ward"] = { 40, 1, "SELF" },
			["gale.shelter"] = { 20, 2, "ALL_ALLIES" },
			["tide.purge"] = { 15, 1, "ALLY" },
		}
		for abilityId, values in expected do
			local shield, definition = effect(abilityId, "SHIELD")
			Harness.equal(shield.amount, values[1])
			Harness.equal(definition.energyCost, values[2])
			Harness.equal(definition.targetingRule, values[3])
		end
	end)

	Harness.test("Run 4 poison values use two-round duration", function()
		local expected = {
			["verdant.seed"] = 12,
			["verdant.bramble"] = 10,
			["feral.rend"] = 9,
			["feral.maul"] = 9,
			["shade.toxin"] = 15,
		}
		for abilityId, magnitude in expected do
			local poison = effect(abilityId, "STATUS")
			Harness.equal(poison.statusId, "POISON")
			Harness.equal(poison.magnitude, magnitude)
			Harness.equal(poison.duration, 2)
		end
	end)
end
