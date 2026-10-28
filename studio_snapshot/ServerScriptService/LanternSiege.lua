--// LanternSiege.lua
-- The Lantern Siege mode's field and rounds (design doc "Lantern Siege - tactical flagship
-- mode", 2026-10-27). The orchestrator hands it the IN_GAME phase of a "LanternSiege" match.
-- It only puts things on the field and keeps the score; what the Quins do about them comes from
-- their own brain (QuinCore Modules/Objectives -> TaskChoice), nothing here tells a Quin what to do.
--
--   Field    two Shrines (A, B) on the defenders' half; the Lantern (a small orb) on a pedestal
--            in the centre.
--   Round    plant and defuse (owner 2026-10-27: "valorant but fist fights and ballistic moves"):
--            Huddle (everyone still) -> Live: any attacker takes the orb (held in the hand, no
--            limits on how it moves); a blow knocks it out of the hand, and any attacker can pick
--            it up again -> Planting: on a Shrine the carrier kneels PlantTime seconds (a blow stops
--            it and the orb falls) -> Planted: it goes off after DetonateTime; a defender kneels on
--            it DefuseTime seconds to defuse it (a blow stops it; past half way that half is kept).
--            Going off it blasts everything within BlastRadius (a red ring on the ground from the
--            plant; the orb glows brighter to the end): caught in it, a Quin is knocked out.
--   Carry-over  a Quin knocked out in a round (or caught in the blast) starts the next one shaken:
--            ShakenEnergy of its mana (dash, projectile jump). Getting clear is worth something.
--            Attackers win: it goes off, or every defender is out.
--            Defenders win: it is defused, the round clock runs out before a plant, or every
--            attacker is out before a plant (after a plant they must still defuse it).
--   Knockout a Quin at 0 health is not removed: it glitches out and sits the round out, and the
--            same Quin comes back for the next one.
--   Match    first to RoundsToWin; sides swap after SwapAfter rounds.
-- Published for brains and screens: Workspace.LanternSiege (attributes Live, Phase, Round,
-- Attackers, ScoreTeamAlpha/Beta, PhaseEndsAt, RoundEndsAt, PlantedShrine, PlantProgress,
-- DetonateAt, DefuseProgress, Defuser; the Lantern part's
-- State / Carrier; Shrines/A, Shrines/B). Tuning: CombatConfig.LanternSiege.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.QuinCore.CombatConfig)
local VfxModule = require(ReplicatedStorage.QuinCore.Modules.VfxModule)
local AnimationModule = require(ReplicatedStorage.QuinCore.Modules.AnimationModule)
local AudioModule = require(ReplicatedStorage.QuinCore.Modules.AudioModule)
local ArenaAudio = require(game:GetService("ServerScriptService"):WaitForChild("ArenaAudioManager"))

-- The stadium warhorn marks a round (owner 2026-10-27: reuse the warhorn): when it goes live and
-- when it is decided
local function warhorn()
	pcall(ArenaAudio.playWarhorn, 1.0)
end
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

local function now() return GameClock.serverNow() end

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
		-- (the arena made for this mode already holds the sites: ArenaGenerator.setPurpose)
		local spot = layout.shrines and layout.shrines[name] or nil
		for try = 0, spot and -1 or 8 do
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
	lantern.Size = Vector3.new(1.3, 1.3, 1.3)
	lantern.Material = Enum.Material.Neon
	lantern.Color = LANTERN_COLOR
	lantern.Anchored, lantern.CanCollide, lantern.CanQuery, lantern.CanTouch, lantern.Massless = true, false, false, false, true
	local light = Instance.new("PointLight")
	light.Color = LANTERN_COLOR
	light.Range = 14
	light.Brightness = 3
	light.Parent = lantern
	billboard(lantern, "ORB", LANTERN_COLOR, 80).Parent.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	lantern.Parent = folder
	folder.Parent = Workspace

	field = { folder = folder, lantern = lantern, shrines = shrines, bench = bench, attackAnchor = attackAnchor, center = center, pedestal = layout.pedestal }
	return field
end

----------------------------------------------------------------------------------------
-- Quins: knockouts sit the round out (the same Quin comes back)
----------------------------------------------------------------------------------------
local roster = {} -- [quin] = { team, parked, shaken (knocked out last round: starts low on mana) }

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
	GameClock.delay(0.5, function()
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
local lanternState = { carrier = nil, weld = nil, hitAt = 0 }
local noGrabUntil = {} -- [quin] = clock: it just lost the orb to a blow, it does not snatch it straight back

-- (no limits on the carrier: it dashes, jumps and fights like any Quin; a blow costs it the orb)
local function setCarrierFlags(q, on)
	if not roster[q] then return end
	q:SetAttribute("LanternCarrier", on or nil)
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
	if state ~= "Planted" then
		lantern.Transparency = 0
		lantern.Size = Vector3.new(1.3, 1.3, 1.3)
		lantern.PointLight.Enabled = true
		lantern.PointLight.Range = 14
		lantern.PointLight.Brightness = 3
	end
	lantern:SetAttribute("State", state)
	lantern:SetAttribute("Carrier", nil)
end

local function carry(q)
	local root = q:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local lantern = field.lantern
	lantern.Anchored = false
	-- by its right hand (each screen puts it in the hand itself: LanternOrbClient)
	lantern.CFrame = root.CFrame * CFrame.new(1.5, -0.8, -0.8)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, lantern
	weld.Parent = lantern
	lanternState.weld, lanternState.carrier, lanternState.hitAt = weld, q, q:GetAttribute("ImpactTime") or 0
	setCarrierFlags(q, true)
	lantern:SetAttribute("State", "Carried")
	lantern:SetAttribute("Carrier", q.Name)
end

-- The superhero landing (Parkour.LandingSuperHero) for planting and defusing: the Quin goes down
-- on one knee, still, for `hold` seconds; the ground shakes.
local function heroLand(q, hold, position)
	local h = q:FindFirstChildOfClass("Humanoid")
	local root = q:FindFirstChild("HumanoidRootPart")
	if not h or not root then return end
	q:SetAttribute("IsInert", true)
	q:SetAttribute("LoudUntil", now() + 1) -- (the slam is heard across much of the arena: Senses)
	root.AssemblyLinearVelocity = Vector3.zero
	AnimationModule.playConfig(h, "Parkour.LandingSuperHero", 1.0, Enum.AnimationPriority.Action4, false)
	VfxModule.createLandingImpact(root, 0.8)
	VfxModule.createShockwave(position or root.Position, 18, 0.6)
	AudioModule.playSlam(position or root.Position)
	local token = {}
	q:SetAttribute("HeroLandToken", tostring(token))
	GameClock.delay(hold, function()
		if q:GetAttribute("HeroLandToken") == tostring(token) and onField(q) and field and field.folder:GetAttribute("Live") then
			q:SetAttribute("IsInert", false)
		end
	end)
end

local function heroLandRelease(q)
	if not q then return end
	q:SetAttribute("HeroLandToken", nil)
	if onField(q) and field and field.folder:GetAttribute("Live") then
		q:SetAttribute("IsInert", false)
	end
end

-- Struck since `since` (DamageModule's ImpactTime)
local function struck(q, since)
	return (q:GetAttribute("ImpactTime") or 0) > since
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
			-- knocked out last round: it starts this one low on mana
			local rec = roster[q]
			q:SetAttribute("Shaken", rec.shaken or nil)
			if rec.shaken then
				q:SetAttribute("Energy", (CombatConfig.MaxEnergy or 100) * cfg("ShakenEnergy", 0.5))
				rec.shaken = nil
			end
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
	for _, key in ipairs({ "PlantedShrine", "PlantProgress", "DetonateAt", "DefuseProgress", "Defuser", "Planter" }) do
		folder:SetAttribute(key, nil)
	end
	noGrabUntil = {}
	folder:SetAttribute("Live", false)

	placeTeams(attackers)
	-- the Lantern waits on its pedestal in the centre (the round opens with the fight for it)
	local base = field.pedestal or field.center
	placeLantern(groundAt(base) + Vector3.new(0, 2, 0), "Base")

	setPhase("Huddle", cfg("HuddleTime", 10))
	announce(string.format("ROUND %d  //  %s ATTACK", folder:GetAttribute("Round"), attackers == "TeamAlpha" and "ALPHA" or "BETA"), 4, "LANTERN SIEGE", COLOR[attackers])
	local t = GameClock.now() + cfg("HuddleTime", 10)
	while GameClock.now() < t do
		if isCancelled() then return nil end
		GameClock.wait(0.2)
	end

	folder:SetAttribute("Live", true)
	setPhase("Live", cfg("LiveTime", 100))
	warhorn()
	release()
	local liveEnds = GameClock.now() + cfg("LiveTime", 100)
	folder:SetAttribute("RoundEndsAt", now() + cfg("LiveTime", 100))
	local lantern = field.lantern
	local planter, plantAt, plantHit, plantShrine = nil, 0, 0, nil
	local detonateAt = nil
	local defuser, defuseHit, defuse, defuseLand = nil, 0, 0, 0
	local zone = nil -- the blast ring on the ground
	local last = GameClock.now()

	local function drop(at, why)
		placeLantern(groundAt(at) + Vector3.new(0, 1, 0), "Dropped")
		announce(why or "THE ORB IS DOWN", 2, "LANTERN SIEGE", LANTERN_COLOR)
	end

	while true do
		GameClock.wait(0.1)
		if isCancelled() then return nil end
		local clock = GameClock.now()
		local dt = clock - last
		last = clock
		local state = lantern:GetAttribute("State")

		if state == "Base" or state == "Dropped" then
			for q, rec in pairs(roster) do
				local root = q:FindFirstChild("HumanoidRootPart")
				if rec.team == attackers and onField(q) and root and clock >= (noGrabUntil[q] or 0)
					and flat(root.Position, lantern.Position) <= cfg("PickUpRange", 5)
					and math.abs(root.Position.Y - lantern.Position.Y) < 8 then
					carry(q)
					break
				end
			end
		elseif state == "Carried" then
			local c = lanternState.carrier
			local root = c and c:FindFirstChild("HumanoidRootPart")
			if not c or not onField(c) or not root then
				drop(root and root.Position or lantern.Position)
			elseif struck(c, lanternState.hitAt) then
				-- knocked out of its hand: it falls a step away
				noGrabUntil[c] = clock + cfg("RegrabDelay", 1.2)
				local away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
				drop(root.Position + (away.Magnitude > 0.01 and away.Unit or Vector3.xAxis) * 4, "ORB KNOCKED LOOSE")
			else
				for name, ring in pairs(field.shrines) do
					if flat(root.Position, ring.Position) <= cfg("ShrineRadius", 7)
						and math.abs(root.Position.Y - ring.Position.Y) < 6 then
						-- it kneels and plants
						planter, plantAt, plantHit, plantShrine = c, clock, c:GetAttribute("ImpactTime") or 0, name
						lantern:SetAttribute("State", "Planting")
						folder:SetAttribute("Planter", c.Name)
						folder:SetAttribute("PlantedShrine", name)
						heroLand(c, cfg("PlantTime", 4), ring.Position)
						break
					end
				end
			end
		elseif state == "Planting" then
			local root = planter and planter:FindFirstChild("HumanoidRootPart")
			if not planter or not onField(planter) or not root or struck(planter, plantHit) then
				-- stopped: the orb falls on the Shrine
				if planter then
					heroLandRelease(planter)
					noGrabUntil[planter] = clock + cfg("RegrabDelay", 1.2)
				end
				folder:SetAttribute("PlantProgress", nil)
				folder:SetAttribute("Planter", nil)
				folder:SetAttribute("PlantedShrine", nil)
				drop(field.shrines[plantShrine].Position + Vector3.new(3, 0, 0), "PLANT STOPPED")
				planter = nil
			else
				local progress = (clock - plantAt) / cfg("PlantTime", 4)
				folder:SetAttribute("PlantProgress", math.min(progress, 1))
				if progress >= 1 then
					local ring = field.shrines[plantShrine]
					placeLantern(ring.Position + Vector3.new(0, 1.2, 0), "Planted")
					heroLandRelease(planter)
					planter = nil
					field.lantern.PointLight.Range = 26
					folder:SetAttribute("PlantProgress", nil)
					folder:SetAttribute("Planter", nil)
					folder:SetAttribute("PlantedShrine", plantShrine)
					detonateAt = clock + cfg("DetonateTime", 40)
					folder:SetAttribute("DetonateAt", now() + cfg("DetonateTime", 40))
					folder:SetAttribute("BlastRadius", cfg("BlastRadius", 40))
					-- the blast area, on the ground from the start: everyone can see where safe is
					zone = Instance.new("Part")
					zone.Name = "BlastZone"
					zone.Shape = Enum.PartType.Cylinder
					zone.Size = Vector3.new(0.3, cfg("BlastRadius", 40) * 2, cfg("BlastRadius", 40) * 2)
					zone.CFrame = CFrame.new(groundAt(ring.Position) + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
					zone.Material = Enum.Material.Neon
					zone.Color = Color3.fromRGB(255, 60, 40)
					zone.Transparency = 0.88
					zone.Anchored, zone.CanCollide, zone.CanQuery, zone.CanTouch, zone.CastShadow = true, false, false, false, false
					zone.Parent = folder
					setPhase("Planted", cfg("DetonateTime", 40))
					announce(string.format("ORB PLANTED AT %s  //  %ds TO DEFUSE", plantShrine, cfg("DetonateTime", 40)), 3, "LANTERN SIEGE", LANTERN_COLOR)
				end
			end
		elseif state == "Planted" then
			-- a defender on it kneels and defuses; a blow stops it (past half way, that half stays)
			local d = defuser
			local dRoot = d and d:FindFirstChild("HumanoidRootPart")
			if d and (not onField(d) or not dRoot or flat(dRoot.Position, lantern.Position) > cfg("DefuseRange", 5) + 2 or struck(d, defuseHit)) then
				heroLandRelease(d)
				defuser = nil
				defuse = defuse >= 0.5 and 0.5 or 0
				folder:SetAttribute("Defuser", nil)
				announce("DEFUSE STOPPED", 1.5, "LANTERN SIEGE", COLOR[attackers])
			end
			if not defuser then
				for q, rec in pairs(roster) do
					local root = q:FindFirstChild("HumanoidRootPart")
					if rec.team == defenders and onField(q) and root and flat(root.Position, lantern.Position) <= cfg("DefuseRange", 5)
						and math.abs(root.Position.Y - lantern.Position.Y) < 8 then
						defuser, defuseHit, defuseLand = q, q:GetAttribute("ImpactTime") or 0, 0
						folder:SetAttribute("Defuser", q.Name)
						break
					end
				end
			end
			if defuser then
				if clock - defuseLand >= 1.2 then
					defuseLand = clock
					heroLand(defuser, 1.3, lantern.Position)
				end
				defuse += dt / cfg("DefuseTime", 7)
			end
			folder:SetAttribute("DefuseProgress", defuse > 0 and math.min(defuse, 1) or nil)
			if defuse >= 1 then
				heroLandRelease(defuser)
				lantern.PointLight.Enabled = false
				lantern.Transparency = 0.7
				if zone then zone:Destroy() end
				VfxModule.createShockwave(lantern.Position, 30, 0.8)
				return defenders, "Defused"
			end
			-- it glows brighter toward the end, and in the last seconds it throbs
			local frac = 1 - math.max(0, detonateAt - clock) / cfg("DetonateTime", 40)
			local throb = (detonateAt - clock < 10) and (0.5 + 0.5 * math.sin(clock * (8 + 12 * frac))) or 0
			lantern.PointLight.Range = 20 + 40 * frac * frac
			lantern.PointLight.Brightness = 3 + 5 * frac + 4 * throb
			lantern.Size = Vector3.new(1.3, 1.3, 1.3) * (1 + 0.6 * frac + 0.5 * throb)
			if zone then zone.Transparency = 0.88 - 0.25 * frac - 0.15 * throb end
			if clock >= detonateAt then
				-- the blast: everyone inside is knocked out (and starts the next round shaken)
				local radius = cfg("BlastRadius", 40)
				for q in pairs(roster) do
					local root = q:FindFirstChild("HumanoidRootPart")
					if onField(q) and root and (root.Position - lantern.Position).Magnitude <= radius then
						park(q)
					end
				end
				VfxModule.createShockwave(lantern.Position, radius * 1.6, 1.2)
				VfxModule.createShockwave(lantern.Position, radius, 0.6)
				AudioModule.playSlam(lantern.Position)
				lantern.Transparency = 1
				lantern.PointLight.Range = 80
				lantern.PointLight.Brightness = 20
				if zone then zone:Destroy() end
				return attackers, "The orb went off"
			end
		end

		state = lantern:GetAttribute("State")
		local planted = state == "Planted"
		if not planted then
			if clock >= liveEnds and state ~= "Planting" then return defenders, "Time ran out" end
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
		-- the knocked out (and those the blast caught) start the next round shaken
		local blastZone = folder:FindFirstChild("BlastZone")
		if blastZone then blastZone:Destroy() end
		for q, rec in pairs(roster) do
			rec.shaken = rec.parked or nil
		end
		score[winner] += 1
		folder:SetAttribute("ScoreTeamAlpha", score.TeamAlpha)
		folder:SetAttribute("ScoreTeamBeta", score.TeamBeta)
		folder:SetAttribute("Live", false)
		folder:SetAttribute("LastRound", string.format("%d:%s:%s", round, winner, why))
		setPhase("RoundOver", cfg("RoundOverTime", 4))
		freeze()
		warhorn()
		announce(string.format("%s TAKE ROUND %d  -  %s  (%d - %d)", winner == "TeamAlpha" and "ALPHA" or "BETA", round, why:upper(), score.TeamAlpha, score.TeamBeta), 4, "LANTERN SIEGE", COLOR[winner])
		print(string.format("[LanternSiege] round %d: %s (%s)  %d-%d", round, winner, why, score.TeamAlpha, score.TeamBeta))
		local t = GameClock.now() + cfg("RoundOverTime", 4)
		while GameClock.now() < t do
			if isCancelled() then LanternSiege.cleanup() return nil, "Stopped" end
			GameClock.wait(0.2)
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
