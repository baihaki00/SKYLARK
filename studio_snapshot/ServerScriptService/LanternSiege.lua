--// LanternSiege.lua
-- The Lantern Siege mode's field and rounds (design doc "Lantern Siege - tactical flagship
-- mode", 2026-10-27). The orchestrator hands it the IN_GAME phase of a "LanternSiege" match.
-- It only puts things on the field and keeps the score; what the Quins do about them comes from
-- their own brain (QuinCore Modules/Objectives -> TaskChoice), nothing here tells a Quin what to do.
--
--   Field    two Shrines (A, B) on the defenders' half; one Lantern at the attackers' start.
--   Round    Huddle (everyone still) -> Live: the attackers carry the Lantern to a Shrine (the
--            carrier is slower and can't dash or projectile-jump; it drops the Lantern when
--            knocked out, and any attacker can pick it up) -> Ignition: it burns; defenders stamp
--            it out by standing on it.
--            Attackers win: it burns out, or every defender is out.
--            Defenders win: it is stamped out, time runs out before a plant, or every attacker is
--            out before a plant.
--   Knockout a Quin at 0 health is not removed: it glitches out and sits the round out, and the
--            same Quin comes back for the next one.
--   Match    first to RoundsToWin; sides swap after SwapAfter rounds.
-- Published for brains and screens: Workspace.LanternSiege (attributes Live, Phase, Round,
-- Attackers, ScoreTeamAlpha/Beta, PhaseEndsAt, PlantedShrine, IgniteEndsAt; the Lantern part's
-- State / Carrier; Shrines/A, Shrines/B). Tuning: CombatConfig.LanternSiege.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.QuinCore.CombatConfig)
local VfxModule = require(ReplicatedStorage.QuinCore.Modules.VfxModule)
local ArenaGenerator = require(ServerScriptService:WaitForChild("ArenaGenerator"))

local LanternSiege = {}

local function cfg(key, default)
	local t = CombatConfig.LanternSiege
	local v = t and t[key]
	if v == nil then return default end
	return v
end

local TEAMS = { "TeamAlpha", "TeamBeta" }
local COLOR = { TeamAlpha = Color3.fromRGB(80, 160, 255), TeamBeta = Color3.fromRGB(255, 90, 90) }
local LANTERN_COLOR = Color3.fromRGB(255, 190, 80)

local function now() return Workspace:GetServerTimeNow() end

local function other(team) return team == "TeamAlpha" and "TeamBeta" or "TeamAlpha" end

local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end

-- The floor (or whatever stands) under a point
local function groundAt(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { Workspace:FindFirstChild("QuinServer"), Workspace:FindFirstChild("LanternSiege") }
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(Vector3.new(pos.X, pos.Y + 200, pos.Z), Vector3.new(0, -600, 0), params)
	return hit and hit.Position or pos
end

local function billboard(parent, text, color, size)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size, size * 0.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 1500
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = parent
	return label
end

----------------------------------------------------------------------------------------
-- The field
----------------------------------------------------------------------------------------
local field = nil -- { folder, lantern, shrines = {A=part,B=part}, attackSide, defendSide, base }

local function buildField()
	local old = Workspace:FindFirstChild("LanternSiege")
	if old then old:Destroy() end
	local layout = ArenaGenerator.getLayout()
	local center, floorY = ArenaGenerator.getCenter()
	if not layout or not center then return nil end

	local folder = Instance.new("Folder")
	folder.Name = "LanternSiege"
	folder:SetAttribute("Live", false)
	local shrineFolder = Instance.new("Folder")
	shrineFolder.Name = "Shrines"
	shrineFolder.Parent = folder
	local bench = Instance.new("Folder")
	bench.Name = "Bench"
	bench.Parent = folder

	-- Shrines on the defenders' half (the beta anchor side; roles swap, the field does not)
	local defendAnchor, attackAnchor = layout.betaAnchor, layout.alphaAnchor
	local toCenter = Vector3.new(center.X - defendAnchor.X, 0, center.Z - defendAnchor.Z)
	local span = toCenter.Magnitude
	local dir = span > 1 and toCenter.Unit or Vector3.new(1, 0, 0)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local shrines = {}
	for i, name in ipairs({ "A", "B" }) do
		local sign = i == 1 and 1 or -1
		-- (on the floor: a point on a platform is nudged toward the middle until it is not)
		local spot = nil
		for try = 0, 8 do
			local p = defendAnchor + dir * span * (cfg("ShrineForward", 0.35) + try * 0.04) + side * sign * span * (cfg("ShrineSide", 0.55) - try * 0.04)
			local g = groundAt(Vector3.new(p.X, (floorY or center.Y), p.Z))
			if math.abs(g.Y - (floorY or g.Y)) < 2 then spot = g break end
			spot = spot or g
		end
		local ring = Instance.new("Part")
		ring.Name = name
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, cfg("ShrineRadius", 7) * 2, cfg("ShrineRadius", 7) * 2)
		ring.CFrame = CFrame.new(spot + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(255, 225, 150)
		ring.Transparency = 0.55
		ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
		ring.Parent = shrineFolder
		billboard(ring, name, Color3.fromRGB(255, 230, 170), 90)
		shrines[name] = ring
	end

	local lantern = Instance.new("Part")
	lantern.Name = "Lantern"
	lantern.Shape = Enum.PartType.Ball
	lantern.Size = Vector3.new(2.4, 2.4, 2.4)
	lantern.Material = Enum.Material.Neon
	lantern.Color = LANTERN_COLOR
	lantern.Anchored, lantern.CanCollide, lantern.CanQuery, lantern.CanTouch, lantern.Massless = true, false, false, false, true
	local light = Instance.new("PointLight")
	light.Color = LANTERN_COLOR
	light.Range = 18
	light.Brightness = 3
	light.Parent = lantern
	billboard(lantern, "LANTERN", LANTERN_COLOR, 110).Parent.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	lantern.Parent = folder
	folder.Parent = Workspace

	field = { folder = folder, lantern = lantern, shrines = shrines, bench = bench, attackAnchor = attackAnchor, center = center }
	return field
end

----------------------------------------------------------------------------------------
-- Quins: knockouts sit the round out (the same Quin comes back)
----------------------------------------------------------------------------------------
local roster = {} -- [quin] = { team, parked, savedPJ }

local function parked(q) return roster[q] and roster[q].parked end

local function onField(q)
	local h = q.Parent and q:FindFirstChildOfClass("Humanoid")
	return h and h.Health > 0 and roster[q] and not roster[q].parked
end

local function park(q)
	local rec = roster[q]
	if not rec or rec.parked then return end
	rec.parked = true
	local h = q:FindFirstChildOfClass("Humanoid")
	if h then h.Health = 1 end
	q:SetAttribute("KnockedOut", true)
	q:SetAttribute("IsInert", true)
	q:SetAttribute("InCombat", false)
	VfxModule.holoGlitch(q, 0.5, "out")
	task.delay(0.5, function()
		if not rec.parked or not q.Parent then return end
		CollectionService:RemoveTag(q, "Quin") -- (nobody's senses, targets or counts see it)
		local root = q:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true
			q:PivotTo(CFrame.new(0, cfg("BenchHeight", 3000), 0))
		end
		q.Parent = field and field.bench or q.Parent
	end)
end

local function unpark(q, cf)
	local rec = roster[q]
	if not rec then return end
	local qServer = Workspace:FindFirstChild("QuinServer")
	if rec.parked then
		rec.parked = false
		q.Parent = qServer or Workspace
		CollectionService:AddTag(q, "Quin")
		q:SetAttribute("KnockedOut", nil)
	end
	local root = q:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end
	q:PivotTo(cf) -- (spawn points stand 3 studs over the pads already)
	local h = q:FindFirstChildOfClass("Humanoid")
	if h then h.Health = h.MaxHealth end
	q:SetAttribute("Energy", CombatConfig.MaxEnergy or 100)
	q:SetAttribute("Posture", 100)
	q:SetAttribute("CurrentState", "Idle")
	q:SetAttribute("ForceState", "Idle")
	VfxModule.holoGlitch(q, 0.5, "in")
end

local function enroll(q)
	if roster[q] then return end
	local h = q:FindFirstChildOfClass("Humanoid")
	if not h then return end
	roster[q] = { team = q:GetAttribute("Team") }
	h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	h.HealthChanged:Connect(function(hp)
		if hp <= 0 and roster[q] and not roster[q].parked then
			park(q)
		end
	end)
end

----------------------------------------------------------------------------------------
-- The Lantern
----------------------------------------------------------------------------------------
local lanternState = { carrier = nil, weld = nil }

local function setCarrierFlags(q, on)
	local rec = roster[q]
	if not rec then return end
	if on then
		rec.savedPJ = q:GetAttribute("EnableProjectileJump")
		q:SetAttribute("EnableProjectileJump", false)
		q:SetAttribute("NoDash", true)
		q:SetAttribute("LanternCarrier", true)
	else
		q:SetAttribute("EnableProjectileJump", rec.savedPJ)
		q:SetAttribute("NoDash", nil)
		q:SetAttribute("LanternCarrier", nil)
	end
end

local function placeLantern(pos, state)
	local lantern = field.lantern
	if lanternState.weld then lanternState.weld:Destroy() lanternState.weld = nil end
	if lanternState.carrier then
		setCarrierFlags(lanternState.carrier, false)
		lanternState.carrier = nil
	end
	lantern.Anchored = true
	lantern.CFrame = CFrame.new(pos)
	lantern:SetAttribute("State", state)
	lantern:SetAttribute("Carrier", nil)
end

local function carry(q)
	local root = q:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local lantern = field.lantern
	lantern.Anchored = false
	lantern.CFrame = root.CFrame * CFrame.new(0, 1.2, 1.4)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, lantern
	weld.Parent = lantern
	lanternState.weld, lanternState.carrier = weld, q
	setCarrierFlags(q, true)
	lantern:SetAttribute("State", "Carried")
	lantern:SetAttribute("Carrier", q.Name)
end

----------------------------------------------------------------------------------------
-- Rounds
----------------------------------------------------------------------------------------
local function setPhase(phase, seconds)
	field.folder:SetAttribute("Phase", phase)
	field.folder:SetAttribute("PhaseEndsAt", seconds and (now() + seconds) or nil)
end

local function spawnSide(role)
	-- attackers start on the alpha anchor's side, defenders on the beta side (the Shrines' side)
	return role == "Attack" and "TeamAlpha" or "TeamBeta"
end

local function placeTeams(attackers)
	for _, team in ipairs(TEAMS) do
		local role = team == attackers and "Attack" or "Defend"
		local members = {}
		for q, rec in pairs(roster) do
			if rec.team == team and q.Parent then table.insert(members, q) end
		end
		local points, facing = ArenaGenerator.getSpawnPoints(spawnSide(role), #members)
		for i, q in ipairs(members) do
			local p = points and points[i] or field.center
			local look = facing or field.center
			unpark(q, CFrame.lookAt(p, Vector3.new(look.X, p.Y, look.Z)))
			q:SetAttribute("IsInert", true)
			q:SetAttribute("InCombat", false)
		end
	end
end

local function release()
	for q in pairs(roster) do
		if q.Parent and not parked(q) then
			q:SetAttribute("IsInert", false)
			q:SetAttribute("InCombat", true)
			q:SetAttribute("ForceState", nil)
		end
	end
end

local function freeze()
	for q in pairs(roster) do
		if q.Parent then
			q:SetAttribute("IsInert", true)
			q:SetAttribute("InCombat", false)
		end
	end
end

local function aliveCount(team)
	local n = 0
	for q, rec in pairs(roster) do
		if rec.team == team and onField(q) then n += 1 end
	end
	return n
end

-- One round. Returns the winning team and why.
local function playRound(attackers, isCancelled, announce)
	local defenders = other(attackers)
	local folder = field.folder
	folder:SetAttribute("Attackers", attackers)
	folder:SetAttribute("PlantedShrine", nil)
	folder:SetAttribute("IgniteEndsAt", nil)
	folder:SetAttribute("Live", false)

	placeTeams(attackers)
	-- the Lantern waits a little in front of the attackers' start
	local base = field.attackAnchor + (Vector3.new(field.center.X, 0, field.center.Z) - Vector3.new(field.attackAnchor.X, 0, field.attackAnchor.Z)).Unit * cfg("LanternAhead", 14)
	placeLantern(groundAt(base) + Vector3.new(0, 2, 0), "Base")

	setPhase("Huddle", cfg("HuddleTime", 10))
	announce(string.format("ROUND %d  //  %s ATTACK", folder:GetAttribute("Round"), attackers == "TeamAlpha" and "ALPHA" or "BETA"), 4, "LANTERN SIEGE", COLOR[attackers])
	local t = os.clock() + cfg("HuddleTime", 10)
	while os.clock() < t do
		if isCancelled() then return nil end
		task.wait(0.2)
	end

	folder:SetAttribute("Live", true)
	setPhase("Live", cfg("LiveTime", 100))
	release()
	local liveEnds = os.clock() + cfg("LiveTime", 100)
	local igniteEnds, stamp = nil, 0
	local lantern = field.lantern
	local last = os.clock()
	while true do
		task.wait(0.1)
		if isCancelled() then return nil end
		local clock = os.clock()
		local dt = clock - last
		last = clock
		local state = lantern:GetAttribute("State")

		if state == "Base" or state == "Dropped" then
			for q, rec in pairs(roster) do
				local root = q:FindFirstChild("HumanoidRootPart")
				if rec.team == attackers and onField(q) and root and flat(root.Position, lantern.Position) <= cfg("PickUpRange", 5)
					and math.abs(root.Position.Y - lantern.Position.Y) < 8 then
					carry(q)
					break
				end
			end
		elseif state == "Carried" then
			local c = lanternState.carrier
			local root = c and c:FindFirstChild("HumanoidRootPart")
			if not c or not onField(c) or not root then
				local at = root and root.Position or lantern.Position
				placeLantern(groundAt(at) + Vector3.new(0, 1.5, 0), "Dropped")
				announce("THE LANTERN IS DOWN", 2.5, "LANTERN SIEGE", LANTERN_COLOR)
			else
				for name, ring in pairs(field.shrines) do
					if flat(root.Position, ring.Position) <= cfg("ShrineRadius", 7) then
						placeLantern(ring.Position + Vector3.new(0, 2.5, 0), "Planted")
						folder:SetAttribute("PlantedShrine", name)
						igniteEnds = clock + cfg("IgniteTime", 20)
						folder:SetAttribute("IgniteEndsAt", now() + cfg("IgniteTime", 20))
						setPhase("Ignition", cfg("IgniteTime", 20))
						announce(string.format("LANTERN LIT AT %s  //  %ds", name, cfg("IgniteTime", 20)), 3, "LANTERN SIEGE", LANTERN_COLOR)
						break
					end
				end
			end
		elseif state == "Planted" then
			local stamping = false
			for q, rec in pairs(roster) do
				local root = q:FindFirstChild("HumanoidRootPart")
				if rec.team == defenders and onField(q) and root and flat(root.Position, lantern.Position) <= cfg("StampRange", 5) then
					stamping = true
					break
				end
			end
			stamp = stamping and stamp + dt or math.max(0, stamp - dt * 2)
			folder:SetAttribute("StampProgress", stamp / cfg("StampTime", 2.5))
			if stamp >= cfg("StampTime", 2.5) then
				return defenders, "Stamped it out"
			end
			if clock >= igniteEnds then
				return attackers, "The Lantern burned"
			end
		end

		state = lantern:GetAttribute("State")
		if state ~= "Planted" then
			if clock >= liveEnds then return defenders, "Time ran out" end
			if aliveCount(attackers) == 0 then return defenders, "Attackers wiped out" end
		end
		if aliveCount(defenders) == 0 then return attackers, "Defenders wiped out" end
	end
end

-- The whole match. hooks: { isCancelled = fn() -> bool, announce = fn(text, seconds, tag, color) }
-- Returns winnerTeam ("TeamAlpha" | "TeamBeta" | nil when stopped), reason
function LanternSiege.run(hooks)
	local isCancelled = hooks.isCancelled or function() return false end
	local announce = hooks.announce or function() end
	if not buildField() then
		warn("[LanternSiege] no generated arena: nothing to play on")
		return nil, "No arena"
	end
	roster = {}
	local qServer = Workspace:FindFirstChild("QuinServer")
	for _, q in ipairs(qServer and qServer:GetChildren() or {}) do
		if q:IsA("Model") and CollectionService:HasTag(q, "AI_Fighter") and q:GetAttribute("Team") then
			enroll(q)
		end
	end

	local score = { TeamAlpha = 0, TeamBeta = 0 }
	local folder = field.folder
	local attackers = "TeamAlpha"
	local round = 0
	local toWin = cfg("RoundsToWin", 5)
	while score.TeamAlpha < toWin and score.TeamBeta < toWin do
		round += 1
		if round == cfg("SwapAfter", 4) + 1 then
			attackers = other(attackers)
			announce("SIDES SWAP", 3, "LANTERN SIEGE", Color3.fromRGB(255, 255, 255))
		end
		folder:SetAttribute("Round", round)
		local winner, why = playRound(attackers, isCancelled, announce)
		if not winner then
			LanternSiege.cleanup()
			return nil, "Stopped"
		end
		score[winner] += 1
		folder:SetAttribute("ScoreTeamAlpha", score.TeamAlpha)
		folder:SetAttribute("ScoreTeamBeta", score.TeamBeta)
		folder:SetAttribute("Live", false)
		folder:SetAttribute("LastRound", string.format("%d:%s:%s", round, winner, why))
		setPhase("RoundOver", cfg("RoundOverTime", 4))
		freeze()
		announce(string.format("%s TAKE ROUND %d  -  %s  (%d - %d)", winner == "TeamAlpha" and "ALPHA" or "BETA", round, why:upper(), score.TeamAlpha, score.TeamBeta), 4, "LANTERN SIEGE", COLOR[winner])
		print(string.format("[LanternSiege] round %d: %s (%s)  %d-%d", round, winner, why, score.TeamAlpha, score.TeamBeta))
		local t = os.clock() + cfg("RoundOverTime", 4)
		while os.clock() < t do
			if isCancelled() then LanternSiege.cleanup() return nil, "Stopped" end
			task.wait(0.2)
		end
	end
	local winner = score.TeamAlpha > score.TeamBeta and "TeamAlpha" or "TeamBeta"
	-- everyone back on the field for the ceremony
	for q, rec in pairs(roster) do
		if rec.parked and q.Parent then
			local p = field.center + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
			unpark(q, CFrame.new(groundAt(p)))
			q:SetAttribute("IsInert", true)
		end
	end
	return winner, string.format("Lantern Siege %d - %d", math.max(score.TeamAlpha, score.TeamBeta), math.min(score.TeamAlpha, score.TeamBeta))
end

function LanternSiege.cleanup()
	if lanternState.carrier then setCarrierFlags(lanternState.carrier, false) end
	lanternState = { carrier = nil, weld = nil }
	for q, rec in pairs(roster) do
		if rec.parked and q.Parent then
			pcall(function() q:Destroy() end)
		end
		local h = q.Parent and q:FindFirstChildOfClass("Humanoid")
		if h then pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end) end
	end
	roster = {}
	local f = Workspace:FindFirstChild("LanternSiege")
	if f then f:Destroy() end
	field = nil
end

return LanternSiege
