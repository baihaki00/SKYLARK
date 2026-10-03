--// ArenaCrowdManager.lua
-- Procedural spatial stadium crowd for ArenaOne (Arena System toggle "CrowdFX").
--
-- * Sounds come from the CrowdFX folder tree (Workspace.argoniaonion.ArenaOne.ArenaSoundFX.CrowdFX
--   /<Group>/<Category>/<Sound>); config names Categories only, so sounds can be swapped or added.
-- * Every stand part named "CrowdFX" becomes a section with emitters spread along its length:
--   a murmur bed on each emitter, a mood layer on every other one, one-shots on a random one.
-- * Sections pick a team when the fighters arrive (contiguous arcs of equal row length, the arc
--   nearer a team's spawn backs that team) and keep it until the match ends. They cheer their
--   team's hits, groan or boo when it suffers, chant when excited. FFA: every section is neutral.
-- * Anthem crowd/drum stems are played through the section emitters (ArenaAudioManager.playAnthem
--   asks getStemEmitters).
--
-- Driven by ArenaSystemOrchestrator: setEnabled, resetMatch, setPhase, assignTeams, onWinner.

local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.QuinCore.ArenaConfig)
local CFG = ArenaConfig.CrowdFX

local Crowd = {}

local library = nil        -- Category name -> { Sound templates }
local lastPick = {}        -- Category -> last template (avoid back-to-back repeats)
local sections = nil       -- { part, center, length, emitters = { {att, index, loops = {}} }, team, nextMinor }
local crowdGroup = nil

local enabled = false
local phase = "IDLE"
local matchMode = "TeamBattle"
local teamsAssigned = false
local excitement = { TeamAlpha = 0, TeamBeta = 0, Neutral = 0 }
local angryUntil = { TeamAlpha = 0, TeamBeta = 0, Neutral = 0 }
local chantTeam, chantUntil, nextChantAt = nil, 0, 0
local winnerTeam = nil
local activeShots = {}    -- one-shots playing or about to: { sound, major, cancelled }
local lastMinorAt = 0
local directorThread = nil
local isDucked = false
local levelsPrintToken = 0
local watched = {}         -- fighter Model -> { connections }

-- ============================================================================
-- Library, channel, emitters
-- ============================================================================

local function findFolder()
	local node = Workspace
	for _, name in ipairs(CFG.Folder) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function loadLibrary()
	library = {}
	local folder = findFolder()
	if not folder then
		warn("[ArenaCrowd] CrowdFX folder not found; the crowd is silent.")
		return
	end
	local count = 0
	for _, s in ipairs(folder:GetDescendants()) do
		if s:IsA("Sound") then
			local cat = s.Parent.Name
			library[cat] = library[cat] or {}
			table.insert(library[cat], s)
			count += 1
		end
	end
	print(string.format("[ArenaCrowd] Loaded %d crowd sounds from %s", count, folder:GetFullName()))
end

local function ensureGroup()
	if crowdGroup and crowdGroup.Parent then return crowdGroup end
	local master = SoundService:FindFirstChild("ArenaSpeakerGroup")
	crowdGroup = (master or SoundService):FindFirstChild("ArenaCrowdChannel")
	if not crowdGroup then
		crowdGroup = Instance.new("SoundGroup")
		crowdGroup.Name = "ArenaCrowdChannel"
		crowdGroup.Parent = master or SoundService
	end
	crowdGroup.Volume = CFG.Volume
	return crowdGroup
end

local function arenaCenter()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ArenaGround" then
			return d.Position
		end
	end
	return nil
end

-- One section per stand part; emitters along the part's longest axis
local function buildSections()
	if sections then return sections end
	sections = {}
	local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
	if not arenaOne then return sections end
	for _, part in ipairs(arenaOne:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == CFG.EmitterPartName then
			local size, cf = part.Size, part.CFrame
			local axis, length = cf.RightVector, size.X
			if size.Y > length then axis, length = cf.UpVector, size.Y end
			if size.Z > length then axis, length = cf.LookVector, size.Z end
			local n = math.clamp(math.ceil(length / CFG.EmitterSpacing), CFG.MinEmitters, CFG.MaxEmitters)
			local section = { part = part, center = part.Position, length = length, emitters = {}, team = "Neutral", nextMinor = 0 }
			for i = 1, n do
				local att = Instance.new("Attachment")
				att.Name = "CrowdEmitter" .. i
				att.Parent = part
				att.WorldPosition = part.Position + axis * (((i - 0.5) / n) - 0.5) * length
				table.insert(section.emitters, { att = att, index = i, loops = {} })
			end
			local stem = Instance.new("Attachment")
			stem.Name = "CrowdStem"
			stem.Parent = part
			section.stem = stem
			table.insert(sections, section)
		end
	end
	print(string.format("[ArenaCrowd] %d stand sections ready", #sections))
	return sections
end

local function pick(category)
	if not library then loadLibrary() end
	local list = category and library[category]
	if not list or #list == 0 then return nil end
	local usable = {}
	for _, s in ipairs(list) do
		-- (a sound that failed to load reports no length)
		if s.TimeLength > 0 and (s ~= lastPick[category] or #list == 1) then
			table.insert(usable, s)
		end
	end
	if #usable == 0 then return nil end
	local chosen = usable[math.random(1, #usable)]
	lastPick[category] = chosen
	return chosen
end

local function makeSound(template, parent, looped)
	local s = Instance.new("Sound")
	s.Name = "Crowd_" .. template.Name
	s.SoundId = template.SoundId
	s.Looped = looped
	s.Volume = 0
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * CFG.PitchJitter
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = CFG.RollOffMin
	s.RollOffMaxDistance = CFG.RollOffMax
	s.SoundGroup = ensureGroup()
	s.Parent = parent
	return s
end

local function fadeTo(sound, volume, t)
	TweenService:Create(sound, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = volume }):Play()
end

local function fadeOutAndDestroy(sound, t)
	fadeTo(sound, 0, t)
	task.delay(t + 0.1, function()
		sound:Destroy()
	end)
end

-- A looping slot on an emitter ("bed" / "layer"): same category -> volume follows,
-- new category -> crossfade to a random variant started at a random point
local function setLoop(emitter, slot, category, volume)
	local cur = emitter.loops[slot]
	if not category or volume <= 0.001 then
		if cur then
			fadeOutAndDestroy(cur.sound, CFG.Crossfade)
			emitter.loops[slot] = nil
		end
		return
	end
	if cur and cur.category == category then
		if math.abs(cur.volume - volume) > 0.01 then
			fadeTo(cur.sound, volume, 1.5)
			cur.volume = volume
		end
		return
	end
	local template = pick(category)
	if not template then return end
	if cur then
		fadeOutAndDestroy(cur.sound, CFG.Crossfade)
	end
	local s = makeSound(template, emitter.att, true)
	s.TimePosition = math.random() * math.max(0, template.TimeLength - 0.5)
	s:Play()
	fadeTo(s, volume, CFG.Crossfade)
	emitter.loops[slot] = { sound = s, category = category, volume = volume }
end

local function releaseShot(entry)
	local i = table.find(activeShots, entry)
	if i then table.remove(activeShots, i) end
end

-- At the cap a minor one-shot is dropped; a major one (elimination, kick-off, winner) always plays
-- and fades out the oldest minor one-shot, or the oldest one when all are major
local function oneShot(section, category, volume, delay, major)
	if #activeShots >= CFG.MaxOneShots then
		if not major then return end
		local victim = nil
		for _, e in ipairs(activeShots) do
			if not e.major then victim = e break end
		end
		victim = victim or activeShots[1]
		victim.cancelled = true
		releaseShot(victim)
		if victim.sound then fadeOutAndDestroy(victim.sound, 0.5) end
	end
	local template = pick(category)
	if not template then return end
	local emitter = section.emitters[math.random(1, #section.emitters)]
	local entry = { major = major == true }
	table.insert(activeShots, entry)
	task.delay(delay or 0, function()
		if not enabled or entry.cancelled then
			releaseShot(entry)
			return
		end
		local s = makeSound(template, emitter.att, false)
		entry.sound = s
		s.Volume = volume
		s:Play()
		task.delay(template.TimeLength / s.PlaybackSpeed + 0.3, function()
			releaseShot(entry)
			s:Destroy()
		end)
	end)
end

-- Sections backing `team` react (team nil = every section). Minor reactions are rate limited.
local function react(team, category, chance, major)
	if not enabled or not category or not sections then return end
	local now = os.clock()
	if not major then
		if now - lastMinorAt < CFG.MinorGap then return end
		lastMinorAt = now
	end
	for _, section in ipairs(sections) do
		if (team == nil or section.team == team) and math.random() < (chance or 1) then
			if major or now >= section.nextMinor then
				section.nextMinor = now + CFG.SectionCooldown
				oneShot(section, category, major and CFG.MajorVolume or CFG.ReactVolume, math.random() * (major and 0.4 or 0.6), major)
			end
		end
	end
end

local function otherTeam(team)
	if team == "TeamAlpha" then return "TeamBeta" end
	if team == "TeamBeta" then return "TeamAlpha" end
	return nil
end

local function bump(team, amount)
	if team and excitement[team] then
		excitement[team] = math.clamp(excitement[team] + amount, 0, 1)
	end
end

-- ============================================================================
-- Fighters -> moments
-- ============================================================================

local function isTeamMode()
	return matchMode ~= "FFA"
end

local function onDamage(model, damage, maxHealth)
	if phase ~= "IN_GAME" then return end
	local frac = damage / math.max(1, maxHealth)
	local victimTeam = model:GetAttribute("Team")
	local R = CFG.Reactions
	if isTeamMode() and victimTeam then
		local forTeam = otherTeam(victimTeam)
		bump(forTeam, frac * 4)
		bump(victimTeam, -frac * 1.5)
		local r = frac >= CFG.HeavyHitFraction and R.HeavyHit or R.LightHit
		if math.random() < r.Chance then
			react(forTeam, r.For, 0.8)
			if r.Against then react(victimTeam, r.Against, 0.6) end
		end
	else
		bump("Neutral", frac * 3)
		if frac >= CFG.HeavyHitFraction and math.random() < R.NeutralHeavy.Chance then
			react(nil, R.NeutralHeavy.For, 0.5)
		end
	end
end

local function onKnockdown(model)
	if phase ~= "IN_GAME" then return end
	local victimTeam = model:GetAttribute("Team")
	local R = CFG.Reactions
	if isTeamMode() and victimTeam then
		local forTeam = otherTeam(victimTeam)
		bump(forTeam, 0.12)
		if math.random() < R.Knockdown.Chance then
			react(forTeam, R.Knockdown.For, 0.85)
			react(victimTeam, R.Knockdown.Against, 0.6)
		end
	else
		bump("Neutral", 0.1)
		if math.random() < R.NeutralKnockdown.Chance then
			react(nil, R.NeutralKnockdown.For, 0.6)
		end
	end
end

local function onEliminated(_name, team)
	if phase ~= "IN_GAME" then return end
	local R = CFG.Reactions
	if isTeamMode() and (team == "TeamAlpha" or team == "TeamBeta") then
		local forTeam = otherTeam(team)
		bump(forTeam, 0.45)
		bump(team, -0.2)
		angryUntil[team] = os.clock() + CFG.AngryTime
		react(forTeam, R.Elimination.For, R.Elimination.Chance, true)
		react(team, R.Elimination.Against, R.Elimination.Chance, true)
	else
		bump("Neutral", 0.4)
		react(nil, R.NeutralElimination.For, R.NeutralElimination.Chance, true)
	end
end

local function unwatch(model)
	local conns = watched[model]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		watched[model] = nil
	end
end

local function watchFighter(model)
	if watched[model] or not model:IsA("Model") then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local last = hum.Health
	local conns = {}
	table.insert(conns, hum.HealthChanged:Connect(function(health)
		local d = last - health
		last = health
		if d > 0 then
			onDamage(model, d, hum.MaxHealth)
		end
	end))
	table.insert(conns, model:GetAttributeChangedSignal("CurrentState"):Connect(function()
		if model:GetAttribute("CurrentState") == "Knockback" then
			onKnockdown(model)
		end
	end))
	table.insert(conns, model.AncestryChanged:Connect(function(_, parent)
		if not parent then unwatch(model) end
	end))
	watched[model] = conns
end

local function fighters()
	local list = {}
	local qServer = Workspace:FindFirstChild("QuinServer")
	if qServer then
		for _, m in ipairs(qServer:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- ============================================================================
-- Allegiance
-- ============================================================================

-- Contiguous arcs (sorted by angle round the arena) of about equal row length; the arc nearer a
-- team's fighters backs that team. Kept until resetMatch.
function Crowd.assignTeams(mode)
	buildSections()
	matchMode = mode or matchMode
	for _, s in ipairs(sections) do
		s.team = "Neutral"
		s.part:SetAttribute("CrowdTeam", "Neutral")
	end
	teamsAssigned = true
	if not isTeamMode() or #sections < 2 then return end

	local center = arenaCenter()
	if not center then
		center = Vector3.zero
		for _, s in ipairs(sections) do center += s.center end
		center /= #sections
	end
	local ring = table.clone(sections)
	table.sort(ring, function(a, b)
		return math.atan2(a.center.Z - center.Z, a.center.X - center.X) < math.atan2(b.center.Z - center.Z, b.center.X - center.X)
	end)
	local total = 0
	for _, s in ipairs(ring) do total += s.length end

	-- best split: arc starting at `start`, taking sections until about half the row length
	local bestStart, bestCount, bestErr = 1, 1, math.huge
	for start = 1, #ring do
		local sum = 0
		for count = 1, #ring - 1 do
			sum += ring[((start + count - 2) % #ring) + 1].length
			local err = math.abs(sum - total / 2)
			if err < bestErr then
				bestStart, bestCount, bestErr = start, count, err
			end
		end
	end
	local arcA, arcB = {}, {}
	for i = 0, #ring - 1 do
		local s = ring[((bestStart + i - 1) % #ring) + 1]
		table.insert(i < bestCount and arcA or arcB, s)
	end

	local function centroid(list, key)
		local sum, n = Vector3.zero, 0
		for _, item in ipairs(list) do
			local root = not key and item:FindFirstChild("HumanoidRootPart")
			local p = key and item[key] or (root and root.Position)
			if p then sum += p n += 1 end
		end
		return n > 0 and sum / n or nil
	end
	local alpha, beta = {}, {}
	for _, f in ipairs(fighters()) do
		local t = f:GetAttribute("Team")
		if t == "TeamAlpha" then table.insert(alpha, f) elseif t == "TeamBeta" then table.insert(beta, f) end
	end
	local alphaAt, betaAt = centroid(alpha), centroid(beta)
	local cA = centroid(arcA, "center")
	local aIsAlpha = true
	if alphaAt and betaAt and cA then
		aIsAlpha = (cA - alphaAt).Magnitude <= (cA - betaAt).Magnitude
	end
	for _, s in ipairs(arcA) do s.team = aIsAlpha and "TeamAlpha" or "TeamBeta" end
	for _, s in ipairs(arcB) do s.team = aIsAlpha and "TeamBeta" or "TeamAlpha" end
	for _, s in ipairs(sections) do s.part:SetAttribute("CrowdTeam", s.team) end
	print(string.format("[ArenaCrowd] Allegiance: %d sections TeamAlpha, %d TeamBeta", aIsAlpha and #arcA or #arcB, aIsAlpha and #arcB or #arcA))
end

-- ============================================================================
-- Director: beds, mood layers, chants
-- ============================================================================

local function aliveCounts()
	local alpha, beta, all = 0, 0, 0
	for _, f in ipairs(fighters()) do
		local h = f:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and not f:GetAttribute("IsCostume") then
			all += 1
			local t = f:GetAttribute("Team")
			if t == "TeamAlpha" then alpha += 1 elseif t == "TeamBeta" then beta += 1 end
		end
	end
	return alpha, beta, all
end

local function sectionMood(section, tense, now)
	local M = CFG.Moods
	local team = section.team
	if phase == "WINNER_DETERMINATION" then
		if winnerTeam == "Draw" or winnerTeam == nil then return M.Tense, 0.6 end
		if team == winnerTeam or team == "Neutral" then return M.Celebration, 1.0 end
		return M.Calm, 0.5
	end
	if phase ~= "IN_GAME" then
		local P = CFG.Phases[phase]
		return P and P.Layer, P and P.LayerLevel or 0
	end
	local e = excitement[team] or 0
	if chantTeam and now < chantUntil and (chantTeam == team or chantTeam == "Neutral") then
		return CFG.Chant.Bed, CFG.ChantVolume / CFG.LayerVolume
	end
	if now < (angryUntil[team] or 0) then return M.Angry, 0.8 end
	if tense then return M.Tense, 0.75 end
	if e >= CFG.ExcitedAbove then return M.Excited, 0.4 + 0.6 * e end
	return M.Calm, 0.35 + 0.4 * e
end

local function updateChant(now)
	if phase ~= "IN_GAME" then
		chantTeam = nil
		return
	end
	if nextChantAt == 0 then
		nextChantAt = now + CFG.ChantEvery[1] * 0.5
	end
	if now < nextChantAt then return end
	nextChantAt = now + CFG.ChantEvery[1] + math.random() * (CFG.ChantEvery[2] - CFG.ChantEvery[1])
	if isTeamMode() then
		local a, b = excitement.TeamAlpha + 0.05, excitement.TeamBeta + 0.05
		chantTeam = (math.random() * (a + b) < a) and "TeamAlpha" or "TeamBeta"
	else
		chantTeam = "Neutral"
	end
	chantUntil = now + CFG.ChantLength[1] + math.random() * (CFG.ChantLength[2] - CFG.ChantLength[1])
	react(chantTeam ~= "Neutral" and chantTeam or nil, CFG.Chant.Phrase, 0.5, true)
end

local function directorStep(dt)
	local now = os.clock()
	for team, e in pairs(excitement) do
		local rest = CFG.ExcitementRest
		excitement[team] = e + math.clamp(rest - e, -CFG.ExcitementDecay * dt, CFG.ExcitementDecay * dt)
	end
	updateChant(now)

	local tense = false
	if phase == "IN_GAME" then
		for _, f in ipairs(fighters()) do watchFighter(f) end -- (late spawns, possessed costumes)
		local alpha, beta, all = aliveCounts()
		if isTeamMode() then
			tense = (alpha > 0 and alpha <= CFG.TenseWhenAlive) or (beta > 0 and beta <= CFG.TenseWhenAlive)
		else
			tense = all > 0 and all <= CFG.TenseWhenAlive + 1
		end
	end

	local P = CFG.Phases[phase]
	local bedCat = P and ((tense and P.TenseBed) or P.Bed)
	local bedVol = P and CFG.BedVolume * (P.Level or 1) or 0
	for _, section in ipairs(sections) do
		local layerCat, layerLevel = sectionMood(section, tense, now)
		for _, emitter in ipairs(section.emitters) do
			setLoop(emitter, "bed", bedCat, bedVol)
			if emitter.index % 2 == 1 then
				setLoop(emitter, "layer", layerCat, CFG.LayerVolume * (layerLevel or 0))
			end
		end
	end
end

local function silenceAll(fade)
	if not sections then return end
	for _, section in ipairs(sections) do
		for _, emitter in ipairs(section.emitters) do
			for slot, loop in pairs(emitter.loops) do
				fadeOutAndDestroy(loop.sound, fade or CFG.Crossfade)
				emitter.loops[slot] = nil
			end
		end
	end
end

local function startDirector()
	if directorThread then return end
	directorThread = task.spawn(function()
		local last = os.clock()
		while enabled do
			local now = os.clock()
			local ok, err = pcall(directorStep, now - last)
			if not ok then warn("[ArenaCrowd] director: " .. tostring(err)) end
			-- (readable telemetry for tests and the Studio attribute pane)
			local st = Crowd.getState()
			Workspace:SetAttribute("CrowdFXState", string.format("%s loops=%d shots=%d exA=%.2f exB=%.2f exN=%.2f chant=%s",
				st.Phase, st.Loops, st.OneShots, st.Excitement.TeamAlpha, st.Excitement.TeamBeta, st.Excitement.Neutral, tostring(st.Chant)))
			last = now
			task.wait(0.5)
		end
		directorThread = nil
	end)
end

-- ============================================================================
-- API
-- ============================================================================

function Crowd.setEnabled(on)
	on = on == true
	if on == enabled then return end
	enabled = on
	if on then
		if not library then loadLibrary() end
		buildSections()
		ensureGroup()
		for _, f in ipairs(fighters()) do watchFighter(f) end
		startDirector()
		if (phase == "PRE_GAME" or phase == "IN_GAME") and not teamsAssigned then
			Crowd.assignTeams(matchMode) -- (switched on mid-match)
		end
		print("[ArenaCrowd] Crowd on")
	else
		silenceAll()
		Workspace:SetAttribute("CrowdFXState", "off")
		print("[ArenaCrowd] Crowd off")
	end
end

function Crowd.isEnabled()
	return enabled
end

-- New match: allegiances and moods start fresh
function Crowd.resetMatch(mode)
	matchMode = mode or "TeamBattle"
	teamsAssigned = false
	winnerTeam = nil
	chantTeam, chantUntil, nextChantAt = nil, 0, 0
	for k in pairs(excitement) do
		excitement[k] = CFG.ExcitementRest
		angryUntil[k] = 0
	end
	if sections then
		for _, s in ipairs(sections) do s.team = "Neutral" end
	end
end

function Crowd.setPhase(name)
	phase = name
	if name == "IDLE" then
		Crowd.setEnabled(false)
		Crowd.resetMatch(matchMode)
		return
	end
	if not enabled then return end
	if (name == "PRE_GAME" or name == "IN_GAME") and not teamsAssigned then
		Crowd.assignTeams(matchMode)
	end
	if name == "IN_GAME" then
		for _, f in ipairs(fighters()) do watchFighter(f) end
		nextChantAt = 0
	end
	local P = CFG.Phases[name]
	if P and P.Cue then
		react(nil, P.Cue, P.CueMajor and 1 or 0.8, true)
	end
end

function Crowd.onWinner(team)
	winnerTeam = team
	if not enabled then return end
	local W = CFG.Winner
	if isTeamMode() and (team == "TeamAlpha" or team == "TeamBeta") then
		react(team, W.For, 1, true)
		react(otherTeam(team), W.Against, 1, true)
	elseif team == "Draw" then
		react(nil, W.Draw, 1, true)
	else
		react(nil, W.For, 1, true)
	end
	print(string.format("[ArenaCrowd] Winner %s (mode %s): %d one-shots", tostring(team), matchMode, #activeShots))
end

-- ARIA ducking: the crowd dips with the music
function Crowd.duck(on, t)
	isDucked = on == true
	local g = ensureGroup()
	fadeTo(g, CFG.Volume * (isDucked and CFG.DuckMultiplier or 1), t or 0.4)
end

-- Live mix from the Arena System panel (CROWD MIX sliders). Loops follow on the next director
-- step (1.5 s fade), one-shots from their next play. Values are not saved: once the slider
-- settles the server prints a line to paste into ArenaConfig.CrowdFX.
local LEVEL_KEYS = {
	Volume = { 0, 2 }, BedVolume = { 0, 1.5 }, LayerVolume = { 0, 1.5 }, ChantVolume = { 0, 1.5 },
	ReactVolume = { 0, 1.5 }, MajorVolume = { 0, 2 }, AnthemStemScale = { 0, 2 }, DuckMultiplier = { 0, 1 },
}
local LEVEL_ORDER = { "Volume", "BedVolume", "LayerVolume", "ChantVolume", "ReactVolume", "MajorVolume", "AnthemStemScale", "DuckMultiplier" }

function Crowd.getLevels()
	local levels = {}
	for key in pairs(LEVEL_KEYS) do levels[key] = CFG[key] end
	return levels
end

function Crowd.setLevels(levels)
	if type(levels) ~= "table" then return end
	local changed = false
	for key, range in pairs(LEVEL_KEYS) do
		local v = tonumber(levels[key])
		if v and v == v then
			v = math.clamp(v, range[1], range[2])
			if CFG[key] ~= v then
				CFG[key] = v
				changed = true
			end
		end
	end
	if not changed then return end
	local g = ensureGroup()
	fadeTo(g, CFG.Volume * (isDucked and CFG.DuckMultiplier or 1), 0.2)
	levelsPrintToken += 1
	local token = levelsPrintToken
	task.delay(1.5, function()
		if token ~= levelsPrintToken then return end
		local parts = {}
		for _, key in ipairs(LEVEL_ORDER) do
			table.insert(parts, string.format("%s = %.2f", key, CFG[key]))
		end
		print("[ArenaCrowd] Mix (paste into ArenaConfig.CrowdFX to keep): " .. table.concat(parts, ", "))
	end)
	Workspace:SetAttribute("CrowdFXLevels", game:GetService("HttpService"):JSONEncode(Crowd.getLevels()))
end

-- One attachment per section (its middle) for anthem crowd/drum stems
function Crowd.getStemEmitters()
	buildSections()
	local list = {}
	for _, s in ipairs(sections) do
		table.insert(list, s.stem)
	end
	return list
end

function Crowd.getStemScale()
	return CFG.AnthemStemScale
end

function Crowd.getRollOff()
	return CFG.RollOffMin, CFG.RollOffMax
end

-- Debug/telemetry
function Crowd.getState()
	local loops, teams = 0, {}
	for _, s in ipairs(sections or {}) do
		teams[s.team] = (teams[s.team] or 0) + 1
		for _, e in ipairs(s.emitters) do
			for _ in pairs(e.loops) do loops += 1 end
		end
	end
	return {
		Enabled = enabled, Phase = phase, Mode = matchMode, Loops = loops, OneShots = #activeShots,
		Teams = teams, Excitement = table.clone(excitement), Chant = chantTeam, ChantUntil = chantUntil - os.clock(),
	}
end

-- Eliminations come from DeathState's BindableEvent
local elimEvent = ReplicatedStorage:FindFirstChild("QuinEliminated")
if not elimEvent then
	elimEvent = Instance.new("BindableEvent")
	elimEvent.Name = "QuinEliminated"
	elimEvent.Parent = ReplicatedStorage
end
elimEvent.Event:Connect(onEliminated)

-- Studio test hook: Workspace attribute CrowdDevCommand = "winner <Team|Draw>" | "react <Team|all> <Category>"
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("CrowdDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("CrowdDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("CrowdDevCommand", nil)
		local verb, a, b = cmd:match("^(%S+)%s*(%S*)%s*(%S*)")
		if verb == "winner" then
			Crowd.onWinner(a)
		elseif verb == "react" then
			react(a ~= "all" and a or nil, b, 1, true)
		end
	end)
end

return Crowd
