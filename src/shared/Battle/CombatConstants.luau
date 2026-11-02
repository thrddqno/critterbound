--!strict

-- Documented Run 4B tuning constants. Changing any value here is replay-breaking.

local CombatConstants = {
	AdvantageMultiplier = 1.15,
	DisadvantageMultiplier = 0.85,
	NeutralMultiplier = 1.0,

	-- Flat defense reduction applied after class and attack modifiers.
	DefenseReductionRatio = 0.5,

	-- Ordinary shields last through the current resolution and expire at its round end.
	ShieldDurationRounds = 0,

	MaxStacks = {
		POISON = 5,
		ATTACK_UP = 3,
		ATTACK_DOWN = 3,
		SPEED_UP = 3,
		SPEED_DOWN = 3,
	},

	-- Per-round economy and draw. Mirrors RoundEconomy and Deck hand cap.
	EnergyPerRound = 2,
	MaxEnergy = 10,
	DrawPerRound = 3,
	MaxHandSize = 10,
}

CombatConstants.MaxStacks = table.freeze(CombatConstants.MaxStacks)
return table.freeze(CombatConstants)
