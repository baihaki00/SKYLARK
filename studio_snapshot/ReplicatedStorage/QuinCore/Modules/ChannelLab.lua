--// ChannelLab.lua
-- Studio test bench for body channels (FIGHT_PROGRAMME.md step 2): makes arms-only copies of the
-- strike clips so the owner can judge, by eye, a punch thrown over moving legs before any clip is
-- authored or uploaded.
--   armsOnly(id)            the clip with its legs taken out: the Hips key is emptied (weight 0) and
--                           both legs' keys are removed; the hips' turn and tilt move into the Spine
--                           key, so the chest, shoulders and arm keep the angle they had in the full
--                           clip (owner 2026-10-29: without it the punch went up into the air, aimed
--                           by the stance's hips). The hips' drop is left to the legs. Markers stay.
--   setArmsOnlyPunches(on)  Studio play only: every AnimationConfig.Attacks.Punches entry plays its
--                           arms-only copy (channel "Arms") or goes back to its own clip. The copies
--                           have temporary ids (KeyframeSequenceProvider:RegisterKeyframeSequence)
--                           that only work in Studio; the server starts it from the Workspace
--                           attribute Test_ArmsOnlyPunches.
--   saveArmsOnlyPunches()   Edit mode: the copies as KeyframeSequences in ServerStorage.ArmsOnlyClips,
--                           for the owner to publish (right-click > Save to Roblox) once they look
--                           right; the new ids then go in AnimationConfig with channel = "Arms".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local StrikeMarkers = require(QuinCore:WaitForChild("Modules"):WaitForChild("StrikeMarkers"))

local ChannelLab = {}

local HIPS = "mixamorig:Hips"
local SPINE = "mixamorig:Spine"
-- the Spine bone's rest offset from the Hips on the Quin rigs (male and female alike), used when no
-- live Quin is there to read it from
local SPINE_REST = CFrame.new(0, 0.437, 0.054) * CFrame.Angles(math.rad(7), 0, 0)

local function spineRest()
	local folder = workspace:FindFirstChild("QuinServer")
	for _, model in ipairs(folder and folder:GetChildren() or {}) do
		local bone = model:FindFirstChild(SPINE, true)
		if bone and bone:IsA("Bone") then return bone.CFrame end
	end
	return SPINE_REST
end
local LEG_ROOTS = { ["mixamorig:LeftUpLeg"] = true, ["mixamorig:RightUpLeg"] = true }

function ChannelLab.armsOnly(sourceId)
	local sequence = KeyframeSequenceProvider:GetKeyframeSequenceAsync(sourceId)
	local rest = spineRest()
	for _, keyframe in ipairs(sequence:GetKeyframes()) do
		local legs = {}
		for _, pose in ipairs(keyframe:GetDescendants()) do
			if pose:IsA("Pose") then
				if pose.Name == HIPS then
					-- the spine takes over the hips' rotation about the hips (same chest in the root's
					-- space): rest^-1 * hipsRotation * rest * spine
					local spine = pose:FindFirstChild(SPINE)
					if spine and spine:IsA("Pose") and pose.Weight > 0 then
						spine.CFrame = rest:Inverse() * pose.CFrame.Rotation * rest * spine.CFrame
						spine.Weight = 1
					end
					pose.Weight = 0
					pose.CFrame = CFrame.identity
				elseif LEG_ROOTS[pose.Name] then
					table.insert(legs, pose)
				end
			end
		end
		for _, pose in ipairs(legs) do pose:Destroy() end
	end
	return sequence
end

local swapped = {} -- entry -> its own id

function ChannelLab.setArmsOnlyPunches(on)
	if not RunService:IsStudio() then return end
	local punches = AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Punches or {}
	for name, entry in pairs(punches) do
		if on and not swapped[entry] then
			local ok, sequence = pcall(ChannelLab.armsOnly, entry.id)
			if ok then
				local newId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
				StrikeMarkers.alias(entry.id, newId)
				swapped[entry] = entry.id
				entry.id = newId
				entry.channel = "Arms"
			else
				warn("[ChannelLab] " .. name .. ": " .. tostring(sequence))
			end
		elseif not on and swapped[entry] then
			entry.id = swapped[entry]
			entry.channel = nil
			swapped[entry] = nil
		end
	end
	print("[ChannelLab] arms-only punches " .. (on and "on" or "off"))
end

function ChannelLab.saveArmsOnlyPunches()
	local folder = game:GetService("ServerStorage"):FindFirstChild("ArmsOnlyClips") or Instance.new("Folder")
	folder.Name = "ArmsOnlyClips"
	folder.Parent = game:GetService("ServerStorage")
	local punches = AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Punches or {}
	for name, entry in pairs(punches) do
		local sequence = ChannelLab.armsOnly(swapped[entry] or entry.id)
		sequence.Name = name .. "_ArmsOnly"
		local old = folder:FindFirstChild(sequence.Name)
		if old then old:Destroy() end
		sequence.Parent = folder
	end
	return folder
end

return ChannelLab
