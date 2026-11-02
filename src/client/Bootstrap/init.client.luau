--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevelopmentLogger = require(Shared.DevelopmentLogger)

DevelopmentLogger.info("Client initialized")
