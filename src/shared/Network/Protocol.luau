--!strict

local Protocol = table.freeze({
	Version = 3,
	CommandTypes = table.freeze({
		QUEUE_CARD = "QUEUE_CARD",
		REMOVE_QUEUED_CARD = "REMOVE_QUEUED_CARD",
		REORDER_QUEUED_CARD = "REORDER_QUEUED_CARD",
		CLEAR_PLAN = "CLEAR_PLAN",
		COMMIT_PLAN = "COMMIT_PLAN",
	}),
	RequestKinds = table.freeze({
		START_BATTLE = "START_BATTLE",
		COMMAND = "COMMAND",
		REQUEST_SNAPSHOT = "REQUEST_SNAPSHOT",
		RESTART_BATTLE = "RESTART_BATTLE",
	}),
	RemoteFolderName = "Remotes",
	BattleRequestName = "BattleRequest",
})

return Protocol
