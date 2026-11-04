--!strict

return function(Harness)
	local Fixtures = require("../Fixtures/ProfileFixtures")
	local TradeEligibilityService = require("../../src/server/Services/TradeEligibilityService")
	local TradeEligibilityValidator = require("../../src/server/Services/TradeEligibilityValidator")

	local function setup(userId: number)
		local now = 1_700_000_000
		local store = Fixtures.MockDataStore.new()
		local profileService =
			Fixtures.newService(Fixtures.newRepository(store, `trade-{userId}`), {
				clock = function()
					return now
				end,
				ownershipLockSeconds = 10,
			})
		Harness.expect(profileService.LoadProfile(userId).ok)
		local profile = profileService.ReadProfile(userId).value
		local starterId = profile.selectedTeam[1]
		local tradable = Harness.clone(profile.ownedCritters[starterId])
		tradable.id = `critter:tradable-{userId}`
		tradable.acquisition.source = "REWARD"
		tradable.tradable = true
		tradable.equipmentIds = {}
		Harness.expect(profileService.UpdateProfile(userId, function(candidate)
			candidate.ownedCritters[tradable.id] = tradable
			return { ok = true, value = true }
		end).ok)
		local service = TradeEligibilityService.new({
			profileService = profileService,
			validator = TradeEligibilityValidator,
		})
		return profileService, service, tradable.id, starterId, function(value)
			now = value
		end
	end

	Harness.test("trade eligibility enforces ownership and trade flags", function()
		local profileService, service, tradableId, starterId = setup(901)
		Harness.expect(service.CheckEligibility(901, tradableId).ok)
		Harness.expect(
			Harness.hasError(service.CheckEligibility(901, starterId), "STARTER_NOT_TRADABLE")
		)
		Harness.expect(
			Harness.hasError(service.CheckEligibility(901, "critter:missing"), "CRITTER_NOT_FOUND")
		)

		Harness.expect(profileService.UpdateProfile(901, function(profile)
			profile.ownedCritters[tradableId].tradable = false
			return { ok = true, value = true }
		end).ok)
		Harness.expect(
			Harness.hasError(service.CheckEligibility(901, tradableId), "CRITTER_NOT_TRADABLE")
		)

		local foreignProfile = profileService.ReadProfile(901).value
		foreignProfile.ownedCritters[tradableId].tradable = true
		foreignProfile.ownedCritters[tradableId].ownerUserId = 999
		local foreign =
			TradeEligibilityValidator.validate(foreignProfile, 901, tradableId, nil, nil)
		Harness.expect(Harness.hasError(foreign, "CRITTER_NOT_OWNED"))
	end)

	Harness.test("trade eligibility rejects team-equipped Critters", function()
		local profileService, service, tradableId = setup(902)
		Harness.expect(profileService.UpdateProfile(902, function(profile)
			profile.selectedTeam = {
				tradableId,
				profile.selectedTeam[1],
				profile.selectedTeam[2],
			}
			return { ok = true, value = true }
		end).ok)
		Harness.expect(
			Harness.hasError(service.CheckEligibility(902, tradableId), "CRITTER_EQUIPPED")
		)
	end)

	Harness.test("ownership locks reject simultaneous conflicting operations", function()
		local profileService, service, tradableId = setup(903)
		local breeding = profileService.AcquireOwnershipLocks(903, { tradableId }, "BREEDING")
		Harness.expect(breeding.ok)
		Harness.expect(
			Harness.hasError(service.CheckEligibility(903, tradableId), "CRITTER_LOCKED")
		)
		Harness.expect(
			Harness.hasError(
				profileService.AcquireOwnershipLocks(903, { tradableId }, "TRANSFER"),
				"OWNERSHIP_LOCK_CONFLICT"
			)
		)
		Harness.expect(profileService.ReleaseOwnershipLocks(903, breeding.value.token).ok)
		Harness.expect(service.CheckEligibility(903, tradableId).ok)
	end)

	Harness.test("ownership locks expire and interrupted operations clean up", function()
		local profileService, service, tradableId, _, setNow = setup(904)
		local first = service.AcquireTransferLock(904, tradableId)
		Harness.expect(first.ok)
		setNow(first.value.expiresAt)
		Harness.equal(profileService.GetOwnershipLock(tradableId), nil)
		Harness.expect(
			Harness.hasError(
				service.RevalidateTransfer(904, tradableId, first.value.lockToken),
				"TRANSFER_LOCK_REQUIRED"
			)
		)

		local second = service.AcquireTransferLock(904, tradableId)
		Harness.expect(second.ok)
		Harness.expect(profileService.UpdateProfile(904, function(profile)
			profile.ownedCritters[tradableId].tradable = false
			return { ok = true, value = true }
		end).ok)
		Harness.expect(
			Harness.hasError(
				service.RevalidateTransfer(904, tradableId, second.value.lockToken),
				"CRITTER_NOT_TRADABLE"
			)
		)
		Harness.equal(profileService.GetOwnershipLock(tradableId), nil)
	end)

	Harness.test("future transfer candidate is revalidated under its lock", function()
		local profileService, service, tradableId = setup(906)
		local locked = service.AcquireTransferLock(906, tradableId)
		Harness.expect(locked.ok)
		Harness.expect(profileService.UpdateProfile(906, function(profile)
			local validation =
				service.ValidateTransferCandidate(profile, 906, tradableId, locked.value.lockToken)
			Harness.expect(validation.ok)
			return { ok = true, value = true }
		end).ok)
		Harness.expect(service.ReleaseTransferLock(906, locked.value.lockToken).ok)
	end)

	Harness.test("profile release removes ownership locks", function()
		local profileService, service, tradableId = setup(905)
		local locked = service.AcquireTransferLock(905, tradableId)
		Harness.expect(locked.ok)
		Harness.expect(profileService.ReleaseProfile(905).ok)
		Harness.equal(profileService.GetOwnershipLock(tradableId), nil)
	end)
end
