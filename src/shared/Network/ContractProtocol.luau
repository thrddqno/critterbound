--!strict

return table.freeze({
	Version = 1,
	RemoteName = "ContractRequest",
	RequestKinds = table.freeze({
		GET_CONTRACTS = "GET_CONTRACTS",
		ACCEPT_CONTRACT = "ACCEPT_CONTRACT",
		GET_CONTRACT_PROGRESS = "GET_CONTRACT_PROGRESS",
		CLAIM_CONTRACT_REWARD = "CLAIM_CONTRACT_REWARD",
	}),
})
