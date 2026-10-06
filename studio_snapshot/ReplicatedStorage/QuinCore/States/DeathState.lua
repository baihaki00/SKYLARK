--// DeathState.lua
-- A defeated Quin: it goes down with its death clip, lies there for a moment, breaks up in a
-- holographic glitch and is removed. Nothing is cut short: the clip plays to its end, held on its
-- last frame, and the body is removed only after the glitch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local DeathState = { name = "Death" }

-- The body is held where a living Quin stands. A dead Humanoid stops holding its root up: about a
-- second after the knockout the root dropped from 4.9 studs above the floor to 0.9 while the clip
-- was lowering the body from that same root, and the feet ended 3 studs under the ground. A Quin
-- that dies in the air is brought down to the floor first.
local function holdBody(fighter, humanoid, rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local floor = Workspace:Raycast(rootPart.Position, Vector3.new(0, -400, 0), params)
	if not floor then return end
	local standHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	local look = rootPart.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = facing.Magnitude > 0.05 and facing.Unit or Vector3.new(0, 0, -1)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DeathHoldAtt"
	attachment.Parent = rootPart

	local position = Instance.new("AlignPosition")
	position.Name = "DeathHold"
	position.Mode = Enum.PositionAlignmentMode.OneAttachment
	position.Attachment0 = attachment
	position.Position = Vector3.new(rootPart.Position.X, floor.Position.Y + standHeight, rootPart.Position.Z)
	position.MaxForce = 1e6
	position.MaxVelocity = CombatConfig.Death_SettleSpeed or 90
	position.Responsiveness = 40
	position.Parent = rootPart

	local upright = Instance.new("AlignOrientation")
	upright.Name = "DeathUpright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = attachment
	upright.CFrame = CFrame.lookAt(Vector3.zero, facing)
	upright.MaxTorque = 1e6
	upright.Responsiveness = 40
	upright.Parent = rootPart
end

function DeathState.enter(fighter, humanoid, rootPart)
	require(QuinCore.Modules.Drives).onAllyDown(fighter) -- (its allies close by: fury)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	AnimationModule.stopAll(humanoid, 0.1)

	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		holdBody(fighter, humanoid, rootPart)
	end

	-- Sound
	local soundPart = fighter:FindFirstChild("Sounds")
	if soundPart then
		local deathSound = soundPart:FindFirstChild("death")
		if deathSound then
			deathSound.Volume = 0.3
			deathSound:Play()
		end
	end

	-- Notify game mode manager
	local elimEvent = ReplicatedStorage:FindFirstChild("QuinEliminated")
	if not elimEvent then
		elimEvent = Instance.new("BindableEvent")
		elimEvent.Name = "QuinEliminated"
		elimEvent.Parent = ReplicatedStorage
	end
	elimEvent:Fire(fighter.Name, fighter:GetAttribute("Team") or "None", fighter:GetAttribute("QuinType") or "Unknown")

	-- The death clip (OnTheSpot vs Standard), played to its end and held on its last frame
	local deathType = fighter:GetAttribute("DeathType") or "Standard"
	local animPath = (deathType == "OnTheSpot") and "Reactions.DeathOnTheSpot" or "Reactions.Death"
	local track = AnimationModule.playConfig(humanoid, animPath, 1.0, Enum.AnimationPriority.Action4, false)
	local clipTime = AnimationModule.getEffectiveDuration(humanoid, animPath, 1.0)
	if not clipTime or clipTime <= 0.2 then
		clipTime = CombatConfig.Death_FallbackClipTime or 2.5
	end
	task.delay(clipTime * 0.96, function()
		if track and fighter.Parent then
			track:AdjustSpeed(0)
		end
	end)

	-- Then it lies there a moment, breaks up, and only then is removed
	local rest = CombatConfig.Death_RestTime or 0.6
	local glitch = CombatConfig.Death_GlitchTime or 1.1
	task.delay(clipTime + rest, function()
		if fighter.Parent then
			VfxModule.holoGlitch(fighter, glitch, "out")
		end
	end)
	task.delay(clipTime + rest + glitch + 0.1, function()
		if fighter and fighter.Parent then
			AnimationModule.cleanup(humanoid)
			fighter:Destroy()
		end
	end)
end

function DeathState.exit(fighter, humanoid, rootPart)
	-- No exit from death
end

function DeathState.update(fighter, humanoid, rootPart, DEBUG)
	-- Dead. No updates. Just wait for cleanup.
	return DeathState
end

return DeathState
