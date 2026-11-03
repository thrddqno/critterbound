--!strict

return table.freeze({
	Version = 1,
	RemoteName = "BreedingRequest",
	RequestKinds = table.freeze({
		CHECK_BREEDING = "CHECK_BREEDING",
		PREVIEW_BREEDING = "PREVIEW_BREEDING",
		BREED_CRITTERS = "BREED_CRITTERS",
	}),
	IncubationSeconds = 300,
})
