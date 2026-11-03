--!strict

return table.freeze({
	Version = 2,
	RemoteName = "EggRequest",
	RequestKinds = table.freeze({
		GET_EGGS = "GET_EGGS",
		GET_EGG_STATUS = "GET_EGG_STATUS",
		HATCH_EGG = "HATCH_EGG",
	}),
})
