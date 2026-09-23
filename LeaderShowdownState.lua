--// LeaderShowdownState.lua
-- Phase 12: Leader Showdown FSM State
-- Governs Duelist focus and Organic Quirky-Driven Spectator Staging (On-Platform vs Ground, Sitting, Taunting)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local LeaderShowdownState = { name = "LeaderShowdown" }

local showdownData = {}

local ARENA_CENTER = Vector3.new(0, 2.0, -38.0)
local PLATFORM_RADIUS = 48.0
local PLATFORM_HEIGHT = 4.5
local INNER_RING_RADIUS = 36.0

local DAIS_TOP_Y = ARENA_CENTER.Y + PLATFORM_HEIGHT        -- 6.50
local STAND_OFFSET = 5.33                                  -- Exact sole-to-HRP height
local PLATFORM_STAND_Y = DAIS_TOP_Y + STAND_OFFSET         -- 11.83
local GROUND_STAND_Y = ARENA_CENTER.Y + STAND_OFFSET       -- 7.33
local GROUND_SIT_Y = ARENA_CENTER.Y + 2.40                 -- 4.40

function LeaderShowdownState.enter(fighter, humanoid, rootPart)
	local role = fighter:GetAttribute("LeaderShowdownRole") or "PerimeterGuard"
	local quirky = fighter:GetAttribute("Quirky") or fighter:GetAttribute("AssignedQuirky") or "Observer"
	local angle = fighter:GetAttribute("PerimeterAngle") or 0
	local radius = fighter:GetAttribute("SpectatorRadius") or 42.0
	local platformStatus = fighter:GetAttribute("SpectatorPlatformStatus") or "OnPlatform"

	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	showdownData[fighter] = {
		enterTime = tick(),
		role = role,
		quirky = quirky,
		perimeterAngle = angle,
		spectatorRadius = radius,
		platformStatus = platformStatus,
		lastActionTime = tick(),
		pacingOffset = 0,
	}

	-- Quirky initial posture
	if role == "PerimeterGuard" then
		if quirky == "Lazy" and platformStatus == "OnGround" then
			-- Relaxed seated posture on the arena floor near dais base
			pcall(function() humanoid.Sit = true end)
		elseif quirky == "Showoff" then
			AnimationModule.playConfig(humanoid, "Emotes.Victory", 1.0, Enum.AnimationPriority.Action)
		else
			AnimationModule.playIdle(humanoid, 0.9)
		end
	elseif role == "Duelist" then
		AnimationModule.playConfig(humanoid, "Locomotion.ConfidentWalk", 1.1, Enum.AnimationPriority.Movement)
	end
end

function LeaderShowdownState.exit(fighter, humanoid, rootPart)
	local data = showdownData[fighter]
	if data and data.quirky == "Lazy" then
		pcall(function() humanoid.Sit = false end)
	end
	humanoid.AutoRotate = true
	local baseSpeed = fighter:GetAttribute("Speed") or 40
	humanoid.WalkSpeed = baseSpeed
	showdownData[fighter] = nil
end

function LeaderShowdownState.update(fighter, humanoid, rootPart, DEBUG)
	local role = fighter:GetAttribute("LeaderShowdownRole") or "PerimeterGuard"
	local data = showdownData[fighter]
	if not data then
		if role == "PerimeterGuard" or role == "Transition" then
			LeaderShowdownState.enter(fighter, humanoid, rootPart)
			data = showdownData[fighter]
		else
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	local now = tick()

	-- 1. DUELIST BEHAVIOR
	if role == "Duelist" then
		local targetName = fighter:GetAttribute("TargetQuin") or fighter:GetAttribute("CurrentTarget")
		if targetName and targetName ~= "" then
			local target = workspace:FindFirstChild(targetName, true)
			if target and target:FindFirstChild("HumanoidRootPart") then
				local tHRP = target.HumanoidRootPart
				local lookAt = CFrame.lookAt(rootPart.Position, Vector3.new(tHRP.Position.X, rootPart.Position.Y, tHRP.Position.Z))
				rootPart.CFrame = rootPart.CFrame:Lerp(lookAt, 0.25)
			end
		end

		-- If duel is actively authorized by server, transition to FightState
		local sys = _G.LeaderShowdownSystem or shared.LeaderShowdownSystem
		if sys and sys.activePhase == "DuelActive" then
			return require(script.Parent:WaitForChild("FightState"))
		end
		return LeaderShowdownState
	end

	-- 2. PERIMETER SPECTATOR BEHAVIOR (Organic Leisurely Staging)
	if role == "PerimeterGuard" then
		local quirky = data.quirky
		local angle = fighter:GetAttribute("PerimeterAngle") or data.perimeterAngle or 0
		local radius = fighter:GetAttribute("SpectatorRadius") or data.spectatorRadius or 42.0
		local platformStatus = fighter:GetAttribute("SpectatorPlatformStatus") or data.platformStatus or "OnPlatform"

		local targetY = PLATFORM_STAND_Y
		if platformStatus == "OnGround" then
			targetY = (quirky == "Lazy") and GROUND_SIT_Y or GROUND_STAND_Y
		end

		-- Target horizontal spot
		local desiredPos = ARENA_CENTER + Vector3.new(math.cos(angle) * radius, targetY - ARENA_CENTER.Y, math.sin(angle) * radius)

		-- ZERO SINKING FEET: Do NOT overwrite physics Y coordinate if already grounded!
		local currentY = rootPart.Position.Y
		if currentY < (targetY - 3.5) or currentY > (targetY + 6.0) then
			-- Teleport/snap back if fallen or out of bounds
			currentY = targetY
		end

		local distErr = Vector2.new(rootPart.Position.X - desiredPos.X, rootPart.Position.Z - desiredPos.Z).Magnitude

		if distErr <= 3.5 then
			-- At designated spectator spot: face center smoothly
			if humanoid.WalkSpeed > 0 then
				humanoid.WalkSpeed = 0
				humanoid:MoveTo(rootPart.Position)
				AnimationModule.playIdle(humanoid, 0.9)
			end
			local lookAtCF = CFrame.lookAt(rootPart.Position, Vector3.new(ARENA_CENTER.X, rootPart.Position.Y, ARENA_CENTER.Z))
			rootPart.CFrame = rootPart.CFrame:Lerp(lookAtCF, 0.15)
		else
			-- In transit: walk naturally towards designated mark (no teleporting)
			if humanoid.WalkSpeed <= 1 then
				humanoid.WalkSpeed = 16
				humanoid:MoveTo(Vector3.new(desiredPos.X, rootPart.Position.Y, desiredPos.Z))
				AnimationModule.playConfig(humanoid, "Locomotion.ConfidentWalk", 1.0, Enum.AnimationPriority.Movement)
			end
		end

		-- Quirky periodic behavioral flair
		if (now - data.lastActionTime) >= 3.8 then
			data.lastActionTime = now

			if quirky == "Showoff" then
				-- Taunt / Flex towards the duelists
				AnimationModule.playConfig(humanoid, "Attacks.Kicks.PowerKick", 0.85, Enum.AnimationPriority.Action)
			elseif quirky == "Revengeful" then
				-- Restless twitch / boundary pacing jitter
				local jitter = (math.random() - 0.5) * 0.18
				rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, jitter, 0)
			elseif quirky == "Observer" then
				-- Calm head tracking
				AnimationModule.playIdle(humanoid, 0.85)
			elseif quirky == "Lazy" and platformStatus == "OnGround" then
				-- Keep relaxed sitting posture
				pcall(function() humanoid.Sit = true end)
			end
		end

		-- Stay in LeaderShowdownState until the entire showdown completes
		return LeaderShowdownState
	end

	return LeaderShowdownState
end

return LeaderShowdownState
