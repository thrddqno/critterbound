--!strict

return function(Harness)
	local Layout = require("../../src/client/Presentation/BattleHudLayout")
	local Hud = require("../../src/client/Presentation/BattleHudPresentation")

	Harness.test("desktop HUD is full-screen and vertically ordered", function()
		local layout = Layout.compute(1440, 900)
		Harness.expect(layout.ignoreGuiInset)
		Harness.expect(not layout.compact)
		Harness.expect(layout.topHud.y < layout.orderStrip.y)
		Harness.expect(layout.orderStrip.y < layout.battlefield.y)
		Harness.expect(layout.battlefield.y < layout.queue.y)
		Harness.expect(layout.queue.y < layout.hand.y)
		Harness.equal(layout.hand.y, layout.controls.y)
		Harness.expect(layout.controls.x > layout.hand.x)
		Harness.expect(layout.hand.width > layout.controls.width)
		Harness.expect(layout.hand.x + layout.hand.width < layout.controls.x)
		Harness.expect(layout.hand.height >= 260)
	end)

	Harness.test("compact HUD keeps bottom hand and right controls in bounds", function()
		local layout = Layout.compute(900, 620)
		Harness.expect(layout.compact)
		Harness.expect(layout.hand.x >= 0)
		Harness.expect(layout.controls.x + layout.controls.width <= layout.content.width)
		Harness.expect(layout.hand.y + layout.hand.height <= layout.content.height)
		Harness.expect(layout.hand.x + layout.hand.width < layout.controls.x)
		Harness.expect(layout.hand.height >= 240)
	end)

	Harness.test("top HUD state formats timer and commit state", function()
		local ready = Hud.state({
			phase = "PLANNING",
			roundNumber = 3,
			planningDeadline = 165,
			committed = false,
		}, 100)
		Harness.equal(ready.timer, "01:05")
		Harness.equal(ready.commitment, "READY")
		Harness.expect(string.find(ready.text, "ROUND 3", 1, true) ~= nil)
		local locked = Hud.state({
			phase = "RESOLVING",
			roundNumber = 3,
			planningDeadline = nil,
			committed = true,
		}, 100)
		Harness.equal(locked.timer, "--:--")
		Harness.equal(locked.commitment, "COMMITTED")
	end)

	Harness.test("order chips preserve authoritative positions and identities", function()
		local chips = Hud.orderChips({
			{
				position = 2,
				combatantId = "slow",
				displayName = "Slow",
				class = "Stone",
				side = "ALLY",
				speed = 10,
			},
			{
				position = 1,
				combatantId = "fast",
				displayName = "Fast",
				class = "Feral",
				side = "ENEMY",
				speed = 30,
			},
		})
		Harness.equal(chips[1].position, 1)
		Harness.equal(chips[1].combatantId, "fast")
		Harness.equal(chips[2].position, 2)
		Harness.equal(chips[2].combatantId, "slow")
	end)

	Harness.test("top HUD warns before Blood Moon and shows escalating damage", function()
		local config = {
			Enabled = true,
			StartingRound = 10,
			InitialDamage = 50,
			DamageIncrement = 30,
			BypassesShields = true,
		}
		local warning = Hud.state({
			phase = "PLANNING",
			roundNumber = 9,
			planningDeadline = nil,
			committed = false,
			bloodMoon = config,
		}, 100)
		Harness.expect(warning.bloodMoonWarning)
		Harness.expect(string.find(warning.text, "WARNING: BLOOD MOON NEXT", 1, true) ~= nil)
		local active = Hud.state({
			phase = "PLANNING",
			roundNumber = 12,
			planningDeadline = nil,
			committed = false,
			bloodMoon = config,
		}, 100)
		Harness.equal(active.bloodMoonDamage, 110)
		Harness.expect(string.find(active.text, "BLOOD MOON — 110 HP", 1, true) ~= nil)
	end)
end
