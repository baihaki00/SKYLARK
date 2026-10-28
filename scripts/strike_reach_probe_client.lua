--// strike_reach_probe_client.lua
-- FIGHT_PROGRAMME.md step 1: how far each strike clip really reaches. Pasted into an MCP
-- execute_luau call on the Client while a match runs. For every Attacks clip playing on a QuinServer
-- body, from its HitStart marker to its HitEnd marker, the striking limb (the HitStart parameter, e.g.
-- "RightFoot"; both hands and feet when it is empty) is measured in the root's own space:
--   forward   studs ahead of the root along its facing (the reach the step-in has to respect)
--   height    studs above the root (head / body / legs height of the strike, for step 3)
-- The deepest forward point in each window is one sample. Result per clip: median and p90 of
-- forward, median height, sample count; JSON in the client's Workspace StrikeReach_<LABEL>.

local LABEL = "reach"
local DURATION = 120

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationConfig = require(ReplicatedStorage.QuinCore.AnimationConfig)
local folder = Workspace:WaitForChild("QuinServer", 10)

local clipName = {}
local function walk(tbl, path)
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			if type(v.id) == "string" and v.id ~= "" then clipName[v.id] = path .. k else walk(v, path .. k .. ".") end
		end
	end
end
walk(AnimationConfig.Registry.Attacks or {}, "")

local samples = {} -- clip -> { forward = {}, height = {} }
local open = {}    -- track -> { model, limbs, best, bestH }
local hooked = setmetatable({}, { __mode = "k" })

local function limbBones(model, limb)
	local names = limb and { limb } or { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }
	local out = {}
	for _, n in ipairs(names) do
		local b = model:FindFirstChild("mixamorig:" .. n, true)
		if b then table.insert(out, b) end
	end
	return out
end

local function hook(model, track)
	if hooked[track] then return end
	local id = track.Animation and track.Animation.AnimationId
	local name = id and clipName[id]
	if not name then return end
	hooked[track] = true
	track:GetMarkerReachedSignal("HitStart"):Connect(function(param)
		open[track] = { model = model, clip = name, limbs = limbBones(model, param ~= "" and param or nil), best = -math.huge, bestH = 0 }
	end)
	track:GetMarkerReachedSignal("HitEnd"):Connect(function()
		local o = open[track]
		open[track] = nil
		if o and o.best > -math.huge then
			local s = samples[o.clip] or { forward = {}, height = {} }
			samples[o.clip] = s
			table.insert(s.forward, o.best)
			table.insert(s.height, o.bestH)
		end
	end)
end

local t0 = os.clock()
local function finish()
	RunService:UnbindFromRenderStep("StrikeReachProbe")
	local function q(list, p)
		if #list == 0 then return nil end
		table.sort(list)
		return math.floor(list[math.clamp(math.ceil(#list * p), 1, #list)] * 100) / 100
	end
	local out = { label = LABEL, clips = {} }
	for clip, s in pairs(samples) do
		out.clips[clip] = { n = #s.forward, forwardMedian = q(s.forward, 0.5), forwardP90 = q(s.forward, 0.9), heightMedian = q(s.height, 0.5) }
	end
	Workspace:SetAttribute("StrikeReach_" .. LABEL, HttpService:JSONEncode(out))
end

RunService:BindToRenderStep("StrikeReachProbe", Enum.RenderPriority.Last.Value, function()
	if os.clock() - t0 >= DURATION then finish() return end
	pcall(function()
		for _, model in ipairs(folder:GetChildren()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do hook(model, track) end
			end
		end
		for track, o in pairs(open) do
			local root = o.model:FindFirstChild("HumanoidRootPart")
			if not root or not track.IsPlaying then
				open[track] = nil
			else
				for _, bone in ipairs(o.limbs) do
					local p = root.CFrame:PointToObjectSpace(bone.TransformedWorldCFrame.Position)
					if -p.Z > o.best then o.best, o.bestH = -p.Z, p.Y end
				end
			end
		end
	end)
end)

return "strike reach probe started: " .. LABEL .. ", " .. DURATION .. " s"
