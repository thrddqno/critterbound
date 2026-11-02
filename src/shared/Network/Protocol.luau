--!strict

local Protocol = table.freeze({
	Version = 2,
	CommandTypes = table.freeze({
		QUEUE_CARD = "QUEUE_CARD",
		REMOVE_QUEUED_CARD = "REMOVE_QUEUED_CARD",
		REORDER_QUEUED_CARD = "REORDER_QUEUED_CARD",
		CLEAR_PLAN = "CLEAR_PLAN",
		COMMIT_PLAN = "COMMIT_PLAN",
	}),
})

return Protocol
