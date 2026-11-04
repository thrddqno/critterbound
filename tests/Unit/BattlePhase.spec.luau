--!strict

return function(Harness)
	local BattlePhase = require("../../src/shared/Battle/BattlePhase")
	local Phase = BattlePhase.Phase

	Harness.test("battle phase transition graph", function()
		Harness.expect(BattlePhase.canTransition(Phase.PLANNING, Phase.RESOLVING))
		Harness.expect(BattlePhase.canTransition(Phase.RESOLVING, Phase.PLANNING))
		Harness.expect(BattlePhase.canTransition(Phase.RESOLVING, Phase.FINISHED))
	end)

	Harness.test("invalid battle phase transitions", function()
		Harness.expect(not BattlePhase.canTransition(Phase.PLANNING, Phase.FINISHED))
		Harness.expect(not BattlePhase.canTransition(Phase.FINISHED, Phase.PLANNING))
		Harness.expect(BattlePhase.isValid("RESOLVING"))
		Harness.expect(not BattlePhase.isValid("BROKEN"))
	end)
end
