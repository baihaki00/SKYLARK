--// LeaderWristbands.client.lua
-- A hologram band round a pack leader's right wrist (SocialLeaders sets SocialRole = "Leader"),
-- like the ArenaGlobe's ring: a loop of panels sitting just off the wrist (not wrapping the hand),
-- "ALPHA LEADER" / "BETA LEADER" scrolling round it, full team colour (Alpha blue, Beta red).
-- It follows the wrist bone every frame and does not wobble. It glitches in when a Quin becomes
-- a leader and out when the role passes on. Client only: purely visual.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CFG = {
	Panels = 16,
	RadiusPerForearm = 0.2,  -- band radius as a share of the forearm length (wrist + a hair)
	MinRadius = 0.18,
	Height = 0.32,           -- studs of band (share of the forearm below)
	HeightPerForearm = 0.22,
	WristOffset = 0.32,      -- band centre this far up the forearm from the wrist joint (share of its height)
	PixelsPerStud = 220,
	ScrollSpeed = 0.25,      -- studs of text per second round the band
	BandTransparency = 0.55,
	TrimHeight = 0.035,
	Colors = {
		TeamAlpha = Color3.fromRGB(0, 70, 255),
		TeamBeta = Color3.fromRGB(255, 20, 20),
	},
	Labels = { TeamAlpha = "ALPHA LEADER", TeamBeta = "BETA LEADER" },
}

local bands = {} -- model -> band

local function quinFolder()
	return Workspace:FindFirstChild("QuinServer")
end

local function makePart(parent, name, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p:SetAttribute("TargetTransparency", transparency)
	p.Parent = parent
	return p
end

local function forearmLength(model)
	local fore = model:FindFirstChild("mixamorig:RightForeArm", true)
	local hand = model:FindFirstChild("mixamorig:RightHand", true)
	if not (fore and hand and fore:IsA("Bone") and hand:IsA("Bone")) then return nil end
	return (hand.TransformedWorldCFrame.Position - fore.TransformedWorldCFrame.Position).Magnitude, fore, hand
end

local function build(model)
	local team = model:GetAttribute("Team")
	local color = CFG.Colors[team]
	local text = CFG.Labels[team]
	if not color then return nil end
	local length, fore, hand = forearmLength(model)
	if not length or length < 0.05 then return nil end

	local radius = math.max(CFG.MinRadius, length * CFG.RadiusPerForearm)
	local height = math.max(0.12, length * CFG.HeightPerForearm)
	local count = CFG.Panels
	local step = math.pi * 2 / count
	local chord = 2 * radius * math.sin(step / 2)
	local folder = Instance.new("Folder")
	folder.Name = "LeaderWristband_" .. model.Name
	folder.Parent = Workspace

	-- the text strip: the label repeated to go once round the band
	local ringStuds = chord * count
	local panelPx = math.max(8, math.floor(chord * CFG.PixelsPerStud))
	local heightPx = math.max(8, math.floor(height * CFG.PixelsPerStud))
	local unit = text .. "  \u{2022}  "
	local band = { model = model, fore = fore, hand = hand, radius = radius, height = height, folder = folder,
		panels = {}, labels = {}, parts = {}, ringPx = panelPx * count, scroll = 0, count = count, step = step }

	for i = 1, count do
		local panel = makePart(folder, "Panel" .. i, Vector3.new(chord * 1.04, height, 0.01), color, Enum.Material.SmoothPlastic, CFG.BandTransparency)
		local top = makePart(folder, "Trim" .. i, Vector3.new(chord * 1.04, CFG.TrimHeight, 0.02), color, Enum.Material.Neon, 0.1)
		local bottom = makePart(folder, "TrimB" .. i, Vector3.new(chord * 1.04, CFG.TrimHeight, 0.02), color, Enum.Material.Neon, 0.1)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(panelPx, heightPx)
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.ClipsDescendants = true
		gui.Parent = panel
		-- two copies of the strip so the panel is always covered while it scrolls
		local labels = {}
		for c = 0, 1 do
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(0, band.ringPx, 1, 0)
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = false
			label.TextSize = math.floor(heightPx * 0.62)
			label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
			label.TextStrokeTransparency = 0.6
			label.TextStrokeColor3 = color
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTransparency = 1
			label.Text = string.rep(unit, 8)
			label.Parent = gui
			labels[c + 1] = label
		end
		table.insert(band.panels, { panel = panel, top = top, bottom = bottom, labels = labels, index = i })
		table.insert(band.parts, panel)
		table.insert(band.parts, top)
		table.insert(band.parts, bottom)
	end
	-- the strip repeats every ring length: trim the text to one ring (TextBounds after render)
	task.defer(function()
		local sample = band.panels[1] and band.panels[1].labels[1]
		if sample then
			local per = sample.TextBounds.X / 8
			if per > 0 then
				local reps = math.max(1, math.floor(band.ringPx / per + 0.5))
				for _, p in ipairs(band.panels) do
					for _, l in ipairs(p.labels) do l.Text = string.rep(unit, reps) end
				end
			end
		end
	end)
	return band
end

local function glitch(band, visible)
	for _, part in ipairs(band.parts) do
		task.spawn(function()
			for _ = 1, math.random(2, 3) do
				part.Transparency = 0.05
				task.wait(0.03 + math.random() * 0.04)
				part.Transparency = 0.9
				task.wait(0.03 + math.random() * 0.05)
			end
			local to = visible and part:GetAttribute("TargetTransparency") or 1
			TweenService:Create(part, TweenInfo.new(0.25), { Transparency = to }):Play()
		end)
	end
	for _, p in ipairs(band.panels) do
		for _, l in ipairs(p.labels) do
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = visible and 0 or 1 }):Play()
		end
	end
end

local function remove(model)
	local band = bands[model]
	if not band then return end
	bands[model] = nil
	glitch(band, false)
	task.delay(0.6, function() band.folder:Destroy() end)
end

local function refresh(model)
	local isLeader = model.Parent and model:GetAttribute("SocialRole") == "Leader"
	if isLeader and not bands[model] then
		local band = build(model)
		if band then
			bands[model] = band
			glitch(band, true)
		end
	elseif not isLeader and bands[model] then
		remove(model)
	end
end

local watched = {}
local function watch(model)
	if watched[model] or not model:IsA("Model") then return end
	watched[model] = true
	model:GetAttributeChangedSignal("SocialRole"):Connect(function() refresh(model) end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			watched[model] = nil
			remove(model)
		end
	end)
	refresh(model)
end

task.spawn(function()
	local folder = quinFolder() or Workspace:WaitForChild("QuinServer")
	for _, m in ipairs(folder:GetChildren()) do watch(m) end
	folder.ChildAdded:Connect(function(m) task.defer(watch, m) end)
end)

-- Every frame: the band follows the wrist (no wobble), the text scrolls
RunService.RenderStepped:Connect(function(dt)
	for model, band in pairs(bands) do
		if not (band.fore.Parent and band.hand.Parent) then
			remove(model)
		else
			local forePos = band.fore.TransformedWorldCFrame.Position
			local handCF = band.hand.TransformedWorldCFrame
			local axis = forePos - handCF.Position
			if axis.Magnitude > 0.01 then
				axis = axis.Unit
				local center = handCF.Position + axis * band.height * CFG.WristOffset
				-- a frame round the forearm axis, its zero angle locked to the hand's own facing
				local ref = handCF.LookVector
				if math.abs(ref:Dot(axis)) > 0.95 then ref = handCF.RightVector end
				local right = (ref - axis * ref:Dot(axis)).Unit
				local fwd = axis:Cross(right)
				band.scroll = (band.scroll + dt * CFG.ScrollSpeed * CFG.PixelsPerStud) % band.ringPx
				local cframes, parts = {}, {}
				for _, p in ipairs(band.panels) do
					local a = (p.index - 1) * band.step
					local out = right * math.cos(a) + fwd * math.sin(a)
					local pos = center + out * band.radius
					-- (front face outward: Z = -out, X = Y x Z)
					local cf = CFrame.fromMatrix(pos, axis:Cross(-out), axis, -out)
					table.insert(parts, p.panel) table.insert(cframes, cf)
					table.insert(parts, p.top) table.insert(cframes, cf * CFrame.new(0, band.height / 2, 0))
					table.insert(parts, p.bottom) table.insert(cframes, cf * CFrame.new(0, -band.height / 2, 0))
					local offset = -(((p.index - 1) * (band.ringPx / band.count) + band.scroll) % band.ringPx)
					p.labels[1].Position = UDim2.new(0, offset, 0, 0)
					p.labels[2].Position = UDim2.new(0, offset + band.ringPx, 0, 0)
				end
				Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
end)
