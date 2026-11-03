--!strict

-- Server-only and still guarded by RunService:IsStudio(). Never grants production profiles.
return table.freeze({
	EnableStudioInventoryFixture = true,
	EnableStudioBreedingFixture = true,
	EnableStudioAcquisitionFixture = true,
})
