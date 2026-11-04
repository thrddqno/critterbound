--!strict

local Theme = require(script.Parent.Parent.Theme)
local TweenService = game:GetService("TweenService")
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)
local CritterHealthBar = require(script.Parent.CritterHealthBar)

local CritterView = {}

export type Props = {
	critter: any,
	resolveAsset: (string) -> any,
	side: "ALLY" | "ENEMY",
	compact: boolean?,
	selectable: boolean?,
	highlighted: boolean?,
	highlightKind: string?,
	onActivated: ((string) -> ())?,
	animationCommand: any?,
	feedback: any?,
}

function CritterView.mount(parent: Instance, props: Props)
	local root = Instance.new("Frame")
	root.Name = "CritterView"
	root.BackgroundColor3 = Theme.Panel
	root.BackgroundTransparency = 0.18
	root.BorderColor3 = if props.side == "ALLY" then Theme.Ally else Theme.Enemy
	root.BorderSizePixel = 1
	root.ClipsDescendants = true
	root.Size = UDim2.new(0.32, -4, 1, 0)
	root.Parent = parent

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(5, 3)
	title.Size = UDim2.new(1, -10, 0, 20)
	title.TextColor3 = Theme.Text
	title.TextSize = 14
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = root

	local identity = Instance.new("TextLabel")
	identity.Name = "CombatantIdentity"
	identity.BackgroundTransparency = 1
	identity.Position = UDim2.fromOffset(5, 23)
	identity.Size = UDim2.new(1, -10, 0, 16)
	identity.TextColor3 = Theme.MutedText
	identity.TextSize = 10
	identity.TextTruncate = Enum.TextTruncate.AtEnd
	identity.TextXAlignment = Enum.TextXAlignment.Left
	identity.Visible = false
	identity.Parent = root

	local artHost = Instance.new("Frame")
	artHost.Name = "ArtHost"
	artHost.BackgroundTransparency = 1
	artHost.ClipsDescendants = true
	artHost.Position = UDim2.fromOffset(4, 25)
	artHost.Size = UDim2.new(1, -8, 1, -65)
	artHost.Parent = root

	local spriteHandle = CritterSpriteRig.mount(artHost, {
		className = props.critter.class,
		appearanceGenome = props.critter.appearanceGenome,
		facing = if props.side == "ALLY" then "RIGHT" else "LEFT",
		resolveAsset = props.resolveAsset,
	})
	local healthHandle = CritterHealthBar.mount(root, props.critter)
	healthHandle.instance.Position = UDim2.new(0, 4, 1, -39)
	healthHandle.instance.Size = UDim2.new(1, -8, 0, 20)

	local speed = Instance.new("TextLabel")
	speed.Name = "Speed"
	speed.BackgroundTransparency = 1
	speed.Position = UDim2.new(0, 4, 1, -19)
	speed.Size = UDim2.new(1, -8, 0, 16)
	speed.TextColor3 = Theme.MutedText
	speed.TextSize = 12
	speed.TextXAlignment = Enum.TextXAlignment.Left
	speed.Parent = root

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusEffects"
	statusLabel.BackgroundColor3 = Theme.Background
	statusLabel.BackgroundTransparency = 0.25
	statusLabel.Position = UDim2.fromOffset(4, 24)
	statusLabel.Size = UDim2.new(1, -8, 0, 17)
	statusLabel.TextColor3 = Theme.Text
	statusLabel.TextSize = 10
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.ZIndex = 8
	statusLabel.Parent = root

	local defeatedBadge = Instance.new("TextLabel")
	defeatedBadge.Name = "DefeatedBadge"
	defeatedBadge.AnchorPoint = Vector2.new(0.5, 0.5)
	defeatedBadge.BackgroundColor3 = Theme.Error
	defeatedBadge.BackgroundTransparency = 0.15
	defeatedBadge.Position = UDim2.fromScale(0.5, 0.5)
	defeatedBadge.Rotation = -8
	defeatedBadge.Size = UDim2.fromScale(0.72, 0.18)
	defeatedBadge.Text = "DEFEATED"
	defeatedBadge.TextColor3 = Theme.Text
	defeatedBadge.TextScaled = true
	defeatedBadge.Visible = false
	defeatedBadge.ZIndex = 9
	defeatedBadge.Parent = root

	local feedbackLabel = Instance.new("TextLabel")
	feedbackLabel.Name = "FloatingCombatText"
	feedbackLabel.BackgroundTransparency = 1
	feedbackLabel.Position = UDim2.fromScale(0.05, 0.5)
	feedbackLabel.Size = UDim2.fromScale(0.9, 0.18)
	feedbackLabel.TextColor3 = Theme.Text
	feedbackLabel.TextScaled = true
	feedbackLabel.TextStrokeTransparency = 0.2
	feedbackLabel.Visible = false
	feedbackLabel.ZIndex = 20
	feedbackLabel.Parent = root

	local targetButton = Instance.new("TextButton")
	targetButton.Name = "TargetButton"
	targetButton.BackgroundTransparency = 1
	targetButton.Size = UDim2.fromScale(1, 1)
	targetButton.Text = ""
	targetButton.ZIndex = 10
	targetButton.Parent = root
	local currentProps = props
	local lastAnimationSequence = nil
	local lastFeedbackSequence = nil
	local feedbackTween: Tween? = nil
	local feedbackConnection: RBXScriptConnection? = nil
	local targetConnection = targetButton.Activated:Connect(function()
		if currentProps.selectable and currentProps.onActivated ~= nil then
			currentProps.onActivated(currentProps.critter.id)
		end
	end)

	local function update(nextProps: Props)
		currentProps = nextProps
		root.BorderColor3 = if nextProps.highlightKind == "TARGETED"
			then Theme.Error
			elseif
				nextProps.highlightKind == "ACTING"
				or nextProps.highlighted
				or nextProps.selectable
			then Theme.Action
			elseif nextProps.side == "ALLY" then Theme.Ally
			else Theme.Enemy
		root.BorderSizePixel = if nextProps.highlightKind ~= nil
				or nextProps.highlighted
				or nextProps.selectable
			then 4
			else 1
		title.Text = `{nextProps.critter.displayName} · {nextProps.critter.class}`
		identity.Text = nextProps.critter.id
		local statuses = {}
		local statusLabels = {
			POISON = "[P] Poison",
			DAMAGE_UP = "[DMG+] Damage Up",
			DAMAGE_DOWN = "[DMG-] Damage Down",
			SPEED_UP = "[SPD+] Speed Up",
			SPEED_DOWN = "[SPD-] Speed Down",
		}
		for _, status in nextProps.critter.statuses or {} do
			table.insert(
				statuses,
				`{statusLabels[status.statusId] or status.statusId} x{status.stackCount or 1}`
			)
		end
		speed.Text = `Speed {nextProps.critter.speed}`
		statusLabel.Text = table.concat(statuses, " · ")
		statusLabel.Visible = #statuses > 0
		title.TextTransparency = if nextProps.critter.defeated then 0.45 else 0
		defeatedBadge.Visible = nextProps.critter.defeated
		artHost.Visible = true
		targetButton.Active = nextProps.selectable == true
		spriteHandle.update({
			className = nextProps.critter.class,
			appearanceGenome = nextProps.critter.appearanceGenome,
			facing = if nextProps.side == "ALLY" then "RIGHT" else "LEFT",
			resolveAsset = nextProps.resolveAsset,
		})
		local command = nextProps.animationCommand
		if command ~= nil and command.sequence ~= lastAnimationSequence then
			lastAnimationSequence = command.sequence
			spriteHandle.play(command.id)
		elseif nextProps.critter.defeated and spriteHandle.animationState() ~= "DEFEAT" then
			spriteHandle.play("DEFEAT")
		end
		local feedback = nextProps.feedback
		if feedback ~= nil and feedback.sequence ~= lastFeedbackSequence then
			lastFeedbackSequence = feedback.sequence
			if feedbackConnection ~= nil then
				feedbackConnection:Disconnect()
				feedbackConnection = nil
			end
			if feedbackTween ~= nil then
				feedbackTween:Cancel()
				feedbackTween = nil
			end
			feedbackLabel.Text = feedback.text
			feedbackLabel.TextColor3 = if feedback.kind == "DAMAGE"
					or feedback.kind == "DEFEAT"
					or feedback.kind == "CANCELED"
					or feedback.kind == "ENVIRONMENT"
				then Theme.Error
				elseif feedback.kind == "CRITICAL" then Theme.Action
				elseif feedback.kind == "HEAL" then Theme.Health
				elseif feedback.kind == "SHIELD" then Theme.Shield
				else Theme.Action
			feedbackLabel.Position = UDim2.fromScale(0.05, 0.5)
			feedbackLabel.TextTransparency = 0
			feedbackLabel.TextStrokeTransparency = 0.2
			feedbackLabel.Visible = true
			feedbackTween = TweenService:Create(
				feedbackLabel,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromScale(0.05, 0.27),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}
			)
			local sequence = feedback.sequence
			feedbackConnection = feedbackTween.Completed:Connect(function()
				if lastFeedbackSequence == sequence then
					feedbackLabel.Visible = false
				end
			end)
			feedbackTween:Play()
		end
		healthHandle.update(nextProps.critter)
	end

	update(props)
	return table.freeze({
		instance = root,
		update = update,
		destroy = function()
			targetConnection:Disconnect()
			if feedbackConnection ~= nil then
				feedbackConnection:Disconnect()
			end
			if feedbackTween ~= nil then
				feedbackTween:Cancel()
			end
			spriteHandle.destroy()
			healthHandle.destroy()
			root:Destroy()
		end,
	})
end

return table.freeze(CritterView)
