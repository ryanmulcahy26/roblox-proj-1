-- LevelConfig: tuning values for each Backrooms level.
-- Edit the numbers here; other scripts read them from this module.

local LevelConfig = {}

-- Ascension level of the entity on each level.
-- A player needs a higher ascension than the entity to mog it.
LevelConfig.Levels = {
	[1] = { EntityAscension = 10 },
	[2] = { EntityAscension = 25 },
	[3] = { EntityAscension = 45 },
	[4] = { EntityAscension = 70 },
	[5] = { EntityAscension = 100 },
	[6] = { EntityAscension = 135 },
	[7] = { EntityAscension = 175 },
	[8] = { EntityAscension = 220 },
	[9] = { EntityAscension = 270 },
	[10] = { EntityAscension = 325 },
}

-- Placeholder: how long an entity stays dead after being mogged.
LevelConfig.EntityDeadSeconds = 60

function LevelConfig.GetCount()
	return #LevelConfig.Levels
end

function LevelConfig.GetEntityAscension(level)
	local data = LevelConfig.Levels[level]
	return data and data.EntityAscension or nil
end

-- Entity behaviour. Tweak these to change how the entities feel.
LevelConfig.Entity = {
	StepSeconds = 0.15, -- how often an entity thinks

	-- Wandering: slow, at a random pace
	WanderSpeedMin = 5,
	WanderSpeedMax = 9,
	WanderDistanceMin = 25, -- how far each random wander leg goes
	WanderDistanceMax = 60,
	WanderRadiusFromSpawn = 120, -- keeps it from drifting into other levels
	PauseMin = 1, -- random pause between legs
	PauseMax = 4,

	-- Seeing a player
	SightRange = 70,
	FieldOfViewDegrees = 120,
	SenseRadius = 12, -- notices players this close even from behind
	ActivateSeconds = 0.8, -- freezes and stares when it first spots you
	LoseSightSeconds = 4, -- gives up this long after losing you

	-- Chasing: faster and erratic
	ChaseSpeedMin = 14,
	ChaseSpeedMax = 24,
	ChaseJitterStuds = 8, -- sideways zig-zag
	JitterIntervalMin = 0.15,
	JitterIntervalMax = 0.5,
	StutterChance = 0.08, -- chance each step to briefly stop
	StutterMin = 0.1,
	StutterMax = 0.35,

	-- Contact
	CatchDistance = 6,
	CooldownAfterKill = 2,
}

return LevelConfig
