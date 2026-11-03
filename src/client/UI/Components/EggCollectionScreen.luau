--!strict

local Theme = require(script.Parent.Parent.Theme)
local UIFactory = require(script.Parent.UIFactory)
local AssetCatalog = require(script.Parent.Parent.Parent.Assets.AssetCatalog)
local CritterSpriteRig = require(script.Parent.Parent.Parent.Rendering.CritterSpriteRig)
local EggPresentation = require(script.Parent.Parent.Parent.Presentation.EggPresentation)
local CollectionPresentation =
	require(script.Parent.Parent.Parent.Presentation.CollectionPresentation)

local EggCollectionScreen = {}
local Tabs = EggPresentation.Tabs

local function eggTitle(egg, index: number): string
	local parentA = if type(egg.parentA) == "table" then egg.parentA.displayName else "Unknown"
	local parentB = if type(egg.parentB) == "table" then egg.parentB.displayName else "Unknown"
	return `Egg {index}: {parentA} + {parentB}`
end

function EggCollectionScreen.mount(parent: Instance, props)
	local screen, root = UIFactory.screen(parent, "CritterboundEggs")
	local title = UIFactory.label(root, "Eggs", 28)
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -180, 0, 42)
	local back = UIFactory.button(root, "Main Menu")
	back.Position = UDim2.new(1, -154, 0, 10)
	back.Size = UDim2.fromOffset(136, 44)

	local activeTabButton = UIFactory.button(root, "Active Eggs")
	activeTabButton.Position = UDim2.fromOffset(18, 66)
	activeTabButton.Size = UDim2.fromOffset(160, 42)
	local historyTabButton = UIFactory.button(root, "Hatch History")
	historyTabButton.Position = UDim2.fromOffset(186, 66)
	historyTabButton.Size = UDim2.fromOffset(160, 42)

	local list = Instance.new("ScrollingFrame")
	list.BackgroundColor3 = Theme.Panel
	list.BorderColor3 = Theme.Border
	list.Position = UDim2.fromOffset(18, 118)
	list.Size = UDim2.new(0.44, -24, 1, -136)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = root
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.Parent = list
	local listLayout = UIFactory.list(list, 6)
	local listEmpty = UIFactory.label(list, "", 16)
	listEmpty.Size = UDim2.new(1, -16, 0, 72)
	listEmpty.TextColor3 = Theme.MutedText
	listEmpty.TextXAlignment = Enum.TextXAlignment.Center
	listEmpty.TextYAlignment = Enum.TextYAlignment.Center

	local detailHost = Instance.new("ScrollingFrame")
	detailHost.BackgroundColor3 = Theme.Panel
	detailHost.BorderColor3 = Theme.Border
	detailHost.Position = UDim2.new(0.44, 6, 0, 118)
	detailHost.Size = UDim2.new(0.56, -24, 1, -136)
	detailHost.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailHost.CanvasSize = UDim2.new()
	detailHost.ScrollBarThickness = 6
	detailHost.Parent = root
	local detailPadding = Instance.new("UIPadding")
	detailPadding.PaddingLeft = UDim.new(0, 12)
	detailPadding.PaddingRight = UDim.new(0, 12)
	detailPadding.PaddingTop = UDim.new(0, 12)
	detailPadding.PaddingBottom = UDim.new(0, 12)
	detailPadding.Parent = detailHost
	UIFactory.list(detailHost, 10)

	local eggArt = Instance.new("Frame")
	eggArt.BackgroundColor3 = Theme.PanelAlt
	eggArt.BorderColor3 = Theme.Border
	eggArt.Size = UDim2.fromOffset(120, 150)
	eggArt.LayoutOrder = 1
	eggArt.Parent = detailHost
	local eggCorner = Instance.new("UICorner")
	eggCorner.CornerRadius = UDim.new(0.5, 0)
	eggCorner.Parent = eggArt
	local eggMark = UIFactory.label(eggArt, "EGG", 22)
	eggMark.Size = UDim2.fromScale(1, 1)
	eggMark.TextXAlignment = Enum.TextXAlignment.Center
	eggMark.TextYAlignment = Enum.TextYAlignment.Center

	local offspringArtHost = Instance.new("Frame")
	offspringArtHost.BackgroundColor3 = Theme.PanelAlt
	offspringArtHost.BorderColor3 = Theme.Border
	offspringArtHost.Size = UDim2.fromOffset(180, 180)
	offspringArtHost.LayoutOrder = 1
	offspringArtHost.Visible = false
	offspringArtHost.Parent = detailHost

	local detail = UIFactory.label(detailHost, "", 16)
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.Size = UDim2.fromScale(1, 0)
	detail.LayoutOrder = 2
	detail.RichText = true

	local hatch = UIFactory.button(detailHost, "Hatch")
	hatch.Size = UDim2.new(1, 0, 0, 48)
	hatch.LayoutOrder = 3
	hatch.Visible = false

	local viewOffspring = UIFactory.button(detailHost, "View in Collection")
	viewOffspring.Size = UDim2.new(1, 0, 0, 48)
	viewOffspring.LayoutOrder = 4
	viewOffspring.Visible = false

	local status = UIFactory.label(detailHost, "", 15)
	status.AutomaticSize = Enum.AutomaticSize.Y
	status.Size = UDim2.fromScale(1, 0)
	status.LayoutOrder = 5

	local connections = { back.Activated:Connect(props.onBack) }
	local rows = {}
	local rowById = {}
	local rowWidgets = {}
	local activeTab = props.selectedTab or Tabs.ACTIVE
	local selectedIds = {
		[Tabs.ACTIVE] = if props.selectedEggIds == nil
			then nil
			else props.selectedEggIds[Tabs.ACTIVE],
		[Tabs.HISTORY] = if props.selectedEggIds == nil
			then nil
			else props.selectedEggIds[Tabs.HISTORY],
	}
	local localPending = false
	local destroyed = false
	local refreshRequested = false
	local offspringRig = nil
	local previewedOffspringId: string? = nil

	local function rowInTab(eggId: string?, tab: string)
		if eggId == nil then
			return nil
		end
		local row = rowById[eggId]
		if row ~= nil and EggPresentation.tabForStatus(row.status) == tab then
			return row
		end
		return nil
	end

	local function firstRow(tab: string)
		for _, row in rows do
			if EggPresentation.tabForStatus(row.status) == tab then
				return row
			end
		end
		return nil
	end

	local function setSelection(tab: string, eggId: string?)
		selectedIds[tab] = eggId
		if props.onSelect ~= nil then
			props.onSelect(tab, eggId)
		end
	end

	local function reconcileSelection(tab: string)
		if rowInTab(selectedIds[tab], tab) ~= nil then
			return
		end
		local first = firstRow(tab)
		setSelection(tab, if first == nil then nil else first.id)
	end

	local function clearOffspringPreview()
		if offspringRig ~= nil then
			offspringRig.destroy()
			offspringRig = nil
		end
		previewedOffspringId = nil
	end

	local function showOffspringPreview(row)
		local offspring = row.offspring
		if offspring == nil then
			clearOffspringPreview()
			return
		end
		if offspringRig ~= nil and previewedOffspringId == offspring.id then
			return
		end
		clearOffspringPreview()
		offspringRig = CritterSpriteRig.mount(offspringArtHost, {
			className = offspring.class,
			appearanceGenome = offspring.appearanceGenome,
			facing = "RIGHT",
			resolveAsset = function(id)
				return AssetCatalog:resolve(id)
			end,
			size = UDim2.fromOffset(170, 170),
		})
		previewedOffspringId = offspring.id
	end

	local function render()
		local selected = rowInTab(selectedIds[activeTab], activeTab)
		local selectedId = if selected == nil then nil else selected.id
		local visibleCount = 0
		for id, widget in rowWidgets do
			local row = rowById[id]
			local visible = EggPresentation.tabForStatus(row.status) == activeTab
			widget.button.Visible = visible
			if visible then
				visibleCount += 1
			end
			widget.button.BackgroundColor3 = if id == selectedId
				then Theme.Action
				elseif row.canHatch then Theme.PanelAlt
				else Theme.Panel
			widget.label.Text = if row.status == "INCUBATING"
				then `{row.parentText}\n{row.generationText} | {row.statusText} {row.remainingText}`
				elseif
					row.status == "HATCHED"
				then `{row.parentText}\n{row.generationText} | Hatched {row.hatchDateText}`
				else `{row.parentText}\n{row.generationText} | {row.statusText}`
		end

		activeTabButton.BackgroundColor3 = if activeTab == Tabs.ACTIVE
			then Theme.Action
			else Theme.PanelAlt
		historyTabButton.BackgroundColor3 = if activeTab == Tabs.HISTORY
			then Theme.Action
			else Theme.PanelAlt
		listEmpty.Visible = visibleCount == 0
		listEmpty.Text = if activeTab == Tabs.ACTIVE
			then "No active eggs. Breed two eligible Critters to create one."
			else "No hatch history yet. Hatched eggs will appear here."

		local hasEgg = selected ~= nil
		eggArt.Visible = hasEgg and activeTab == Tabs.ACTIVE
		offspringArtHost.Visible = hasEgg and activeTab == Tabs.HISTORY
		if not hasEgg then
			clearOffspringPreview()
			detail.Text = if visibleCount == 0 then listEmpty.Text else "Select an egg."
			hatch.Visible = false
			viewOffspring.Visible = false
			status.Text = props.message or ""
			return
		end

		local egg = selected.egg
		if activeTab == Tabs.ACTIVE then
			clearOffspringPreview()
			local lines = {
				`<b>{eggTitle(egg, selected.index)}</b>`,
				`Parents: {selected.parentText}`,
				selected.generationText,
				selected.offspringText,
			}
			if selected.status == "INCUBATING" then
				table.insert(lines, "Status: Incubating")
				table.insert(lines, `Time remaining: {selected.remainingText}`)
			else
				table.insert(lines, "Status: Ready to hatch")
			end
			detail.Text = table.concat(lines, "\n")
			hatch.Visible = selected.status == "READY"
			hatch.Active = hatch.Visible and not props.pending and not localPending
			hatch.AutoButtonColor = hatch.Active
			hatch.BackgroundColor3 = if hatch.Active then Theme.Action else Theme.Disabled
			hatch.Text = if localPending or props.pending then "Hatching..." else "Hatch"
			viewOffspring.Visible = false
		else
			showOffspringPreview(selected)
			local offspring = selected.offspring
			local offspringName = if offspring == nil then "Unavailable" else offspring.displayName
			local offspringClass = if offspring == nil
				then egg.offspringClass or "Unknown"
				else offspring.class
			local offspringStats = if offspring == nil
				then "Stats unavailable."
				else offspring.statsText
			detail.Text = table.concat({
				`<b>{eggTitle(egg, selected.index)}</b>`,
				`Parents: {selected.parentText}`,
				selected.generationText,
				`Hatched: {selected.hatchDateText}`,
				`Linked offspring: {offspringName} ({offspringClass})`,
				`Offspring ID: {egg.offspringId or "Unavailable"}`,
				`<b>Stats</b>\n{offspringStats}`,
			}, "\n")
			hatch.Visible = false
			viewOffspring.Visible = egg.offspringId ~= nil
			viewOffspring.Active = viewOffspring.Visible
		end
		status.Text = props.message or ""
	end

	local function selectEgg(eggId: string)
		if rowInTab(eggId, activeTab) == nil then
			return
		end
		setSelection(activeTab, eggId)
		render()
	end

	local function switchTab(tab: string)
		if activeTab == tab then
			return
		end
		activeTab = tab
		if props.onTabChange ~= nil then
			props.onTabChange(tab)
		end
		reconcileSelection(tab)
		render()
	end

	local now = os.time()
	for index, egg in props.eggs or {} do
		local row = EggPresentation.mapEgg(egg, now)
		if EggPresentation.tabForStatus(row.status) ~= nil then
			row.index = index
			if row.status == "HATCHED" and egg.offspring ~= nil then
				row.offspring = CollectionPresentation.mapCritter(egg.offspring)
			end
			table.insert(rows, row)
			rowById[row.id] = row
			local button = UIFactory.button(list, "")
			button.LayoutOrder = index
			button.Size = UDim2.new(1, -16, 0, 78)
			button.Text = ""
			local marker = UIFactory.label(button, eggTitle(egg, index), 15)
			marker.Position = UDim2.fromOffset(8, 6)
			marker.Size = UDim2.new(1, -16, 0, 20)
			local rowLabel = UIFactory.label(button, "", 13)
			rowLabel.Position = UDim2.fromOffset(8, 30)
			rowLabel.Size = UDim2.new(1, -16, 0, 42)
			rowLabel.TextColor3 = Theme.MutedText
			rowWidgets[row.id] = { button = button, label = rowLabel }
			table.insert(
				connections,
				button.Activated:Connect(function()
					selectEgg(row.id)
				end)
			)
		end
	end

	table.insert(
		connections,
		activeTabButton.Activated:Connect(function()
			switchTab(Tabs.ACTIVE)
		end)
	)
	table.insert(
		connections,
		historyTabButton.Activated:Connect(function()
			switchTab(Tabs.HISTORY)
		end)
	)
	table.insert(
		connections,
		hatch.Activated:Connect(function()
			local selected = rowInTab(selectedIds[activeTab], activeTab)
			if selected == nil or not selected.canHatch or props.pending or localPending then
				return
			end
			localPending = true
			render()
			props.onHatch(selected.id)
		end)
	)
	table.insert(
		connections,
		viewOffspring.Activated:Connect(function()
			local selected = rowInTab(selectedIds[activeTab], activeTab)
			if
				activeTab == Tabs.HISTORY
				and selected ~= nil
				and selected.egg.offspringId ~= nil
			then
				props.onViewOffspring(selected.egg.offspringId)
			end
		end)
	)
	table.insert(
		connections,
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y)
		end)
	)

	reconcileSelection(activeTab)
	render()

	task.spawn(function()
		while not destroyed do
			task.wait(1)
			if destroyed then
				break
			end
			local timestamp = os.time()
			for _, row in rows do
				if row.status == "INCUBATING" then
					row.remainingSeconds = EggPresentation.remainingSeconds(row.egg, timestamp)
					row.remainingText = EggPresentation.formatRemaining(row.remainingSeconds)
					if row.remainingSeconds == 0 and not refreshRequested then
						refreshRequested = true
						props.onRefresh()
						if destroyed then
							return
						end
					end
				end
			end
			render()
		end
	end)

	return table.freeze({
		update = function() end,
		destroy = function()
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			clearOffspringPreview()
			screen:Destroy()
		end,
	})
end

return table.freeze(EggCollectionScreen)
