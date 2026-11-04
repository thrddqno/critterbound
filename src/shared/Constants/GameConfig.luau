--!strict

local GameConfig = table.freeze({
	GameName = "Critterbound",
	LogPrefix = "[Critterbound]",
	BattleDesign = table.freeze({
		TeamSize = 3,
		InitialEnergy = 3,
		EnergyPerRound = 2,
		MaxEnergy = 10,
		StartingHandSize = 6,
		MaxHandSize = 9,
		CardsDrawnPerRound = 3,
		TeamDeckSize = 24,
		AbilitiesPerCritter = 4,
		CopiesPerAbility = 2,
		MaxQueuedCards = 10,
	}),
})

return GameConfig
