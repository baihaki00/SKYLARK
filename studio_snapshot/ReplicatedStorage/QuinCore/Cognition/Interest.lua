--// Cognition.Interest
-- What catches a Quin's eye beyond its own fight (owner 2026-10-28, movement step 6: "points of
-- interest" come from what it senses, not from how far away they are). Built from this tick's
-- percepts, so a Quin only finds interesting what it saw or heard:
--   brawl   three or more Quins fighting close together (an enemy among them seen or heard)
--   leader  a pack leader in a fight, seen
--   loud    a loud moment (LoudUntil: a slam), heard
-- Fights it is part of (its own target, Quins after it, itself) are its business, not interest.
-- The pick holds until the event ends or a clearly bigger one appears (no flicking between two).
-- It gets used to an event: after a few seconds of the same one it is old news (in a 16v16
-- some brawl is always on; without this one was "interesting" 83% of the time). An event is
-- the same event while one of its Quins is still in it, wherever it drifts.
-- How strongly it is drawn is a leaning: aware Quins notice more, aggressive Quins are pulled
-- by fights. Published for probes as InterestKind / InterestPos; Workspace InterestDebug shows a
-- label. Workspace or Quin InterestOff: nothing is noticed (as before this layer).
-- What it does with it (a glance now; curving toward / round it next) is up to the readers.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Pers = require(QuinCore:WaitForChild("Modules"):WaitForChild("Pers"))

local Interest = {}

local FIGHTING = { Fight = true, Knockback = true, Recovery = true, MidAirClash = true, Special = true }
local ENGAGED = { Fight = true, Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Special = true }
local THINK_EVERY = 0.4  -- seconds between looks at the scene
local BRAWL_RADIUS = 16  -- studs: Quins this close while fighting are one brawl
local HOLD_GONE = 1.5    -- seconds an event may vanish before the interest drops
local SWITCH_RATIO = 1.5 -- a new event must be this much more interesting to take over


-- Tuning: CombatConfig.Cognition.<name>, or live in a test via a Workspace attribute of the
-- same name (e.g. InterestMinScore)
local function cfg(name, default)
	local live = Workspace:GetAttribute(name)
	if type(live) == "number" then return live end
	local c = CombatConfig.Cognition or {}
	local v = c[name]
	if v == nil then return default end
	return v
end

function Interest.off(quinModel)
	return Workspace:GetAttribute("InterestOff") == true or quinModel:GetAttribute("InterestOff") == true
end

local function tag(quinModel, text, color)
	if Workspace:GetAttribute("InterestDebug") ~= true then return end
	local root = quinModel:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local old = root:FindFirstChild("InterestTag")
	if old then old:Destroy() end
	if not text then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "InterestTag"
	gui.Size = UDim2.fromOffset(200, 24)
	gui.StudsOffset = Vector3.new(0, 9.5, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = root
end

-- The events this Quin can sense right now, each { kind, pos, size, score, members }
local function events(quinModel, percepts)
	local myName = quinModel.Name
	local myTarget = quinModel:GetAttribute("CurrentTarget") or quinModel:GetAttribute("TargetQuin")
	local fighting = {}
	local found = {}
	for _, p in ipairs(percepts) do
		local m = p.model
		local state = m:GetAttribute("CurrentState") or ""
		local mine = m.Name == myTarget or m:GetAttribute("CurrentTarget") == myName
		if not mine and (FIGHTING[state] or m:GetAttribute("Attacking") == true) then
			table.insert(fighting, p)
		end
		local sensed = p.channel == "sight" or p.channel == "hearing"
		if not mine and p.channel == "hearing" and (m:GetAttribute("LoudUntil") or 0) > Workspace:GetServerTimeNow() then
			table.insert(found, { kind = "loud", pos = p.position, size = 1, score = 60, members = { m } })
		end
		if not mine and p.channel == "sight" and m:GetAttribute("SocialRole") == "Leader" and FIGHTING[state] then
			table.insert(found, { kind = "leader", pos = p.position, size = 1, score = 45, members = { m } })
		end
		p.sensedForInterest = sensed or (p.isAlly and p.hasLineOfSight == true)
	end
	-- brawls: fighting Quins near each other, grown from each unclaimed one
	local claimed = {}
	for i, seed in ipairs(fighting) do
		if not claimed[i] then
			claimed[i] = true
			local group, sum, enemySensed = { seed }, seed.position, (not seed.isAlly) and seed.sensedForInterest
			local k = 1
			while k <= #group do
				local a = group[k]
				for j, other in ipairs(fighting) do
					if not claimed[j] and (other.position - a.position).Magnitude <= BRAWL_RADIUS then
						claimed[j] = true
						table.insert(group, other)
						sum += other.position
						if not other.isAlly and other.sensedForInterest then enemySensed = true end
					end
				end
				k += 1
			end
			if #group >= cfg("InterestBrawlMin", 3) and enemySensed then
				local members = {}
				for _, g in ipairs(group) do table.insert(members, g.model) end
				table.insert(found, { kind = "brawl", pos = sum / #group, size = #group, score = 20 * #group, members = members })
			end
		end
	end
	return found
end

-- Run once per reasoning tick (Cognition.update); keeps board.interest
function Interest.update(board, quinModel, rootPart, now)
	if Interest.off(quinModel) then
		if board.interest then
			board.interest = nil
			quinModel:SetAttribute("InterestKind", nil)
			quinModel:SetAttribute("InterestPos", nil)
			tag(quinModel, nil)
		end
		return nil
	end
	if now < (board.interestNext or 0) then return board.interest end
	board.interestNext = now + THINK_EVERY

	local aware = Pers.get(quinModel, "Awareness")
	local aggression = Pers.get(quinModel, "Aggression")
	local found = events(quinModel, board.percepts or {})
	for _, e in ipairs(found) do
		local score = e.score * (0.6 + 0.6 * aware)
		if e.kind ~= "loud" then score *= 0.7 + 0.6 * aggression end
		e.score = score
	end

	-- old news: events with a Quin it already got used to
	local old = board.interestOld or {}
	board.interestOld = old
	for m, untilT in pairs(old) do
		if now > untilT or not m.Parent then old[m] = nil end
	end
	local function oldNews(e)
		for _, m in ipairs(e.members) do
			if old[m] then return true end
		end
		return false
	end
	local function shares(e, members)
		for _, m in ipairs(e.members) do
			if members[m] then return true end
		end
		return false
	end

	local cur = board.interest
	local same = nil
	local fresh, freshScore = nil, 0
	for _, e in ipairs(found) do
		if cur and e.kind == cur.kind and shares(e, cur.memberSet) then
			if not same or e.score > same.score then same = e end
		elseif not oldNews(e) and e.score > freshScore then
			fresh, freshScore = e, e.score
		end
	end
	local function setOf(members)
		local set = {}
		for _, m in ipairs(members) do set[m] = true end
		return set
	end
	if cur and not same and cur.kind == "brawl" then
		-- once noticed, a brawl is followed through its Quins, seen right now or not: one that
		-- turns its head away does not forget the fight (9 of 10 interests ended that way)
		local live, sum = {}, Vector3.zero
		for m in pairs(cur.memberSet) do
			local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
			local root = m.Parent and m:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and (FIGHTING[m:GetAttribute("CurrentState") or ""] or m:GetAttribute("Attacking") == true) then
				table.insert(live, m)
				sum += root.Position
			end
		end
		if #live >= 2 then
			same = { kind = "brawl", pos = sum / #live, size = #live, score = cur.raw or cur.score, members = live }
		end
	end
	if cur then
		if same then
			-- the same event still going: follow it (it moves as the fight moves)
			cur.pos, cur.size, cur.lastSeen = same.pos, same.size, now
			cur.memberSet = setOf(same.members)
			cur.raw = same.score
			cur.score = same.score * 0.5 ^ ((now - cur.since) / cfg("InterestUsedTo", 6))
		end
		if cur.score < cfg("InterestMinScore", 85) * cfg("InterestLetGo", 0.5) then
			-- got used to it: old news for a while, and a pause before anything else catches its eye
			for m in pairs(cur.memberSet) do old[m] = now + cfg("InterestRemember", 12) end
			board.interestRestUntil = now + cfg("InterestRest", 5) + math.random() * cfg("InterestRestSpan", 5) * (1 - aware)
			quinModel:SetAttribute("InterestEndWhy", "used to it")
			cur = nil
		elseif fresh and freshScore >= (cur.raw or cur.score) * SWITCH_RATIO then -- (against how big it is, not how used to it it is)
			for m in pairs(cur.memberSet) do old[m] = now + cfg("InterestRemember", 12) * 0.5 end
			quinModel:SetAttribute("InterestEndWhy", "bigger")
			cur = nil -- a bigger one takes over below
		elseif not same and now - cur.lastSeen > HOLD_GONE then
			board.interestRestUntil = now + cfg("InterestRest", 5) * 0.5
			quinModel:SetAttribute("InterestEndWhy", "over")
			cur = nil
		end
	end
	if not cur and fresh and freshScore >= cfg("InterestMinScore", 85) and now >= (board.interestRestUntil or 0) then
		cur = { kind = fresh.kind, pos = fresh.pos, size = fresh.size, score = fresh.score, raw = fresh.score, since = now, lastSeen = now,
			memberSet = setOf(fresh.members), fresh = true }
	end

	if cur ~= board.interest then
		board.interest = cur
		quinModel:SetAttribute("InterestKind", cur and cur.kind or nil)
		quinModel:SetAttribute("InterestSince", cur and Workspace:GetServerTimeNow() or nil) -- (probes: a new event)
		tag(quinModel, cur and ("! " .. cur.kind .. (cur.size > 1 and (" x" .. cur.size) or "")) or nil, Color3.fromRGB(255, 170, 60))
	end
	if cur then
		quinModel:SetAttribute("InterestPos", cur.pos)
		-- a glance at it: on noticing, then now and then while it is free to look round
		local state = quinModel:GetAttribute("CurrentState") or ""
		if not ENGAGED[state] and (cur.fresh or now >= (cur.nextGlance or 0)) then
			cur.fresh = false
			cur.nextGlance = now + 2.5 + math.random() * 2.5 * (1 - aware)
			local serverNow = Workspace:GetServerTimeNow()
			if (quinModel:GetAttribute("SocialLookUntil") or 0) <= serverNow then
				quinModel:SetAttribute("LookPoint", cur.pos + Vector3.new(0, 2, 0))
				quinModel:SetAttribute("LookUntil", serverNow + 0.7 + 0.5 * aware)
			end
		end
	else
		quinModel:SetAttribute("InterestPos", nil)
	end
	return cur
end

return Interest
