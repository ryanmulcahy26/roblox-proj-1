-- LevelClient: hides collectibles you've collected (only for you)
-- and shows the server's notifications.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local events = ReplicatedStorage:WaitForChild("LevelEvents")

-- [part] = list of { instance, transparency } saved before hiding
local hidden = {}

local function hide(part)
	if hidden[part] then
		return
	end
	local saved = {}
	local function save(instance)
		if instance:IsA("BasePart") then
			table.insert(saved, { instance = instance, transparency = instance.Transparency })
			instance.Transparency = 1
		end
	end
	save(part)
	for _, descendant in ipairs(part:GetDescendants()) do
		save(descendant)
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
	hidden[part] = saved
end

local function restoreAll()
	for part, saved in pairs(hidden) do
		for _, entry in ipairs(saved) do
			entry.instance.Transparency = entry.transparency
		end
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end
	hidden = {}
end

events.OnClientEvent:Connect(function(kind, arg)
	if kind == "Collected" then
		if typeof(arg) == "Instance" then
			hide(arg)
		end
	elseif kind == "Reset" then
		restoreAll()
	elseif kind == "Notify" then
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Backrooms",
				Text = tostring(arg),
				Duration = 3,
			})
		end)
	end
end)
