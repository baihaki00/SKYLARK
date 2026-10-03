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
local started = false

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
	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	local GaitModule = require(Modules:WaitForChild("GaitModule"))
	LocomotionModule.steer(quin, humanoid, rootPart, Vector3.new(point.X, rootPart.Position.Y, point.Z), speed, dt or 0.1)
	GaitModule.update(humanoid, rootPart, dt or 0.1)
	return true
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

function SocialSystem.addTicker(name, fn)
	table.insert(tickers, { name = name, fn = fn })
end

function SocialSystem.reset()
	Workspace:SetAttribute("ArenaEventLevel", "Normal")
	Workspace:SetAttribute("ArenaEvent", nil)
	for _, t in ipairs(tickers) do
		if t.reset then pcall(t.reset) end
	end
end

function SocialSystem.start()
	if started or CFG.Enabled == false then return end
	started = true
	Workspace:SetAttribute("ArenaEventLevel", Workspace:GetAttribute("ArenaEventLevel") or "Normal")
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1 / (CFG.TickRate or 4))
			local now = os.clock()
			local dt = now - last
			last = now
			for _, t in ipairs(tickers) do
				local ok, err = pcall(t.fn, dt, now)
				if not ok then
					warn("[Social] " .. t.name .. ": " .. tostring(err))
				end
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
