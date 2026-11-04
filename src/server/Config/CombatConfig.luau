--!strict

-- Server-owned combat environment configuration. Clients receive a read-only projection for HUD
-- presentation and never submit or override these values.
local BloodMoon = table.freeze({
	Enabled = true,
	StartingRound = 10,
	InitialDamage = 50,
	DamageIncrement = 30,
	BypassesShields = true,
})

return table.freeze({
	BloodMoon = BloodMoon,
})
