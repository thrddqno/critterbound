--!strict

local GameConfig = table.freeze({
	GameName = "Critterbound",
	LogPrefix = "[Critterbound]",
	BattleDesign = table.freeze({
		TeamSize = 3,
		InitialEnergy = 3,
		EnergyPerRound = 2,
		StartingHandSize = 6,
		CardsDrawnPerRound = 3,
		TeamDeckSize = 24,
		AbilitiesPerCritter = 4,
		CopiesPerAbility = 2,
	}),
})

return GameConfig
