--// QuinEyes.client.lua
-- Eyes on the Quin's face: a cosmetic prototype (owner 2026-10-27: eyes players may buy later; test
-- how they look and move). Purely visual and on this client only: it never changes what a Quin
-- does. It reads what the brain already publishes and shows it:
--   where it looks   the pupils go the rest of the way to the point the head is turning to
--                    (LookController), so the eyes lead and the head follows
--   focus            fighting or squaring up, the lids narrow on the target
--   alert            a glance at something (Gaze), a callout heard, the Alert gesture: wide open
--   hurt             knocked back or getting up: squeezed shut a moment
--   out              knocked out, benched, dead: no eyes
--   blink            now and then, like anyone
-- The face is one skinned mesh (no face part to put a decal on), so each eye is its own small thin
-- plate laid on the face like a sticker: placed every frame on the head bone's animated position
-- (after the head look is applied), on the measured face surface at that spot and turned with its
-- curve (a single flat plate across both eyes stood off the round head: it floated).
-- Styles: Slit, Calm, Visor (no pupils); Round, Dot, Anime (pupils).
-- Choose: Workspace attribute QuinEyes = "Mix" (default: each Quin its own) | "Off" | a style
-- name (all Quins). A Quin's own attribute EyeStyle wins over Mix (for a bought style later).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local STYLES = { "Slit", "Round", "Calm", "Dot", "Anime", "Visor" }
local PX = 500                      -- canvas pixels per stud
local PLATE = Vector2.new(0.24, 0.2) -- studs, one per eye
-- Where each eye sits on the face, from the head bone (measured on the Quin head, 2026-10-27: at
-- 0.125 to the side and 0.3 up the face is 0.39 out, its surface turned ~37 degrees outward)
local EYE_X, EYE_Y, EYE_Z = 0.125, 0.3, -0.392
local EYE_NORMAL = Vector3.new(0.6, 0, -0.8)
local LIFT = 0.012                  -- studs off the surface (just clear of it, no z-fighting)
local function eyeOffset(side)
	local n = Vector3.new(EYE_NORMAL.X * side, EYE_NORMAL.Y, EYE_NORMAL.Z).Unit
	local pos = Vector3.new(EYE_X * side, EYE_Y, EYE_Z) + n * LIFT
	return CFrame.lookAt(pos, pos + n)
end
local OFFSETS = { [-1] = eyeOffset(-1), [1] = eyeOffset(1) }
local SHOW_RANGE = 160              -- studs from the camera

local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(15, 15, 22)

-- Anime irises: one per Quin, picked from its name (the same on every screen, every match);
-- a Quin's own EyeColor attribute (Color3) wins
local IRIS = {
	Color3.fromRGB(40, 90, 200), Color3.fromRGB(30, 160, 120), Color3.fromRGB(200, 50, 60),
	Color3.fromRGB(150, 60, 200), Color3.fromRGB(230, 150, 30), Color3.fromRGB(40, 170, 210),
	Color3.fromRGB(220, 80, 150), Color3.fromRGB(120, 180, 40), Color3.fromRGB(150, 90, 50),
	Color3.fromRGB(90, 100, 120),
}

local entries = {} -- model -> entry

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function round(parent) new("UICorner", { CornerRadius = UDim.new(1, 0) }, parent) end

local function hash(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end

local function styleFor(model)
	local mode = Workspace:GetAttribute("QuinEyes") or "Mix"
	if mode == "Off" then return nil end
	local own = model:GetAttribute("EyeStyle")
	if own then return own end
	if mode ~= "Mix" then return mode end
	return STYLES[hash(model.Name) % #STYLES + 1]
end

-- One eye: { frame (scaled for the lids), pupil (moved), w, h, slant }
local function buildEye(canvas, style, side, iris)
	local cx = PLATE.X * PX / 2
	local cy = PLATE.Y * PX / 2
	local eye = { pupil = nil, glow = false }
	local function frame(w, h, color)
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color, BorderSizePixel = 0 }, canvas)
		round(f)
		return f
	end
	if style == "Slit" then
		-- glowing slanted slits, inner corners low (the reference: a creature that means it)
		eye.frame, eye.w, eye.h, eye.glow = frame(86, 20, WHITE), 86, 20, true
		eye.frame.Rotation = -side * 14
	elseif style == "Calm" then
		eye.frame, eye.w, eye.h, eye.glow = frame(46, 34, WHITE), 46, 34, true
	elseif style == "Visor" then
		-- one band across: each half runs to its plate's edge
		eye.frame, eye.w, eye.h, eye.glow = frame(PLATE.X * PX, 18, WHITE), PLATE.X * PX, 18, true
	elseif style == "Round" then
		eye.frame, eye.w, eye.h = frame(60, 60, WHITE), 60, 60
		eye.frame.ClipsDescendants = true
		eye.pupil = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = INK, BorderSizePixel = 0 }, eye.frame)
		round(eye.pupil)
		eye.shift = 14
	elseif style == "Dot" then
		-- no white: the pupil is the eye, and it moves inside an empty socket
		eye.frame, eye.w, eye.h = frame(52, 52, WHITE), 52, 52
		eye.frame.BackgroundTransparency = 1
		eye.pupil = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = INK, BorderSizePixel = 0 }, eye.frame)
		round(eye.pupil)
		eye.shift = 12
	elseif style == "Anime" then
		eye.frame, eye.w, eye.h = frame(48, 70, WHITE), 48, 70
		eye.frame.ClipsDescendants = true
		eye.pupil = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(32, 44),
			BackgroundColor3 = iris, BorderSizePixel = 0 }, eye.frame)
		round(eye.pupil)
		-- a dark centre and a lighter lower rim, so the colour reads as an iris
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(iris:Lerp(INK, 0.35), iris:Lerp(WHITE, 0.25)) }, eye.pupil)
		local core = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 22),
			BackgroundColor3 = INK, BorderSizePixel = 0 }, eye.pupil)
		round(core)
		local shine = new("Frame", { Position = UDim2.fromScale(0.18, 0.12), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, eye.pupil)
		round(shine)
		eye.shift = 9
	else
		return nil
	end
	if eye.glow then
		new("UIStroke", { Color = WHITE, Thickness = 4, Transparency = 0.6 }, eye.frame)
	end
	return eye
end

local function destroyEntry(model)
	local e = entries[model]
	if e then
		for _, p in ipairs(e.plates or {}) do p.part:Destroy() end
		entries[model] = nil
	end
end

local function build(model, style)
	destroyEntry(model)
	local head = model:FindFirstChild("mixamorig:Head", true)
	local surface = model:FindFirstChild("Alpha_Surface")
	if not head or not surface then return end
	local plates, eyes, glow = {}, {}, false
	for _, side in ipairs({ -1, 1 }) do
		local plate = new("Part", {
			Name = "QuinEyes", Size = Vector3.new(PLATE.X, PLATE.Y, 0.01), Transparency = 1, Anchored = true,
			CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		}, nil)
		local gui = new("SurfaceGui", {
			Face = Enum.NormalId.Front, CanvasSize = PLATE * PX, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
			LightInfluence = 0.3, AlwaysOnTop = false, ZOffset = 1,
		}, plate)
		local canvas = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
		local iris = model:GetAttribute("EyeColor")
		if typeof(iris) ~= "Color3" then iris = IRIS[hash(model.Name .. "iris") % #IRIS + 1] end
		local eye = buildEye(canvas, style, side, iris)
		if eye then
			table.insert(eyes, eye)
			glow = glow or eye.glow
		end
		if glow then
			gui.LightInfluence = 0
			gui.Brightness = 2.5
		end
		plate.Parent = Workspace.CurrentCamera -- (client-only: nobody else sees this copy)
		table.insert(plates, { part = plate, gui = gui, offset = OFFSETS[side] })
	end
	entries[model] = {
		plates = plates, eyes = eyes, style = style, head = head, surface = surface,
		open = 1, nextBlink = os.clock() + 1 + (hash(model.Name) % 300) / 100, blinkUntil = 0,
		px = 0, py = 0, alertUntil = 0, seenGlance = nil, seenCallout = nil,
	}
end

-- How open the lids are, from what it is doing (1 = normal)
local function lidTarget(model, e, now)
	local state = model:GetAttribute("CurrentState")
	if model:GetAttribute("KnockedOut") or state == "Death" then return 0 end
	if state == "Knockback" or state == "Recovery" then return 0.15 end
	-- something new: wide for a moment
	local glance = model:GetAttribute("GazeMode") == "glance" and model:GetAttribute("GazeAt")
	if glance and glance ~= e.seenGlance then e.alertUntil = now + 0.7 end
	e.seenGlance = glance
	local heard = model:GetAttribute("HeardCalloutAt")
	if heard and heard ~= e.seenCallout then
		if e.seenCallout ~= nil then e.alertUntil = now + 0.7 end
		e.seenCallout = heard
	end
	local gesture = model:GetAttribute("Gesture")
	if gesture == "Alert" or now < e.alertUntil then return 1.3 end
	if gesture == "Acknowledge" then return 0.55 end
	if state == "Fight" or state == "Circling" or gesture == "Focus" or gesture == "Ready" then return 0.62 end
	return 1
end

local function update(dt)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	local folder = Workspace:FindFirstChild("QuinServer")
	local seen = {}
	for _, model in ipairs(folder and folder:GetChildren() or {}) do
		seen[model] = true
		local style = styleFor(model)
		local e = entries[model]
		if not style then
			if e then destroyEntry(model) end
		else
			if not e or e.style ~= style then
				build(model, style)
				e = entries[model]
			end
			if e then
				local headPos = e.head.TransformedWorldCFrame.Position
				local visible = e.surface.Parent and e.surface.LocalTransparencyModifier < 0.5 and e.surface.Transparency < 0.5
					and (headPos - cam.CFrame.Position).Magnitude < SHOW_RANGE
				local lids = visible and lidTarget(model, e, now) or 0
				local shown = visible and lids > 0.01
				for _, p in ipairs(e.plates) do p.gui.Enabled = shown end
				if shown then
					local headCF = e.head.TransformedWorldCFrame
					for _, p in ipairs(e.plates) do p.part.CFrame = headCF * p.offset end
					-- blink
					if now >= e.nextBlink then
						e.blinkUntil = now + 0.12
						e.nextBlink = now + 2.5 + ((hash(model.Name) + math.floor(now)) % 400) / 100
					end
					if now < e.blinkUntil then lids = 0.05 end
					e.open += (lids - e.open) * math.clamp(dt * 18, 0, 1)
					-- the pupils: the rest of the way to what the head is turning toward
					local tx, ty = 0, 0
					local presentation = shared.QuinPresentationControllers and shared.QuinPresentationControllers[model]
					local target = presentation and presentation.look and presentation.look.lastTargetPos
					if target then
						local loc = headCF:PointToObjectSpace(target)
						if loc.Z < -0.5 then
							tx = math.clamp(math.atan2(loc.X, -loc.Z) / 0.7, -1, 1)
							ty = math.clamp(-math.atan2(loc.Y - 0.3, -loc.Z) / 0.5, -1, 1)
						end
					end
					e.px += (tx - e.px) * math.clamp(dt * 14, 0, 1)
					e.py += (ty - e.py) * math.clamp(dt * 14, 0, 1)
					for _, eye in ipairs(e.eyes) do
						eye.frame.Size = UDim2.fromOffset(eye.w, math.max(2, eye.h * math.min(e.open, 1.3)))
						if eye.pupil then
							eye.pupil.Position = UDim2.new(0.5, e.px * eye.shift, 0.5, e.py * eye.shift)
						end
					end
				end
			end
		end
	end
	for model in pairs(entries) do
		if not seen[model] or not model.Parent then destroyEntry(model) end
	end
end

-- (after the head look is applied: QuinPresentation runs at Camera - 1)
RunService:BindToRenderStep("QuinEyes", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local ok, err = pcall(update, dt)
	if not ok then warn("[QuinEyes] " .. tostring(err)) end
end)
