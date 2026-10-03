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
local treeTemplate = nil    -- clone of the edit-mode tree model (CFG.Trees.Template)
local fxToken = nil         -- the running flicker loop
local shownCount = 0        -- hologram blocks on show
local scanlines = {}

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
	local T = CFG.Trees
	local tops = {}  -- platform tops (trees may grow there)
	local trees = {} -- { cf (base, yawed), scale }

	local function addTree(pos, baseY, owner)
		local scale = range(rng, T.Scale)
		table.insert(trees, { cf = CFrame.new(pos.X, baseY, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), scale = scale })
		table.insert(placed, { pos = Vector3.new(pos.X, 0, pos.Z), r = T.Footprint / 2, y0 = baseY, y1 = baseY + T.Height * scale, owner = owner })
	end

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
					table.insert(tops, { cf = cf * CFrame.new(0, size.Y / 2, 0), size = size, top = floorY + top, owner = owner })
					for _, s in ipairs(stones) do
						add(s.cf, s.size, "Stone", owner)
					end
					break
				end
			end
		end
	end

	-- Trees on wide platform tops
	if T then
		for _, top in ipairs(tops) do
			local w = math.min(top.size.X, top.size.Z)
			if w >= T.MinPlatformWidth and rng:NextNumber() < T.OnPlatformChance then
				local inset = w / 2 - T.Footprint / 2
				local p = top.cf:PointToWorldSpace(Vector3.new(rng:NextNumber(-inset, inset), 0, rng:NextNumber(-inset, inset)))
				if fits(p, T.Footprint / 2, top.top, top.top + T.Height, top.owner) then
					addTree(p, top.top, top.owner)
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
	-- Walls (long, thin, tall: cover lines)
	if P.Wall then
		for _ = 1, irange(rng, P.Wall.Count) do
			tryPlace("Wall", function()
				return Vector3.new(range(rng, P.Wall.Length), range(rng, P.Wall.Height), range(rng, P.Wall.Thickness))
			end, function() return floorY end)
		end
	end
	-- Ground cover (random in X, Y and Z)
	for _ = 1, irange(rng, P.Cover.Count) do
		tryPlace("Cover", function()
			return Vector3.new(range(rng, P.Cover.Width), range(rng, P.Cover.Height), range(rng, P.Cover.Depth))
		end, function() return floorY end)
	end

	-- Trees on the ground
	if T then
		for _ = 1, irange(rng, T.Ground) do
			for _ = 1, CFG.PlacementTries do
				local spot = randomSpot()
				if fits(spot, T.Footprint / 2, floorY, floorY + T.Height) then
					addTree(spot, floorY)
					break
				end
			end
		end
	end

	-- Mirror everything to the other half
	local count = #pieces
	for i = 1, count do
		local p = pieces[i]
		table.insert(pieces, { cf = mirrorCFrame(center, p.cf), size = p.size, kind = p.kind })
	end
	local treeCount = #trees
	for i = 1, treeCount do
		table.insert(trees, { cf = mirrorCFrame(center, trees[i].cf), scale = trees[i].scale })
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
		alphaAnchor = alphaAnchor, betaAnchor = betaAnchor, pieces = pieces, trees = trees,
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
	local blockers = table.clone(layout.pieces)
	for _, t in ipairs(layout.trees or {}) do
		local trunk = CFG.Trees.TrunkBlock * t.scale
		table.insert(blockers, { cf = t.cf + Vector3.new(0, 10, 0), size = Vector3.new(trunk, 20, trunk) })
	end
	for _, p in ipairs(blockers) do
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

-- Generation sounds come from the arena centre (an invisible emitter in the generated folder,
-- so restore() also silences them), routed through the arena master volume
local function playFx(key)
	local S = CFG.Sounds or {}
	local name = S[key] or key
	local a = arenaOne()
	local sfx = a and a:FindFirstChild("ArenaSoundFX")
	local template = sfx and (sfx:FindFirstChild(name) or (sfx:FindFirstChild("GenerationFX") and sfx.GenerationFX:FindFirstChild(name)))
	local center, _, _, floorY = metrics()
	local f = folder()
	if not (template and template:IsA("Sound") and center and f) then return nil end
	local emitter = f:FindFirstChild("GenAudio")
	if not emitter then
		emitter = Instance.new("Part")
		emitter.Name = "GenAudio"
		emitter.Anchored = true
		emitter.Transparency = 1
		emitter.Size = Vector3.new(1, 1, 1)
		emitter.CanCollide, emitter.CanQuery, emitter.CanTouch, emitter.CastShadow = false, false, false, false
		emitter.CFrame = CFrame.new(center.X, floorY + (S.Height or 25), center.Z)
		emitter.Parent = f
	end
	local s = template:Clone()
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = S.RollOffMin or 200
	s.RollOffMaxDistance = S.RollOffMax or 1600
	s.Volume = template.Volume * (S.Volume or 1)
	local master = game:GetService("SoundService"):FindFirstChild("ArenaSpeakerGroup")
	if master then s.SoundGroup = master end
	s.Parent = emitter
	s:Play()
	task.delay(math.max(template.TimeLength, 1) + 0.5, function() s:Destroy() end)
	return s
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

-- TV static: a particle snow inside a hologram block
local function setStatic(part, on)
	if not CFG.StaticNoise then return end
	local e = part:FindFirstChild("Static")
	if not e and on then
		e = Instance.new("ParticleEmitter")
		e.Name = "Static"
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Lifetime = NumberRange.new(0.04, 0.12)
		e.Speed = NumberRange.new(0)
		e.Size = NumberSequence.new(0.9)
		e.LightEmission = 1
		e.LockedToPart = true
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), CFG.HoloColor)
		e.Transparency = NumberSequence.new(0.15)
		e.Parent = part
	end
	if e then
		e.Rate = math.clamp(part.Size.X * part.Size.Y * part.Size.Z / 300, CFG.StaticRate[1], CFG.StaticRate[2])
		e.Enabled = on
	end
end

-- Scanner frames: thin neon bars round the arena edge, jumping to random heights on every
-- switch (full planes washed the whole arena cyan)
local function setScanlines(on, topY)
	if not on then
		for _, frame in ipairs(scanlines) do
			for _, bar in ipairs(frame) do bar:Destroy() end
		end
		scanlines = {}
		return
	end
	local center, halfX, halfZ, floorY = metrics()
	local w = CFG.ScanlineWidth or 0.8
	for i = 1, CFG.Scanlines or 0 do
		local frame = scanlines[i]
		if not frame or not frame[1].Parent then
			frame = {}
			for k = 1, 4 do
				local bar = Instance.new("Part")
				bar.Name = "GenScanline"
				bar.Anchored = true
				bar.CanCollide, bar.CanQuery, bar.CanTouch, bar.CastShadow = false, false, false, false
				bar.Material = Enum.Material.Neon
				bar.Color = CFG.HoloColor
				bar.Size = (k <= 2) and Vector3.new(halfX * 2, w, w) or Vector3.new(w, w, halfZ * 2)
				bar.Parent = folder()
				frame[k] = bar
			end
			scanlines[i] = frame
		end
		local y = floorY + math.random() * (topY or 60)
		local transparency = 0.15 + math.random() * 0.5
		local spots = {
			Vector3.new(center.X, y, center.Z - halfZ), Vector3.new(center.X, y, center.Z + halfZ),
			Vector3.new(center.X - halfX, y, center.Z), Vector3.new(center.X + halfX, y, center.Z),
		}
		for k, bar in ipairs(frame) do
			bar.CFrame = CFrame.new(spots[k])
			bar.Transparency = transparency
		end
	end
end

-- Blocks to draw for a layout: its pieces, then a trunk and a canopy per tree
local function holoShapes(layout)
	local shapes = {}
	for _, p in ipairs(layout.pieces) do
		table.insert(shapes, { cf = p.cf, size = p.size })
	end
	for _, t in ipairs(layout.trees or {}) do
		local s = t.scale
		table.insert(shapes, { cf = t.cf * CFrame.new(0, 11 * s, 0), size = Vector3.new(3 * s, 22 * s, 3 * s) })
		table.insert(shapes, { cf = t.cf * CFrame.new(0, 31 * s, 0), size = Vector3.new(22 * s, 18 * s, 22 * s) })
	end
	return shapes
end

local function highestTop(layout)
	local top = 20
	for _, p in ipairs(layout.pieces) do
		top = math.max(top, p.cf.Position.Y + p.size.Y / 2 - layout.floorY)
	end
	return top
end

-- glitch = a switch in the seed sweep: transparency spread, jitter, tears, white flashes, static
local function showHologram(layout, valid, glitch)
	local shapes = holoShapes(layout)
	local spread = CFG.HoloTransparencyRange or { CFG.HoloTransparency, CFG.HoloTransparency }
	for i, sh in ipairs(shapes) do
		local part = poolPart(i)
		holoStyle(part, valid)
		local size, cf = sh.size, sh.cf
		if glitch then
			part.Transparency = lerp(spread[1], spread[2], math.random())
			if math.random() < CFG.GlitchShare then
				cf = cf + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * CFG.GlitchJitter
			end
			if math.random() < (CFG.TearShare or 0) then
				local k = 1 + math.random() * (CFG.TearStretch or 0)
				size = Vector3.new(size.X * k, size.Y * (0.6 + math.random() * 0.4), size.Z)
			end
			if math.random() < (CFG.FlashShare or 0) then
				part.Color = Color3.new(1, 1, 1)
				part.Transparency = 0.05
			end
		end
		part.Size = size
		part.CFrame = cf
		setStatic(part, glitch)
	end
	for i = #shapes + 1, #pool do
		if pool[i] and pool[i].Parent then
			pool[i].Transparency = 1
			setStatic(pool[i], false)
		end
	end
	return #shapes
end

-- Between switches random blocks blink (pop / nearly gone)
local function startFlicker()
	local token = {}
	fxToken = token
	task.spawn(function()
		while fxToken == token do
			local n = shownCount
			if n > 0 then
				for _ = 1, math.max(1, math.floor(n * CFG.FlickerShare)) do
					local p = pool[math.random(1, n)]
					if p and p.Parent then
						p.Transparency = (math.random() < 0.5) and 0.92 or 0.12
					end
				end
			end
			task.wait(1 / CFG.FlickerRate)
		end
	end)
end

local function stopFlicker()
	fxToken = nil
end

local function clearPool()
	stopFlicker()
	scanlines = {}
	shownCount = 0
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
	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") and table.find(CFG.EditLayoutModels or {}, model.Name) and not model:FindFirstAncestorOfClass("Model") then
			local pivot = model:GetPivot().Position
			if math.abs(pivot.X - center.X) <= halfX and math.abs(pivot.Z - center.Z) <= halfZ then
				table.insert(stash, { part = model, parent = model.Parent })
			end
		end
	end
	for _, entry in ipairs(stash) do
		entry.part.Parent = box
	end
end

local function ensureTreeTemplate()
	if treeTemplate or not CFG.Trees then return treeTemplate end
	local function find(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and d.Name == CFG.Trees.Template then return d end
		end
		return nil
	end
	local source = find(Workspace) or (ServerStorage:FindFirstChild("ArenaEditLayoutStash") and find(ServerStorage.ArenaEditLayoutStash))
	if source then
		treeTemplate = source:Clone()
	else
		warn("[ArenaGenerator] No tree model named " .. CFG.Trees.Template .. "; generated arenas have no trees")
	end
	return treeTemplate
end

-- A tree clone standing on t.cf (base point, yawed), faded in
local function spawnTree(t, parent)
	if not treeTemplate then return nil end
	local tree = treeTemplate:Clone()
	tree:PivotTo(CFrame.new(t.cf.Position) * t.cf.Rotation * treeTemplate:GetPivot().Rotation)
	if t.scale ~= 1 then tree:ScaleTo(t.scale) end
	local bb, size = tree:GetBoundingBox()
	tree:PivotTo(tree:GetPivot() + (t.cf.Position - Vector3.new(bb.X, bb.Y - size.Y / 2, bb.Z)))
	tree:SetAttribute("GenKind", "Tree")
	local fades = {}
	for _, p in ipairs(tree:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(fades, { part = p, to = p.Transparency })
			p.Transparency = 1
		end
	end
	tree.Parent = parent
	for _, f in ipairs(fades) do
		TweenService:Create(f.part, TweenInfo.new(0.5), { Transparency = f.to }):Play()
	end
	return tree
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
			local static = part:FindFirstChild("Static")
			if static then static:Destroy() end
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
	-- trees: their hologram trunk + canopy give way to the real tree
	local base = #layout.pieces
	for k, t in ipairs(layout.trees or {}) do
		local holoA, holoB = pool[base + 2 * k - 1], pool[base + 2 * k]
		pool[base + 2 * k - 1], pool[base + 2 * k] = false, false
		local height = t.cf.Position.Y - floorY + 30
		task.delay(seconds * 0.8 * math.min(1, height / topMost), function()
			if holoA then holoA:Destroy() end
			if holoB then holoB:Destroy() end
			local f = folder()
			if f then spawnTree(t, f) end
		end)
	end
	for i = #layout.pieces + 1, #pool do
		if pool[i] then pool[i]:Destroy() end
		pool[i] = nil
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
	ensureTreeTemplate()
	stashEditLayout()
	refreshCatalogue()
	folder()

	local t0 = os.clock()
	local function hurry() return isCancelled and isCancelled() end
	local function frac() return math.clamp((os.clock() - t0) / duration, 0, 1) end

	-- 1. scan
	playFx("Sweep")
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
	startFlicker()
	while true do
		local seed = CFG.FixedSeed or seedRng:NextInteger(1, 0xFFFFFF)
		local layout = generate(seed)
		local ok, why = validate(layout)
		tries += 1
		if ok then lastGood = layout end
		local done = (os.clock() >= shuffleUntil or hurry()) and ok
		if not hurry() or done then
			shownCount = showHologram(layout, ok, not done)
			setScanlines(not done, highestTop(layout))
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

	stopFlicker()
	setScanlines(false)
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
		-- white flash pulses: the seed is locked
		for _ = 1, 3 do
			for i = 1, shownCount do
				local p = pool[i]
				if p then p.Color = Color3.new(1, 1, 1) p.Transparency = 0.05 end
			end
			task.wait(0.08)
			for i = 1, shownCount do
				local p = pool[i]
				if p then p.Color = CFG.HoloColor p.Transparency = CFG.HoloTransparency end
			end
			task.wait(0.22)
		end
	end

	-- 4. materialize
	progress(math.max(frac(), 0.8), "MATERIALIZING SECTORS")
	local remaining = math.max(0.5, duration - (os.clock() - t0) - 0.5)
	materialize(chosen, hurry() and 0.6 or math.min(CFG.MaterializeTime, remaining))
	current = chosen
	active = true
	applySpawnPads(chosen)
	refreshCatalogue()
	playFx("Finish")
	progress(1, string.format("ARENA READY • SEED %06X", chosen.seed))
	Workspace:SetAttribute("ArenaSeed", string.format("%06X", chosen.seed))
	print(string.format("[ArenaGenerator] Seed %06X locked after %d candidates: %s, %d pieces + %d trees (half each side)",
		chosen.seed, tries, chosen.option, #chosen.pieces, #(chosen.trees or {})))
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
