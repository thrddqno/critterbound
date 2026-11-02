--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevelopmentLogger = require(Shared.DevelopmentLogger)

local camera = Workspace.CurrentCamera
if camera ~= nil then
	camera.CameraType = Enum.CameraType.Scriptable
end

DevelopmentLogger.info("Client initialized")

if RunService:IsStudio() then
	local BattleScreenController = require(script.Parent.Controllers.BattleScreenController)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	BattleScreenController.start(playerGui)
	DevelopmentLogger.info("Studio battle presentation shell mounted")
end
