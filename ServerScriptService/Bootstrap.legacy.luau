-- Bootstrap: starts the server-side systems.
local PlayerData = require(script.Parent.PlayerData)
local LevelService = require(script.Parent.LevelService)
local EntityService = require(script.Parent.EntityService)

PlayerData.Start()
LevelService.Start()
EntityService.Start()
