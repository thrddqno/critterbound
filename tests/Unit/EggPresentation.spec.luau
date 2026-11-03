--!strict

return function(Harness)
	local EggPresentation = require("../../src/client/Presentation/EggPresentation")

	local function egg(overrides)
		local value = {
			eggId = "egg:one",
			status = "INCUBATING",
			createdAt = 1000,
			hatchAt = 1300,
			generation = 1,
			parentA = { id = "critter:a", displayName = "Zephyr", class = "Gale" },
			parentB = { id = "critter:b", displayName = "Rill", class = "Tide" },
			offspringClass = "Gale",
			possibleOffspringClasses = { "Gale" },
		}
		for key, override in overrides or {} do
			value[key] = override
		end
		return value
	end

	Harness.test("egg presentation maps incubating egg and parent names", function()
		local row = EggPresentation.mapEgg(egg(), 1100)
		Harness.equal(row.id, "egg:one")
		Harness.equal(row.status, "INCUBATING")
		Harness.equal(row.statusText, "Incubating")
		Harness.equal(row.parentText, "Zephyr (Gale) + Rill (Tide)")
		Harness.equal(row.generationText, "Generation 1")
		Harness.equal(row.remainingSeconds, 200)
		Harness.equal(row.remainingText, "3:20")
		Harness.equal(row.canHatch, false)
	end)

	Harness.test("egg presentation marks ready egg hatchable", function()
		local row = EggPresentation.mapEgg(egg({ status = "READY" }), 1400)
		Harness.equal(row.statusText, "Ready to hatch")
		Harness.equal(row.remainingSeconds, 0)
		Harness.equal(row.canHatch, true)
	end)

	Harness.test("egg presentation marks hatched egg and clamps remaining time", function()
		local row = EggPresentation.mapEgg(egg({ status = "HATCHED" }), 2000)
		Harness.equal(row.statusText, "Hatched")
		Harness.equal(row.remainingSeconds, 0)
		Harness.equal(row.remainingText, "Hatched")
		Harness.equal(row.canHatch, false)
	end)

	Harness.test("egg presentation maps lists deterministically", function()
		local rows = EggPresentation.map({ egg(), egg({ eggId = "egg:two" }) }, 1100)
		Harness.equal(#rows, 2)
		Harness.equal(rows[1].id, "egg:one")
		Harness.equal(rows[2].id, "egg:two")
	end)

	Harness.test("egg presentation partitions active eggs from hatch history", function()
		local eggs = {
			egg({ eggId = "egg:incubating" }),
			egg({ eggId = "egg:ready", status = "READY" }),
			egg({ eggId = "egg:hatched", status = "HATCHED" }),
		}
		local active = EggPresentation.filterByTab(eggs, EggPresentation.Tabs.ACTIVE)
		local history = EggPresentation.filterByTab(eggs, EggPresentation.Tabs.HISTORY)
		Harness.equal(#active, 2)
		Harness.equal(active[1].eggId, "egg:incubating")
		Harness.equal(active[2].eggId, "egg:ready")
		Harness.equal(#history, 1)
		Harness.equal(history[1].eggId, "egg:hatched")
	end)

	Harness.test("egg presentation formats authoritative hatch date in UTC", function()
		Harness.equal(EggPresentation.formatHatchDate(nil), "Unknown")
		Harness.equal(EggPresentation.formatHatchDate(1_700_000_000), "2023-11-14 22:13 UTC")
	end)

	Harness.test("egg presentation formats minute and second padding", function()
		Harness.equal(EggPresentation.formatRemaining(0), "0:00")
		Harness.equal(EggPresentation.formatRemaining(9), "0:09")
		Harness.equal(EggPresentation.formatRemaining(60), "1:00")
		Harness.equal(EggPresentation.formatRemaining(125), "2:05")
	end)
end
