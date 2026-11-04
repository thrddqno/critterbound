--!strict

return function(Harness)
	local Rng = require("../../src/shared/Battle/DeterministicRng")
	local Deck = require("../../src/shared/Battle/Deck")
	local DeckShuffler = require("../../src/shared/Battle/DeckShuffler")
	local DeckState = require("../../src/shared/Battle/DeckState")
	local Economy = require("../../src/shared/Battle/RoundEconomy")

	Harness.test("round energy carries and caps", function()
		Harness.equal(Economy.initialEnergy(), 3)
		Harness.equal(Economy.nextRoundEnergy(3).value, 5)
		Harness.equal(Economy.nextRoundEnergy(9).value, 10)
		Harness.equal(Economy.nextRoundEnergy(10).value, 10)
	end)

	Harness.test("scheduled draw never exceeds the hand cap", function()
		local cases = {
			{ handSize = 6, drawnCount = 3 },
			{ handSize = 7, drawnCount = 2 },
			{ handSize = 8, drawnCount = 1 },
			{ handSize = 9, drawnCount = 0 },
		}
		for _, case in cases do
			local hand = {}
			for index = 1, case.handSize do
				table.insert(hand, `h{index}`)
			end
			local rng = Rng.new(10).value
			local result = Deck.draw({
				drawPileCardInstanceIds = { "a", "b", "c" },
				handCardInstanceIds = hand,
				discardCardInstanceIds = {},
			}, 3, rng, Rng.shuffle)
			Harness.expect(result.ok)
			Harness.equal(#result.value.zones.handCardInstanceIds, 9)
			Harness.equal(result.value.requestedCount, 3)
			Harness.equal(result.value.drawnCount, case.drawnCount)
			Harness.equal(result.value.isPartial, case.drawnCount < 3)
			Harness.equal(#result.value.zones.drawPileCardInstanceIds, 3 - case.drawnCount)
			Harness.equal(#result.value.drawnCardInstanceIds, case.drawnCount)
		end
	end)

	Harness.test("capped draw does not consume RNG", function()
		local hand = { "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8", "h9" }
		local rng = Rng.new(10).value
		local result = Deck.draw({
			drawPileCardInstanceIds = { "a", "b", "c" },
			handCardInstanceIds = hand,
			discardCardInstanceIds = { "d" },
		}, 3, rng, Rng.shuffle)
		Harness.expect(result.ok)
		Harness.deepEqual(result.value.rng, rng)
		Harness.equal(result.value.drawnCount, 0)
		Harness.deepEqual(result.value.zones.drawPileCardInstanceIds, { "a", "b", "c" })
		Harness.deepEqual(result.value.zones.discardCardInstanceIds, { "d" })
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

	Harness.test("deck shuffler is deterministic and does not mutate input", function()
		local values = { "a", "b", "c", "d" }
		local before = Harness.clone(values)
		local rng = Rng.new(123).value
		local firstState, first = DeckShuffler.shuffle(rng, values, Rng)
		local secondState, second = DeckShuffler.shuffle(rng, values, Rng)
		Harness.deepEqual(firstState, secondState)
		Harness.deepEqual(first, second)
		Harness.deepEqual(values, before)
	end)

	Harness.test("draw consumes remaining pile before recycling discard", function()
		local rng = Rng.new(20).value
		local function shuffle(state, values)
			return DeckShuffler.shuffle(state, values, Rng)
		end
		local result = Deck.draw({
			drawPileCardInstanceIds = { "last" },
			handCardInstanceIds = { "held" },
			discardCardInstanceIds = { "discard.1", "discard.2", "discard.3" },
			removedCardInstanceIds = { "exiled" },
		}, 3, rng, shuffle)
		Harness.expect(result.ok)
		Harness.equal(result.value.drawnCardInstanceIds[1], "last")
		Harness.equal(result.value.drawnCount, 3)
		Harness.expect(not result.value.isPartial)
		Harness.equal(#result.value.zones.handCardInstanceIds, 4)
		Harness.equal(#result.value.zones.drawPileCardInstanceIds, 1)
		Harness.deepEqual(result.value.zones.removedCardInstanceIds, { "exiled" })
	end)

	Harness.test("insufficient cards return an explicit partial draw", function()
		local rng = Rng.new(20).value
		local result = Deck.draw({
			drawPileCardInstanceIds = { "only" },
			handCardInstanceIds = {},
			discardCardInstanceIds = {},
		}, 3, rng, Rng.shuffle)
		Harness.expect(result.ok)
		Harness.equal(result.value.requestedCount, 3)
		Harness.equal(result.value.drawnCount, 1)
		Harness.expect(result.value.isPartial)
	end)

	Harness.test("deck state rejects cards present in multiple zones", function()
		local valid = DeckState.validateUnique({
			drawPileCardInstanceIds = { "draw" },
			handCardInstanceIds = { "hand" },
			discardCardInstanceIds = { "discard" },
			removedCardInstanceIds = { "removed" },
		})
		Harness.expect(valid.ok)
		Harness.equal(valid.value.cardCount, 4)
		local invalid = DeckState.validateUnique({
			drawPileCardInstanceIds = { "duplicate" },
			handCardInstanceIds = { "duplicate" },
		})
		Harness.expect(Harness.hasError(invalid, "CARD_IN_MULTIPLE_ZONES"))
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
		Harness.deepEqual(result.removedCardInstanceIds, { "retired.1", "retired.2" })
		Harness.deepEqual(zones, before)
	end)
end
