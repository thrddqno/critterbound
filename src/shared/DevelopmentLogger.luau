--!strict

local GameConfig = require(script.Parent.Constants.GameConfig)

local DevelopmentLogger = {}

function DevelopmentLogger.info(message: string)
	print(`{GameConfig.LogPrefix} {message}`)
end

function DevelopmentLogger.warn(message: string)
	warn(`{GameConfig.LogPrefix} {message}`)
end

return table.freeze(DevelopmentLogger)
