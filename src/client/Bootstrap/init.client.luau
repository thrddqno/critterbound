--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevelopmentLogger = require(Shared.DevelopmentLogger)

local camera = Workspace.CurrentCamera
if camera ~= nil then
	camera.CameraType = Enum.CameraType.Scriptable
end

DevelopmentLogger.info("Client initialized")

local Protocol = require(Shared.Network.Protocol)
local remotes = ReplicatedStorage:WaitForChild(Protocol.RemoteFolderName)
local battleRequest = remotes:WaitForChild(Protocol.BattleRequestName) :: RemoteFunction
local BattleScreenController = require(script.Parent.Controllers.BattleScreenController)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
BattleScreenController.start(playerGui, battleRequest)
DevelopmentLogger.info("Authoritative battle screen mounted")
