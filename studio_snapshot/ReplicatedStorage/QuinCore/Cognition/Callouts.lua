--// Cognition.Callouts
-- Shared team knowledge, out loud (Lantern Siege design, brain step 1; works in every mode).
-- A Quin that spots an enemy the team has not had eyes on for a while may call it out. Allies
-- within earshot of the shout take it as a second-hand belief (a "report" track that fades like
-- any memory) and may glance where it was called. Nothing is telepathy: a call has a place, a
-- time and a range; a Quin too far away never hears it.
-- Who calls is a leaning: aware Quins call more, nobody calls every time, and an enemy a teammate
-- called a moment ago is not called again.
-- Neutral (layer off): nobody calls and nobody hears; Memory's quiet sharing between Quins
-- standing close together still works.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local Workspace = game:GetService("Workspace")

local Callouts = {}

local QUIET_STATES = { Knockback = true, Recovery = true, Death = true }
-- Pointing (owner 2026-10-28: "quin are mute creature, they cant really talk"). The caller holds
-- an arm toward the enemy (LookController draws it); an ally takes the call in only if it sees
-- the caller while the arm is up, so a Quin in a brawl facing away misses it. A busy one that
-- does see it often does not register it. It then answers with its body: a look at the caller,
-- a look where it points, then a nod (on it) or a shake of the head (not worth it).
-- Workspace PointOff: the old shout, heard by everyone within CalloutRange.
local NO_POINT_STATES = { Fight = true, Knockback = true, Recovery = true, Death = true, ProjectileJump = true, MidAirClash = true, Special = true }
local BUSY_STATES = { Fight = true, Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Special = true }

local function pointing()
	return Workspace:GetAttribute("PointOff") ~= true
end

-- Studio labels over a head (Workspace PointDebug): what it pointed at, or what it made of a point
function Callouts.debugTag(model, text, color)
	if Workspace:GetAttribute("PointDebug") ~= true then return end
	if (Workspace:GetAttribute("DebugScopeQuin") or model.Name) ~= model.Name then return end -- (DebugSwitches scope: Workspace DebugScopeQuin, unset = every Quin)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local old = root:FindFirstChild("PointTag")
	if old then old:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PointTag"
	gui.Size = UDim2.fromOffset(220, 28)
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = root
	game:GetService("Debris"):AddItem(gui, 2.2)
end

local calls = {} -- team -> { { id, caller, enemy, position, velocity, from, at } }, newest last
local nextId = 0

local function cfg(key, default)
	local v = CombatConfig.Cognition[key]
	if v == nil then return default end
	return v
end

local function teamList(team)
	local list = calls[team]
	if not list then
		list = {}
		calls[team] = list
	end
	return list
end

local function prune(list, now)
	local keep = cfg("CalloutKeep", 3)
	while list[1] and now - list[1].at > keep do
		table.remove(list, 1)
	end
end

-- Did a teammate call this enemy a moment ago?
local function recentlyCalled(list, enemy, now)
	for i = #list, 1, -1 do
		local call = list[i]
		if now - call.at > cfg("CalloutTeamRepeat", 4) then break end
		if call.enemy == enemy then return true end
	end
	return false
end

-- fresh: { percept } the enemies this Quin sees itself that the team has not had eyes on for a
-- while (Memory decides). Calls at most one, the nearest, now and then.
function Callouts.maybeCall(board, quinModel, rootPart, fresh, now)
	if #fresh == 0 or now < (board.nextCallout or 0) then return end
	if QUIET_STATES[quinModel:GetAttribute("CurrentState") or ""] then return end
	local point = pointing()
	if point and (NO_POINT_STATES[quinModel:GetAttribute("CurrentState") or ""] or quinModel:GetAttribute("Attacking") == true) then
		return -- (both arms are busy)
	end
	local team = quinModel:GetAttribute("Team") or "None"
	local list = teamList(team)
	prune(list, now)

	table.sort(fresh, function(a, b) return a.distance < b.distance end)
	for _, percept in ipairs(fresh) do
		local inFront = true
		if point then
			local off = Vector3.new(percept.position.X - rootPart.Position.X, 0, percept.position.Z - rootPart.Position.Z)
			local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
			inFront = off.Magnitude < 0.5 or look.Magnitude < 0.01
				or look.Unit:Dot(off.Unit) >= math.cos(math.rad(cfg("PointMaxAngle", 115)))
		end
		if inFront and point and not recentlyCalled(list, percept.model, now) and not Callouts.hasAudience(quinModel, rootPart) then
			-- nobody it can see is looking its way: a point would be for no one (owner 2026-10-28)
			board.nextCallout = now + 0.6
			return
		end
		if inFront and not recentlyCalled(list, percept.model, now) then
			local awareness = Pers.get(quinModel, "Awareness")
			local chance = cfg("CalloutChanceBase", 0.35) + cfg("CalloutChanceAwareness", 0.5) * awareness
			board.nextCallout = now + cfg("CalloutCooldown", 2.5)
			if math.random() >= chance then return end
			nextId += 1
			table.insert(list, {
				id = nextId, caller = quinModel, enemy = percept.model, position = percept.position,
				velocity = percept.velocity, healthRatio = percept.healthRatio, energyRatio = percept.energyRatio,
				from = rootPart.Position, at = now,
			})
			board.called = { enemy = percept.model, at = now }
			quinModel:SetAttribute("CalloutOf", percept.model.Name)
			quinModel:SetAttribute("CalloutAt", GameClock.serverNow())
			if point then
				quinModel:SetAttribute("PointAtName", percept.model.Name)
				quinModel:SetAttribute("PointAtPos", nil)
				quinModel:SetAttribute("PointAt", GameClock.serverNow()) -- (LookController raises the arm)
				Callouts.debugTag(quinModel, "point: " .. percept.model.Name, Color3.fromRGB(255, 230, 120))
			end
			return
		end
	end
end

-- Take in every call from this Quin's team made since it last listened, within earshot of where
-- it was shouted. learn(call) stores it as a belief; returns the newest call heard, or nil.
-- Does this Quin see another's gesture (in front of it, nothing in between)? Also used for a
-- pack leader's points (SocialLeaders).
function Callouts.sees(quinModel, rootPart, other)
	local callerRoot = other.Parent and other:FindFirstChild("HumanoidRootPart")
	if not callerRoot then return false end
	local cog = CombatConfig.Cognition
	local offset = callerRoot.Position - rootPart.Position
	if offset.Magnitude > math.min(cfg("PointSeeRange", 80), cog.VisionRange or 260) then return false end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flat.Magnitude > 1 and look.Magnitude > 0.01
		and look.Unit:Dot(flat.Unit) < math.cos(math.rad(cfg("PointSeeHalfAngle", 60))) then
		return false
	end
	return SpatialModule.checkLineOfSight(SpatialModule.getEyePosition(rootPart), SpatialModule.getEyePosition(callerRoot), { quinModel, other })
end
-- Does this Quin know someone would see it point: an ally it can see itself (in its own sight
-- cone, near enough) that is facing it with nothing in between. accept(ally) narrows who counts
-- (a leader: its followers).
function Callouts.hasAudience(quinModel, rootPart, accept)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return false end
	local team = quinModel:GetAttribute("Team") or "None"
	local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	local cone = math.cos(math.rad(CombatConfig.Cognition.VisionHalfAngle or 100))
	for _, m in ipairs(folder:GetChildren()) do
		if m ~= quinModel and (m:GetAttribute("Team") or "None") == team and (not accept or accept(m)) then
			local mRoot = m:FindFirstChild("HumanoidRootPart")
			local hum = m:FindFirstChildOfClass("Humanoid")
			if mRoot and hum and hum.Health > 0 then
				local off = Vector3.new(mRoot.Position.X - rootPart.Position.X, 0, mRoot.Position.Z - rootPart.Position.Z)
				if off.Magnitude <= cfg("PointSeeRange", 80) and (off.Magnitude < 1 or look.Magnitude < 0.01 or look.Unit:Dot(off.Unit) >= cone)
					and Callouts.sees(m, mRoot, quinModel) then
					return true
				end
			end
		end
	end
	return false
end

local function seesCaller(quinModel, rootPart, call)
	return Callouts.sees(quinModel, rootPart, call.caller)
end

-- What it makes of a point it saw: go after that enemy, or not. A leaning (temperament, what it
-- is doing, how far, how hurt the enemy is), never a rule. Returns go, why.
-- The watcher's whole reaction to a point it saw, as a chain in time:
--   notice (a beat) -> head to the pointer -> head to where it points -> thinks -> answers:
--   turns back to the pointer then nods / shakes, or nods straight away still looking there.
-- aim: a Quin or a place. quick (0..1, e.g. trust in a leader) shortens the thinking; so does
-- an impulsive temperament. onAnswer() runs at the answer. Used by callouts, pack leaders and
-- the smoke test, so the chain is the same everywhere.
local function lookAtThing(quin, thing, seconds)
	local serverNow = GameClock.serverNow()
	if typeof(thing) == "Instance" then
		quin:SetAttribute("SocialLookAt", thing.Name)
		quin:SetAttribute("SocialLookUntil", serverNow + seconds)
	elseif typeof(thing) == "Vector3" then
		quin:SetAttribute("SocialLookUntil", serverNow) -- (a place: the social look would win)
		quin:SetAttribute("LookPoint", thing)
		quin:SetAttribute("LookUntil", serverNow + seconds)
	end
end

function Callouts.react(watcher, pointer, aim, go, label, onAnswer, quick)
	local reacting = watcher:GetAttribute("PointReactUntil")
	if reacting and reacting > GameClock.serverNow() then return false end -- (one at a time)
	local function r(a, b) return a + math.random() * (b - a) end
	local notice = r(cfg("PointNoticeMin", 0.1), cfg("PointNoticeMax", 0.3))
	local onPointer = cfg("PointLookPointer", 0.4) * r(0.85, 1.2)
	local onAim = cfg("PointLookAim", 0.5) * r(0.85, 1.2)
	local impulsive = Pers.get(watcher, "Aggression")
	local think = r(cfg("PointThinkMin", 0.3), cfg("PointThinkMax", 0.8)) * (1.25 - 0.5 * impulsive) * (1 - 0.3 * (quick or 0))
	local back = math.random() < cfg("PointBackToPointer", 0.5)
	local total = notice + onPointer + onAim + think + (back and 0.3 or 0) + 0.6
	watcher:SetAttribute("PointReactUntil", GameClock.serverNow() + total)
	task.spawn(function()
		GameClock.wait(notice)
		if not (watcher.Parent and pointer.Parent) then return end
		Callouts.debugTag(watcher, "? " .. pointer.Name, Color3.fromRGB(200, 220, 255))
		lookAtThing(watcher, pointer, onPointer)
		GameClock.wait(onPointer)
		if not watcher.Parent then return end
		if typeof(aim) ~= "Instance" or aim.Parent then
			lookAtThing(watcher, aim, onAim + think + (back and 0.05 or 0.7))
		end
		GameClock.wait(onAim + think)
		if not watcher.Parent then return end
		if back and pointer.Parent then
			lookAtThing(watcher, pointer, 0.9)
			GameClock.wait(0.3) -- (the head gets there before the nod)
		end
		watcher:SetAttribute(go and "NodAt" or "ShakeAt", GameClock.serverNow())
		Callouts.debugTag(watcher, label, go and Color3.fromRGB(140, 255, 140) or Color3.fromRGB(255, 150, 150))
		if onAnswer then onAnswer() end
	end)
	return true
end

function Callouts.decide(quinModel, rootPart, board, call)
	local state = quinModel:GetAttribute("CurrentState") or ""
	local target = quinModel:GetAttribute("CurrentTarget")
	if target == call.enemy.Name then return true, "already on it" end
	local lean = ({ Idle = 0.7, Chase = 0.3, Circling = 0.35, Retreat = 0.05, Fight = 0.1 })[state] or 0.25
	local aggression = Pers.get(quinModel, "Aggression")
	lean += 0.4 * (aggression - 0.5) + 0.15 * (Pers.get(quinModel, "Awareness") - 0.5)
	local far = (call.position - rootPart.Position).Magnitude > 140
	if far then lean -= 0.2 end
	local hurt = (call.healthRatio or 1) < 0.35
	if hurt then lean += 0.25 end
	local busyWith = nil
	for _, contact in ipairs(board.contacts and board.contacts.enemies or {}) do
		if contact.model.Name == target and contact.distance < 25 then busyWith = target break end
	end
	if busyWith then lean -= 0.25 end
	local post = quinModel:GetAttribute("ObjectiveFace") ~= nil
	if post then lean -= 0.3 end
	local go = math.random() < math.clamp(lean, 0.03, 0.95)
	local why
	if go then
		why = hurt and "easy pick" or state == "Idle" and "free" or aggression > 0.65 and "eager" or "why not"
	else
		why = post and "holding post" or busyWith and ("busy with " .. busyWith) or state == "Retreat" and "getting away"
			or BUSY_STATES[state] and "mid-fight" or far and "too far" or "not worth it"
	end
	return go, why
end

function Callouts.listen(board, quinModel, rootPart, now, learn)
	local team = quinModel:GetAttribute("Team") or "None"
	local list = calls[team]
	if not list then return nil end
	if pointing() then
		-- it takes in a call only by seeing the arm up, at any moment while it is up
		board.seenCalls = board.seenCalls or {}
		local duration = cfg("PointDuration", 1.1)
		local state = quinModel:GetAttribute("CurrentState") or ""
		local busy = BUSY_STATES[state] or quinModel:GetAttribute("Attacking") == true
		local saw = nil
		for _, call in ipairs(list) do
			if not board.seenCalls[call.id] and call.caller ~= quinModel and call.enemy.Parent
				and now <= call.at + duration and seesCaller(quinModel, rootPart, call) then
				board.seenCalls[call.id] = true
				local notice = not busy or math.random() < cfg("PointBusyNotice", 0.15) + cfg("PointBusyNoticeAwareness", 0.4) * Pers.get(quinModel, "Awareness")
				if notice then
					if learn(call) then
						quinModel:SetAttribute("HeardCalloutOf", call.enemy.Name)
						quinModel:SetAttribute("HeardCalloutFrom", call.caller.Name)
						quinModel:SetAttribute("HeardCalloutAt", GameClock.serverNow())
					end
					saw = call
				end
			end
		end
		for id in pairs(board.seenCalls) do
			if not list[1] or id < list[1].id then board.seenCalls[id] = nil end
		end
		if saw then
			local go, why = Callouts.decide(quinModel, rootPart, board, saw)
			local enemy = saw.enemy
			Callouts.react(quinModel, saw.caller, enemy, go, (go and "on it: " or "nah: ") .. why, function()
				quinModel:SetAttribute("PointAnswer", (go and "on it: " or "nah: ") .. why)
				quinModel:SetAttribute("PointAnswerAt", GameClock.serverNow())
				if go and enemy.Parent and quinModel:GetAttribute("CurrentTarget") ~= enemy.Name then
					require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule")).setTarget(quinModel, enemy, "Pointed")
				end
			end)
		end
		return saw
	end
	local lastId = board.lastCallId or 0
	local range = cfg("CalloutRange", 110)
	local heard = nil
	for _, call in ipairs(list) do
		if call.id > lastId then
			lastId = call.id
			if call.caller ~= quinModel and call.enemy.Parent and (call.from - rootPart.Position).Magnitude <= range then
				if learn(call) then heard = call end
			end
		end
	end
	board.lastCallId = lastId
	if heard then
		board.heard = { from = heard.caller, enemy = heard.enemy, at = now }
		quinModel:SetAttribute("HeardCalloutOf", heard.enemy.Name)
		quinModel:SetAttribute("HeardCalloutFrom", heard.caller.Name)
		quinModel:SetAttribute("HeardCalloutAt", GameClock.serverNow())
	end
	return heard
end

return Callouts
