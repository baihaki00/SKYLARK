--// DeathState.lua
-- Handles death: ragdoll, fade out, cleanup, notify game mode manager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local DeathState = { name = "Death" }

function DeathState.enter(fighter, humanoid, rootPart)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	AnimationModule.stopAll(humanoid, 0.1)
	
	-- Halt physics drift
	if rootPart then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
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
	
	-- Play cinematic death animation (OnTheSpot vs Standard)
	local deathType = fighter:GetAttribute("DeathType") or "Standard"
	local animPath = (deathType == "OnTheSpot") and "Reactions.DeathOnTheSpot" or "Reactions.Death"
	AnimationModule.playConfig(humanoid, animPath, 1.0, Enum.AnimationPriority.Action4, false)
	
	-- Smooth dissolve / fade-out sequence after floor collapse
	task.spawn(function()
		task.wait(CombatConfig.DeathImpactDelay or 1.2) -- Allow full collapse animation before fading
		local steps = 24
		local stepWait = 1.2 / steps
		for i = 1, steps do
			if not fighter or not fighter.Parent then break end
			local alpha = i / steps
			fighter:SetAttribute("DeathFadeAlpha", alpha)
			task.wait(stepWait)
		end
	end)
	
	-- Cleanup after delay
	local cleanupDelay = CombatConfig.DeathCleanupDelay or 3.2
	task.delay(cleanupDelay, function()
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
