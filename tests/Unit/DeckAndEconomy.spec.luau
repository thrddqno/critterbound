--!strict

return function(Harness)
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local Economy = require("../../src/shared/Battle/RoundEconomy")

	Harness.test("round energy carries and caps", function()
		Harness.equal(Economy.initialEnergy(), 3)
		Harness.equal(Economy.nextRoundEnergy(3).value, 5)
		Harness.equal(Economy.nextRoundEnergy(9).value, 10)
		Harness.equal(Economy.nextRoundEnergy(10).value, 10)
	end)

	Harness.test("draw respects hand capacity", function()
		local hand = { "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8", "h9" }
		local rng = Rng.new(10).value
		local result = Deck.draw({
			drawPileCardInstanceIds = { "a", "b", "c" },
			handCardInstanceIds = hand,
			discardCardInstanceIds = {},
		}, 3, rng, Rng.shuffle)
		Harness.expect(result.ok)
		Harness.equal(#result.value.zones.handCardInstanceIds, 10)
		Harness.equal(#result.value.zones.drawPileCardInstanceIds, 2)
	end)

	Harness.test("empty draw pile reshuffles discard deterministically", function()
		local rng = Rng.new(20).value
		local zones = {
			drawPileCardInstanceIds = {},
			handCardInstanceIds = {},
			discardCardInstanceIds = { "a", "b", "c" },
		}
		local first = Deck.draw(zones, 2, rng, Rng.shuffle)
		local second = Deck.draw(zones, 2, rng, Rng.shuffle)
		Harness.deepEqual(first, second)
		Harness.equal(#first.value.zones.handCardInstanceIds, 2)
		Harness.equal(#first.value.zones.discardCardInstanceIds, 0)
	end)

	Harness.test("card retirement preserves survivor order without mutation", function()
		local zones = {
			drawPileCardInstanceIds = { "d1", "retired.1", "d2" },
			handCardInstanceIds = { "retired.2", "h1", "h2" },
			discardCardInstanceIds = { "x1", "retired.1", "x2" },
		}
		local before = Harness.clone(zones)
		local result = Deck.removeCards(zones, { ["retired.1"] = true, ["retired.2"] = true })
		Harness.deepEqual(result.drawPileCardInstanceIds, { "d1", "d2" })
		Harness.deepEqual(result.handCardInstanceIds, { "h1", "h2" })
		Harness.deepEqual(result.discardCardInstanceIds, { "x1", "x2" })
		Harness.deepEqual(zones, before)
	end)
end
