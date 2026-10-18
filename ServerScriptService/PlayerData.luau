-- PlayerData: permanent profile (saved) plus run state (wiped on death).
-- Saved: LevelsCompleted, BestAscension, EntitiesMogged, Purchases.
-- Run (never saved): Ascension, CurrentLevel, Keys, Collected.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PlayerData = {}

-- GetDataStore throws in places that aren't published yet, so guard it.
-- Without stores the game still runs, it just can't save.
local PROFILE_STORE
local BOARDS = {}
do
	local ok, err = pcall(function()
		PROFILE_STORE = DataStoreService:GetDataStore("PlayerProfile_v1")
		BOARDS.LevelsCompleted = DataStoreService:GetOrderedDataStore("LB_LevelsCompleted_v1")
		BOARDS.BestAscension = DataStoreService:GetOrderedDataStore("LB_BestAscension_v1")
		BOARDS.EntitiesMogged = DataStoreService:GetOrderedDataStore("LB_EntitiesMogged_v1")
	end)
	if not ok then
		PROFILE_STORE = nil
		BOARDS = {}
		warn("PlayerData: DataStores unavailable, running without saving. Publish the place and enable Studio API access. (" .. tostring(err) .. ")")
	end
end
local AUTOSAVE_SECONDS = 120
local MAX_ATTEMPTS = 3

local profiles = {}
local runs = {}
local canSave = {}
local finalizing = setmetatable({}, { __mode = "k" })
local activeSaves = 0
local started = false

local function newProfile()
	return {
		LevelsCompleted = 0,
		BestAscension = 0,
		EntitiesMogged = 0,
		Purchases = {},
	}
end

local function newRun()
	return { Ascension = 0, CurrentLevel = 1, Keys = {}, Collected = {} }
end

local function retry(fn)
	local lastError
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(attempt)
	end
	return false, lastError
end

local function profileKey(player)
	return "Player_" .. player.UserId
end

local function loadProfile(player)
	if not PROFILE_STORE then
		profiles[player] = newProfile()
		canSave[player] = false
		return
	end
	local ok, data = retry(function()
		return PROFILE_STORE:GetAsync(profileKey(player))
	end)
	if player.Parent ~= Players then
		return
	end
	local profile = newProfile()
	if ok then
		if type(data) == "table" then
			for field in pairs(profile) do
				if data[field] ~= nil then
					profile[field] = data[field]
				end
			end
		end
		canSave[player] = true
	else
		warn("PlayerData: could not load data for " .. player.Name .. ", nothing will be saved this session: " .. tostring(data))
		canSave[player] = false
	end
	profiles[player] = profile
end

local function saveProfile(player)
	local profile = profiles[player]
	if not profile or not canSave[player] then
		return
	end
	local ok, err = retry(function()
		PROFILE_STORE:SetAsync(profileKey(player), profile)
	end)
	if not ok then
		warn("PlayerData: save failed for " .. player.Name .. ": " .. tostring(err))
		return
	end
	local boardKey = tostring(player.UserId)
	for statName, board in pairs(BOARDS) do
		local value = math.max(0, math.floor(profile[statName] or 0))
		local boardOk, boardErr = retry(function()
			board:SetAsync(boardKey, value)
		end)
		if not boardOk then
			warn("PlayerData: leaderboard save failed (" .. statName .. ") for " .. player.Name .. ": " .. tostring(boardErr))
		end
	end
end

local function finalize(player)
	if finalizing[player] then
		return
	end
	finalizing[player] = true
	activeSaves += 1
	saveProfile(player)
	profiles[player] = nil
	runs[player] = nil
	canSave[player] = nil
	activeSaves -= 1
end

local function autosaveLoop()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveProfile, player)
		end
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		PlayerData.ResetRun(player)
	end)
end

local function onPlayerAdded(player)
	runs[player] = newRun()
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	loadProfile(player)
end

-- Public API ------------------------------------------------------------

function PlayerData.GetProfile(player)
	return profiles[player]
end

function PlayerData.GetRun(player)
	return runs[player]
end

function PlayerData.WaitForProfile(player)
	while player.Parent == Players and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Wipes the run (ascension, level, keys). Saved stats are untouched.
function PlayerData.ResetRun(player)
	runs[player] = newRun()
end

function PlayerData.AddAscension(player, amount)
	local run, profile = runs[player], profiles[player]
	if not run or not profile then
		return
	end
	run.Ascension += amount
	if run.Ascension > profile.BestAscension then
		profile.BestAscension = run.Ascension
	end
end

-- Call when a player mogs the entity on `level`. They get the key for it.
function PlayerData.RecordMog(player, level)
	local run, profile = runs[player], profiles[player]
	if not run or not profile then
		return
	end
	profile.EntitiesMogged += 1
	run.Keys[level] = true
end

function PlayerData.HasKey(player, level)
	local run = runs[player]
	return run ~= nil and run.Keys[level] == true
end

-- Call when a player passes through a door to the next level.
function PlayerData.AdvanceLevel(player)
	local run, profile = runs[player], profiles[player]
	if not run or not profile then
		return
	end
	profile.LevelsCompleted += 1
	run.CurrentLevel += 1
end

function PlayerData.GrantPurchase(player, itemId)
	local profile = profiles[player]
	if profile then
		profile.Purchases[itemId] = true
	end
end

function PlayerData.HasPurchase(player, itemId)
	local profile = profiles[player]
	return profile ~= nil and profile.Purchases[itemId] == true
end

-- statName: "LevelsCompleted", "BestAscension" or "EntitiesMogged".
-- Returns a list of { Rank, UserId, Value }, highest first.
function PlayerData.GetTop(statName, count)
	local board = BOARDS[statName]
	if not board then
		return {}
	end
	local ok, pages = pcall(function()
		return board:GetSortedAsync(false, count or 10)
	end)
	if not ok then
		warn("PlayerData: could not read leaderboard " .. statName .. ": " .. tostring(pages))
		return {}
	end
	local pageOk, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not pageOk then
		warn("PlayerData: could not read leaderboard page " .. statName .. ": " .. tostring(page))
		return {}
	end
	local result = {}
	for rank, entry in ipairs(page) do
		table.insert(result, { Rank = rank, UserId = tonumber(entry.key), Value = entry.value })
	end
	return result
end

function PlayerData.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(finalize, player)
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(finalize, player)
		end
		while activeSaves > 0 do
			task.wait()
		end
	end)
	task.spawn(autosaveLoop)
end

return PlayerData
