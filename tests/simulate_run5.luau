--!strict

local process = require("@lune/process")
local Simulation = require("./Simulation/CombatBalanceSimulation")

local requested = tonumber(process.env.RUN5_MATCHES or "1000")
assert(requested ~= nil and requested % 1 == 0, "RUN5_MATCHES must be an integer")

local function percent(value: number): string
	return string.format("%.1f%%", value * 100)
end

local function average(value: number, count: number): string
	return string.format("%.2f", value / math.max(1, count))
end

local results = Simulation.run(requested)
print(`RUN5_MATCHES_PER_MATCHUP={requested}`)
for _, result in results do
	print(`MATCHUP|{result.id}|{result.name}`)
	print(`TEAMS|{result.aName}|{result.aClasses}|{result.bName}|{result.bClasses}`)
	print(
		`OUTCOME|{result.matches}|{percent(result.aWinRate)}|{percent(result.bWinRate)}|{percent(
			result.drawRate
		)}|{percent(result.aCiLow)}-{percent(result.aCiHigh)}|{percent(result.bCiLow)}-{percent(
			result.bCiHigh
		)}`
	)
	print(
		`DURATION|{string.format("%.2f", result.averageRounds)}|{result.medianRounds}|{result.p90Rounds}|{result.shortest}|{result.longest}|{string.format(
			"%.2f",
			result.averageFirstDefeatRound
		)}|{result.medianFirstDefeatRound}|{string.format("%.2f", result.averageWinnerRemainingHp)}`
	)
	for _, role in { "a", "b" } do
		local metrics = result[role]
		print(
			`METRICS_{string.upper(role)}|{average(metrics.hpDamage, result.matches)}|{average(
				metrics.shieldAbsorbed,
				result.matches
			)}|{average(metrics.healing, result.matches)}|{average(
				metrics.poisonDamage,
				result.matches
			)}|{metrics.criticalHits}|{metrics.criticalRolls}|{percent(
				metrics.criticalHits / math.max(1, metrics.criticalRolls)
			)}|{metrics.skillComboActivations}|{average(metrics.energySpent, result.matches)}|{average(
				metrics.unusedEnergy,
				result.matches
			)}|{average(metrics.cardsDrawn, result.matches)}|{metrics.partialDraws}|{metrics.drawOpportunities}|{metrics.handCapBlocks}|{metrics.blockedCards}`
		)
	end
	print(
		`INTEGRITY|{result.timeouts}|{result.failures}|{result.stalemates}|{result.zeroProgressRounds}|{result.maxZeroProgressStreak}|{result.conservationErrors}|{result.sequenceErrors}|{result.shieldOrderErrors}|{result.statusExpiryErrors}|{result.replayErrors}|{result.sideOneWins}|{result.sideTwoWins}`
	)
end
