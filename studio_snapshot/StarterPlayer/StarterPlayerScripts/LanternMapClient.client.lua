--// LanternMapClient.client.lua
-- A panel on the player's screen during a Lantern Siege match, broadcast style (owner 2026-10-27: "map out the
-- arena from top view, like a map"): a top-down map of the generated arena with the Shrines, the
-- Lantern and every Quin as a dot in its team's colour, a top bar with round / score / phase /
-- clock, and a column per team with each Quin's health and its job right now (TaskChoice's Task),
-- so a viewer can read who is doing what.
-- Top right of the player's screen (owner 2026-10-27: off the arena screen, which shows its usual
-- scenes again), with a minimise button: minimised it is a small pill that opens it again. Drawn
-- on this client only while Workspace.LanternSiege exists. Reads only what the server publishes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CANVAS = Vector2.new(1920, 1115)
local MAP = { x = 40, y = 120, w = 1180, h = 950 } -- the map panel on the canvas
local TEAM_COLOR = { TeamAlpha = Color3.fromRGB(80, 160, 255), TeamBeta = Color3.fromRGB(255, 90, 90) }
local TEAM_NAME = { TeamAlpha = "ALPHA", TeamBeta = "BETA" }
local GOLD = Color3.fromRGB(255, 190, 80)
local BG = Color3.fromRGB(10, 14, 22)
local PANEL = Color3.fromRGB(18, 24, 36)
local TEXT = Color3.fromRGB(235, 240, 250)
local DIM = Color3.fromRGB(140, 150, 170)
local PIECE = Color3.fromRGB(70, 80, 100)

local TASK_LABEL = {
	Carry = "CARRY", PickUp = "GRAB LANTERN", Escort = "ESCORT", HoldPlant = "HOLD", Guard = "GUARD",
	Retake = "RETAKE", Fight = "FIGHT", Hunt = "HUNT", Rescue = "RESCUE",
}

local PANEL_WIDTH = 0.36 -- of the screen's width (between 320 and 700 pixels)
local minimised = false  -- (kept between matches)

local guis = {}      -- the one ScreenGui
local views = {}     -- per gui: { root, map, dots = {}, lantern, shrines = {}, top, cols = {} }
local drawnRound = nil

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

local function destroyViews()
	for _, g in ipairs(guis) do g:Destroy() end
	guis, views, drawnRound = {}, {}, nil
end

local function buildViews()
	destroyViews()
	do
		local gui = new("ScreenGui", { Name = "LanternMap", ResetOnSpawn = false, DisplayOrder = 30 }, player:WaitForChild("PlayerGui"))
		table.insert(guis, gui)
		-- the canvas is laid out at 1920 wide and scaled down to the panel's width
		local holder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y), BackgroundTransparency = 1, Visible = not minimised }, gui)
		local scaler = new("UIScale", { Scale = 0.3 }, holder)
		local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0 }, holder)
		corner(root, 24)
		new("UIStroke", { Color = GOLD, Thickness = 5 }, root)
		local pill = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(150, 34), BackgroundColor3 = BG,
			BackgroundTransparency = 0.1, Text = "SIEGE MAP", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = GOLD, Visible = minimised, AutoButtonColor = true,
		}, gui)
		corner(pill, 17)
		new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.3 }, pill)
		local function setMinimised(on)
			minimised = on
			holder.Visible, pill.Visible = not on, on
		end
		pill.MouseButton1Click:Connect(function() setMinimised(false) end)

		-- top bar
		local top = new("Frame", { Position = UDim2.fromOffset(40, 24), Size = UDim2.fromOffset(1840, 80), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
		corner(top, 14)
		local title = label(top, "LANTERN SIEGE", 34, GOLD, { Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(420, 80) })
		local score = label(top, "", 46, TEXT, { Position = UDim2.fromOffset(560, 0), Size = UDim2.fromOffset(720, 80), TextXAlignment = Enum.TextXAlignment.Center, RichText = true })
		local phase = label(top, "", 32, TEXT, { Position = UDim2.fromOffset(1220, 0), Size = UDim2.fromOffset(500, 80), TextXAlignment = Enum.TextXAlignment.Right, RichText = true })
		local minBtn = new("TextButton", {
			Position = UDim2.fromOffset(1752, 10), Size = UDim2.fromOffset(76, 60), BackgroundColor3 = Color3.fromRGB(45, 55, 75),
			Text = "—", Font = Enum.Font.GothamBold, TextSize = 40, TextColor3 = TEXT, AutoButtonColor = true,
		}, top)
		corner(minBtn, 10)
		minBtn.MouseButton1Click:Connect(function() setMinimised(true) end)

		-- map panel
		local mapFrame = new("Frame", { Position = UDim2.fromOffset(MAP.x, MAP.y), Size = UDim2.fromOffset(MAP.w, MAP.h), BackgroundColor3 = PANEL, BorderSizePixel = 0, ClipsDescendants = true }, root)
		corner(mapFrame, 14)
		local layer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, mapFrame)

		-- stamp bar (shown while the Lantern burns)
		local stampBack = new("Frame", { Position = UDim2.fromOffset(MAP.x + 40, MAP.y + MAP.h - 60), Size = UDim2.fromOffset(MAP.w - 80, 26), BackgroundColor3 = Color3.fromRGB(40, 40, 50), BorderSizePixel = 0, Visible = false }, root)
		corner(stampBack, 8)
		local stampFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TEAM_COLOR.TeamBeta, BorderSizePixel = 0 }, stampBack)
		corner(stampFill, 8)
		local stampText = label(stampBack, "", 22, TEXT, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

		-- team columns
		local cols = {}
		for i, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
			local col = new("Frame", { Position = UDim2.fromOffset(1250, MAP.y + (i - 1) * 480), Size = UDim2.fromOffset(630, 465), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, root)
			corner(col, 14)
			new("Frame", { Size = UDim2.fromOffset(8, 465), BackgroundColor3 = TEAM_COLOR[team], BorderSizePixel = 0 }, col)
			local head = label(col, TEAM_NAME[team], 34, TEAM_COLOR[team], { Position = UDim2.fromOffset(28, 10), Size = UDim2.fromOffset(580, 50), RichText = true })
			local rows = {}
			for r = 1, 5 do
				local row = new("Frame", { Position = UDim2.fromOffset(28, 66 + (r - 1) * 78), Size = UDim2.fromOffset(580, 70), BackgroundTransparency = 1 }, col)
				local name = label(row, "", 26, TEXT, { Size = UDim2.fromOffset(330, 34) })
				local job = label(row, "", 24, GOLD, { Position = UDim2.fromOffset(330, 0), Size = UDim2.fromOffset(250, 34), TextXAlignment = Enum.TextXAlignment.Right })
				local hpBack = new("Frame", { Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(580, 14), BackgroundColor3 = Color3.fromRGB(40, 44, 56), BorderSizePixel = 0 }, row)
				corner(hpBack, 6)
				local hp = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAM_COLOR[team], BorderSizePixel = 0 }, hpBack)
				corner(hp, 6)
				rows[r] = { frame = row, name = name, job = job, hp = hp }
			end
			cols[team] = { head = head, rows = rows }
		end

		views[gui] = { scaler = scaler, root = root, layer = layer, top = { title = title, score = score, phase = phase }, cols = cols,
			stamp = { back = stampBack, fill = stampFill, text = stampText }, dots = {}, shrines = {}, lantern = nil, static = {} }
	end
end

-- The arena itself: ground outline, the generated pieces (grey), the Shrines. Redrawn each round.
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
	local shrineFolder = folder:FindFirstChild("Shrines")
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

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function jobText(q)
	local task = q:GetAttribute("Task")
	local text = TASK_LABEL[task] or (task and task:upper()) or ""
	local spot = q:GetAttribute("TaskSpot")
	if spot and (task == "Carry" or task == "Guard") then text ..= " " .. spot end
	if q:GetAttribute("LanternCarrier") then text = "CARRY " .. (spot or "") end
	return text
end

local function update()
	local folder = Workspace:FindFirstChild("LanternSiege")
	if not folder then
		if #guis > 0 then destroyViews() end
		return
	end
	if #guis == 0 then buildViews() end
	local round = folder:GetAttribute("Round")
	local redraw = round ~= drawnRound
	drawnRound = round
	local center, hx, hz = bounds()
	if not center then return end

	local attackers = folder:GetAttribute("Attackers") or "TeamAlpha"
	local phaseName = folder:GetAttribute("Phase") or ""
	local left = (folder:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow()
	local lanternPart = folder:FindFirstChild("Lantern")
	local qServer = Workspace:FindFirstChild("QuinServer")
	local quins = qServer and qServer:GetChildren() or {}

	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local width = math.clamp(viewport.X * PANEL_WIDTH, 320, math.min(700, viewport.X - 32))
	for _, view in pairs(views) do
		view.scaler.Scale = width / CANVAS.X
		if redraw then drawStatic(view, folder) end
		local a, b = folder:GetAttribute("ScoreTeamAlpha") or 0, folder:GetAttribute("ScoreTeamBeta") or 0
		view.top.score.Text = string.format('<font color="#50A0FF">ALPHA %d</font>   <font color="#8C96AA">ROUND %s</font>   <font color="#FF5A5A">%d BETA</font>', a, tostring(round or 1), b)
		local phaseLabel = ({ Huddle = "HUDDLE", Live = "LIVE", Ignition = "LANTERN LIT", RoundOver = "ROUND OVER" })[phaseName] or phaseName:upper()
		view.top.phase.Text = string.format('<font color="#%s">%s ATTACKS</font>   %s   %s', TEAM_COLOR[attackers]:ToHex(), TEAM_NAME[attackers], phaseLabel, left > 0 and fmtTime(left) or "")

		-- the Lantern
		if lanternPart then
			if not view.lantern then
				view.lantern = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 12, Rotation = 45 }, view.layer)
				new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, view.lantern)
			end
			local x, y = toMap(lanternPart.Position, center, hx, hz)
			view.lantern.Position = UDim2.fromOffset(x, y)
			local lit = lanternPart:GetAttribute("State") == "Planted"
			local pulse = lit and (0.5 + 0.5 * math.sin(os.clock() * 8)) or 0
			view.lantern.Size = UDim2.fromOffset(26 + pulse * 14, 26 + pulse * 14)
			view.lantern.Visible = lanternPart:GetAttribute("State") ~= "Carried"
			for name, ring in pairs(view.shrines) do
				ring.BackgroundTransparency = (lit and folder:GetAttribute("PlantedShrine") == name) and (0.35 + 0.3 * pulse) or 0.75
			end
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
				d.Size = UDim2.fromOffset(carrying and 30 or 20, carrying and 30 or 20)
				d.Ring.Color = carrying and GOLD or Color3.new(1, 1, 1)
				d.Ring.Thickness = carrying and 5 or 2
			end
		end
		for q, d in pairs(view.dots) do
			if not seen[q] then d:Destroy() view.dots[q] = nil end
		end

		-- team columns: on the field first, then the knocked out (greyed)
		for _, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
			local col = view.cols[team]
			local members = {}
			for _, q in ipairs(quins) do
				if q:GetAttribute("Team") == team then table.insert(members, { q = q, out = false }) end
			end
			local bench = folder:FindFirstChild("Bench")
			for _, q in ipairs(bench and bench:GetChildren() or {}) do
				if q:GetAttribute("Team") == team then table.insert(members, { q = q, out = true }) end
			end
			col.head.Text = string.format("%s  <font color=\"#8C96AA\">%s  %d/%d</font>", TEAM_NAME[team], team == attackers and "ATTACK" or "DEFEND",
				#members - (function() local n = 0 for _, m in ipairs(members) do if m.out then n += 1 end end return n end)(), #members)
			for r, row in ipairs(col.rows) do
				local m = members[r]
				row.frame.Visible = m ~= nil
				if m then
					local h = m.q:FindFirstChildOfClass("Humanoid")
					local ratio = (h and not m.out) and math.clamp(h.Health / math.max(1, h.MaxHealth), 0, 1) or 0
					row.name.Text = m.q.Name:gsub("^Quin_", "")
					row.name.TextColor3 = m.out and DIM or TEXT
					row.job.Text = m.out and "OUT" or jobText(m.q)
					row.job.TextColor3 = m.out and DIM or (m.q:GetAttribute("LanternCarrier") and GOLD or Color3.fromRGB(200, 210, 230))
					row.hp.Size = UDim2.fromScale(ratio, 1)
				end
			end
		end

		-- stamping
		local progress = folder:GetAttribute("StampProgress") or 0
		local burning = phaseName == "Ignition"
		view.stamp.back.Visible = burning
		if burning then
			view.stamp.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			view.stamp.text.Text = progress > 0.02 and string.format("STAMPING OUT  %d%%", progress * 100) or string.format("LANTERN BURNING AT %s", tostring(folder:GetAttribute("PlantedShrine")))
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
