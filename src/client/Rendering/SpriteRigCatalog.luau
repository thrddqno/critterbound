--!strict

local function point(x: number, y: number)
	return table.freeze({ x = x, y = y })
end

local function part(x: number, y: number, width: number, height: number, rotation: number?)
	return table.freeze({
		position = point(x, y),
		size = table.freeze({ width = width, height = height }),
		rotation = rotation or 0,
	})
end

local function rgb(red: number, green: number, blue: number)
	return table.freeze({ red = red, green = green, blue = blue })
end

local LAYER_ORDER = table.freeze({
	shadow = 0,
	tail = 5,
	wings = 8,
	body = 10,
	color = 15,
	markings = 20,
	eyes = 50,
	mouth = 60,
	accessories = 70,
})

local function palette(values)
	return table.freeze({
		outline = rgb(values.outline[1], values.outline[2], values.outline[3]),
		shadow = rgb(values.shadow[1], values.shadow[2], values.shadow[3]),
		body = rgb(values.body[1], values.body[2], values.body[3]),
		head = rgb(values.head[1], values.head[2], values.head[3]),
		belly = rgb(values.belly[1], values.belly[2], values.belly[3]),
		marking = rgb(values.marking[1], values.marking[2], values.marking[3]),
		wing = rgb(values.wing[1], values.wing[2], values.wing[3]),
		eye = rgb(values.eye[1], values.eye[2], values.eye[3]),
		pupil = rgb(values.pupil[1], values.pupil[2], values.pupil[3]),
		mouth = rgb(values.mouth[1], values.mouth[2], values.mouth[3]),
		accessory = rgb(values.accessory[1], values.accessory[2], values.accessory[3]),
		accent = rgb(values.accent[1], values.accent[2], values.accent[3]),
	})
end

local function freezeRig(rig)
	rig.nativeSize = table.freeze({ width = 256, height = 256 })
	rig.anchor = point(0.5, 0.88)
	rig.layerOrder = LAYER_ORDER
	rig.attachments = table.freeze(rig.attachments)
	rig.animation = table.freeze(rig.animation)
	return table.freeze(rig)
end

local rigs = table.freeze({
	verdant = freezeRig({
		id = "verdant",
		style = "VERDANT",
		palette = palette({
			outline = { 39, 72, 50 },
			shadow = { 24, 36, 29 },
			body = { 91, 151, 105 },
			head = { 112, 177, 119 },
			belly = { 158, 201, 137 },
			marking = { 60, 111, 76 },
			wing = { 126, 181, 132 },
			eye = { 243, 247, 220 },
			pupil = { 31, 55, 40 },
			mouth = { 125, 62, 68 },
			accessory = { 232, 190, 75 },
			accent = { 78, 137, 83 },
		}),
		attachments = {
			shadow = part(0.5, 0.88, 0.68, 0.09),
			body = part(0.5, 0.62, 0.56, 0.52),
			head = part(0.5, 0.37, 0.43, 0.34),
			leftFoot = part(0.38, 0.84, 0.2, 0.11, -5),
			rightFoot = part(0.62, 0.84, 0.2, 0.11, 5),
			belly = part(0.5, 0.66, 0.35, 0.26),
			markings = part(0.5, 0.65, 0.36, 0.22),
			leftEye = part(0.43, 0.37, 0.075, 0.095),
			rightEye = part(0.57, 0.37, 0.075, 0.095),
			mouth = part(0.5, 0.48, 0.15, 0.025),
			tail = part(0.22, 0.64, 0.32, 0.13, 20),
			tailTip = part(0.1, 0.56, 0.15, 0.1, 35),
			wingLeft = part(0.3, 0.58, 0.2, 0.25, -18),
			wingRight = part(0.7, 0.58, 0.2, 0.25, 18),
			accessory = part(0.5, 0.18, 0.27, 0.16),
			earLeft = part(0.37, 0.21, 0.14, 0.2, -35),
			earRight = part(0.63, 0.21, 0.14, 0.2, 35),
			crest = part(0.5, 0.16, 0.12, 0.22),
			shoulderLeft = part(0.29, 0.55, 0.17, 0.2),
			shoulderRight = part(0.71, 0.55, 0.17, 0.2),
			snout = part(0.61, 0.45, 0.19, 0.11),
			wispLeft = part(0.3, 0.79, 0.16, 0.2, 20),
			wispRight = part(0.7, 0.79, 0.16, 0.2, -20),
		},
		animation = {
			idleScale = 1.025,
			idleY = -0.008,
			idleDuration = 0.8,
			attackX = 0.1,
			attackY = -0.035,
			hitX = -0.055,
			hitY = 0.01,
			defeatY = 0.18,
			defeatRotation = 72,
		},
	}),
	feral = freezeRig({
		id = "feral",
		style = "FERAL",
		palette = palette({
			outline = { 83, 35, 25 },
			shadow = { 42, 24, 21 },
			body = { 196, 73, 45 },
			head = { 225, 103, 48 },
			belly = { 240, 143, 65 },
			marking = { 116, 39, 30 },
			wing = { 165, 54, 38 },
			eye = { 255, 226, 151 },
			pupil = { 65, 24, 19 },
			mouth = { 90, 25, 24 },
			accessory = { 245, 188, 61 },
			accent = { 236, 126, 48 },
		}),
		attachments = {
			shadow = part(0.5, 0.86, 0.7, 0.08),
			body = part(0.48, 0.62, 0.57, 0.39, -7),
			head = part(0.64, 0.42, 0.36, 0.27, -8),
			leftFoot = part(0.38, 0.82, 0.22, 0.09, -12),
			rightFoot = part(0.65, 0.8, 0.24, 0.09, -4),
			belly = part(0.53, 0.64, 0.32, 0.17, -7),
			markings = part(0.49, 0.6, 0.38, 0.2, -7),
			leftEye = part(0.59, 0.4, 0.07, 0.075, -8),
			rightEye = part(0.69, 0.39, 0.07, 0.075, -8),
			mouth = part(0.71, 0.49, 0.13, 0.022, -8),
			tail = part(0.19, 0.61, 0.46, 0.1, 15),
			tailTip = part(0.04, 0.5, 0.17, 0.08, 35),
			wingLeft = part(0.3, 0.48, 0.16, 0.25, -35),
			wingRight = part(0.5, 0.43, 0.14, 0.22, -18),
			accessory = part(0.62, 0.24, 0.24, 0.13, -8),
			earLeft = part(0.55, 0.27, 0.1, 0.24, -25),
			earRight = part(0.72, 0.25, 0.1, 0.25, 25),
			crest = part(0.43, 0.35, 0.1, 0.24, -45),
			shoulderLeft = part(0.31, 0.49, 0.15, 0.19),
			shoulderRight = part(0.58, 0.47, 0.14, 0.18),
			snout = part(0.76, 0.46, 0.22, 0.1, -8),
			wispLeft = part(0.3, 0.76, 0.14, 0.18),
			wispRight = part(0.68, 0.75, 0.14, 0.18),
		},
		animation = {
			idleScale = 1.018,
			idleY = -0.004,
			idleDuration = 0.55,
			attackX = 0.16,
			attackY = -0.025,
			hitX = -0.07,
			hitY = 0.005,
			defeatY = 0.2,
			defeatRotation = 82,
		},
	}),
	stone = freezeRig({
		id = "stone",
		style = "STONE",
		palette = palette({
			outline = { 55, 49, 43 },
			shadow = { 29, 28, 27 },
			body = { 112, 105, 94 },
			head = { 132, 122, 105 },
			belly = { 156, 143, 119 },
			marking = { 77, 72, 66 },
			wing = { 93, 87, 79 },
			eye = { 229, 216, 170 },
			pupil = { 43, 39, 35 },
			mouth = { 72, 54, 46 },
			accessory = { 184, 137, 72 },
			accent = { 143, 126, 96 },
		}),
		attachments = {
			shadow = part(0.5, 0.87, 0.8, 0.1),
			body = part(0.5, 0.65, 0.72, 0.39),
			head = part(0.5, 0.45, 0.46, 0.28),
			leftFoot = part(0.34, 0.84, 0.27, 0.13),
			rightFoot = part(0.66, 0.84, 0.27, 0.13),
			belly = part(0.5, 0.68, 0.42, 0.2),
			markings = part(0.5, 0.66, 0.5, 0.2),
			leftEye = part(0.43, 0.44, 0.075, 0.07),
			rightEye = part(0.57, 0.44, 0.075, 0.07),
			mouth = part(0.5, 0.53, 0.14, 0.025),
			tail = part(0.18, 0.68, 0.24, 0.16, 8),
			tailTip = part(0.09, 0.66, 0.12, 0.15),
			wingLeft = part(0.22, 0.55, 0.25, 0.28),
			wingRight = part(0.78, 0.55, 0.25, 0.28),
			accessory = part(0.5, 0.29, 0.3, 0.13),
			earLeft = part(0.37, 0.34, 0.15, 0.14, -10),
			earRight = part(0.63, 0.34, 0.15, 0.14, 10),
			crest = part(0.5, 0.29, 0.16, 0.16),
			shoulderLeft = part(0.22, 0.56, 0.25, 0.3),
			shoulderRight = part(0.78, 0.56, 0.25, 0.3),
			snout = part(0.5, 0.5, 0.22, 0.11),
			wispLeft = part(0.3, 0.78, 0.18, 0.16),
			wispRight = part(0.7, 0.78, 0.18, 0.16),
		},
		animation = {
			idleScale = 1.012,
			idleY = -0.003,
			idleDuration = 1.05,
			attackX = 0.07,
			attackY = -0.02,
			hitX = -0.035,
			hitY = 0.015,
			defeatY = 0.13,
			defeatRotation = 55,
		},
	}),
	tide = freezeRig({
		id = "tide",
		style = "TIDE",
		palette = palette({
			outline = { 27, 67, 84 },
			shadow = { 21, 34, 43 },
			body = { 50, 139, 176 },
			head = { 67, 171, 202 },
			belly = { 123, 218, 218 },
			marking = { 31, 103, 145 },
			wing = { 91, 203, 214 },
			eye = { 230, 251, 246 },
			pupil = { 20, 63, 84 },
			mouth = { 35, 84, 111 },
			accessory = { 238, 207, 106 },
			accent = { 96, 224, 211 },
		}),
		attachments = {
			shadow = part(0.5, 0.83, 0.77, 0.075),
			body = part(0.5, 0.59, 0.68, 0.34),
			head = part(0.67, 0.47, 0.31, 0.24, -4),
			leftFoot = part(0.42, 0.77, 0.18, 0.08, -10),
			rightFoot = part(0.65, 0.75, 0.18, 0.08, 8),
			belly = part(0.54, 0.62, 0.39, 0.16),
			markings = part(0.51, 0.59, 0.44, 0.17),
			leftEye = part(0.63, 0.45, 0.065, 0.075),
			rightEye = part(0.72, 0.45, 0.065, 0.075),
			mouth = part(0.75, 0.53, 0.11, 0.02),
			tail = part(0.18, 0.6, 0.38, 0.18, 5),
			tailTip = part(0.05, 0.58, 0.2, 0.28),
			wingLeft = part(0.39, 0.45, 0.2, 0.24, -35),
			wingRight = part(0.57, 0.72, 0.22, 0.2, 25),
			accessory = part(0.66, 0.3, 0.24, 0.13),
			earLeft = part(0.56, 0.35, 0.12, 0.17, -25),
			earRight = part(0.7, 0.33, 0.12, 0.18, 20),
			crest = part(0.54, 0.36, 0.12, 0.22, -35),
			shoulderLeft = part(0.34, 0.51, 0.16, 0.22),
			shoulderRight = part(0.65, 0.63, 0.16, 0.2),
			snout = part(0.78, 0.5, 0.2, 0.09),
			wispLeft = part(0.29, 0.71, 0.17, 0.18, 30),
			wispRight = part(0.57, 0.76, 0.17, 0.16, -20),
		},
		animation = {
			idleScale = 1.02,
			idleY = -0.012,
			idleDuration = 0.9,
			attackX = 0.12,
			attackY = -0.015,
			hitX = -0.05,
			hitY = 0.005,
			defeatY = 0.16,
			defeatRotation = 62,
		},
	}),
	gale = freezeRig({
		id = "gale",
		style = "GALE",
		palette = palette({
			outline = { 57, 77, 91 },
			shadow = { 31, 38, 45 },
			body = { 221, 205, 112 },
			head = { 242, 225, 135 },
			belly = { 239, 235, 189 },
			marking = { 105, 157, 184 },
			wing = { 145, 207, 226 },
			eye = { 252, 250, 224 },
			pupil = { 48, 74, 91 },
			mouth = { 151, 89, 51 },
			accessory = { 232, 168, 70 },
			accent = { 102, 181, 215 },
		}),
		attachments = {
			shadow = part(0.5, 0.9, 0.58, 0.075),
			body = part(0.5, 0.62, 0.39, 0.55),
			head = part(0.5, 0.31, 0.34, 0.27),
			leftFoot = part(0.41, 0.87, 0.16, 0.09, -8),
			rightFoot = part(0.59, 0.87, 0.16, 0.09, 8),
			belly = part(0.5, 0.65, 0.24, 0.29),
			markings = part(0.5, 0.62, 0.27, 0.28),
			leftEye = part(0.44, 0.31, 0.065, 0.085),
			rightEye = part(0.56, 0.31, 0.065, 0.085),
			mouth = part(0.5, 0.41, 0.12, 0.022),
			tail = part(0.29, 0.75, 0.26, 0.2, 35),
			tailTip = part(0.22, 0.84, 0.16, 0.18, 45),
			wingLeft = part(0.25, 0.58, 0.37, 0.48, -18),
			wingRight = part(0.75, 0.58, 0.37, 0.48, 18),
			accessory = part(0.5, 0.12, 0.25, 0.17),
			earLeft = part(0.39, 0.18, 0.1, 0.2, -25),
			earRight = part(0.61, 0.18, 0.1, 0.2, 25),
			crest = part(0.5, 0.1, 0.14, 0.26),
			shoulderLeft = part(0.34, 0.49, 0.14, 0.2),
			shoulderRight = part(0.66, 0.49, 0.14, 0.2),
			snout = part(0.5, 0.39, 0.16, 0.1),
			wispLeft = part(0.35, 0.81, 0.13, 0.18, 20),
			wispRight = part(0.65, 0.81, 0.13, 0.18, -20),
		},
		animation = {
			idleScale = 1.028,
			idleY = -0.018,
			idleDuration = 0.65,
			attackX = 0.13,
			attackY = -0.06,
			hitX = -0.06,
			hitY = 0.0,
			defeatY = 0.21,
			defeatRotation = 88,
		},
	}),
	shade = freezeRig({
		id = "shade",
		style = "SHADE",
		palette = palette({
			outline = { 40, 29, 59 },
			shadow = { 18, 15, 27 },
			body = { 75, 55, 103 },
			head = { 95, 67, 128 },
			belly = { 127, 92, 151 },
			marking = { 48, 35, 72 },
			wing = { 104, 75, 137 },
			eye = { 223, 208, 245 },
			pupil = { 28, 20, 42 },
			mouth = { 47, 28, 59 },
			accessory = { 180, 124, 213 },
			accent = { 142, 99, 179 },
		}),
		attachments = {
			shadow = part(0.5, 0.87, 0.69, 0.1),
			body = part(0.5, 0.61, 0.58, 0.46),
			head = part(0.5, 0.39, 0.45, 0.35),
			leftFoot = part(0.38, 0.82, 0.18, 0.13, 15),
			rightFoot = part(0.62, 0.82, 0.18, 0.13, -15),
			belly = part(0.5, 0.64, 0.33, 0.23),
			markings = part(0.5, 0.62, 0.37, 0.23),
			leftEye = part(0.42, 0.38, 0.085, 0.1),
			rightEye = part(0.58, 0.38, 0.085, 0.1),
			mouth = part(0.5, 0.5, 0.14, 0.022),
			tail = part(0.2, 0.68, 0.35, 0.13, 28),
			tailTip = part(0.08, 0.76, 0.17, 0.08, 48),
			wingLeft = part(0.25, 0.58, 0.25, 0.29, -25),
			wingRight = part(0.75, 0.58, 0.25, 0.29, 25),
			accessory = part(0.5, 0.18, 0.27, 0.14),
			earLeft = part(0.36, 0.24, 0.14, 0.17, -30),
			earRight = part(0.64, 0.24, 0.14, 0.17, 30),
			crest = part(0.5, 0.16, 0.13, 0.2),
			shoulderLeft = part(0.27, 0.53, 0.22, 0.24),
			shoulderRight = part(0.73, 0.53, 0.22, 0.24),
			snout = part(0.5, 0.47, 0.2, 0.1),
			wispLeft = part(0.31, 0.83, 0.18, 0.23, 25),
			wispRight = part(0.69, 0.83, 0.18, 0.23, -25),
		},
		animation = {
			idleScale = 1.035,
			idleY = -0.014,
			idleDuration = 1.1,
			attackX = 0.11,
			attackY = -0.045,
			hitX = -0.065,
			hitY = 0.015,
			defeatY = 0.16,
			defeatRotation = 45,
		},
	}),
})

local LEGACY_RIG_DEFAULTS = table.freeze({ heavy = "stone", round = "verdant", agile = "feral" })
local SLOT_ATTACHMENTS = table.freeze({
	shadow = "shadow",
	tail = "tail",
	wings = "body",
	body = "body",
	color = "belly",
	markings = "markings",
	eyes = "head",
	mouth = "mouth",
	accessories = "accessory",
})

local SpriteRigCatalog = {}

function SpriteRigCatalog.get(rigId: string)
	return rigs[rigId] or rigs[LEGACY_RIG_DEFAULTS[rigId]] or rigs.verdant
end

function SpriteRigCatalog.attachment(rigId: string, name: string)
	local rig = SpriteRigCatalog.get(rigId)
	return rig.attachments[name] or rig.attachments.body
end

function SpriteRigCatalog.pivot(rigId: string, slot: string)
	return SpriteRigCatalog.attachment(rigId, SLOT_ATTACHMENTS[slot] or "body").position
end

function SpriteRigCatalog.all()
	return rigs
end

SpriteRigCatalog.Ids = table.freeze({ "stone", "feral", "verdant", "tide", "gale", "shade" })
return table.freeze(SpriteRigCatalog)
