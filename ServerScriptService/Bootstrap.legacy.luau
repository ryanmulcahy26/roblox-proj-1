-- Bootstrap: starts the server-side systems.
local PlayerData = require(script.Parent.PlayerData)
local LevelService = require(script.Parent.LevelService)

PlayerData.Start()
LevelService.Start()
