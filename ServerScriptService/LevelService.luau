-- LevelService: doors, collectibles, level entry and the respawn point.
-- It finds map parts by CollectionService tag, so you can build freely:
--   Door         attribute Level = the level this door leads out of
--   Collectible  attributes Level, Value (ascension gained; default 5)
--   LevelEntry   attribute Level = the level a player enters by touching it
--   LevelStart   a SpawnLocation; the start of the run (death sends you here)
--   EntitySpawn  attribute Level; used by the entity system later

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent.PlayerData)

local LevelService = {}

local DEFAULT_COLLECTIBLE_VALUE = 5
local started = false
local events

local function notify(player, text)
	events:FireClient(player, "Notify", text)
end

local function getPlayerFromHit(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character)
end

local function bindTag(tag, setupFn)
	local seen = setmetatable({}, { __mode = "k" })
	local function handle(instance)
		if seen[instance] then
			return
		end
		seen[instance] = true
		setupFn(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(handle)
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		handle(instance)
	end
end

local function setupDoor(door)
	if not door:IsA("BasePart") then
		return
	end
	local level = door:GetAttribute("Level")
	if type(level) ~= "number" then
		warn("LevelService: door " .. door:GetFullName() .. " needs a number attribute called Level")
		return
	end
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Locked door"
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = door
	end
	prompt.Triggered:Connect(function(player)
		if door:GetAttribute("Open") then
			return
		end
		if not PlayerData.HasKey(player, level) then
			notify(player, "This door is locked. Mog the entity to get the key.")
			return
		end
		-- Once open, the door stays open for everyone in the lobby.
		door:SetAttribute("Open", true)
		door.CanCollide = false
		door.Transparency = 0.7
		prompt.Enabled = false
	end)
end

local function setupCollectible(part)
	if not part:IsA("BasePart") then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Collect"
		prompt.ObjectText = "Ascension"
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = part
	end
	prompt.Triggered:Connect(function(player)
		local run = PlayerData.GetRun(player)
		if not run or not PlayerData.GetProfile(player) then
			return
		end
		run.Collected = run.Collected or {}
		if run.Collected[part] then
			return
		end
		run.Collected[part] = true
		local value = part:GetAttribute("Value")
		if type(value) ~= "number" then
			value = DEFAULT_COLLECTIBLE_VALUE
		end
		PlayerData.AddAscension(player, value)
		events:FireClient(player, "Collected", part)
		notify(player, "+" .. value .. " ascension (total " .. run.Ascension .. ")")
	end)
end

local function setupLevelEntry(part)
	if not part:IsA("BasePart") then
		return
	end
	local level = part:GetAttribute("Level")
	if type(level) ~= "number" then
		warn("LevelService: level entry " .. part:GetFullName() .. " needs a number attribute called Level")
		return
	end
	part.Touched:Connect(function(hit)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end
		local run = PlayerData.GetRun(player)
		if run and run.CurrentLevel == level - 1 then
			PlayerData.AdvanceLevel(player)
			notify(player, "Level " .. level)
		end
	end)
end

local function getStartSpawn()
	for _, instance in ipairs(CollectionService:GetTagged("LevelStart")) do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

local function onPlayerAdded(player)
	local spawn = getStartSpawn()
	if spawn then
		player.RespawnLocation = spawn
	end
	-- A new character means a fresh run, so collectibles show again.
	player.CharacterAdded:Connect(function()
		events:FireClient(player, "Reset")
	end)
end

function LevelService.Start()
	if started then
		return
	end
	started = true

	events = Instance.new("RemoteEvent")
	events.Name = "LevelEvents"
	events.Parent = ReplicatedStorage

	bindTag("Door", setupDoor)
	bindTag("Collectible", setupCollectible)
	bindTag("LevelEntry", setupLevelEntry)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return LevelService
