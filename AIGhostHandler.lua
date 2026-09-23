local enableghostmode = true

if enableghostmode then
	--// AIGhostHandler.client.lua
	-- Client-side visual ghost replicator for server-owned AI (pure visual, visible)
	-- Integrates procedural LookController for dynamic head, neck, and upper torso tracking

	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CollectionService = game:GetService("CollectionService")
	local QuinServer = Workspace:FindFirstChild("QuinServer")

	local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
	local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
	local LookController = require(QuinCore:WaitForChild("Modules"):WaitForChild("LookController"))
	local ProceduralCombatReactionController = require(QuinCore:WaitForChild("Modules"):WaitForChild("ProceduralCombatReactionController"))

	-- === SETTINGS ===
	local AI_TAG = "Quin" -- Pattern for server NPCs
	local SMOOTH_FACTOR = 0.4 -- 0.1 = loose, 0.25 = medium, 0.4 = tight
	local ghostMap = {} -- aiModel -> ghostModel
	local ghostLookControllers = {} -- ghostModel -> LookController instance
	local ghostReactionControllers = {} -- ghostModel -> ProceduralCombatReactionController instance

	_G.GhostLookControllers = ghostLookControllers
	shared.GhostLookControllers = ghostLookControllers
	_G.GhostReactionControllers = ghostReactionControllers
	shared.GhostReactionControllers = ghostReactionControllers

	-- Create a folder to store all ghosts safely (under Workspace)
	local GhostFolder = Workspace:FindFirstChild("QuinGhost")
	if not GhostFolder then
		GhostFolder = Instance.new("Folder")
		GhostFolder.Name = "QuinGhost"
		GhostFolder.Parent = Workspace
	end

	-- Clean up any stale ghosts on initialization
	for _, child in ipairs(GhostFolder:GetChildren()) do
		child:Destroy()
	end
	-----------------------------------------------------------

	-- === FUNCTION: Create ghost clone (no skin changes) ===
	local function createGhost(aiModel)
		if ghostMap[aiModel] then return end
		if not aiModel or not aiModel:IsA("Model") then return end
		if aiModel.Parent == GhostFolder or aiModel:IsDescendantOf(GhostFolder) or string.find(aiModel.Name, "_Visual") then
			return
		end

		ghostMap[aiModel] = "pending" -- Prevent concurrent creation calls during yield

		-- Wait for Alpha_Surface to replicate so the mesh is not missing
		local alpha = aiModel:WaitForChild("Alpha_Surface", 5)
		if not alpha then
			warn("[AIGhostHandler] Timed out waiting for Alpha_Surface on " .. aiModel.Name)
			ghostMap[aiModel] = nil
			return
		end

		if not aiModel.Parent then
			ghostMap[aiModel] = nil
			return
		end

		aiModel.Archivable = true
		local ghost = aiModel:Clone()
		if not ghost then
			warn("[AIGhostHandler] Failed to clone " .. aiModel.Name)
			ghostMap[aiModel] = nil
			return
		end

		-- Strip ALL CollectionService tags so this ghost is never tagged as a Quin
		for _, tag in ipairs(CollectionService:GetTags(ghost)) do
			CollectionService:RemoveTag(ghost, tag)
		end

		ghost.Name = aiModel.Name .. "_Visual"
		ghost.Parent = GhostFolder
		ghost:MakeJoints()

		-- Disable physics & scripts only; keep visuals intact
		for _, desc in ipairs(ghost:GetDescendants()) do
			if desc:IsA("BasePart") then
				-- Only anchor the root; let Motor6Ds + Animator drive everything else
				if desc.Name == "HumanoidRootPart" then
					desc.Anchored = true
					local gui = desc:FindFirstChild("BillboardGui")
					if gui then
						gui.Enabled = false
					end
				else
					desc.Anchored = false
				end
				desc.CanCollide = false
				desc.Massless = true

				-- Set visibility: Alpha_Surface must be visible!
				if desc.Name == "Alpha_Surface" then
					desc.Transparency = 0
					desc.LocalTransparencyModifier = 0
					desc.CastShadow = true
				elseif desc.Name == "TeamRing" then
					desc:Destroy()
				else
					desc.Transparency = 1
					desc.LocalTransparencyModifier = 0
					desc.CastShadow = false
				end
			elseif desc:IsA("Script") or desc:IsA("LocalScript") then
				desc:Destroy()
			elseif desc:IsA("Highlight") and desc.Name == "ElementHighlight" then
				desc.Adornee = ghost
			end
		end

		-----------------------------------------------------------
		-- ANIMATION SYNC
		-----------------------------------------------------------
		local realHumanoid = aiModel:FindFirstChildOfClass("Humanoid")
		local ghostHumanoid = ghost:FindFirstChildOfClass("Humanoid")

		if realHumanoid and ghostHumanoid then
			if not ghostHumanoid:FindFirstChildOfClass("Animator") then
				local animator = Instance.new("Animator")
				animator.Parent = ghostHumanoid
			end

			task.spawn(function()
				while aiModel.Parent and ghostHumanoid.Parent do
					local tracks = realHumanoid:GetPlayingAnimationTracks()
					local ghostTracks = ghostHumanoid:GetPlayingAnimationTracks()

					local playingIds = {}
					for _, track in ipairs(tracks) do
						if track.Animation then
							playingIds[track.Animation.AnimationId] = track
						end
					end

					-- Stop ghost tracks not on real
					for _, gTrack in ipairs(ghostTracks) do
						if not playingIds[gTrack.Animation.AnimationId] then
							gTrack:Stop(0.1)
						end
					end

					-- Play any missing tracks
					for animId, track in pairs(playingIds) do
						local alreadyPlaying = false
						for _, gTrack in ipairs(ghostTracks) do
							if gTrack.Animation.AnimationId == animId then
								alreadyPlaying = true
								gTrack:AdjustSpeed(track.Speed)
								gTrack.Looped = track.Looped
								gTrack.Priority = track.Priority
							end
						end
						if not alreadyPlaying then
							local anim = Instance.new("Animation")
							anim.AnimationId = animId
							local ghostTrack = ghostHumanoid:LoadAnimation(anim)
							ghostTrack.Looped = track.Looped
							ghostTrack.Priority = track.Priority
							ghostTrack:Play(0.1, 1, track.Speed)
							anim:Destroy()
						end
					end

					-- If no animations playing, stop ghost's too
					if #tracks == 0 then
						for _, gTrack in ipairs(ghostTracks) do
							gTrack:Stop(0.2)
						end
					end

					task.wait(0.05)
				end
			end)
		end

		-- Attach procedural LookController to this visual ghost
		local lookCtrl = LookController.new(ghost, aiModel)
		ghostLookControllers[ghost] = lookCtrl

		-- Attach procedural Combat Reaction Controller to this visual ghost
		local reactionCtrl = ProceduralCombatReactionController.new(ghost, aiModel)
		ghostReactionControllers[ghost] = reactionCtrl

		ghostMap[aiModel] = ghost
	end

	-----------------------------------------------------------
	-- FUNCTION: Remove ghost
	-----------------------------------------------------------
	local function removeGhost(aiModel)
		local ghost = ghostMap[aiModel]
		if ghost and typeof(ghost) == "Instance" then
			if ghostLookControllers[ghost] then
				ghostLookControllers[ghost]:destroy()
				ghostLookControllers[ghost] = nil
			end
			if ghostReactionControllers[ghost] then
				ghostReactionControllers[ghost]:destroy()
				ghostReactionControllers[ghost] = nil
			end
			ghost:Destroy()
		end
		ghostMap[aiModel] = nil
	end

	-----------------------------------------------------------
	-- LOOP: Detect server AI and create/remove ghosts
	-----------------------------------------------------------
	RunService.Heartbeat:Connect(function()
		if not QuinServer then
			QuinServer = Workspace:FindFirstChild("QuinServer")
		end

		local candidates = {}
		if QuinServer then
			for _, aiModel in ipairs(QuinServer:GetChildren()) do
				if aiModel:IsA("Model") and aiModel:FindFirstChild("HumanoidRootPart") and not string.find(aiModel.Name, "_Visual") then
					table.insert(candidates, aiModel)
				end
			end
		end

		for _, tagged in ipairs(CollectionService:GetTagged("Quin")) do
			if tagged:IsA("Model") and tagged.Parent ~= GhostFolder and not tagged:IsDescendantOf(GhostFolder) and not string.find(tagged.Name, "_Visual") and tagged:FindFirstChild("HumanoidRootPart") and not table.find(candidates, tagged) then
				table.insert(candidates, tagged)
			end
		end

		for _, aiModel in ipairs(candidates) do
			if not ghostMap[aiModel] then
				createGhost(aiModel)
			end
		end

		-- Cleanup destroyed ones
		for aiModel, _ in pairs(ghostMap) do
			if not aiModel.Parent then
				removeGhost(aiModel)
			end
		end
	end)

	-----------------------------------------------------------
	-- LOOP: Smooth visual update & procedural look-at (RenderStepped)
	-----------------------------------------------------------
	RunService.RenderStepped:Connect(function(dt)
		for aiModel, ghost in pairs(ghostMap) do
			if typeof(ghost) == "Instance" then
				local root = aiModel:FindFirstChild("HumanoidRootPart")
				local ghostRoot = ghost:FindFirstChild("HumanoidRootPart")

				if root and ghostRoot then
					local yOffset = CombatConfig.VisualGhostHeightOffset or 0.16
					local targetCF = root.CFrame * CFrame.new(0, yOffset, 0)
					
					-- Adaptive frame-rate independent exponential smoothing
					local currentVel = root.AssemblyLinearVelocity
					local flatSpeed = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
					local distErr = (ghostRoot.Position - targetCF.Position).Magnitude
					local lambda = 25.0 + 0.35 * flatSpeed + math.max(0, (distErr - 0.8) * 20.0)
					local alpha = 1.0 - math.exp(-lambda * dt)
					alpha = math.clamp(alpha, 0.10, 1.0)
					
					ghostRoot.CFrame = ghostRoot.CFrame:Lerp(targetCF, alpha)
				end

				local isDead = (aiModel:GetAttribute("CurrentState") == "Death")
				local deathFade = aiModel:GetAttribute("DeathFadeAlpha")

				-- Visual dissolve fade-out
				if deathFade and deathFade > 0 then
					for _, part in ipairs(ghost:GetDescendants()) do
						if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
							part.Transparency = math.max(part.Transparency, deathFade)
						elseif part:IsA("Decal") or part:IsA("Texture") then
							part.Transparency = math.max(part.Transparency, deathFade)
						end
					end
				end

				-- 1. Procedural combat reaction controller (hips, spine, neck, head)
				local reactionCtrl = ghostReactionControllers[ghost]
				if reactionCtrl and not isDead then
					reactionCtrl:update(dt)
					ghost:SetAttribute("ReactionType", reactionCtrl.activeReactionType)
					ghost:SetAttribute("ReactionPitch", math.round(math.deg(reactionCtrl.currentPitch) * 10) / 10)
					ghost:SetAttribute("ReactionRoll", math.round(math.deg(reactionCtrl.currentRoll) * 10) / 10)
					ghost:SetAttribute("ReactionHips", math.round(reactionCtrl.hipsOffset * 100) / 100)
				end

				-- 2. Procedural look controller (head, neck, spine2)
				local lookCtrl = ghostLookControllers[ghost]
				if lookCtrl and not isDead then
					lookCtrl:update(dt)
					ghost:SetAttribute("LookMode", lookCtrl.gazeMode)
					ghost:SetAttribute("GazeYaw", math.round(math.deg(lookCtrl.currentYaw)))
					ghost:SetAttribute("GazePitch", math.round(math.deg(lookCtrl.currentPitch)))
				end
			end
		end
	end)

end