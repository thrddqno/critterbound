--!strict

return function(Harness)
	local CombatStats = require("../../src/shared/Battle/CombatStats")
	local CritterCatalog = require("../../src/shared/Definitions/CritterCatalog")

	Harness.test("Health converts to maximum HP", function()
		Harness.equal(CombatStats.maxHealth(0), 150)
		Harness.equal(CombatStats.maxHealth(27), 258)
		Harness.equal(CombatStats.maxHealth(52), 358)
	end)

	Harness.test("all class baselines produce specified maximum HP", function()
		local expected = {
			Gale = { health = 27, maxHealth = 258 },
			Shade = { health = 29, maxHealth = 266 },
			Feral = { health = 31, maxHealth = 274 },
			Tide = { health = 39, maxHealth = 306 },
			Verdant = { health = 43, maxHealth = 322 },
			Stone = { health = 52, maxHealth = 358 },
		}
		for className, values in expected do
			local definition = CritterCatalog.getByClass(className)
			Harness.equal(definition.baseStats.health, values.health)
			Harness.equal(CombatStats.maxHealth(definition.baseStats.health), values.maxHealth)
		end
	end)

	Harness.test("current HP clamps to zero and maximum", function()
		Harness.equal(CombatStats.clampHealth(-10, 258), 0)
		Harness.equal(CombatStats.clampHealth(100, 258), 100)
		Harness.equal(CombatStats.clampHealth(300, 258), 258)
	end)
end
