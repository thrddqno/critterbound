--!strict

-- Documented Run 4B tuning constants. Changing any value here is replay-breaking.

local CombatConstants = {
	AdvantageMultiplier = 1.15,
	DisadvantageMultiplier = 0.85,
	NeutralMultiplier = 1.0,
	SameClassMultiplier = 1.10,
	CrossClassMultiplier = 1.00,
	SkillMultiplierPerPoint = 0.03,
	SkillComboMinimumCards = 3,
	NormalDamageMultiplier = 1.00,
	CriticalDamageMultiplier = 1.50,
	BaseCriticalChance = 0.05,
	CriticalChancePerMorale = 0.02,
	MaximumCriticalChance = 0.35,

	-- Ordinary shields last through the current resolution and expire at its round end.
	ShieldDurationRounds = 0,

	MaxStacks = {
		POISON = 5,
		DAMAGE_UP = 3,
		DAMAGE_DOWN = 3,
		SPEED_UP = 3,
		SPEED_DOWN = 3,
	},

	-- Per-round economy and draw. Mirrors RoundEconomy and Deck hand cap.
	EnergyPerRound = 2,
	MaxEnergy = 10,
	CardsPerCritter = 4,
	CardCopiesPerAbility = 2,
	TeamDeckSize = 24,
	StartingHandSize = 6,
	DrawPerRound = 3,
	MaxHandSize = 9,
}

CombatConstants.MaxStacks = table.freeze(CombatConstants.MaxStacks)
return table.freeze(CombatConstants)
