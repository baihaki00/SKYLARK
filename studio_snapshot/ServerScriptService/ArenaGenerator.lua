--// ArenaGenerator.lua
-- Procedural arena layout for ArenaOne (Arena System toggle "ProceduralTerrain").
--
-- During ARENA_GENERATION the arena shows a blue hologram that flicks through candidate seeds
-- ("tutututu"); each candidate is checked (routes between the spawns and the centre stay open),
-- a good seed locks and the hologram materializes into solid grassy blocks.
--
-- Rules (ArenaConfig.ArenaGeneration):
-- * Volume: the ArenaGround footprint, up to MaxHeight above it. High platforms at most
--   PlatformMaxHeight above the ground. The central CenterClear x CenterClear square stays empty.
-- * Fair: one half is generated, the other half is its point mirror through the arena centre
--   (same pieces, same heights, same spawn group), so both teams get the same arena.
-- * Spawn: one of the SpawnOptions (two edges, two midpoints); fighters spawn scattered but
--   grouped around their side's anchor, mirrored for the other team.
-- * Traversable: no ground piece taller than a vault blocks the routes (flood fill on a grid);
--   platforms up to LadderMaxHeight get a spiral of jumpable stepping stones, higher ones are
--   projectile-jump perches with a clear landing.
-- * The edit-mode layout (parts named "OB" / "highplatform" on the ground) is only stashed, never
--   deleted, and comes back with restore() when the match ends.
--
-- Driven by ArenaSystemOrchestrator: runSequence, restore, isActive, getSpawnPoints.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.QuinCore.ArenaConfig)
local CFG = ArenaConfig.ArenaGeneration

local Gen = {}

local active = false        -- a generated layout is in the arena
local current = nil         -- the locked layout
local stash = nil           -- { { part, parent } } edit-mode parts put aside
local spawnPadHome = nil    -- { { part, cframe } } QuinSpawn parts' edit-mode places
local pool = {}             -- hologram / generated parts
local running = false

-- ============================================================================
-- Arena geometry
-- ============================================================================

local function arenaOne()
	local root = Workspace:FindFirstChild("argoniaonion")
	return root and root:FindFirstChild("ArenaOne")
end

local function ground()
	local a = arenaOne()
	return a and a:FindFirstChild("ArenaGround", true)
end

-- centre (at floor height), half size X / Z, floor Y
local function metrics()
	local g = ground()
	if not g then return nil end
	local floorY = g.Position.Y + g.Size.Y / 2
	return Vector3.new(g.Position.X, floorY, g.Position.Z), g.Size.X / 2, g.Size.Z / 2, floorY
end

local function mirrorPoint(center, p)
	return Vector3.new(2 * center.X - p.X, p.Y, 2 * center.Z - p.Z)
end

local function mirrorCFrame(center, cf)
	local p = mirrorPoint(center, cf.Position)
	return CFrame.new(p) * CFrame.Angles(0, math.pi, 0) * cf.Rotation
end

-- ============================================================================
-- Layout generation (pure data: no instances)
-- ============================================================================

local function lerp(a, b, t) return a + (b - a) * t end

local function range(rng, r)
	return lerp(r[1], r[2], rng:NextNumber())
end

local function irange(rng, r)
	return rng:NextInteger(r[1], r[2])
end

-- A layout: { seed, option, alphaAnchor, betaAnchor, pieces = { {cf, size, kind} }, spawns = { TeamAlpha = {}, TeamBeta = {} } }
local function generate(seed)
	local center, halfX, halfZ, floorY = metrics()
	if not center then return nil end
	local rng = Random.new(seed)
	local option = CFG.SpawnOptions[rng:NextInteger(1, #CFG.SpawnOptions)]
	local alphaAnchor = center + Vector3.new(option.Alpha[1] * halfX, 0, option.Alpha[2] * halfZ)
	local betaAnchor = mirrorPoint(center, alphaAnchor)
	local axis = Vector3.new(alphaAnchor.X - center.X, 0, alphaAnchor.Z - center.Z).Unit
	local clearHalf = CFG.CenterClear / 2
	local spacing = CFG.Spacing

	local placed = {} -- { pos (XZ at floor), r, y0, y1, owner }
	local pieces = {}

	-- Footprint radius of a yawed box
	local function radiusOf(size)
		return 0.5 * math.sqrt(size.X * size.X + size.Z * size.Z)
	end

	local function fits(pos, r, y0, y1, ignoreOwner)
		local dx, dz = pos.X - center.X, pos.Z - center.Z
		-- inside the ground, off the walls
		if math.abs(dx) > halfX - CFG.WallMargin - r or math.abs(dz) > halfZ - CFG.WallMargin - r then return false end
		-- the centre square stays empty
		if math.abs(dx) < clearHalf + r and math.abs(dz) < clearHalf + r then return false end
		-- own half only, far enough from the mirror line that the mirrored copy never touches it
		if Vector3.new(dx, 0, dz):Dot(axis) < r + spacing / 2 then return false end
		-- the spawn group's yard
		if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(alphaAnchor.X, 0, alphaAnchor.Z)).Magnitude < CFG.SpawnClearRadius + r then return false end
		-- other pieces (vertical clearance counts: a Quin must fit under / over)
		for _, q in ipairs(placed) do
			if q.owner == nil or q.owner ~= ignoreOwner then
				local flatDist = (Vector3.new(pos.X - q.pos.X, 0, pos.Z - q.pos.Z)).Magnitude
				if flatDist < r + q.r + spacing and y0 < q.y1 + CFG.VerticalClearance and q.y0 < y1 + CFG.VerticalClearance then
					return false
				end
			end
		end
		return true
	end

	local function add(cf, size, kind, owner)
		table.insert(pieces, { cf = cf, size = size, kind = kind })
		table.insert(placed, {
			pos = Vector3.new(cf.Position.X, 0, cf.Position.Z), r = radiusOf(size),
			y0 = cf.Position.Y - size.Y / 2, y1 = cf.Position.Y + size.Y / 2, owner = owner,
		})
	end

	-- a random spot in the arena (filtered by fits)
	local function randomSpot()
		return Vector3.new(center.X + rng:NextNumber(-halfX, halfX), 0, center.Z + rng:NextNumber(-halfZ, halfZ))
	end

	local function tryPlace(kind, makeSize, makeBottom, tries)
		for _ = 1, tries or CFG.PlacementTries do
			local size = makeSize()
			local bottom = makeBottom(size)
			local spot = randomSpot()
			local r = radiusOf(size)
			if fits(spot, r, bottom, bottom + size.Y) then
				local cf = CFrame.new(spot.X, bottom + size.Y / 2, spot.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
				add(cf, size, kind)
				return cf, size
			end
		end
		return nil
	end

	local P = CFG.Pieces
	-- High platforms first (they need room for their stepping stones)
	for _ = 1, irange(rng, P.High.Count) do
		local laddered = rng:NextNumber() < P.High.LadderedShare
		local top = laddered and range(rng, { P.High.MinHeight, CFG.LadderMaxHeight }) or range(rng, { CFG.LadderMaxHeight, CFG.PlatformMaxHeight })
		local size = Vector3.new(range(rng, P.High.Width), range(rng, P.High.Thickness), range(rng, P.High.Width))
		local owner = {}
		for _ = 1, CFG.PlacementTries do
			local spot = randomSpot()
			local r = radiusOf(size)
			local bottom = floorY + top - size.Y
			if fits(spot, r, bottom, floorY + top) then
				local yaw = rng:NextNumber(0, math.pi)
				local cf = CFrame.new(spot.X, floorY + top - size.Y / 2, spot.Z) * CFrame.Angles(0, yaw, 0)
				-- stepping stones spiralling up round the platform (each a normal jump from the last)
				local stones = {}
				local ok = true
				if laddered then
					local steps = math.ceil((top - CFG.Stone.Rise * 0.5) / CFG.Stone.Rise)
					local radius = r + CFG.Stone.Size / 2 + 6
					local angle = rng:NextNumber(0, math.pi * 2)
					local dir = rng:NextNumber() < 0.5 and 1 or -1
					for k = 1, steps do
						local stoneTop = math.min(floorY + k * CFG.Stone.Rise, floorY + top - 1)
						angle += dir * CFG.Stone.Hop / radius
						local sp = Vector3.new(spot.X + math.cos(angle) * radius, 0, spot.Z + math.sin(angle) * radius)
						local sSize = Vector3.new(CFG.Stone.Size, CFG.Stone.Thickness, CFG.Stone.Size)
						local sBottom = stoneTop - sSize.Y
						if not fits(sp, radiusOf(sSize) * 0.75, sBottom, stoneTop, owner) then
							ok = false
							break
						end
						table.insert(stones, { cf = CFrame.new(sp.X, stoneTop - sSize.Y / 2, sp.Z) * CFrame.Angles(0, -angle, 0), size = sSize })
					end
				end
				if ok then
					add(cf, size, laddered and "High" or "Perch", owner)
					for _, s in ipairs(stones) do
						add(s.cf, s.size, "Stone", owner)
					end
					break
				end
			end
		end
	end

	-- Floating blocks (a Quin passes under them)
	for _ = 1, irange(rng, P.Float.Count) do
		tryPlace("Float", function()
			return Vector3.new(range(rng, P.Float.Width), range(rng, P.Float.Thickness), range(rng, P.Float.Width))
		end, function()
			return floorY + range(rng, P.Float.Underside)
		end)
	end
	-- Low platforms (jumpable from the ground)
	for _ = 1, irange(rng, P.Low.Count) do
		tryPlace("Low", function()
			return Vector3.new(range(rng, P.Low.Width), range(rng, P.Low.Height), range(rng, P.Low.Width))
		end, function() return floorY end)
	end
	-- Ground cover (random in X, Y and Z)
	for _ = 1, irange(rng, P.Cover.Count) do
		tryPlace("Cover", function()
			return Vector3.new(range(rng, P.Cover.Width), range(rng, P.Cover.Height), range(rng, P.Cover.Depth))
		end, function() return floorY end)
	end

	-- Mirror everything to the other half
	local count = #pieces
	for i = 1, count do
		local p = pieces[i]
		table.insert(pieces, { cf = mirrorCFrame(center, p.cf), size = p.size, kind = p.kind })
	end

	-- Spawn group: scattered points round the anchor, the same pattern mirrored
	local alphaSpawns = {}
	for _ = 1, 400 do
		if #alphaSpawns >= CFG.MaxSpawnPoints then break end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = math.sqrt(rng:NextNumber()) * CFG.SpawnClusterRadius
		local p = alphaAnchor + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local free = true
		for _, q in ipairs(alphaSpawns) do
			if (q - p).Magnitude < CFG.SpawnSpacing then free = false break end
		end
		if free then table.insert(alphaSpawns, p) end
	end
	local betaSpawns = {}
	for i, p in ipairs(alphaSpawns) do betaSpawns[i] = mirrorPoint(center, p) end

	return {
		seed = seed, option = option.Name, center = center, floorY = floorY,
		alphaAnchor = alphaAnchor, betaAnchor = betaAnchor, pieces = pieces,
		spawns = { TeamAlpha = alphaSpawns, TeamBeta = betaSpawns },
	}
end

-- ============================================================================
-- Validation: routes on the ground stay open (flood fill on a grid)
-- ============================================================================

local function validate(layout)
	if not layout then return false, "no ground" end
	local center, halfX, halfZ, floorY = metrics()
	local cell = CFG.GridCell
	local nx, nz = math.floor(halfX * 2 / cell), math.floor(halfZ * 2 / cell)
	local minX, minZ = center.X - halfX, center.Z - halfZ
	local blocked = {}
	local inflate = CFG.RouteWidth / 2
	for _, p in ipairs(layout.pieces) do
		local bottom = p.cf.Position.Y - p.size.Y / 2 - floorY
		local top = p.cf.Position.Y + p.size.Y / 2 - floorY
		-- blocks walking: sits low enough to hit a Quin and is too tall to vault
		if bottom < CFG.UnderpassClearance and top > CFG.VaultHeight then
			local hx, hz = p.size.X / 2 + inflate, p.size.Z / 2 + inflate
			local r = math.sqrt(hx * hx + hz * hz)
			local ix0 = math.max(0, math.floor((p.cf.Position.X - r - minX) / cell))
			local ix1 = math.min(nx - 1, math.floor((p.cf.Position.X + r - minX) / cell))
			local iz0 = math.max(0, math.floor((p.cf.Position.Z - r - minZ) / cell))
			local iz1 = math.min(nz - 1, math.floor((p.cf.Position.Z + r - minZ) / cell))
			for ix = ix0, ix1 do
				for iz = iz0, iz1 do
					local wp = Vector3.new(minX + (ix + 0.5) * cell, p.cf.Position.Y, minZ + (iz + 0.5) * cell)
					local lp = p.cf:PointToObjectSpace(wp)
					if math.abs(lp.X) <= hx and math.abs(lp.Z) <= hz then
						blocked[ix * nz + iz] = true
					end
				end
			end
		end
	end
	-- (the wall margin is not walkable either)
	local function cellOf(pos)
		return math.clamp(math.floor((pos.X - minX) / cell), 0, nx - 1), math.clamp(math.floor((pos.Z - minZ) / cell), 0, nz - 1)
	end
	local sx, sz = cellOf(layout.alphaAnchor)
	if blocked[sx * nz + sz] then return false, "spawn blocked" end
	local seen = { [sx * nz + sz] = true }
	local queue, head = { { sx, sz } }, 1
	local reached = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ix, iz = c[1] + d[1], c[2] + d[2]
			if ix >= 0 and ix < nx and iz >= 0 and iz < nz then
				local key = ix * nz + iz
				if not seen[key] and not blocked[key] then
					seen[key] = true
					reached += 1
					table.insert(queue, { ix, iz })
				end
			end
		end
	end
	local bx, bz = cellOf(layout.betaAnchor)
	if not seen[bx * nz + bz] then return false, "no route between spawns" end
	local cx, cz = cellOf(layout.center)
	if not seen[cx * nz + cz] then return false, "centre cut off" end
	local free = 0
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			if not blocked[ix * nz + iz] then free += 1 end
		end
	end
	if reached < free * CFG.MinReachableShare then
		return false, string.format("closed pockets (%d%% reachable)", math.floor(reached / free * 100))
	end
	return true, string.format("%d%% of the floor reachable", math.floor(reached / free * 100))
end

-- ============================================================================
-- Instances: hologram pool, stash, materialize
-- ============================================================================

local function folder()
	local a = arenaOne()
	local f = a and a:FindFirstChild("ArenaGenerated")
	if not f and a then
		f = Instance.new("Folder")
		f.Name = "ArenaGenerated"
		f.Parent = a
	end
	return f
end

local function playFx(name)
	local a = arenaOne()
	local fxFolder = a and a:FindFirstChild("ArenaSoundFX") and a.ArenaSoundFX:FindFirstChild("GenerationFX")
	local template = fxFolder and fxFolder:FindFirstChild(name)
	local g = ground()
	if template and template:IsA("Sound") and g then
		local s = template:Clone()
		s.Parent = g
		s:Play()
		task.delay(math.max(template.TimeLength, 1) + 0.5, function() s:Destroy() end)
	end
end

local function holoStyle(part, valid)
	part.Material = CFG.HoloMaterial or Enum.Material.Neon
	part.Color = valid and CFG.HoloColor or CFG.HoloRejectColor
	part.Transparency = CFG.HoloTransparency
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function poolPart(i)
	local part = pool[i]
	if not part or not part.Parent then
		part = Instance.new("Part")
		part.Name = "GenHolo"
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		holoStyle(part, true)
		part.Parent = folder()
		pool[i] = part
	end
	return part
end

local function showHologram(layout, valid, glitch)
	local n = #layout.pieces
	for i, p in ipairs(layout.pieces) do
		local part = poolPart(i)
		holoStyle(part, valid)
		local jitter = Vector3.zero
		if glitch and math.random() < CFG.GlitchShare then
			jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * CFG.GlitchJitter
			part.Transparency = 0.9
		end
		part.Size = p.size
		part.CFrame = p.cf + jitter
	end
	for i = n + 1, #pool do
		if pool[i] and pool[i].Parent then
			pool[i].Transparency = 1
		end
	end
end

local function clearPool()
	for _, part in ipairs(pool) do
		if part then part:Destroy() end
	end
	pool = {}
	local f = arenaOne() and arenaOne():FindFirstChild("ArenaGenerated")
	if f then f:Destroy() end
end

-- Put the edit-mode obstacles aside (ServerStorage: not replicated, so gone for clients too)
local function stashEditLayout()
	if stash then return end
	stash = {}
	local center, halfX, halfZ = metrics()
	local a = arenaOne()
	local box = ServerStorage:FindFirstChild("ArenaEditLayoutStash") or Instance.new("Folder")
	box.Name = "ArenaEditLayoutStash"
	box.Parent = ServerStorage
	for _, part in ipairs(a:GetDescendants()) do
		if part:IsA("BasePart") and table.find(CFG.EditLayoutNames, part.Name)
			and math.abs(part.Position.X - center.X) <= halfX and math.abs(part.Position.Z - center.Z) <= halfZ then
			table.insert(stash, { part = part, parent = part.Parent })
		end
	end
	for _, entry in ipairs(stash) do
		entry.part.Parent = box
	end
end

local function unstashEditLayout()
	if not stash then return end
	for _, entry in ipairs(stash) do
		if entry.part and entry.parent and entry.parent.Parent then
			entry.part.Parent = entry.parent
		end
	end
	stash = nil
end

local function spawnPads()
	local list = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == "QuinSpawn" and d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- QuinSpawn pads follow the anchors (pad 1 = TeamAlpha, pad 2 = TeamBeta, as QuinSpawner orders them)
local function applySpawnPads(layout)
	local pads = spawnPads()
	spawnPadHome = spawnPadHome or {}
	for i, pad in ipairs(pads) do
		if not spawnPadHome[i] then spawnPadHome[i] = { part = pad, cframe = pad.CFrame } end
		local anchor = (i == 1) and layout.alphaAnchor or (i == 2 and layout.betaAnchor) or nil
		if anchor then
			pad.CFrame = CFrame.new(anchor.X, pad.Position.Y, anchor.Z) * pad.CFrame.Rotation
		end
	end
end

local function restoreSpawnPads()
	if not spawnPadHome then return end
	for _, entry in ipairs(spawnPadHome) do
		if entry.part and entry.part.Parent then entry.part.CFrame = entry.cframe end
	end
	spawnPadHome = nil
end

local function refreshCatalogue()
	local ok, catalogue = pcall(function()
		return require(ReplicatedStorage.QuinCore.Modules.PlatformCatalogue)
	end)
	if ok and catalogue and catalogue.refresh then catalogue.refresh() end
end

-- Hologram -> solid, swept from the ground up
local function materialize(layout, seconds)
	local floorY = layout.floorY
	local topMost = 1
	for _, p in ipairs(layout.pieces) do
		topMost = math.max(topMost, p.cf.Position.Y + p.size.Y / 2 - floorY)
	end
	local rng = Random.new(layout.seed)
	for i, p in ipairs(layout.pieces) do
		local part = poolPart(i)
		part.CFrame = p.cf
		part.Size = p.size
		local height = p.cf.Position.Y + p.size.Y / 2 - floorY
		local delay = seconds * 0.8 * (height / topMost)
		local shade = CFG.GrassColors[1]:Lerp(CFG.GrassColors[2], rng:NextNumber())
		task.delay(delay, function()
			if not part.Parent then return end
			-- (a short glitch flicker, then solid)
			part.Transparency = 0.2
			task.wait(0.05)
			part.Transparency = 0.7
			task.wait(0.05)
			part.Name = "OB"
			part.Material = CFG.SolidMaterial
			part.Color = shade
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = true
			part.CastShadow = true
			part:SetAttribute("GenKind", p.kind)
			part.Transparency = 0.6
			TweenService:Create(part, TweenInfo.new(math.min(0.6, seconds * 0.2)), { Transparency = 0 }):Play()
		end)
	end
	for i = #layout.pieces + 1, #pool do
		if pool[i] then pool[i]:Destroy() pool[i] = nil end
	end
	task.wait(seconds)
end

-- A rising scan plane over the whole volume (start of the sequence)
local function scanSweep(seconds)
	local center, halfX, halfZ, floorY = metrics()
	local plane = Instance.new("Part")
	plane.Name = "GenScan"
	plane.Anchored = true
	plane.CanCollide, plane.CanQuery, plane.CanTouch, plane.CastShadow = false, false, false, false
	plane.Material = Enum.Material.Neon
	plane.Color = CFG.HoloColor
	plane.Transparency = 0.85
	plane.Size = Vector3.new(halfX * 2, 0.4, halfZ * 2)
	plane.CFrame = CFrame.new(center.X, floorY + 0.5, center.Z)
	plane.Parent = folder()
	TweenService:Create(plane, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.new(center.X, floorY + CFG.MaxHeight, center.Z), Transparency = 1,
	}):Play()
	task.delay(seconds + 0.1, function() plane:Destroy() end)
end

-- ============================================================================
-- API
-- ============================================================================

local ArenaScreen = nil
local function progress(fraction, text)
	if not ArenaScreen then
		local ok, mod = pcall(function()
			return require(game:GetService("ServerScriptService"):WaitForChild("ArenaScreenManager"))
		end)
		ArenaScreen = ok and mod or false
	end
	if ArenaScreen then ArenaScreen.setGenerationProgress(fraction, text) end
end

-- Run the whole show in `duration` seconds. isCancelled() true = hurry (SKIP): pick the next
-- good seed and materialize at once. Returns true when a generated arena is in place.
function Gen.runSequence(duration, isCancelled)
	if running then return false end
	running = true
	if active then Gen.restore() end
	local center = metrics()
	if not center then
		running = false
		return false
	end
	stashEditLayout()
	refreshCatalogue()
	folder()

	local t0 = os.clock()
	local function hurry() return isCancelled and isCancelled() end
	local function frac() return math.clamp((os.clock() - t0) / duration, 0, 1) end

	-- 1. scan
	if not hurry() then
		progress(0, "SCANNING ARENA VOLUME")
		scanSweep(duration * CFG.ScanShare)
		task.wait(duration * CFG.ScanShare)
	end

	-- 2. seed sweep: candidates flick past; each is checked
	local shuffleUntil = t0 + duration * CFG.ShuffleUntil
	local seedRng = Random.new()
	local chosen, lastGood = nil, nil
	local tries = 0
	while true do
		local seed = CFG.FixedSeed or seedRng:NextInteger(1, 0xFFFFFF)
		local layout = generate(seed)
		local ok, why = validate(layout)
		tries += 1
		if ok then lastGood = layout end
		local done = (os.clock() >= shuffleUntil or hurry()) and ok
		if not hurry() or done then
			showHologram(layout, ok, not done)
			progress(math.min(frac(), CFG.ShuffleUntil), string.format("SEED %06X • %s • %s", seed, layout.option:upper(), ok and "ROUTES OK" or ("REJECTED: " .. why:upper())))
			if not done then playFx("SeedTick") end
		end
		if done then
			chosen = layout
			break
		end
		if tries >= CFG.MaxTries then
			chosen = lastGood
			break
		end
		if CFG.FixedSeed and not ok then break end
		if not hurry() then
			task.wait(CFG.SeedInterval * (0.7 + 0.6 * math.random()))
		end
	end

	if not chosen then
		warn("[ArenaGenerator] No traversable layout found; keeping the edit-mode arena")
		clearPool()
		unstashEditLayout()
		refreshCatalogue()
		progress(nil)
		running = false
		return false
	end

	-- 3. lock: the good seed pulses
	progress(math.max(frac(), CFG.ShuffleUntil), string.format("SEED %06X LOCKED • %s", chosen.seed, chosen.option:upper()))
	playFx("SeedLock")
	if not hurry() then
		for _ = 1, 3 do
			for i = 1, #chosen.pieces do pool[i].Transparency = CFG.HoloTransparency * 0.4 end
			task.wait(0.12)
			for i = 1, #chosen.pieces do pool[i].Transparency = CFG.HoloTransparency end
			task.wait(0.18)
		end
	end

	-- 4. materialize
	progress(math.max(frac(), 0.8), "MATERIALIZING SECTORS")
	playFx("Materialize")
	local remaining = math.max(0.5, duration - (os.clock() - t0) - 0.5)
	materialize(chosen, hurry() and 0.6 or math.min(CFG.MaterializeTime, remaining))
	current = chosen
	active = true
	applySpawnPads(chosen)
	refreshCatalogue()
	progress(1, string.format("ARENA READY • SEED %06X", chosen.seed))
	Workspace:SetAttribute("ArenaSeed", string.format("%06X", chosen.seed))
	print(string.format("[ArenaGenerator] Seed %06X locked after %d candidates: %s, %d pieces (%d per side)",
		chosen.seed, tries, chosen.option, #chosen.pieces, #chosen.pieces / 2))
	running = false
	return true
end

-- Back to the edit-mode arena
function Gen.restore()
	clearPool()
	unstashEditLayout()
	restoreSpawnPads()
	active = false
	current = nil
	progress(nil)
	Workspace:SetAttribute("ArenaSeed", nil)
	refreshCatalogue()
end

function Gen.isActive()
	return active
end

function Gen.getLayout()
	return current
end

-- Spawn points for `count` fighters of a team: scattered round the side's anchor, the same
-- pattern mirrored for the other team. nil when no generated arena is in place.
function Gen.getSpawnPoints(team, count)
	if not active or not current then return nil end
	local list = current.spawns[team]
	if not list or #list == 0 then return nil end
	local out = {}
	for i = 1, count do
		local p = list[((i - 1) % #list) + 1]
		out[i] = p + Vector3.new(0, 3, 0)
	end
	return out, (team == "TeamAlpha") and current.betaAnchor or current.alphaAnchor
end

-- Half size of the empty centre square (FFA ring spawns stay inside it)
function Gen.getCenterClearHalf()
	return CFG.CenterClear / 2
end

-- Studio test hook: Workspace attribute ArenaGenDevCommand = "run <seconds>" | "restore" | "check <count>"
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("ArenaGenDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("ArenaGenDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("ArenaGenDevCommand", nil)
		local verb, arg = cmd:match("^(%S+)%s*(%S*)")
		if verb == "run" then
			task.spawn(Gen.runSequence, tonumber(arg) or 15)
		elseif verb == "restore" then
			Gen.restore()
		elseif verb == "check" then
			-- statistics over many seeds (no instances)
			local n, good, pieces = tonumber(arg) or 200, 0, 0
			local reasons = {}
			for seed = 1, n do
				local layout = generate(seed * 7919)
				local ok, why = validate(layout)
				if ok then
					good += 1
					pieces += #layout.pieces
				else
					reasons[why:gsub("%(.*%)", "")] = (reasons[why:gsub("%(.*%)", "")] or 0) + 1
				end
			end
			local parts = {}
			for k, v in pairs(reasons) do table.insert(parts, k .. "=" .. v) end
			Workspace:SetAttribute("ArenaGenCheck", string.format("%d/%d valid, %.1f pieces avg; rejected: %s",
				good, n, good > 0 and pieces / good or 0, table.concat(parts, ", ")))
		end
	end)
end

return Gen
