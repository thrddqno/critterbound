--!strict

-- Server-only and still guarded by RunService:IsStudio(). Never grants production profiles.
return table.freeze({
	EnableStudioInventoryFixture = true,
	EnableStudioBreedingFixture = true,
	EnableStudioAcquisitionFixture = true,
	-- G6 acceptance only. Bootstrap also requires RunService:IsStudio(), so production stays legacy.
	EnableStudioClassicGeneticsAcceptance = true,
})
