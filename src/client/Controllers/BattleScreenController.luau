--!strict

local BattlePresentationMapper = require(script.Parent.Parent.Presentation.BattlePresentationMapper)
local PlanningState = require(script.Parent.Parent.Presentation.PlanningState)
local MockBattleSession = require(script.Parent.Parent.Development.MockBattleSession)
local AssetCatalog = require(script.Parent.Parent.Assets.AssetCatalog)
local BattleScreen = require(script.Parent.Parent.UI.Components.BattleScreen)

local BattleScreenController = {}
local activeControllerHandle: any = nil

function BattleScreenController.start(playerGui: PlayerGui)
	if activeControllerHandle ~= nil then
		activeControllerHandle.destroy()
		activeControllerHandle = nil
	end

	local mapped = BattlePresentationMapper.map(MockBattleSession.createSnapshot())
	assert(mapped.ok, "Mock battle snapshot failed presentation mapping")

	local model = mapped.value
	local planningState = PlanningState.new()
	local message: string? = nil
	local screenHandle: any = nil
	local updateScreen: () -> ()

	local function resolveAsset(id: string)
		return AssetCatalog:resolve(id)
	end

	local function onCardSelected(card)
		local result = PlanningState.queueCard(planningState, card, model)
		planningState = result.state
		message = result.error
		updateScreen()
	end

	local function onRemoveCard(cardInstanceId)
		local result = PlanningState.removeCard(planningState, cardInstanceId)
		planningState = result.state
		message = result.error
		updateScreen()
	end

	local function onCommit()
		local result = PlanningState.commit(planningState, model)
		planningState = result.state
		message = if result.ok
			then "Local mock plan locked; no server request sent"
			else result.error
		updateScreen()
	end

	local function onReset()
		planningState = PlanningState.reset()
		message = nil
		updateScreen()
	end

	local function buildProps()
		return {
			model = model,
			planningState = planningState,
			energy = PlanningState.energy(model, planningState),
			resolveAsset = resolveAsset,
			onCardSelected = onCardSelected,
			onRemoveCard = onRemoveCard,
			onCommit = onCommit,
			onReset = onReset,
			message = message,
		}
	end

	updateScreen = function()
		if screenHandle ~= nil then
			screenHandle.update(buildProps())
		end
	end

	screenHandle = BattleScreen.mount(playerGui, buildProps())

	local controllerHandle: any = nil
	controllerHandle = table.freeze({
		destroy = function()
			if screenHandle ~= nil then
				screenHandle.destroy()
				screenHandle = nil
			end
			if activeControllerHandle == controllerHandle then
				activeControllerHandle = nil
			end
		end,
	})
	activeControllerHandle = controllerHandle
	return controllerHandle
end

return table.freeze(BattleScreenController)
