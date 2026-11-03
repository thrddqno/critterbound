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
local PlayerDataProtocol = require(Shared.Network.PlayerDataProtocol)
local BreedingProtocol = require(Shared.Network.BreedingProtocol)
local remotes = ReplicatedStorage:WaitForChild(Protocol.RemoteFolderName)
local battleRequest = remotes:WaitForChild(Protocol.BattleRequestName) :: RemoteFunction
local playerDataRequest = remotes:WaitForChild(PlayerDataProtocol.RemoteName) :: RemoteFunction
local breedingRequest = remotes:WaitForChild(BreedingProtocol.RemoteName) :: RemoteFunction
local EggProtocol = require(Shared.Network.EggProtocol)
local ContractProtocol = require(Shared.Network.ContractProtocol)
local eggRequest = remotes:WaitForChild(EggProtocol.RemoteName) :: RemoteFunction
local contractRequest = remotes:WaitForChild(ContractProtocol.RemoteName) :: RemoteFunction
local AppController = require(script.Parent.Controllers.AppController)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
AppController.start(
	playerGui,
	playerDataRequest,
	battleRequest,
	breedingRequest,
	eggRequest,
	contractRequest
)
DevelopmentLogger.info("Application shell mounted")
