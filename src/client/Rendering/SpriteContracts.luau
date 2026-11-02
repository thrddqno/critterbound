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
	assetId: string,
	order: number,
	anchor: SpriteAnchor,
	visible: boolean,
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

export type AnimationState = {
	id: string,
	clipId: string,
	playbackSpeed: number,
}

export type PlaybackLifecycle = "STOPPED" | "PLAYING" | "PAUSED" | "COMPLETED"

return table.freeze({})
