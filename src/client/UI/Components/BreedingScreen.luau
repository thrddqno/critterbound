--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local DevelopmentLogger = require(ReplicatedStorage.Shared.DevelopmentLogger)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)
local BreedingScreen = {}

local function critterById(collection, id)
	for _, critter in collection.critters do
		if critter.id == id then
			return critter
		end
	end
	return nil
end

local function breedCountText(critter)
	local breeding = critter.breeding
	if type(breeding) ~= "table" or breeding.breedable ~= true then
		return "Breeding: Restricted"
	end
	local count = breeding.successfulBreedCount or 0
	return `Breeding: {count}/5 used, {5 - count} remaining`
end

function BreedingScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundBreeding")
	local title = UIFactory.label(root, "Breeding", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local eggs = UIFactory.button(root, "Eggs")
	eggs.Position = UDim2.new(1, -306, 0, 10)
	eggs.Size = UDim2.fromOffset(136, 44)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)

	local collection = props.collection
	local selectedA: string? = nil
	local selectedB: string? = nil
	local preview: any = nil
	local previewPending = false
	local previewToken = 0
	local breedSubmitted = false
	local destroyed = false
	local message = props.message or "Select two different Critters."

	local left = Instance.new("ScrollingFrame")
	left.BackgroundColor3 = Theme.Panel
	left.Position = UDim2.fromOffset(18, 66)
	left.Size = UDim2.new(0.34, -24, 1, -84)
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	left.ScrollBarThickness = 6
	left.Parent = root

	local center = Instance.new("Frame")
	center.BackgroundTransparency = 1
	center.Position = UDim2.new(0.34, 6, 0, 66)
	center.Size = UDim2.new(0.32, -12, 1, -84)
	center.Parent = root

	local right = Instance.new("ScrollingFrame")
	right.BackgroundColor3 = Theme.Panel
	right.Position = UDim2.new(0.66, 6, 0, 66)
	right.Size = UDim2.new(0.34, -24, 1, -84)
	right.AutomaticCanvasSize = Enum.AutomaticSize.Y
	right.CanvasSize = UDim2.new()
	right.ScrollBarThickness = 6
	right.Parent = root
	local rightPadding = Instance.new("UIPadding")
	rightPadding.PaddingLeft = UDim.new(0, 8)
	rightPadding.PaddingRight = UDim.new(0, 8)
	rightPadding.PaddingTop = UDim.new(0, 8)
	rightPadding.PaddingBottom = UDim.new(0, 8)
	rightPadding.Parent = right

	local connections = {
		back.Activated:Connect(props.onBack),
		eggs.Activated:Connect(function()
			if props.onEggs ~= nil then
				props.onEggs()
			end
		end),
	}
	local parentRigs = {}
	local render

	local function makeSlot(host: Instance, titleText: string, yScale: number)
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Theme.PanelAlt
		frame.Position = UDim2.fromScale(0.05, yScale)
		frame.Size = UDim2.fromScale(0.9, 0.42)
		frame.Parent = host
		local label = UIFactory.label(frame, titleText, 18)
		label.Position = UDim2.fromOffset(8, 6)
		label.Size = UDim2.new(1, -16, 0, 24)
		local artHost = Instance.new("Frame")
		artHost.BackgroundTransparency = 1
		artHost.Position = UDim2.fromOffset(8, 34)
		artHost.Size = UDim2.fromOffset(110, 110)
		artHost.Parent = frame
		local info = UIFactory.label(frame, "Empty", 14)
		info.Position = UDim2.fromOffset(128, 38)
		info.Size = UDim2.new(1, -136, 1, -46)
		return frame, artHost, info
	end

	local _, artA, infoA = makeSlot(center, "Parent A", 0.04)
	local _, artB, infoB = makeSlot(center, "Parent B", 0.54)

	UIFactory.list(right, 8)

	local status = UIFactory.label(right, message, 15)
	status.Size = UDim2.new(1, 0, 0, 48)
	status.LayoutOrder = 1

	local compatibility = UIFactory.label(right, "Compatibility: Not evaluated", 15)
	compatibility.Size = UDim2.fromScale(1, 0)
	compatibility.AutomaticSize = Enum.AutomaticSize.Y
	compatibility.LayoutOrder = 2

	local offspring = UIFactory.label(right, "Offspring possibilities: None", 15)
	offspring.Size = UDim2.fromScale(1, 0)
	offspring.AutomaticSize = Enum.AutomaticSize.Y
	offspring.LayoutOrder = 3

	local counts = UIFactory.label(right, "Parent counts: None", 15)
	counts.Size = UDim2.fromScale(1, 0)
	counts.AutomaticSize = Enum.AutomaticSize.Y
	counts.LayoutOrder = 4

	local breed = UIFactory.button(right, "Breed")
	breed.Size = UDim2.new(1, 0, 0, 48)
	breed.LayoutOrder = 5

	local function destroyRig(slot)
		if parentRigs[slot] ~= nil then
			parentRigs[slot].destroy()
			parentRigs[slot] = nil
		end
	end

	local function renderSlot(slot: string, critter)
		local artHost = if slot == "A" then artA else artB
		local info = if slot == "A" then infoA else infoB
		destroyRig(slot)
		if critter == nil then
			info.Text = "Empty"
			return
		end
		local rig = CritterSpriteRig.mount(artHost, {
			className = critter.class,
			appearanceGenome = critter.appearanceGenome,
			facing = "RIGHT",
			resolveAsset = function(id)
				return AssetCatalog:resolve(id)
			end,
			size = UDim2.fromOffset(100, 100),
		})
		parentRigs[slot] = rig
		info.Text = table.concat({
			`{critter.displayName} — {critter.class}`,
			critter.statsText,
			breedCountText(critter),
			critter.restrictionsText,
		}, "\n")
	end

	local function eligibleText(critter)
		if critter.breeding and critter.breeding.breedable then
			return "Eligible"
		end
		if critter.acquisitionText == "STARTER" then
			return "Restricted: starter Critter cannot breed"
		end
		if critter.breeding == nil then
			return "Restricted: breeding data unavailable"
		end
		return "Restricted: cannot breed"
	end

	local function runPreview()
		if selectedA == nil or selectedB == nil or selectedA == selectedB then
			preview = nil
			previewPending = false
			status.Text = message
			compatibility.Text = "Compatibility: Select two different Critters."
			offspring.Text = "Offspring possibilities: None"
			counts.Text = "Parent counts: None"
			return
		end
		previewToken += 1
		local token = previewToken
		previewPending = true
		status.Text = "Checking compatibility..."
		compatibility.Text = "Compatibility: Checking..."
		DevelopmentLogger.info(`Breeding preview: checking {selectedA} x {selectedB}`)
		local check = props.onCheck(selectedA, selectedB)
		if destroyed or token ~= previewToken then
			return
		end
		if not check.ok then
			previewPending = false
			preview = nil
			status.Text = check.errors and check.errors[1] and check.errors[1].message
				or "Compatibility check failed."
			compatibility.Text = "Compatibility: Request failed"
			DevelopmentLogger.warn(`Breeding preview check failed: {status.Text}`)
			render()
			return
		end
		if check.value.eligible ~= true then
			previewPending = false
			preview = check.value
			status.Text = "Incompatible."
			compatibility.Text = "Compatibility: Incompatible"
			local reasons = {}
			for _, err in check.value.errors or {} do
				table.insert(reasons, err.message or err.code)
			end
			if #reasons > 0 then
				compatibility.Text = `Compatibility: Incompatible\n{table.concat(reasons, "\n")}`
			end
			offspring.Text = "Offspring possibilities: None"
			DevelopmentLogger.info(`Breeding preview incompatible: {table.concat(reasons, "; ")}`)
			render()
			return
		end
		status.Text = "Loading compatibility details..."
		local detail = props.onPreviewCompatibility(selectedA, selectedB)
		if destroyed or token ~= previewToken then
			return
		end
		previewPending = false
		if not detail.ok then
			preview = nil
			status.Text = detail.errors and detail.errors[1] and detail.errors[1].message
				or "Preview failed."
			compatibility.Text = "Compatibility: Preview failed"
			DevelopmentLogger.warn(`Breeding preview detail failed: {status.Text}`)
			render()
			return
		end
		preview = detail.value
		status.Text = "Compatible."
		compatibility.Text = "Compatibility: Compatible"
		local classes = detail.value.possibleOffspringClasses or {}
		offspring.Text = if #classes == 0
			then "Offspring possibilities: Backend did not provide possible classes."
			else `Offspring possibilities: {table.concat(classes, ", ")}`
		counts.Text = "Parent counts: see selected Critters."
		DevelopmentLogger.info(
			`Breeding preview compatible: {table.concat(
				detail.value.possibleOffspringClasses or {},
				", "
			)}`
		)
		render()
	end

	local leftPadding = Instance.new("UIPadding")
	leftPadding.PaddingLeft = UDim.new(0, 8)
	leftPadding.PaddingRight = UDim.new(0, 8)
	leftPadding.PaddingTop = UDim.new(0, 8)
	leftPadding.PaddingBottom = UDim.new(0, 8)
	leftPadding.Parent = left

	local listLayout = UIFactory.list(left, 6)
	local buttons = {}
	if collection ~= nil then
		for index, critter in collection.critters do
			local button = UIFactory.button(left, "")
			button.LayoutOrder = index
			button.Size = UDim2.new(1, -16, 0, 88)
			button.BackgroundColor3 = Theme.PanelAlt
			button.Text = ""
			button.AutoButtonColor = true
			local nameLabel =
				UIFactory.label(button, `{critter.displayName} — {critter.class}`, 15)
			nameLabel.Position = UDim2.fromOffset(8, 6)
			nameLabel.Size = UDim2.new(1, -16, 0, 20)
			local statsLabel = UIFactory.label(button, critter.statsText, 13)
			statsLabel.Position = UDim2.fromOffset(8, 30)
			statsLabel.Size = UDim2.new(1, -16, 0, 20)
			statsLabel.TextColor3 = Theme.MutedText
			local eligibility = eligibleText(critter)
			local breedLabel =
				UIFactory.label(button, `{breedCountText(critter)}  |  {eligibility}`, 13)
			breedLabel.Position = UDim2.fromOffset(8, 54)
			breedLabel.Size = UDim2.new(1, -16, 0, 28)
			breedLabel.TextColor3 = if critter.breeding and critter.breeding.breedable
				then Theme.Health
				else Theme.Error
			buttons[critter.id] = button
			table.insert(
				connections,
				button.Activated:Connect(function()
					if selectedA == critter.id then
						selectedA = nil
					elseif selectedB == critter.id then
						selectedB = nil
					elseif selectedA == nil then
						selectedA = critter.id
					elseif selectedB == nil then
						selectedB = critter.id
					end
					render()
					runPreview()
				end)
			)
		end
	end
	table.insert(
		connections,
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			left.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y)
		end)
	)
	table.insert(
		connections,
		right:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function() end)
	)

	render = function()
		for id, button in buttons do
			local selected = id == selectedA or id == selectedB
			button.BackgroundColor3 = if selected then Theme.Ally else Theme.PanelAlt
		end
		renderSlot("A", if selectedA == nil then nil else critterById(collection, selectedA))
		renderSlot("B", if selectedB == nil then nil else critterById(collection, selectedB))
		breed.Active = selectedA ~= nil
			and selectedB ~= nil
			and selectedA ~= selectedB
			and preview ~= nil
			and preview.eligible == true
			and not previewPending
			and not breedSubmitted
			and not props.pending
		breed.AutoButtonColor = breed.Active
		breed.BackgroundColor3 = if breed.Active then Theme.Action else Theme.Disabled
		if collection == nil then
			status.Text = "Loading collection..."
		elseif #collection.critters == 0 then
			status.Text = "No Critters available."
		elseif previewPending then
			status.Text = "Checking compatibility..."
		elseif props.pending or breedSubmitted then
			status.Text = "Breeding..."
		elseif message ~= nil then
			status.Text = message
		end
	end

	table.insert(
		connections,
		breed.Activated:Connect(function()
			if
				not breed.Active
				or selectedA == nil
				or selectedB == nil
				or selectedA == selectedB
			then
				return
			end
			breedSubmitted = true
			message = "Breeding..."
			render()
			props.onBreed(selectedA, selectedB)
		end)
	)

	render()
	runPreview()

	return table.freeze({
		update = function() end,
		destroy = function()
			destroyed = true
			previewToken += 1
			for _, connection in connections do
				connection:Disconnect()
			end
			destroyRig("A")
			destroyRig("B")
			screen:Destroy()
		end,
	})
end

return table.freeze(BreedingScreen)
