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

return LevelConfig
