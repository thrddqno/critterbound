--!strict

export type CritterClass = "Verdant" | "Tide" | "Feral" | "Gale" | "Shade" | "Stone"

local CritterClasses = table.freeze({
	Verdant = "Verdant" :: CritterClass,
	Tide = "Tide" :: CritterClass,
	Feral = "Feral" :: CritterClass,
	Gale = "Gale" :: CritterClass,
	Shade = "Shade" :: CritterClass,
	Stone = "Stone" :: CritterClass,
})

return CritterClasses
