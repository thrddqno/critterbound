--!strict

local process = require("@lune/process")
local Analysis = require("./Simulation/CombatPacingAnalysis")

local count = tonumber(process.env.RUN51_MATCHES or "200")
assert(
	count ~= nil and count % 1 == 0 and count >= 2 and count % 2 == 0,
	"RUN51_MATCHES must be an even integer >= 2"
)

local function ratio(numerator: number, denominator: number): string
	return string.format("%.4f", numerator / math.max(1, denominator))
end

print(`RUN51_MATCHES_PER_MATCHUP={count}`)
for _, result in Analysis.run(count) do
	local m = result.metrics
	print(`SCENARIO|{result.scenario.id}|{result.scenario.name}`)
	print(
		`PACE|{m.matches}|{ratio(m.rounds, m.matches)}|{m.completed}|{m.timeouts}|{m.failures}|{ratio(
			m.firstDefeatRoundTotal,
			m.firstDefeatSamples
		)}|{ratio(m.postDefeatRoundsTotal, m.firstDefeatSamples)}`
	)
	print(
		`AI|{ratio(m.cardsPlayed, m.availableCards)}|{ratio(m.energySpent, m.energyAvailable)}|{m.passesWithAffordable}|{m.availableCards}|{m.cardsPlayed}|{m.affordableCards}|{m.played.damage}|{m.played.healing}|{m.played.defensive}|{m.played.status}|{m.supportOverLethal}|{m.comboOpportunities}|{m.comboActivations}`
	)
	print(
		`HAND|{ratio(m.handSizeTotal, m.teamTurns)}|{ratio(m.cardsDrawn, m.drawTurns)}|{m.zeroDraws}|{m.drawTurns}|{ratio(
			m.cardAgeTotal,
			m.cardAgeSamples
		)}|{m.reshuffles}|{m.fullHandTurns}|{m.fullHandUsefulUnplayed}|{ratio(
			m.originCounts[1],
			m.originSamples
		)}|{ratio(m.originCounts[2], m.originSamples)}|{ratio(m.originCounts[3], m.originSamples)}|{m.blockedByDefeat}|{m.blockedByTarget}|{m.individuallyUnaffordable}|{m.unplayedBlockedByEnergy}`
	)
	print(
		`EFFECTS|{ratio(m.directDamage, m.rounds)}|{ratio(m.shieldAbsorbed, m.rounds)}|{ratio(
			m.healing,
			m.rounds
		)}|{ratio(m.poison, m.rounds)}|{ratio(m.netHpProgress, m.rounds)}|{m.neutralizedTeamRounds}|{m.teamTurns}|{m.unusedShieldExpired}|{m.shieldPrepared}|{ratio(
			m.healRestored,
			m.healRequested
		)}|{ratio(m.overhealing, m.healRequested)}`
	)
end
