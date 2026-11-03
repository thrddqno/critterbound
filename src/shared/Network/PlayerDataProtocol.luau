--!strict

return table.freeze({
	Version = 2,
	RemoteName = "PlayerDataRequest",
	RequestKinds = table.freeze({
		GET_COLLECTION = "GET_COLLECTION",
		GET_INVENTORY = "GET_INVENTORY",
		SET_TEAM = "SET_TEAM",
		EQUIP_ITEM = "EQUIP_ITEM",
		UNEQUIP_ITEM = "UNEQUIP_ITEM",
	}),
})
