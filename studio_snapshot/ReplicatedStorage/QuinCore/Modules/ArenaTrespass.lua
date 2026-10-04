--// ArenaTrespass.lua
-- The arena floor is where the match is fought. The arena wall is part of the game too (a Quin
-- may run along it, stand, run and fight on top of it) and a Quin may be thrown out of the arena
-- altogether, but being off the floor is trespass:
--   * it costs performance (the MatchPenalty attribute, counted against the Quin's standing and
--     its contribution, SocialLeaders / SocialRespect), a little for every second;
--   * after Trespass.MaxTimeOnWall / MaxTimeOutside seconds it is brought back (Main forces
--     ReEntry), unless it came back by itself first;
--   * the Quin that threw another out of the arena pays for it once (KnockoutPenalty).
-- Where a Quin is, is asked of the surface under it and not of a line on the map: the wall
-- overlaps the floor's footprint, so "over the wall's top" and "on the floor beside the wall"
-- can share an X and Z.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local ArenaTrespass = {}

local CFG = CombatConfig.Trespass
local WALL_NAME = "ArenaWall"
local PROBE_DEPTH = 500 -- studs down the surface under a Quin is looked for (the wall is 148 tall)

local records = setmetatable({}, { __mode = "k" }) -- fighter -> { time, thrownAt, thrownBy, charged }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

-- "Ground" (on or over the arena floor and what stands on it), "Wall" (on or over the wall's
-- top) or "Outside" (beyond the floor, not on the wall)
function ArenaTrespass.locate(fighter: Model, rootPart: BasePart): string
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local under = Workspace:Raycast(rootPart.Position, Vector3.new(0, -PROBE_DEPTH, 0), params)
	if under and under.Instance.Name == WALL_NAME then
		return "Wall"
	end
	local bounds = SpatialModule.getArenaBounds()
	local position = rootPart.Position
	if math.abs(position.X - bounds.center.X) <= bounds.halfX and math.abs(position.Z - bounds.center.Z) <= bounds.halfZ then
		return "Ground"
	end
	return "Outside"
end

local function addPenalty(fighter: Model, points: number)
	fighter:SetAttribute("MatchPenalty", (fighter:GetAttribute("MatchPenalty") or 0) + points)
end

-- Call once per AI tick. Returns true when the Quin has been off the floor too long and is to be
-- brought back now.
function ArenaTrespass.update(fighter: Model, rootPart: BasePart, stateName: string, dt: number): boolean
	if CFG.Enabled == false then return false end
	local record = records[fighter]
	if not record then
		record = { time = 0 }
		records[fighter] = record
	end
	local now = os.clock()
	local where = ArenaTrespass.locate(fighter, rootPart)

	if where == "Ground" then
		-- (who threw it, in case it leaves the floor on this throw)
		if stateName == "Knockback" then
			record.thrownAt, record.thrownBy = now, fighter:GetAttribute("LastAttackerName")
		end
		if record.time > 0 then
			record.time, record.charged = 0, nil
			fighter:SetAttribute("Trespass", nil)
			fighter:SetAttribute("TrespassTime", nil)
		end
		return false
	end

	if record.time == 0 then
		-- It has just left the floor. Thrown out? Then the thrower pays, once.
		if record.thrownAt and now - record.thrownAt <= CFG.KnockoutWindow and record.thrownBy then
			local thrower = (Workspace:FindFirstChild("QuinServer") or Workspace):FindFirstChild(record.thrownBy)
			if thrower then
				addPenalty(thrower, CFG.KnockoutPenalty)
				thrower:SetAttribute("KnockedOutOfArena", (thrower:GetAttribute("KnockedOutOfArena") or 0) + 1)
				fighter:SetAttribute("ThrownOutBy", record.thrownBy)
			end
		end
	end
	record.time += dt
	if record.time > CFG.Grace then
		addPenalty(fighter, CFG.PenaltyPerSecond * dt)
	end
	if fighter:GetAttribute("Trespass") ~= where then
		fighter:SetAttribute("Trespass", where)
	end
	fighter:SetAttribute("TrespassTime", math.floor(record.time * 10 + 0.5) / 10)

	local limit = where == "Wall" and CFG.MaxTimeOnWall or CFG.MaxTimeOutside
	return record.time >= limit
end

return ArenaTrespass
