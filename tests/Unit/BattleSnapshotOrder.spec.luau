--!strict

return function(Harness)
	local BattleSnapshotOrder = require("../../src/client/Presentation/BattleSnapshotOrder")

	local function snapshot(battleId, revision, planVersion)
		return {
			revision = revision,
			planVersion = planVersion,
			battleState = { id = battleId },
		}
	end

	Harness.test("out-of-order snapshots cannot restore obsolete plan state", function()
		local current = BattleSnapshotOrder.version(snapshot("battle", 8, 4))
		Harness.expect(not BattleSnapshotOrder.shouldApply(current, snapshot("battle", 7, 9)))
		Harness.expect(not BattleSnapshotOrder.shouldApply(current, snapshot("battle", 8, 3)))
		Harness.expect(BattleSnapshotOrder.shouldApply(current, snapshot("battle", 8, 4)))
		Harness.expect(BattleSnapshotOrder.shouldApply(current, snapshot("battle", 9, 0)))
	end)

	Harness.test("old battle snapshots cannot replace current battle", function()
		local current = BattleSnapshotOrder.version(snapshot("old", 20, 5))
		Harness.expect(not BattleSnapshotOrder.shouldApply(current, snapshot("new", 1, 0)))
		Harness.expect(BattleSnapshotOrder.shouldApply(nil, snapshot("new", 1, 0)))
	end)
end
