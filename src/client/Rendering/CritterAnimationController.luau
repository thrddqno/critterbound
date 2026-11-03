--!strict

local TweenService = game:GetService("TweenService")
local CritterAnimationState = require(script.Parent.CritterAnimationState)

local CritterAnimationController = {}

local DURATION = table.freeze({ ATTACK = 0.12, HIT = 0.1, DEFEAT = 0.32 })
local DEFAULT_OFFSETS = table.freeze({
	idleScale = 1.025,
	idleY = -0.008,
	idleDuration = 0.8,
	attackX = 0.1,
	attackY = -0.035,
	hitX = -0.055,
	hitY = 0.01,
	defeatY = 0.18,
	defeatRotation = 72,
})

function CritterAnimationController.new(root: CanvasGroup)
	local state = CritterAnimationState.new()
	local destroyed = false
	local activeTween: Tween? = nil
	local completionConnection: RBXScriptConnection? = nil
	local basePosition = root.Position
	local baseSize = root.Size
	local presetId = "default"
	local offsets = DEFAULT_OFFSETS

	local function cancelActive()
		if completionConnection ~= nil then
			completionConnection:Disconnect()
			completionConnection = nil
		end
		if activeTween ~= nil then
			activeTween:Cancel()
			activeTween = nil
		end
	end

	local function applyBasePose()
		root.Position = basePosition
		root.Size = baseSize
		root.Rotation = 0
		root.GroupTransparency = 0
	end

	local function scaledSize(scale: number): UDim2
		return UDim2.new(
			baseSize.X.Scale * scale,
			math.round(baseSize.X.Offset * scale),
			baseSize.Y.Scale * scale,
			math.round(baseSize.Y.Offset * scale)
		)
	end

	local function startIdle()
		if destroyed or state.id ~= "IDLE" then
			return
		end
		applyBasePose()
		activeTween = TweenService:Create(
			root,
			TweenInfo.new(
				offsets.idleDuration,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{
				Position = basePosition + UDim2.fromScale(0, offsets.idleY),
				Size = scaledSize(offsets.idleScale),
			}
		)
		activeTween:Play()
	end

	local controller = {}
	function controller.play(animationId: string)
		if destroyed then
			return
		end
		local nextState = CritterAnimationState.transition(state, animationId)
		if nextState == state then
			return
		end
		cancelActive()
		state = nextState
		local revision = state.revision
		applyBasePose()
		if animationId == "IDLE" then
			startIdle()
			return
		end
		local facingDirection = if root:GetAttribute("Facing") == "LEFT" then -1 else 1
		local goal
		local tweenInfo
		if animationId == "ATTACK" then
			goal = {
				Position = basePosition
					+ UDim2.fromScale(offsets.attackX * facingDirection, offsets.attackY),
				Rotation = 5 * facingDirection,
			}
			tweenInfo = TweenInfo.new(
				DURATION.ATTACK,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				true
			)
		elseif animationId == "HIT" then
			goal = {
				Position = basePosition
					+ UDim2.fromScale(offsets.hitX * facingDirection, offsets.hitY),
				Rotation = -7 * facingDirection,
			}
			tweenInfo = TweenInfo.new(
				DURATION.HIT,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				true
			)
		else
			goal = {
				Position = basePosition + UDim2.fromScale(0, offsets.defeatY),
				Rotation = offsets.defeatRotation * facingDirection,
				GroupTransparency = 0.35,
			}
			tweenInfo =
				TweenInfo.new(DURATION.DEFEAT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		activeTween = TweenService:Create(root, tweenInfo, goal)
		completionConnection = activeTween.Completed:Connect(function()
			completionConnection = nil
			activeTween = nil
			state = CritterAnimationState.completion(state, revision)
			if state.id == "IDLE" then
				startIdle()
			end
		end)
		activeTween:Play()
	end

	function controller.state()
		return state.id
	end

	function controller.configure(nextPresetId: string, nextOffsets)
		if destroyed or presetId == nextPresetId then
			return
		end
		presetId = nextPresetId
		offsets = nextOffsets or DEFAULT_OFFSETS
		if state.id == "IDLE" then
			cancelActive()
			startIdle()
		end
	end

	function controller.destroy()
		if destroyed then
			return
		end
		destroyed = true
		cancelActive()
	end

	startIdle()
	return table.freeze(controller)
end

return table.freeze(CritterAnimationController)
