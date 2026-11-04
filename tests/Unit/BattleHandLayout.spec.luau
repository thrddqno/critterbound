--!strict

return function(Harness)
	local HandLayout = require("../../src/client/Presentation/BattleHandLayout")

	Harness.test("desktop nine-card hand scrolls horizontally without clipping", function()
		local layout = HandLayout.compute(1189, 260, 9, false)
		Harness.expect(layout.needsScroll)
		Harness.expect(layout.cardWidth >= 132)
		Harness.expect(layout.cardHeight >= 200)
		Harness.equal(
			layout.cardHeight + layout.verticalPadding * 2 + layout.scrollbarThickness,
			layout.cardAreaHeight
		)
		Harness.expect(layout.contentWidth > 1189)
	end)

	Harness.test("small hand fits without scrolling and stays at a readable width", function()
		local layout = HandLayout.compute(1189, 260, 3, false)
		Harness.expect(not layout.needsScroll)
		Harness.equal(layout.cardWidth, 164)
		Harness.expect(layout.cardHeight >= 200)
	end)

	Harness.test("compact hand keeps cards readable and above the scrollbar", function()
		local layout = HandLayout.compute(705, 232, 9, true)
		Harness.expect(layout.needsScroll)
		Harness.expect(layout.cardWidth >= 118)
		Harness.expect(layout.cardHeight >= 190)
		Harness.equal(
			layout.cardHeight + layout.verticalPadding * 2 + layout.scrollbarThickness,
			layout.cardAreaHeight
		)
		Harness.equal(layout.headerHeight, 20)
		Harness.equal(layout.scrollbarThickness, 8)
	end)

	Harness.test("hand width never collapses below the minimum card width", function()
		local layout = HandLayout.compute(320, 232, 9, true)
		Harness.equal(layout.cardWidth, 118)
		Harness.expect(layout.contentWidth > 320)
		Harness.expect(layout.cardHeight > 0)
	end)
end
