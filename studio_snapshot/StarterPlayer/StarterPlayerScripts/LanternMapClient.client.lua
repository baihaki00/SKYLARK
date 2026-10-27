--// LanternMapClient.client.lua
-- The match panel on the player's screen, broadcast style, for Lantern Siege and for the team
-- battle (16v16) alike (owner 2026-10-27: "make it very clear on the map hud, make them aware of
-- the time also, as for also for 16vs16"):
--   * top bar: the mode, the score / who is left, and a big clock (red in the last 10 s): the
--     round clock, the orb's countdown once it is planted, the match clock in a team battle
--   * the objective line: what each side has to do right now, in its colour (Lantern Siege: take
--     the orb, plant it, stop the planter, defuse it ...)
--   * a top-down map of the arena: the generated pieces, the Shrines, the orb, every Quin a dot
--     in its team's colour (the carrier ringed gold)
--   * the plant / defuse bar while one is kneeling (the defuse's half-way mark: past it a stop
--     keeps that half)
--   * a column per team: each Quin's health and its job right now (TaskChoice's Task); in a big
--     team battle the five most hurt of those still up
-- Top right, with a minimise button: minimised it is a small pill that still shows the clock.
-- Drawn on this client only while Workspace.LanternSiege exists or a timed match runs
-- (Workspace MatchEndsAt). Reads only what the server publishes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CANVAS = Vector2.new(1920, 1115)
local OBJ = { x = 40, y = 118, w = 1840, h = 74 }   -- the objective line
local MAP = { x = 40, y = 206, w = 1180, h = 870 }  -- the map panel on the canvas
local COLS = { x = 1250, y = 206, w = 630, h = 422, gap = 448 }
local TEAM_COLOR = { TeamAlpha = Color3.fromRGB(80, 160, 255), TeamBeta = Color3.fromRGB(255, 90, 90) }
local TEAM_NAME = { TeamAlpha = "ALPHA", TeamBeta = "BETA" }
local GOLD = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 70, 70)
local BG = Color3.fromRGB(10, 14, 22)
local PANEL = Color3.fromRGB(18, 24, 36)
local TEXT = Color3.fromRGB(235, 240, 250)
local DIM = Color3.fromRGB(140, 150, 170)
local PIECE = Color3.fromRGB(70, 80, 100)

local TASK_LABEL = {
	Carry = "PLANT", PickUp = "GRAB ORB", Escort = "ESCORT", HoldPlant = "HOLD SITE", Guard = "GUARD",
	Retake = "RETAKE", Fight = "FIGHT", Hunt = "HUNT", Rescue = "RESCUE", Escape = "GET CLEAR",
}

local PANEL_WIDTH = 0.36 -- of the screen's width (between 320 and 700 pixels)
local minimised = false  -- (kept between matches)

local guis = {}      -- the one ScreenGui
local views = {}     -- per gui
local drawnKey = nil -- what the static map was drawn for (round / arena seed)
local builtFor = nil -- "siege" | "battle"

local function now() return Workspace:GetServerTimeNow() end

local function arena()
	local root = Workspace:FindFirstChild("argoniaonion")
	return root and root:FindFirstChild("ArenaOne")
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function corner(parent, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, parent) end

local function label(parent, text, size, color, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = color or TEXT, Font = Enum.Font.GothamBold,
		TextSize = size, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

local function hex(c) return "#" .. c:ToHex() end

-- Arena ground: centre, half sizes (world X maps across the map, world Z down it)
local function bounds()
	local a = arena()
	local g = a and a:FindFirstChild("ArenaGround", true)
	if not g then return nil end
	return g.Position, g.Size.X / 2, g.Size.Z / 2
end

local function toMap(pos, center, hx, hz)
	local scale = math.min(MAP.w / (hx * 2), MAP.h / (hz * 2))
	local ox = MAP.w / 2 + (pos.X - center.X) * scale
	local oy = MAP.h / 2 + (pos.Z - center.Z) * scale
	return ox, oy, scale
end

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

-- Which match is on: "siege" (with its folder), "battle", or nil
local function currentMode()
	local siege = Workspace:FindFirstChild("LanternSiege")
	if siege then return "siege", siege end
	local endsAt = Workspace:GetAttribute("MatchEndsAt")
	if endsAt and endsAt - now() > -3 then return "battle", nil end
	return nil
end

local function destroyViews()
	for _, g in ipairs(guis) do g:Destroy() end
	guis, views, drawnKey, builtFor = {}, {}, nil, nil
end

local function buildViews(mode)
	destroyViews()
	builtFor = mode
	local gui = new("ScreenGui", { Name = "LanternMap", ResetOnSpawn = false, DisplayOrder = 30 }, player:WaitForChild("PlayerGui"))
	table.insert(guis, gui)
	-- the canvas is laid out at 1920 wide and scaled down to the panel's width
	local holder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y), BackgroundTransparency = 1, Visible = not minimised }, gui)
	local scaler = new("UIScale", { Scale = 0.3 }, holder)
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0 }, holder)
	corner(root, 24)
	new("UIStroke", { Color = GOLD, Thickness = 5 }, root)
	local pill = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(190, 36), BackgroundColor3 = BG,
		BackgroundTransparency = 0.1, Text = "MAP", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = GOLD, Visible = minimised, AutoButtonColor = true,
	}, gui)
	corner(pill, 18)
	new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.3 }, pill)
	local function setMinimised(on)
		minimised = on
		holder.Visible, pill.Visible = not on, on
	end
	pill.MouseButton1Click:Connect(function() setMinimised(false) end)

	-- top bar: mode, score, the clock
	local top = new("Frame", { Position = UDim2.fromOffset(40, 24), Size = UDim2.fromOffset(1840, 80), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
	corner(top, 14)
	local title = label(top, mode == "siege" and "LANTERN SIEGE" or "TEAM BATTLE", 34, GOLD, { Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(420, 80) })
	local score = label(top, "", 46, TEXT, { Position = UDim2.fromOffset(430, 0), Size = UDim2.fromOffset(820, 80), TextXAlignment = Enum.TextXAlignment.Center, RichText = true })
	local clockWhat = label(top, "", 26, DIM, { Position = UDim2.fromOffset(1250, 0), Size = UDim2.fromOffset(270, 80), TextXAlignment = Enum.TextXAlignment.Right })
	local clock = label(top, "", 64, TEXT, { Position = UDim2.fromOffset(1530, 0), Size = UDim2.fromOffset(200, 80), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack })
	local minBtn = new("TextButton", {
		Position = UDim2.fromOffset(1752, 10), Size = UDim2.fromOffset(76, 60), BackgroundColor3 = Color3.fromRGB(45, 55, 75),
		Text = "—", Font = Enum.Font.GothamBold, TextSize = 40, TextColor3 = TEXT, AutoButtonColor = true,
	}, top)
	corner(minBtn, 10)
	minBtn.MouseButton1Click:Connect(function() setMinimised(true) end)

	-- the objective line
	local objFrame = new("Frame", { Position = UDim2.fromOffset(OBJ.x, OBJ.y), Size = UDim2.fromOffset(OBJ.w, OBJ.h), BackgroundColor3 = Color3.fromRGB(30, 26, 18), BorderSizePixel = 0 }, root)
	corner(objFrame, 12)
	local objStroke = new("UIStroke", { Color = GOLD, Thickness = 2, Transparency = 0.4 }, objFrame)
	local objective = label(objFrame, "", 38, TEXT, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, RichText = true, Font = Enum.Font.GothamBlack })

	-- map panel
	local mapFrame = new("Frame", { Position = UDim2.fromOffset(MAP.x, MAP.y), Size = UDim2.fromOffset(MAP.w, MAP.h), BackgroundColor3 = PANEL, BorderSizePixel = 0, ClipsDescendants = true }, root)
	corner(mapFrame, 14)
	local layer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, mapFrame)

	-- the plant / defuse bar
	local barBack = new("Frame", { Position = UDim2.fromOffset(MAP.x + 40, MAP.y + MAP.h - 76), Size = UDim2.fromOffset(MAP.w - 80, 48), BackgroundColor3 = Color3.fromRGB(40, 40, 50), BorderSizePixel = 0, Visible = false, ZIndex = 20 }, root)
	corner(barBack, 10)
	local barFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 21 }, barBack)
	corner(barFill, 10)
	local barHalf = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = TEXT, BorderSizePixel = 0, ZIndex = 22 }, barBack)
	local barText = label(barBack, "", 28, TEXT, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23, TextStrokeTransparency = 0.4 })

	-- team columns
	local cols = {}
	for i, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
		local col = new("Frame", { Position = UDim2.fromOffset(COLS.x, COLS.y + (i - 1) * COLS.gap), Size = UDim2.fromOffset(COLS.w, COLS.h), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
		corner(col, 14)
		new("Frame", { Size = UDim2.fromOffset(8, COLS.h), BackgroundColor3 = TEAM_COLOR[team], BorderSizePixel = 0 }, col)
		local head = label(col, TEAM_NAME[team], 34, TEAM_COLOR[team], { Position = UDim2.fromOffset(28, 8), Size = UDim2.fromOffset(580, 50), RichText = true })
		local rows = {}
		for r = 1, 5 do
			local row = new("Frame", { Position = UDim2.fromOffset(28, 62 + (r - 1) * 70), Size = UDim2.fromOffset(580, 64), BackgroundTransparency = 1 }, col)
			local name = label(row, "", 26, TEXT, { Size = UDim2.fromOffset(330, 32) })
			local job = label(row, "", 24, GOLD, { Position = UDim2.fromOffset(330, 0), Size = UDim2.fromOffset(250, 32), TextXAlignment = Enum.TextXAlignment.Right })
			local hpBack = new("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(580, 14), BackgroundColor3 = Color3.fromRGB(40, 44, 56), BorderSizePixel = 0 }, row)
			corner(hpBack, 6)
			local hp = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAM_COLOR[team], BorderSizePixel = 0 }, hpBack)
			corner(hp, 6)
			rows[r] = { frame = row, name = name, job = job, hp = hp }
		end
		cols[team] = { head = head, rows = rows }
	end

	views[gui] = { scaler = scaler, pill = pill, root = root, layer = layer,
		top = { title = title, score = score, clock = clock, clockWhat = clockWhat },
		objective = objective, objFrame = objFrame, objStroke = objStroke, cols = cols,
		bar = { back = barBack, fill = barFill, half = barHalf, text = barText }, dots = {}, shrines = {}, lantern = nil, static = {} }
end

-- The arena itself: ground outline, the generated pieces (grey), the Shrines.
local function drawStatic(view, folder)
	for _, s in ipairs(view.static) do s:Destroy() end
	view.static, view.shrines = {}, {}
	local center, hx, hz = bounds()
	if not center then return end
	local _, _, scale = toMap(center, center, hx, hz)
	local ground = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MAP.w / 2, MAP.h / 2),
		Size = UDim2.fromOffset(hx * 2 * scale, hz * 2 * scale), BackgroundColor3 = Color3.fromRGB(28, 34, 48), BorderSizePixel = 0, ZIndex = 1,
	}, view.layer)
	new("UIStroke", { Color = Color3.fromRGB(90, 100, 120), Thickness = 2 }, ground)
	table.insert(view.static, ground)
	local gen = arena() and arena():FindFirstChild("ArenaGenerated")
	for _, p in ipairs(gen and gen:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Transparency < 0.9 and p.Size.Magnitude > 4 then
			local x, y = toMap(p.Position, center, hx, hz)
			local _, yaw = p.CFrame:ToEulerAnglesYXZ()
			local high = p.Position.Y - center.Y
			local shade = math.clamp(high / 80, 0, 1)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(math.max(3, p.Size.X * scale), math.max(3, p.Size.Z * scale)),
				Rotation = -math.deg(yaw), BackgroundColor3 = PIECE:Lerp(Color3.fromRGB(140, 150, 175), shade),
				BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 2 + math.floor(shade * 3),
			}, view.layer)
			table.insert(view.static, f)
		end
	end
	local shrineFolder = folder and folder:FindFirstChild("Shrines")
	for _, s in ipairs(shrineFolder and shrineFolder:GetChildren() or {}) do
		local x, y = toMap(s.Position, center, hx, hz)
		local r = math.max(80, s.Size.Y * scale * 2)
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(r, r),
			BackgroundColor3 = GOLD, BackgroundTransparency = 0.75, ZIndex = 6,
		}, view.layer)
		corner(ring, 999)
		new("UIStroke", { Color = GOLD, Thickness = 3 }, ring)
		label(ring, s.Name, 34, GOLD, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		table.insert(view.static, ring)
		view.shrines[s.Name] = ring
	end
end

local function dotFor(view, q)
	local d = view.dots[q]
	if not d then
		d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BorderSizePixel = 0, ZIndex = 10 }, view.layer)
		corner(d, 999)
		new("UIStroke", { Name = "Ring", Color = Color3.new(1, 1, 1), Thickness = 2 }, d)
		view.dots[q] = d
	end
	return d
end

local function jobText(q)
	local task = q:GetAttribute("Task")
	local text = TASK_LABEL[task] or (task and task:upper()) or ""
	local spot = q:GetAttribute("TaskSpot")
	if spot and (task == "Carry" or task == "Guard") then text ..= " " .. spot end
	if q:GetAttribute("LanternCarrier") then text = "ORB → " .. (spot or "?") end
	return text
end

-- What each side has to do right now, the clock, and the bar (Lantern Siege)
local function siegeStatus(folder)
	local attackers = folder:GetAttribute("Attackers") or "TeamAlpha"
	local defenders = attackers == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
	local A = string.format('<font color="%s">%s</font>', hex(TEAM_COLOR[attackers]), TEAM_NAME[attackers])
	local D = string.format('<font color="%s">%s</font>', hex(TEAM_COLOR[defenders]), TEAM_NAME[defenders])
	local G = function(t) return string.format('<font color="%s">%s</font>', hex(GOLD), t) end
	local phase = folder:GetAttribute("Phase") or ""
	local lanternPart = folder:FindFirstChild("Lantern")
	local state = lanternPart and lanternPart:GetAttribute("State") or "Base"
	local site = folder:GetAttribute("PlantedShrine") or "?"
	local t = now()
	local roundLeft = (folder:GetAttribute("RoundEndsAt") or 0) - t
	local status = { clockWhat = "ROUND", clock = roundLeft, accent = GOLD }
	if phase == "Huddle" then
		status.text = string.format("%s ATTACK: TAKE THE ORB, PLANT IT AT A OR B   ·   %s DEFEND", A, D)
		status.clockWhat, status.clock = "STARTS IN", (folder:GetAttribute("PhaseEndsAt") or 0) - t
	elseif phase == "RoundOver" then
		local last = folder:GetAttribute("LastRound") or ""
		local _, winner, why = last:match("^(%d+):([^:]+):(.*)$")
		status.text = winner and string.format('<font color="%s">%s</font> TAKE THE ROUND  ·  %s', hex(TEAM_COLOR[winner] or GOLD), TEAM_NAME[winner] or winner, (why or ""):upper()) or "ROUND OVER"
		status.clockWhat, status.clock = "NEXT", (folder:GetAttribute("PhaseEndsAt") or 0) - t
	elseif state == "Planted" then
		local left = (folder:GetAttribute("DetonateAt") or 0) - t
		status.clockWhat, status.clock, status.accent = "GOES OFF", left, RED
		status.text = left > 8 and string.format("%s AT %s   ·   %s: DEFUSE IT   ·   %s: GUARD IT", G("ORB PLANTED"), site, D, A)
			or string.format("%s   ·   GET OUT OF THE RED OR BE KNOCKED OUT", G("ABOUT TO GO OFF"))
		local p = folder:GetAttribute("DefuseProgress")
		if p then
			local who = folder:GetAttribute("Defuser")
			status.bar = { fill = p, color = TEAM_COLOR[defenders], half = true,
				text = who and string.format("DEFUSING  %d%%  (%s)", p * 100, (who:gsub("^Quin_", ""))) or string.format("DEFUSE STOPPED AT %d%%", p * 100) }
		end
	elseif state == "Planting" then
		local p = folder:GetAttribute("PlantProgress") or 0
		status.text = string.format("%s PLANTING AT %s   ·   %s: HIT THE PLANTER", A, site, D)
		status.bar = { fill = p, color = TEAM_COLOR[attackers], text = string.format("PLANTING  %d%%", p * 100) }
	elseif state == "Carried" then
		local c = lanternPart:GetAttribute("Carrier") or ""
		status.text = string.format("%s HAS THE %s (%s)   ·   %s: STOP THE CARRIER", A, G("ORB"), (c:gsub("^Quin_", "")), D)
	elseif state == "Dropped" then
		status.text = string.format("%s   ·   %s: PICK IT UP   ·   %s: KEEP THEM OFF IT", G("ORB DROPPED"), A, D)
	else
		status.text = string.format("%s ON THE PEDESTAL   ·   %s: GRAB IT AND PLANT   ·   %s: DEFEND A AND B", G("ORB"), A, D)
	end
	return status, attackers
end

local function update()
	local mode, folder = currentMode()
	if not mode then
		if #guis > 0 then destroyViews() end
		return
	end
	if builtFor ~= mode then buildViews(mode) end
	local key = mode == "siege" and ("round" .. tostring(folder:GetAttribute("Round"))) or ("seed" .. tostring(Workspace:GetAttribute("ArenaSeed")))
	local redraw = key ~= drawnKey
	drawnKey = key
	local center, hx, hz = bounds()
	if not center then return end

	local lanternPart = folder and folder:FindFirstChild("Lantern")
	local qServer = Workspace:FindFirstChild("QuinServer")
	local quins = qServer and qServer:GetChildren() or {}
	local t = now()

	-- the status: objective, clock, bar
	local status, attackers
	local alive = { TeamAlpha = 0, TeamBeta = 0 }
	local total = { TeamAlpha = 0, TeamBeta = 0 }
	for _, q in ipairs(quins) do
		local team = q:GetAttribute("Team")
		if total[team] then
			total[team] += 1
			local h = q:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and not q:GetAttribute("KnockedOut") then alive[team] += 1 end
		end
	end
	if mode == "siege" then
		status, attackers = siegeStatus(folder)
	else
		status = {
			text = string.format('KNOCK OUT THE OTHER TEAM   ·   <font color="%s">ALPHA %d</font>  vs  <font color="%s">%d BETA</font>  STILL UP',
				hex(TEAM_COLOR.TeamAlpha), alive.TeamAlpha, hex(TEAM_COLOR.TeamBeta), alive.TeamBeta),
			clockWhat = "TIME LEFT", clock = (Workspace:GetAttribute("MatchEndsAt") or t) - t, accent = GOLD,
		}
	end

	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local width = math.clamp(viewport.X * PANEL_WIDTH, 320, math.min(700, viewport.X - 32))
	for _, view in pairs(views) do
		view.scaler.Scale = width / CANVAS.X
		if redraw then drawStatic(view, folder) end

		-- top bar and clock (red, pulsing, in the last 10 seconds)
		if mode == "siege" then
			local a, b = folder:GetAttribute("ScoreTeamAlpha") or 0, folder:GetAttribute("ScoreTeamBeta") or 0
			view.top.score.Text = string.format('<font color="#50A0FF">ALPHA %d</font>   <font color="#8C96AA">ROUND %s</font>   <font color="#FF5A5A">%d BETA</font>', a, tostring(folder:GetAttribute("Round") or 1), b)
		else
			view.top.score.Text = string.format('<font color="#50A0FF">ALPHA %d/%d</font>   <font color="#8C96AA">LEFT</font>   <font color="#FF5A5A">%d/%d BETA</font>', alive.TeamAlpha, total.TeamAlpha, alive.TeamBeta, total.TeamBeta)
		end
		local left = math.max(0, status.clock or 0)
		view.top.clock.Text = fmtTime(left)
		view.top.clockWhat.Text = status.clockWhat
		local urgent = left <= 10 and status.clockWhat ~= "STARTS IN" and status.clockWhat ~= "NEXT"
		local pulse = urgent and (0.5 + 0.5 * math.sin(os.clock() * 10)) or 0
		view.top.clock.TextColor3 = urgent and RED:Lerp(TEXT, pulse * 0.4) or (status.accent == RED and RED or TEXT)
		view.pill.Text = string.format("%s  %s", mode == "siege" and "SIEGE" or "MAP", fmtTime(left))
		view.pill.TextColor3 = urgent and RED or GOLD

		view.objective.Text = status.text or ""
		view.objStroke.Color = status.accent or GOLD

		-- the bar
		local bar = status.bar
		view.bar.back.Visible = bar ~= nil
		if bar then
			view.bar.fill.Size = UDim2.fromScale(math.clamp(bar.fill, 0, 1), 1)
			view.bar.fill.BackgroundColor3 = bar.color or GOLD
			view.bar.half.Visible = bar.half == true
			view.bar.text.Text = bar.text
		end

		-- the orb
		if lanternPart then
			if not view.lantern then
				view.lantern = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 12 }, view.layer)
				corner(view.lantern, 999)
				new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, view.lantern)
			end
			local x, y = toMap(lanternPart.Position, center, hx, hz)
			view.lantern.Position = UDim2.fromOffset(x, y)
			local state = lanternPart:GetAttribute("State")
			local lit = state == "Planted"
			local p = lit and (0.5 + 0.5 * math.sin(os.clock() * 8)) or 0
			view.lantern.Size = UDim2.fromOffset(26 + p * 16, 26 + p * 16)
			view.lantern.Visible = state ~= "Carried" and state ~= "Planting"
			-- the blast area once it is planted (safe is outside the red)
			if lit then
				if not view.blast then
					view.blast = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = RED, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 8 }, view.layer)
					corner(view.blast, 999)
					new("UIStroke", { Color = RED, Thickness = 3 }, view.blast)
				end
				local _, _, scale = toMap(center, center, hx, hz)
				local r = (folder:GetAttribute("BlastRadius") or 40) * 2 * scale
				view.blast.Position = UDim2.fromOffset(x, y)
				view.blast.Size = UDim2.fromOffset(r, r)
				view.blast.BackgroundTransparency = 0.8 - 0.15 * p
			elseif view.blast then
				view.blast:Destroy()
				view.blast = nil
			end
			for name, ring in pairs(view.shrines) do
				local onIt = (lit or state == "Planting") and folder:GetAttribute("PlantedShrine") == name
				ring.BackgroundTransparency = onIt and (0.35 + 0.3 * p) or 0.75
			end
		elseif view.lantern then
			view.lantern:Destroy()
			view.lantern = nil
		end

		-- Quins
		local seen = {}
		for _, q in ipairs(quins) do
			local root = q:FindFirstChild("HumanoidRootPart")
			local team = q:GetAttribute("Team")
			if root and TEAM_COLOR[team] then
				seen[q] = true
				local d = dotFor(view, q)
				local x, y = toMap(root.Position, center, hx, hz)
				d.Position = UDim2.fromOffset(x, y)
				d.BackgroundColor3 = TEAM_COLOR[team]
				local carrying = q:GetAttribute("LanternCarrier") == true
				local size = mode == "battle" and 14 or (carrying and 30 or 20)
				d.Size = UDim2.fromOffset(size, size)
				d.Ring.Color = carrying and GOLD or Color3.new(1, 1, 1)
				d.Ring.Thickness = carrying and 5 or (mode == "battle" and 1 or 2)
			end
		end
		for q, d in pairs(view.dots) do
			if not seen[q] then d:Destroy() view.dots[q] = nil end
		end

		-- team columns: on the field first, then the knocked out (greyed); in a big battle the five
		-- most hurt of those still up
		for _, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
			local col = view.cols[team]
			local members = {}
			for _, q in ipairs(quins) do
				if q:GetAttribute("Team") == team then
					local h = q:FindFirstChildOfClass("Humanoid")
					local ratio = h and math.clamp(h.Health / math.max(1, h.MaxHealth), 0, 1) or 0
					table.insert(members, { q = q, out = ratio <= 0 or q:GetAttribute("KnockedOut") == true, hp = ratio })
				end
			end
			local bench = folder and folder:FindFirstChild("Bench")
			for _, q in ipairs(bench and bench:GetChildren() or {}) do
				if q:GetAttribute("Team") == team then table.insert(members, { q = q, out = true, hp = 0 }) end
			end
			local outCount = 0
			for _, m in ipairs(members) do if m.out then outCount += 1 end end
			if mode == "battle" then
				local up = {}
				for _, m in ipairs(members) do if not m.out then table.insert(up, m) end end
				table.sort(up, function(a, b) return a.hp < b.hp end)
				members = up
				col.head.Text = string.format("%s  <font color=\"#8C96AA\">%d/%d UP  ·  MOST HURT</font>", TEAM_NAME[team], #up, #up + outCount)
			else
				col.head.Text = string.format("%s  <font color=\"#8C96AA\">%s  %d/%d</font>", TEAM_NAME[team], team == attackers and "ATTACK" or "DEFEND", #members - outCount, #members)
			end
			for r, row in ipairs(col.rows) do
				local m = members[r]
				row.frame.Visible = m ~= nil
				if m then
					row.name.Text = (m.q.Name:gsub("^Quin_", "")) .. (m.q:GetAttribute("Shaken") and "  ·  SHAKEN" or "")
					row.name.TextColor3 = m.out and DIM or TEXT
					row.job.Text = m.out and "OUT" or jobText(m.q)
					row.job.TextColor3 = m.out and DIM or (m.q:GetAttribute("LanternCarrier") and GOLD or Color3.fromRGB(200, 210, 230))
					row.hp.Size = UDim2.fromScale(m.out and 0 or m.hp, 1)
				end
			end
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then return end
	acc = 0
	local ok, err = pcall(update)
	if not ok then warn("[LanternMap] " .. tostring(err)) end
end)
