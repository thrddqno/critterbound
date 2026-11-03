--!strict

export type PixelSize = {
	width: number,
	height: number,
}

export type SpriteAnchor = {
	x: number,
	y: number,
}

export type StaticSprite = {
	assetId: string,
	nativeSize: PixelSize,
	anchor: SpriteAnchor,
}

export type SpriteLayer = {
	id: string,
	slot: string,
	assetId: string,
	order: number,
	anchor: SpriteAnchor,
	pivot: SpriteAnchor,
	visible: boolean,
	placeholder: boolean?,
}

export type LayeredSprite = {
	base: StaticSprite,
	layers: { SpriteLayer },
}

export type SpriteSheetFrame = {
	x: number,
	y: number,
	width: number,
	height: number,
	durationSeconds: number,
}

export type AnimationClip = {
	id: string,
	sheetAssetId: string,
	frames: { SpriteSheetFrame },
	looped: boolean,
	fallbackAssetId: string?,
}

export type Facing = "LEFT" | "RIGHT"
export type CritterAnimationId = "IDLE" | "ATTACK" | "HIT" | "DEFEAT"

export type NormalizedAttachment = {
	position: SpriteAnchor,
	size: PixelSize,
	rotation: number,
}

export type RigMetadata = {
	id: string,
	nativeSize: PixelSize,
	anchor: SpriteAnchor,
	attachments: { [string]: NormalizedAttachment },
}

export type CritterSpriteModel = {
	rigFamily: string,
	spriteRigId: string,
	facing: Facing,
	nativeSize: PixelSize,
	attachments: { [string]: NormalizedAttachment },
	palette: { [string]: { red: number, green: number, blue: number } },
	animation: { [string]: number },
	layers: { SpriteLayer },
}

export type AnimationState = {
	id: string,
	clipId: string,
	playbackSpeed: number,
}

export type PlaybackLifecycle = "STOPPED" | "PLAYING" | "PAUSED" | "COMPLETED"

return table.freeze({})
