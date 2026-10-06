--// StrikeMarkers.lua
-- The timing the owner authored inside each strike clip (COMBAT_ANIMATION_GUIDE.md, Part 1):
--   HitStart / HitEnd   the limb is dangerous between these (FightState checks for contact every
--                       frame of that window)
--   Recover             the move is done: the Quin is free to act and move again
--   Windup              the tell: the first frame the attack can be read (Modules/Instinct)
-- Times are in seconds of the clip at speed 1. Read once per asset from the published animation
-- (KeyframeSequenceProvider; ~0.4 s each) and cached. Every strike clip is read at server start
-- (Server.server.lua: StrikeMarkers.preload) so none is read in the middle of a fight; a clip that
-- has not been read yet, or has no markers, returns nil and the caller uses its config ratios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))

local StrikeMarkers = {}

local cache = {}   -- asset id -> { length, hitStart, hitEnd, recover, limb } | false (no usable markers)
local loading = {} -- asset id -> os.clock() the read started

local RETRY_AFTER = 5 -- seconds before a read that never finished is tried again

local function read(id)
	loading[id] = os.clock()
	local ok, sequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(id)
	end)
	loading[id] = nil
	if not ok or not sequence then
		warn("[StrikeMarkers] could not read " .. tostring(id) .. ": " .. tostring(sequence))
		return
	end
	local found = { length = 0 }
	for _, keyframe in ipairs(sequence:GetKeyframes()) do
		found.length = math.max(found.length, keyframe.Time)
		for _, marker in ipairs(keyframe:GetMarkers()) do
			if marker.Name == "HitStart" then
				found.hitStart = keyframe.Time
				found.limb = marker.Value ~= "" and marker.Value or nil
			elseif marker.Name == "HitEnd" then
				found.hitEnd = keyframe.Time
			elseif marker.Name == "Recover" then
				found.recover = keyframe.Time
			elseif marker.Name == "Windup" then
				found.windup = keyframe.Time -- (the tell: the first frame a defender can read it)
			end
		end
	end
	-- A window needs both ends, in order; Recover is optional (the config ratio stands in)
	if found.hitStart and found.hitEnd and found.hitEnd >= found.hitStart and found.length > 0 then
		cache[id] = found
	else
		cache[id] = false
		warn("[StrikeMarkers] " .. tostring(id) .. " has no HitStart/HitEnd pair: config ratios are used")
	end
end

-- The markers of a clip, or nil (not read yet, or none). Never yields: a clip not read yet is read
-- in the background for next time.
function StrikeMarkers.get(id)
	if not id or id == "" then return nil end
	local entry = cache[id]
	if entry ~= nil then return entry or nil end
	if not loading[id] or os.clock() - loading[id] > RETRY_AFTER then
		task.spawn(read, id)
	end
	return nil
end

-- Every strike clip in AnimationConfig.Attacks, read now (in the background)
function StrikeMarkers.preload()
	local function walk(tbl)
		for _, v in pairs(tbl) do
			if type(v) == "table" then
				if type(v.id) == "string" then
					if v.id ~= "" and cache[v.id] == nil and not loading[v.id] then
						task.spawn(read, v.id)
					end
				else
					walk(v)
				end
			end
		end
	end
	walk(AnimationConfig.Registry.Attacks or {})
end

return StrikeMarkers
