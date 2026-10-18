-- EntityService: one entity per level.
-- It wanders slowly at a random pace. When it sees a player it activates and
-- chases faster and more erratically. On contact:
--   player ascension > entity ascension  -> the player mogs it and gets the key
--   otherwise                            -> the player dies and the run is wiped
-- After a mog the entity stays dead for LevelConfig.EntityDeadSeconds, then
-- respawns at a random EntitySpawn unless the level's door has been opened.
-- Tuning values live in LevelConfig.Entity.
--
-- To use your own model, put a Model named EntityTemplate in ServerStorage
-- (it needs a Humanoid and a part named HumanoidRootPart).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LevelConfig = require(script.Parent.LevelConfig)
local PlayerData = require(script.Parent.PlayerData)

local cfg = LevelConfig.Entity

local EntityService = {}

local AGENT = { AgentRadius = 2.5, AgentHeight = 6, AgentCanJump = false, WaypointSpacing = 6 }

local events
local entitiesFolder
local started = false

local function randomRange(minValue, maxValue)
	return minValue + math.random() * (maxValue - minValue)
end

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function notify(player, text)
	if events then
		events:FireClient(player, "Notify", text)
	end
end

local function computeWaypoints(fromPosition, toPosition)
	local path = PathfindingService:CreatePath(AGENT)
	local ok = pcall(function()
		path:ComputeAsync(fromPosition, toPosition)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end

-- Returns the player's root part if they are alive and on this level.
local function getEligibleRoot(player, level)
	if not player or player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	local run = PlayerData.GetRun(player)
	if run and run.CurrentLevel == level then
		return root
	end
	return nil
end

local function addWeld(model, part0, part1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
end

local function buildPlaceholder()
	local model = Instance.new("Model")

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 6, 1.5)
	root.Color = Color3.fromRGB(22, 22, 26)
	root.Material = Enum.Material.SmoothPlastic
	root.CanCollide = false
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2.6, 2.6, 2.6)
	head.Color = Color3.fromRGB(235, 220, 200)
	head.CanCollide = false
	head.Massless = true
	head.CFrame = root.CFrame * CFrame.new(0, 4.1, 0)
	head.Parent = model
	addWeld(model, root, head)

	for _, x in ipairs({ -0.55, 0.55 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.45, 0.45, 0.45)
		eye.Color = Color3.fromRGB(255, 40, 40)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = root.CFrame * CFrame.new(x, 4.3, -1.15)
		eye.Parent = model
		addWeld(model, root, eye)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 0.1
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

local function buildEntity(level)
	local template = ServerStorage:FindFirstChild("EntityTemplate")
	local model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = buildPlaceholder()
	end
	model.Name = "Entity_Level" .. level
	return model
end

local Entity = {}
Entity.__index = Entity

function Entity.new(level)
	local self = setmetatable({}, Entity)
	self.Level = level
	self.State = "Dead"
	self.DeadUntil = 0
	self.Active = true
	self.CooldownUntil = 0
	self.ActivateUntil = 0
	self.Home = Vector3.zero
	return self
end

function Entity:GetSpawnMarkers()
	local markers = {}
	for _, instance in ipairs(CollectionService:GetTagged("EntitySpawn")) do
		if instance:IsA("BasePart") and instance:GetAttribute("Level") == self.Level then
			table.insert(markers, instance)
		end
	end
	return markers
end

function Entity:IsDoorOpen()
	for _, door in ipairs(CollectionService:GetTagged("Door")) do
		if door:GetAttribute("Level") == self.Level and door:GetAttribute("Open") == true then
			return true
		end
	end
	return false
end

function Entity:Spawn()
	local markers = self:GetSpawnMarkers()
	if #markers == 0 then
		warn("EntityService: no EntitySpawn parts for level " .. self.Level)
		self.State = "Gone"
		return
	end
	local marker = markers[math.random(#markers)]

	local model = buildEntity(self.Level)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		warn("EntityService: the entity model needs a Humanoid and a HumanoidRootPart")
		model:Destroy()
		self.State = "Gone"
		return
	end
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	model:PivotTo(CFrame.new(marker.Position + Vector3.new(0, 4, 0)))
	model.Parent = entitiesFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	self.Model = model
	self.Humanoid = humanoid
	self.Root = root
	self.Home = marker.Position
	self.State = "Wander"
	self.Target = nil
	self.Waypoints = nil
	self.WaypointIndex = 1
	self.PauseUntil = 0
	self.WanderSpeed = randomRange(cfg.WanderSpeedMin, cfg.WanderSpeedMax)
	self.StuckCheckedAt = os.clock()
	self.StuckCheckPos = root.Position
	self.Moving = false
	self.StutterUntil = 0
	self.JitterAmount = 0
	self.NextJitterAt = 0
	self.NextRepathAt = 0
	model:SetAttribute("State", self.State)
end

function Entity:Despawn()
	if self.Model then
		self.Model:Destroy()
	end
	self.Model = nil
	self.Humanoid = nil
	self.Root = nil
end

function Entity:Revive()
	-- If the door has been found and opened, the entity stays dead.
	if self:IsDoorOpen() then
		self.State = "Gone"
		return
	end
	self:Spawn()
end

function Entity:HasLineOfSight(player, playerRoot)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Model, player.Character }
	params.RespectCanCollide = true
	local origin = self.Root.Position + Vector3.new(0, 2, 0)
	return workspace:Raycast(origin, playerRoot.Position - origin, params) == nil
end

function Entity:CanSee(player, playerRoot)
	local root = self.Root
	local offset = playerRoot.Position - root.Position
	local distance = offset.Magnitude
	if distance > cfg.SightRange then
		return false
	end
	if distance > cfg.SenseRadius then
		local look = flat(root.CFrame.LookVector)
		local toPlayer = flat(offset)
		if look.Magnitude > 0.01 and toPlayer.Magnitude > 0.01 then
			local angle = math.deg(math.acos(math.clamp(look.Unit:Dot(toPlayer.Unit), -1, 1)))
			if angle > cfg.FieldOfViewDegrees / 2 then
				return false
			end
		end
	end
	return self:HasLineOfSight(player, playerRoot)
end

function Entity:FindVisible()
	local bestPlayer, bestRoot, bestDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local playerRoot = getEligibleRoot(player, self.Level)
		if playerRoot and self:CanSee(player, playerRoot) then
			local distance = (playerRoot.Position - self.Root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				bestPlayer, bestRoot, bestDistance = player, playerRoot, distance
			end
		end
	end
	return bestPlayer, bestRoot
end

function Entity:FindCaught()
	local bestPlayer, bestDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local playerRoot = getEligibleRoot(player, self.Level)
		if playerRoot then
			local distance = (playerRoot.Position - self.Root.Position).Magnitude
			if distance <= cfg.CatchDistance
				and (not bestDistance or distance < bestDistance)
				and self:HasLineOfSight(player, playerRoot)
			then
				bestPlayer, bestDistance = player, distance
			end
		end
	end
	return bestPlayer
end

function Entity:StartPath(goal)
	local waypoints = computeWaypoints(self.Root.Position, goal)
	if not self.Root or not self.Root.Parent then
		return false
	end
	if not waypoints then
		self.Waypoints = nil
		return false
	end
	self.Waypoints = waypoints
	self.WaypointIndex = 2
	return true
end

-- Moves toward the next waypoint. Returns false once the path is finished.
function Entity:FollowWaypoints()
	local waypoints = self.Waypoints
	if not waypoints then
		return false
	end
	local waypoint = waypoints[self.WaypointIndex]
	while waypoint and flat(waypoint.Position - self.Root.Position).Magnitude < 3 do
		self.WaypointIndex += 1
		waypoint = waypoints[self.WaypointIndex]
	end
	if not waypoint then
		return false
	end
	self.Humanoid:MoveTo(waypoint.Position)
	self.Moving = true
	return true
end

function Entity:StartWanderLeg(now)
	local angle = math.random() * math.pi * 2
	local distance = randomRange(cfg.WanderDistanceMin, cfg.WanderDistanceMax)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local candidate = self.Root.Position + direction * distance
	if flat(candidate - self.Home).Magnitude > cfg.WanderRadiusFromSpawn then
		candidate = self.Home + direction * randomRange(10, cfg.WanderRadiusFromSpawn * 0.5)
	end

	-- Find the floor under the candidate point.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Model }
	params.RespectCanCollide = true
	local start = Vector3.new(candidate.X, self.Root.Position.Y + 2, candidate.Z)
	local hit = workspace:Raycast(start, Vector3.new(0, -30, 0), params)
	if not hit or not self:StartPath(hit.Position) then
		self.PauseUntil = now + 0.5
		return
	end
	self.WanderSpeed = randomRange(cfg.WanderSpeedMin, cfg.WanderSpeedMax)
end

function Entity:StepWander(now)
	local humanoid = self.Humanoid
	humanoid.WalkSpeed = self.WanderSpeed
	if now < self.PauseUntil then
		humanoid:MoveTo(self.Root.Position)
		return
	end
	if not self.Waypoints then
		self:StartWanderLeg(now)
		return
	end
	if not self:FollowWaypoints() then
		-- Reached the end of this leg: stand still for a random while.
		self.Waypoints = nil
		self.PauseUntil = now + randomRange(cfg.PauseMin, cfg.PauseMax)
	end
end

function Entity:StepChase(now, visible, targetRoot)
	local humanoid, root = self.Humanoid, self.Root

	-- Erratic speed
	humanoid.WalkSpeed = randomRange(cfg.ChaseSpeedMin, cfg.ChaseSpeedMax)

	-- Random stutters
	if now < self.StutterUntil then
		humanoid:MoveTo(root.Position)
		return
	end
	if math.random() < cfg.StutterChance then
		self.StutterUntil = now + randomRange(cfg.StutterMin, cfg.StutterMax)
		return
	end

	if visible then
		self.Waypoints = nil
		local goal = targetRoot.Position
		local toGoal = flat(goal - root.Position)
		if toGoal.Magnitude > 0.1 then
			local direction = toGoal.Unit
			local side = Vector3.new(-direction.Z, 0, direction.X)
			if now >= self.NextJitterAt then
				self.JitterAmount = randomRange(-1, 1) * cfg.ChaseJitterStuds
				self.NextJitterAt = now + randomRange(cfg.JitterIntervalMin, cfg.JitterIntervalMax)
			end
			-- Less zig-zag when close, so it can still catch you.
			local scale = math.clamp(toGoal.Magnitude / 20, 0, 1)
			goal = goal + side * self.JitterAmount * scale
		end
		humanoid:MoveTo(goal)
		self.Moving = true
	else
		-- Lost sight: path to where it last saw the player.
		if not self.Waypoints or now >= self.NextRepathAt then
			self.NextRepathAt = now + 0.6
			self:StartPath(self.LastSeen)
		end
		if not self:FollowWaypoints() then
			humanoid:MoveTo(root.Position)
		end
	end
end

function Entity:Alert(player, playerRoot, now)
	self.State = "Chase"
	self.Target = player
	self.LastSeen = playerRoot.Position
	self.LostSightAt = nil
	self.Waypoints = nil
	self.ActivateUntil = now + cfg.ActivateSeconds
	self.NextJitterAt = 0
end

function Entity:Calm(now)
	self.State = "Wander"
	self.Target = nil
	self.Waypoints = nil
	self.PauseUntil = now + 1
	self.WanderSpeed = randomRange(cfg.WanderSpeedMin, cfg.WanderSpeedMax)
	if self.Humanoid and self.Root then
		self.Humanoid:MoveTo(self.Root.Position)
	end
end

function Entity:StepChaseState(now, seen, seenRoot)
	if seen then
		self.Target = seen
		self.LastSeen = seenRoot.Position
		self.LostSightAt = nil
	else
		self.LostSightAt = self.LostSightAt or now
		if now - self.LostSightAt > cfg.LoseSightSeconds or not getEligibleRoot(self.Target, self.Level) then
			self:Calm(now)
			return
		end
	end

	-- Brief "activation": it stops and stares before it starts running.
	if now < self.ActivateUntil then
		self.Humanoid:MoveTo(self.Root.Position)
		local lookAt = Vector3.new(self.LastSeen.X, self.Root.Position.Y, self.LastSeen.Z)
		if (lookAt - self.Root.Position).Magnitude > 0.1 then
			self.Root.CFrame = CFrame.lookAt(self.Root.Position, lookAt)
		end
		return
	end

	self:StepChase(now, seen ~= nil, seenRoot)
end

function Entity:Mog(player, now)
	PlayerData.RecordMog(player, self.Level)
	notify(player, "You mogged the entity. You got the key for level " .. self.Level .. ".")
	self:Despawn()
	self.State = "Dead"
	self.DeadUntil = now + LevelConfig.EntityDeadSeconds
end

function Entity:Resolve(player, now)
	local run = PlayerData.GetRun(player)
	local entityAscension = LevelConfig.GetEntityAscension(self.Level)
	if run and entityAscension and run.Ascension > entityAscension then
		self:Mog(player, now)
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
	notify(player, "The entity got you. Your run has been wiped.")
	self.CooldownUntil = now + cfg.CooldownAfterKill
	self:Calm(now)
end

-- If it's trying to move but isn't getting anywhere, pick a new route.
function Entity:CheckStuck(now)
	if now - self.StuckCheckedAt < 1.5 then
		return
	end
	local moved = (self.Root.Position - self.StuckCheckPos).Magnitude
	if self.Moving and moved < 1 then
		self.Waypoints = nil
		self.NextRepathAt = 0
	end
	self.StuckCheckedAt = now
	self.StuckCheckPos = self.Root.Position
	self.Moving = false
end

function Entity:Step()
	local now = os.clock()

	if self.State == "Gone" then
		self.Active = false
		return
	end
	if self.State == "Dead" then
		if now >= self.DeadUntil then
			self:Revive()
		end
		return
	end
	if not self.Model or not self.Model.Parent or not self.Root or not self.Root.Parent then
		-- The model was removed by something else; try again shortly.
		self:Despawn()
		self.State = "Dead"
		self.DeadUntil = now + 2
		return
	end
	if now < self.CooldownUntil then
		self.Humanoid:MoveTo(self.Root.Position)
		return
	end

	local caught = self:FindCaught()
	if caught then
		self:Resolve(caught, now)
		return
	end

	local seen, seenRoot = self:FindVisible()
	if self.State == "Wander" then
		if seen then
			self:Alert(seen, seenRoot, now)
		else
			self:StepWander(now)
		end
	elseif self.State == "Chase" then
		self:StepChaseState(now, seen, seenRoot)
	end

	if self.Model then
		self:CheckStuck(now)
		self.Model:SetAttribute("State", self.State)
	end
end

function Entity:Run()
	task.spawn(function()
		while self.Active do
			local ok, err = pcall(self.Step, self)
			if not ok then
				warn("EntityService: " .. tostring(err))
			end
			task.wait(cfg.StepSeconds)
		end
	end)
end

function EntityService.Start()
	if started then
		return
	end
	started = true

	events = ReplicatedStorage:WaitForChild("LevelEvents", 5)
	entitiesFolder = Instance.new("Folder")
	entitiesFolder.Name = "Entities"
	entitiesFolder.Parent = workspace

	for level = 1, LevelConfig.GetCount() do
		local entity = Entity.new(level)
		-- Only levels that have EntitySpawn parts get an entity.
		if #entity:GetSpawnMarkers() > 0 then
			entity:Spawn()
			entity:Run()
		end
	end
end

return EntityService
