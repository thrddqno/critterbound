--!strict

local process = require("@lune/process")
local CombatConfig = require("../src/server/Config/CombatConfig")
local Simulation = require("./Simulation/CombatBalanceSimulation")

local count = tonumber(process.env.BLOOD_MOON_MATCHES or "500")
assert(
	count ~= nil and count >= 2 and count % 2 == 0,
	"BLOOD_MOON_MATCHES must be an even integer >= 2"
)

local function percent(value: number, total: number): string
	return string.format("%.2f%%", value / math.max(1, total) * 100)
end

local function printResults(label: string, results)
	for _, result in results do
		print(
			`RESULT|{label}|{result.id}|{result.matches}|{string.format(
				"%.3f",
				result.averageRounds
			)}|{result.medianRounds}|{string.format("%.3f", result.averageFirstDefeatRound)}|{string.format(
				"%.2f",
				result.aWinRate * 100
			)}%|{string.format("%.2f", result.bWinRate * 100)}%|{string.format(
				"%.2f",
				result.drawRate * 100
			)}%|{string.format("%.2f", result.bloodMoonDamage / math.max(1, result.matches))}|{result.environmentalDefeats}|{result.mutualDestructions}|{percent(
				result.reachedRound10,
				result.matches
			)}|{percent(result.endedRounds10To14, result.matches)}`
		)
	end
end

print(`BLOOD_MOON_MATCHES_PER_MATCHUP={count}`)
printResults("BASELINE", Simulation.run(count))
printResults(
	"BLOOD_MOON",
	Simulation.runWithOptions(count, { bloodMoonConfig = CombatConfig.BloodMoon })
)
