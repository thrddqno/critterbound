--!strict

return function(Harness)
	local Playback = require("../../src/client/Presentation/BattlePlayback")

	local function snapshot()
		return {
			battleState = {
				combatants = {
					{ id = "target", currentHealth = 100, statusEffects = {} },
				},
			},
			shieldsByCombatantId = { target = 0 },
			initiativeCombatantIds = {},
		}
	end

	Harness.test("playback applies HP shield status and initiative in event order", function()
		local original = snapshot()
		local state = Playback.new(original)
		state = Playback.apply(state, {
			kind = "INITIATIVE_DETERMINED",
			payload = { initiativeCombatantIds = { "source", "target" } },
			targetCombatantIds = {},
		})
		state = Playback.apply(state, {
			kind = "SHIELD_GRANTED",
			payload = { targetCombatantId = "target", amount = 20 },
			targetCombatantIds = { "target" },
		})
		state = Playback.apply(state, {
			kind = "DAMAGE_APPLIED",
			payload = { targetCombatantId = "target", hpDamage = 15, healthAfter = 85 },
			targetCombatantIds = { "target" },
		})
		state = Playback.apply(state, {
			kind = "STATUS_APPLIED",
			payload = {
				targetCombatantId = "target",
				statusId = "POISON",
				stackCount = 1,
				magnitude = 5,
				expiresAtRound = 2,
			},
			targetCombatantIds = { "target" },
		})
		Harness.equal(original.battleState.combatants[1].currentHealth, 100)
		Harness.equal(state.snapshot.battleState.combatants[1].currentHealth, 85)
		Harness.equal(state.snapshot.shieldsByCombatantId.target, 20)
		Harness.equal(state.snapshot.battleState.combatants[1].statusEffects[1].statusId, "POISON")
		Harness.deepEqual(state.snapshot.initiativeCombatantIds, { "source", "target" })
	end)

	Harness.test("playback does not expose final HP before damage event", function()
		local state = Playback.new(snapshot())
		state = Playback.apply(state, {
			kind = "CARD_PLAYED",
			payload = { cardDefinitionId = "card.attack" },
			targetCombatantIds = { "target" },
		})
		Harness.equal(state.snapshot.battleState.combatants[1].currentHealth, 100)
	end)
end
