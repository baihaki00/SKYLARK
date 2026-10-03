--// SocialSystem.lua
-- The Quins' social layer: pack leaders, signals, respect customs and arena events.
--
-- Battlefield event -> Quins perceive it -> interpret it -> behaviour changes -> others perceive
-- that -> the event emerges. Quins never speak: everything reads through movement, facing, head
-- looks and nods, following or refusing, protecting and making space.
--
-- Server only. Ticked for the whole field (CombatConfig.Social.TickRate) from Main. It keeps its
-- social memory in tables and publishes attributes the rest of QuinCore reads:
--   SocialLookAt / SocialLookUntil   head looks at another Quin (client LookController, SOCIAL)
--   NodAt                            server time of a nod (procedural, client LookController)
--   SocialMoveTo / SocialMovePace / SocialMoveUntil   a place to walk to (Idle/Circling/Chase)
--   RespectRole                      Hesitating / Watching / Spectator / Duelist / Honored
--   SocialHoldOff                    a Quin this one must not attack
--   Workspace ArenaEventLevel / ArenaEvent   how notable the battle is right now
-- Later passes register their ticks with SocialSystem.addTicker.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Modules = QuinCore:WaitForChild("Modules")

local SocialSystem = {}

local CFG = CombatConfig.Social or {}
local tickers = {} -- { name = string, fn = function(dt, now) }
local partsLoaded = false
local loopGeneration = 0
local lastBeat = -math.huge -- os.clock() of the loop's last tick

local function serverNow()
	return Workspace:GetServerTimeNow()
end
SocialSystem.now = serverNow

-- The live fighters (QuinServer children with a living Humanoid)
function SocialSystem.fighters()
	local list = {}
	local folder = Workspace:FindFirstChild("QuinServer")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local hum = m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and m:FindFirstChild("HumanoidRootPart") then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- ============================================================================
-- Body language
-- ============================================================================

-- Turn the head to another Quin for a while (the client head tracks it)
function SocialSystem.lookAt(quin, other, seconds)
	if not (quin and other and quin.Parent and other.Parent) then return end
	quin:SetAttribute("SocialLookAt", other.Name)
	quin:SetAttribute("SocialLookUntil", serverNow() + (seconds or CFG.LookTime or 1.2))
end

function SocialSystem.clearLook(quin)
	quin:SetAttribute("SocialLookAt", nil)
	quin:SetAttribute("SocialLookUntil", nil)
end

-- A nod (two quick dips of the head, procedural on the client), optionally after a delay
function SocialSystem.nod(quin, delay)
	if not quin then return end
	local function go()
		if quin.Parent then quin:SetAttribute("NodAt", serverNow()) end
	end
	if delay and delay > 0 then task.delay(delay, go) else go() end
end

-- Look at someone, then nod: "agreed" / "I see you"
function SocialSystem.acknowledge(quin, other, delay)
	task.delay(delay or 0, function()
		SocialSystem.lookAt(quin, other, (CFG.LookTime or 1.2) + (CFG.NodDuration or 0.6))
		SocialSystem.nod(quin, 0.35)
	end)
end

-- ============================================================================
-- Move intents (where a Quin has decided to walk; Idle / Circling / Chase steer there)
-- ============================================================================

function SocialSystem.setMoveIntent(quin, point, pace, seconds)
	quin:SetAttribute("SocialMoveTo", point)
	quin:SetAttribute("SocialMovePace", pace or "walk")
	quin:SetAttribute("SocialMoveUntil", serverNow() + (seconds or 8))
end

function SocialSystem.clearMoveIntent(quin)
	quin:SetAttribute("SocialMoveTo", nil)
	quin:SetAttribute("SocialMovePace", nil)
	quin:SetAttribute("SocialMoveUntil", nil)
end

-- The active move intent: point, speed (studs/s). Cleared once expired or reached.
function SocialSystem.getMoveIntent(quin, rootPart)
	local point = quin:GetAttribute("SocialMoveTo")
	if typeof(point) ~= "Vector3" then return nil end
	if serverNow() > (quin:GetAttribute("SocialMoveUntil") or 0) then
		SocialSystem.clearMoveIntent(quin)
		return nil
	end
	if rootPart then
		local flat = Vector3.new(point.X - rootPart.Position.X, 0, point.Z - rootPart.Position.Z)
		if flat.Magnitude <= (CFG.ArriveDistance or 4) then
			SocialSystem.clearMoveIntent(quin)
			return nil
		end
	end
	local paces = CFG.Paces or {}
	return point, paces[quin:GetAttribute("SocialMovePace") or "walk"] or 12
end

-- For states: walk toward the move intent if there is one. True when it steered this tick.
function SocialSystem.followMoveIntent(quin, humanoid, rootPart, dt)
	local point, speed = SocialSystem.getMoveIntent(quin, rootPart)
	if not point then return false end
	-- (walking: the locomotion owns facing, not a watcher's gyro)
	local gyro = rootPart:FindFirstChild("IdleGyro")
	if gyro then gyro:Destroy() end
	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	local GaitModule = require(Modules:WaitForChild("GaitModule"))
	LocomotionModule.steer(quin, humanoid, rootPart, Vector3.new(point.X, rootPart.Position.Y, point.Z), speed, dt or 0.1)
	GaitModule.update(humanoid, rootPart, dt or 0.1)
	return true
end

-- For a Quin that has stepped back and is watching (spectators, the hesitating, the reserved):
-- it settles to a stop through the gait into its idle stance (not frozen mid-stride), and turns
-- its body, unhurried, toward what it is watching (SocialWatchPoint).
function SocialSystem.watch(quin, humanoid, rootPart, dt)
	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	local GaitModule = require(Modules:WaitForChild("GaitModule"))
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	LocomotionModule.brake(quin, humanoid, rootPart, dt or 0.1)
	GaitModule.update(humanoid, rootPart, dt or 0.1)
	AnimationModule.ensureBaseIdle(humanoid)
	local point = quin:GetAttribute("SocialWatchPoint")
	if typeof(point) ~= "Vector3" then return end
	local flat = Vector3.new(point.X - rootPart.Position.X, 0, point.Z - rootPart.Position.Z)
	if flat.Magnitude < 1 then return end
	local gyro = rootPart:FindFirstChild("IdleGyro") -- (IdleState.exit removes it)
	if not gyro then
		gyro = Instance.new("AlignOrientation")
		gyro.Name = "IdleGyro"
		gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
		local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
		att.Name = "RootAttachment"
		gyro.Attachment0 = att
		gyro.RigidityEnabled = false
		gyro.Responsiveness = CFG.WatchTurnResponsiveness or 6
		gyro.MaxTorque = 100000
		gyro.MaxAngularVelocity = CFG.WatchTurnRate or 3
		gyro.CFrame = rootPart.CFrame
		gyro.Parent = rootPart
		humanoid.AutoRotate = false
	end
	gyro.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
end

-- A respect-custom standoff: the gap the duellist keeps while circling (nil when none)
function SocialSystem.standoffGap(quin)
	return quin and quin:GetAttribute("SocialStandoff") or nil
end

-- ============================================================================
-- Animation slots (AnimationConfig.Registry.Social, blank until the owner adds clips)
-- ============================================================================

-- Plays the slot if it has a clip; nil when blank (callers fall back to stillness / head looks)
function SocialSystem.playSlot(humanoid, slotName, speed)
	local ok, AnimationConfig = pcall(require, QuinCore:WaitForChild("AnimationConfig"))
	local entry = ok and AnimationConfig.Registry and AnimationConfig.Registry.Social and AnimationConfig.Registry.Social[slotName]
	if not entry or not entry.id or entry.id == "" then return nil end
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	return AnimationModule.playConfig(humanoid, "Social." .. slotName, speed or 1.0)
end

-- ============================================================================
-- Respect custom helpers (filled in by the respect-custom pass)
-- ============================================================================

function SocialSystem.respectRole(quin)
	return quin and quin:GetAttribute("RespectRole") or nil
end

-- A respect-custom duel is on and this Quin is one of its duelists
function SocialSystem.isDuelist(quin)
	return SocialSystem.respectRole(quin) == "Duelist"
end

-- Spectators of a respect custom (they watch; they neither hit nor get hit)
function SocialSystem.isSpectator(quin)
	local role = SocialSystem.respectRole(quin)
	return role == "Spectator" or role == "Watching"
end

-- Stepped back from the fight for the respect custom: hesitating, watching, spectating, or the
-- honoured survivor waiting for its fight. Such a Quin picks no target and its states hand it to
-- Idle, which walks it where it decided to go (target selection otherwise falls back to the
-- nearest enemy, and in an N-v-1 that is the survivor).
local STANDS_DOWN = { Hesitating = true, Watching = true, Spectator = true, Honored = true }
function SocialSystem.standsDown(quin)
	return quin ~= nil and STANDS_DOWN[quin:GetAttribute("RespectRole") or ""] == true
end

-- Keeps a duelist on the ceremony space (no-op until a ceremony exists)
function SocialSystem.constrainToCeremony(rootPart)
	local hook = SocialSystem.ceremonyConstraint
	if hook then hook(rootPart) end
end

-- ============================================================================
-- Arena event level (Normal ... Historic), for the crowd, ARIA, the screen and the HUD
-- ============================================================================

local eventSignal = ReplicatedStorage:FindFirstChild("ArenaSocialEvent")
if not eventSignal then
	eventSignal = Instance.new("BindableEvent")
	eventSignal.Name = "ArenaSocialEvent"
	eventSignal.Parent = ReplicatedStorage
end
SocialSystem.EventSignal = eventSignal

local function levelIndex(name)
	for i, n in ipairs(CFG.EventLevels or {}) do
		if n == name then return i end
	end
	return 1
end

-- Raise the arena event (never lowers it; reset() returns to Normal). data: free-form table
function SocialSystem.raiseEvent(levelName, data)
	local isLevel = false
	for _, n in ipairs(CFG.EventLevels or {}) do
		if n == levelName then isLevel = true break end
	end
	if not isLevel then
		-- a plain signal (e.g. RespectCustomEnd): no level change
		eventSignal:Fire(levelName, data or {})
		return true
	end
	local current = Workspace:GetAttribute("ArenaEventLevel") or "Normal"
	if levelIndex(levelName) < levelIndex(current) then return false end
	Workspace:SetAttribute("ArenaEventLevel", levelName)
	Workspace:SetAttribute("ArenaEvent", data and data.text or levelName)
	eventSignal:Fire(levelName, data or {})
	print(string.format("[Social] Arena event: %s%s", levelName, data and data.text and (" - " .. data.text) or ""))
	return true
end

-- ============================================================================
-- Tick
-- ============================================================================

-- fn(dt, now) runs every tick; reset() runs when the fighters are cleaned up (new match)
function SocialSystem.addTicker(name, fn, reset)
	table.insert(tickers, { name = name, fn = fn, reset = reset })
end

-- What the social layer adds to a candidate's targeting utility (TargetingModule term 13):
-- huge negative for a Quin this one holds off (respect custom), plus followed leader signals
local targetTerms = {} -- extra targeting terms from the parts (showdown, respect custom)

function SocialSystem.addTargetTerm(fn)
	table.insert(targetTerms, fn)
end

function SocialSystem.targetScore(quin, candidate)
	if quin:GetAttribute("SocialHoldOff") == candidate.Name then
		return -1e6
	end
	local score = 0
	local leaderScore = SocialSystem.leaderTargetScore
	if leaderScore then score += leaderScore(quin, candidate) end
	for _, term in ipairs(targetTerms) do
		score += term(quin, candidate)
	end
	return score
end

function SocialSystem.reset()
	Workspace:SetAttribute("ArenaEventLevel", "Normal")
	Workspace:SetAttribute("ArenaEvent", nil)
	for _, t in ipairs(tickers) do
		if t.reset then pcall(t.reset) end
	end
end

-- Starts the social tick (ServerScriptService.Server at game start; each Quin's Main calls it
-- too). A thread dies with the script that started it, and Main is cloned into every Quin: the
-- loop started by the first Quin's Main died when that Quin was cleaned up between matches.
-- So start() restarts a loop that has stopped beating, and only the newest loop runs.
function SocialSystem.start()
	if CFG.Enabled == false then return end
	if os.clock() - lastBeat < 2 then return end -- running
	Workspace:SetAttribute("ArenaEventLevel", Workspace:GetAttribute("ArenaEventLevel") or "Normal")
	-- the parts of the social layer register their tickers when loaded
	if not partsLoaded then
		partsLoaded = true
		for _, partName in ipairs(CFG.Parts or {}) do
			local part = Modules:FindFirstChild(partName)
			local ok, err = part and pcall(require, part)
			if not ok then warn("[Social] could not load " .. partName .. ": " .. tostring(err)) end
		end
	end
	loopGeneration += 1
	local generation = loopGeneration
	lastBeat = os.clock()
	task.spawn(function()
		local last = os.clock()
		local ticks = 0
		while generation == loopGeneration do
			lastBeat = os.clock()
			task.wait(1 / (CFG.TickRate or 4))
			local now = os.clock()
			local dt = now - last
			last = now
			ticks += 1
			for _, t in ipairs(tickers) do
				local ok, err = pcall(t.fn, dt, now)
				if not ok then
					warn("[Social] " .. t.name .. ": " .. tostring(err))
					Workspace:SetAttribute("SocialLastError", t.name .. ": " .. tostring(err))
				end
			end
			-- (telemetry: the social tick is alive, and how many parts it runs)
			if ticks % 8 == 0 then
				Workspace:SetAttribute("SocialTicks", ticks .. " x" .. #tickers)
			end
		end
	end)
end

-- Studio test hook: Workspace attribute SocialDevCommand = "nod <quin>" | "look <quin> <other>"
if game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer() then
	Workspace:GetAttributeChangedSignal("SocialDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("SocialDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("SocialDevCommand", nil)
		local verb, a, b = cmd:match("^(%S+)%s*(%S*)%s*(%S*)")
		local folder = Workspace:FindFirstChild("QuinServer")
		local qa = folder and folder:FindFirstChild(a)
		local qb = folder and folder:FindFirstChild(b)
		if verb == "nod" and qa then
			SocialSystem.nod(qa)
		elseif verb == "look" and qa and qb then
			SocialSystem.lookAt(qa, qb, 3)
		elseif verb == "ack" and qa and qb then
			SocialSystem.acknowledge(qa, qb)
		end
	end)
end

return SocialSystem
