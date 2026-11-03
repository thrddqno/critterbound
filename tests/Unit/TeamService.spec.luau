--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local TrainingGrounds = require("../../src/shared/Definitions/TrainingGrounds")
	local Adapter = require("../../src/server/Services/TrainingBattleInputAdapter")

	local function setup(userId: number)
		local store = Fixtures.MockDataStore.new()
		local profile = Fixtures.newService(Fixtures.newRepository(store, `team-{userId}`))
		Harness.expect(profile.LoadProfile(userId).ok)
		return store, profile, Fixtures.newTeamService(profile)
	end

	Harness.test("TeamService persists valid ordered team", function()
		local store, profile, teamService = setup(821)
		local team = profile.GetProfile(821).value.selectedTeam
		local reordered = { team[3], team[1], team[2] }
		Harness.expect(teamService.SetSelectedTeam(821, reordered).ok)
		Harness.deepEqual(profile.GetProfile(821).value.selectedTeam, reordered)
		Harness.expect(profile.ReleaseProfile(821).ok)
		local reloaded = Fixtures.newService(Fixtures.newRepository(store, "team-reload"))
		Harness.expect(reloaded.LoadProfile(821).ok)
		Harness.deepEqual(reloaded.GetProfile(821).value.selectedTeam, reordered)
	end)

	Harness.test("invalid team preserves previous selection", function()
		local _, profile, teamService = setup(822)
		local previous = profile.GetProfile(822).value.selectedTeam
		Harness.expect(
			Harness.hasError(
				teamService.SetSelectedTeam(822, { previous[1], previous[1], "foreign" }),
				"INVALID_SELECTED_TEAM"
			)
		)
		Harness.deepEqual(profile.GetProfile(822).value.selectedTeam, previous)
		Harness.expect(
			Harness.hasError(
				teamService.SetSelectedTeam(822, { previous[1] }),
				"INVALID_SELECTED_TEAM"
			)
		)
	end)

	Harness.test("Training Grounds remains compatible with selected team order", function()
		local _, profile, teamService = setup(823)
		local team = profile.GetProfile(823).value.selectedTeam
		local reordered = { team[2], team[3], team[1] }
		Harness.expect(teamService.SetSelectedTeam(823, reordered).ok)
		local adapter = Adapter.new({ profileService = profile, content = TrainingGrounds })
		local input = adapter.createInput(823, 1)
		Harness.expect(input.ok)
		for index, id in reordered do
			Harness.equal(input.value.teams[1].critterInstances[index].id, id)
		end
	end)
end
