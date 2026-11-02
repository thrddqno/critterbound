--!strict

return function(Harness)
	local BattlePhase = require("../../src/shared/Battle/BattlePhase")
	local Phase = BattlePhase.Phase

	Harness.test("battle phase transition graph", function()
		Harness.expect(BattlePhase.canTransition(Phase.CREATED, Phase.ROUND_START))
		Harness.expect(BattlePhase.canTransition(Phase.ROUND_START, Phase.PLANNING))
		Harness.expect(BattlePhase.canTransition(Phase.PLANNING, Phase.COMMITTED))
		Harness.expect(BattlePhase.canTransition(Phase.COMMITTED, Phase.RESOLVING))
		Harness.expect(BattlePhase.canTransition(Phase.RESOLVING, Phase.ROUND_END))
		Harness.expect(BattlePhase.canTransition(Phase.ROUND_END, Phase.ROUND_START))
		Harness.expect(BattlePhase.canTransition(Phase.ROUND_END, Phase.COMPLETED))
	end)

	Harness.test("invalid battle phase transitions", function()
		Harness.expect(not BattlePhase.canTransition(Phase.CREATED, Phase.PLANNING))
		Harness.expect(not BattlePhase.canTransition(Phase.PLANNING, Phase.COMPLETED))
		Harness.expect(not BattlePhase.canTransition(Phase.COMPLETED, Phase.ROUND_START))
		Harness.expect(BattlePhase.isValid("RESOLVING"))
		Harness.expect(not BattlePhase.isValid("BROKEN"))
	end)
end
