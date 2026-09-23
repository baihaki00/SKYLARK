--// AnimationLabServer.server.lua
-- Server controller for the interactive Animation Lab
-- Handles animation commands, combo sequencing, live combat mode toggle, and persistent place file synchronization

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AudioModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AudioModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))

local Events = QuinCore:WaitForChild("Events")
local labEvent = Events:WaitForChild("AnimationLabEvent")
local animationStore = DataStoreService:GetDataStore("KibaAnimationLabOverrides_v1")
local persistentOverrides = {}

-- Safe track playback using AnimationModule's built-in cache (zero track leakage)
local function playTrack(model, animId, speed, fadeTime, priorityName, looped)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or not animId or animId == "" then return nil end
	local prio = Enum.AnimationPriority[priorityName or "Action4"] or Enum.AnimationPriority.Action4
	return AnimationModule.play(hum, animId, prio, looped == true, speed or 1.0, fadeTime or 0.05)
end

local function stopAllTracks(model, fadeOut)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	AnimationModule.stopAll(hum, fadeOut or 0.1)
end

-- The lab writes its live configuration onto every active Quin, so it remains
-- inspectable and immediately usable by the current test actors.
local function applyConfigToCurrentQuins(path, entry)
	local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
	for _, model in ipairs(quinServer:GetDescendants()) do
		if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model.Name:find("Quin") then
			model:SetAttribute("AnimationLabPath", path)
			model:SetAttribute("AnimationLabId", entry.id or "")
			model:SetAttribute("AnimationLabSpeed", entry.speed or 1)
			model:SetAttribute("AnimationLabFadeTime", entry.fadeTime or 0.05)
			model:SetAttribute("AnimationLabPriority", entry.priority or "Action4")
			model:SetAttribute("AnimationLabLooped", entry.looped == true)
			model:SetAttribute("AnimationLabImpactRatio", entry.impactRatio or 0.35)
			model:SetAttribute("AnimationLabCancelRatio", entry.cancelRatio or 0.70)
			model:SetAttribute("AnimationLabStartCut", entry.startCut or 0)
			model:SetAttribute("AnimationLabEndCut", entry.endCut or 0)

			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local track = AnimationModule.getExistingTrack(humanoid, entry.id)
			if track and track.IsPlaying then
				track.Priority = Enum.AnimationPriority[entry.priority or "Action4"] or Enum.AnimationPriority.Action4
				track.Looped = entry.looped == true
				track:AdjustSpeed(entry.speed or 1)
			end
		end
	end
end

local function copyValues(entry)
	return {
		id = entry.id,
		speed = entry.speed,
		fadeTime = entry.fadeTime,
		priority = entry.priority,
		looped = entry.looped == true,
		impactRatio = entry.impactRatio,
		cancelRatio = entry.cancelRatio,
		startCut = entry.startCut,
		endCut = entry.endCut,
	}
end

-- Guard against silently overriding the source 'priority' field via lab overrides.
-- A stale priority override caused the "jab cancelled" animation bug (attacks dropped
-- to Action priority and were wiped by hit reactions). Source AnimationConfig stays authoritative.
local function sanitizeOverride(path, values)
	if type(values) ~= "table" then return values end
	if values.priority == nil then return values end

	local sourceEntry = AnimationConfig.get(path)
	local sourcePrio = sourceEntry and sourceEntry.priority
	if sourcePrio and values.priority ~= sourcePrio then
		warn(string.format("[AnimationLab] BLOCKED priority override for %s: requested=%s, source=%s (source is authoritative)",
			tostring(path), tostring(values.priority), tostring(sourcePrio)))
		values.priority = nil
	end
	return values
end

local function loadPersistentOverrides()
	local success, stored = pcall(function()
		return animationStore:GetAsync("Overrides")
	end)
	if not success then
		warn("[AnimationLab] Could not load persistent overrides: " .. tostring(stored))
		return
	end
	if type(stored) ~= "table" then return end
	for path, values in pairs(stored) do
		if type(path) == "string" and type(values) == "table" and AnimationConfig.get(path) then
			local sanitized = sanitizeOverride(path, values)
			AnimationConfig.update(path, sanitized)
			persistentOverrides[path] = copyValues(AnimationConfig.get(path))
		end
	end
	
	-- Broadcast to any clients that loaded before GetAsync finished
	labEvent:FireAllClients("ConfigSnapshot", { updates = persistentOverrides })
end

local function persistOverrides()
	return pcall(function()
		animationStore:SetAsync("Overrides", persistentOverrides)
	end)
end

loadPersistentOverrides()

local function getOrSpawnTesterRigs(force)
	local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
	local tester = quinServer:FindFirstChild("QuinA_Tester")
	local partner = quinServer:FindFirstChild("QuinB_SparringPartner")

	if force or not tester or not partner then
		local GMM = _G.GameModeManager
		if GMM and GMM.startTestAnimationMode then
			print("[AnimationLabServer] Spawning AnimationLab tester rigs (force=" .. tostring(force) .. ")...")
			GMM.startTestAnimationMode()
			local deadline = os.clock() + 3
			while (not tester or not partner) and os.clock() < deadline do
				task.wait(0.1)
				quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
				tester = quinServer:FindFirstChild("QuinA_Tester")
				partner = quinServer:FindFirstChild("QuinB_SparringPartner")
			end
		end
	end

	return tester, partner
end

-- Unified Action Handler (invokable by client remote or direct server dispatch)
local function handleLabAction(player, action, data)
	data = data or {}
	local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace

	if action == "EnsureTesterRigs" or action == "ResetTesterRigs" then
		local force = data and data.force == true
		local tester, partner = getOrSpawnTesterRigs(force)
		labEvent:FireAllClients("TesterRigsReady", {
			testerName = "QuinA_Tester",
			partnerName = "QuinB_SparringPartner",
			success = (tester ~= nil and partner ~= nil)
		})

	elseif action == "PlayAnimation" then
		local model = quinServer:FindFirstChild(data.targetName or "QuinA_Tester")
		if not model then
			model = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not model then return end

		stopAllTracks(model, data.fadeTime or 0.05)
		model:SetAttribute("AnimationLabPath", data.path or "")
		local track = playTrack(model, data.animId, data.speed or 1.0, data.fadeTime or 0.05, data.priority or "Action4", data.looped)
		
		if track then
			local startCut = tonumber(data.startCut) or 0
			local endCut = tonumber(data.endCut)
			if startCut > 0 then
				track.TimePosition = math.min(startCut, track.Length > 0 and track.Length or 5)
			end
			if endCut and endCut > startCut then
				local cutConn
				cutConn = RunService.Heartbeat:Connect(function()
					if not track.IsPlaying or not model.Parent then
						if cutConn then cutConn:Disconnect() end
						return
					end
					if track.TimePosition >= endCut then
						if data.looped then
							track.TimePosition = startCut
						else
							track:Stop(0.05)
							if cutConn then cutConn:Disconnect() end
						end
					end
				end)
			end
		end

		if track and not data.looped then
			local conn
			conn = track.Stopped:Connect(function()
				if conn then conn:Disconnect() end
				if model and model.Parent then
					local idleData = AnimationConfig.get("Movement.Idle")
					if idleData then
						playTrack(model, idleData.id, idleData.speed, 0.15, "Idle", true)
					end
				end
			end)
		end

	elseif action == "StopAnimation" then
		local model = quinServer:FindFirstChild(data.targetName or "QuinA_Tester")
		if model then
			stopAllTracks(model, 0.1)
			local idleData = AnimationConfig.get("Movement.Idle")
			if idleData then
				playTrack(model, idleData.id, idleData.speed, 0.15, "Idle", true)
			end
		end

	elseif action == "ScrubAnimation" then
		local model = quinServer:FindFirstChild(data.targetName or "QuinA_Tester")
		if not model then
			model = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not model then return end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum then return end

		local prio = Enum.AnimationPriority[data.priority or "Action4"] or Enum.AnimationPriority.Action4
		local track = AnimationModule.play(hum, data.animId, prio, false, 0, 0.01)
		if track then
			track:AdjustSpeed(0)
			track.TimePosition = math.clamp(data.timePos or 0, 0, track.Length > 0 and track.Length or 5)
		end

	elseif action == "PlayCombo" then
		local tester = quinServer:FindFirstChild(data.targetName or "QuinA_Tester")
		local partner = quinServer:FindFirstChild(data.partnerName or "QuinB_SparringPartner")
		if not tester or not partner then
			tester, partner = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not tester then return end

		task.spawn(function()
			local steps = data.steps or {}
			for i, step in ipairs(steps) do
				if not tester.Parent then break end
				
				local entry = AnimationConfig.get(step.path) or step
				local animId = entry.id
				local speed = step.customSpeed or entry.speed or 1.0
				local fade = step.customFade or entry.fadeTime or 0.02
				local impactRatio = entry.impactRatio or 0.35
				local cancelRatio = entry.cancelRatio or 0.70

				stopAllTracks(tester, fade)
				local track = playTrack(tester, animId, speed, fade, "Action4", false)
				if not track then break end

				local clipLength = track.Length > 0 and track.Length or 0.8
				local realDuration = clipLength / speed
				local impactDelay = realDuration * impactRatio
				local cancelDelay = realDuration * cancelRatio

				-- Play hit reaction on sparring partner at impact point
				if partner and partner.Parent then
					task.delay(impactDelay, function()
						if not partner or not partner.Parent then return end
						local pHRP = partner:FindFirstChild("HumanoidRootPart")
						local tHRP = tester:FindFirstChild("HumanoidRootPart")
						if pHRP then
							AudioModule.playImpact(pHRP.Position, i == #steps)
							if tHRP then
								local pushDir = (pHRP.Position - tHRP.Position).Unit
								KnockbackModule.applyMicroKnockback(partner, pushDir, i == #steps and 8.0 or 4.0)
							end
						end
						
						local reactPath = (i == #steps) and "Reactions.HitHeavy" or "Reactions.HitLight"
						local rEntry = AnimationConfig.get(reactPath)
						if rEntry then
							stopAllTracks(partner, 0.02)
							playTrack(partner, rEntry.id, rEntry.speed or 1.0, 0.02, "Action4", false)
						end
					end)
				end

				task.wait(cancelDelay)
			end

			task.wait(0.3)
			if tester.Parent then
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then
					stopAllTracks(tester, 0.15)
					playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true)
				end
			end
			if partner and partner.Parent then
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then
					stopAllTracks(partner, 0.15)
					playTrack(partner, idleData.id, idleData.speed, 0.15, "Idle", true)
				end
			end
		end)

	elseif action == "UpdateConfig" then
		if data.path and data.newValues and AnimationConfig.get(data.path) then
			local sanitized = sanitizeOverride(data.path, data.newValues)
			AnimationConfig.update(data.path, sanitized)
			local entry = AnimationConfig.get(data.path)
			persistentOverrides[data.path] = copyValues(entry)
			applyConfigToCurrentQuins(data.path, entry)
			labEvent:FireAllClients("ConfigUpdated", { path = data.path, newValues = persistentOverrides[data.path] })
			print("[AnimationLabServer] HOT-SWAP APPLIED for: " .. tostring(data.path))
		end

	elseif action == "SaveConfigPermanent" or action == "SaveAnimationConfig" then
		-- Apply any pending updates first
		if data.path and data.newValues and AnimationConfig.get(data.path) then
			local sanitized = sanitizeOverride(data.path, data.newValues)
			AnimationConfig.update(data.path, sanitized)
			local entry = AnimationConfig.get(data.path)
			persistentOverrides[data.path] = copyValues(entry)
			applyConfigToCurrentQuins(data.path, entry)
			labEvent:FireAllClients("ConfigUpdated", { path = data.path, newValues = persistentOverrides[data.path] })
		end
		if data.updates and type(data.updates) == "table" then
			for path, values in pairs(data.updates) do
				if AnimationConfig.get(path) then
					local sanitized = sanitizeOverride(path, values)
					AnimationConfig.update(path, sanitized)
					local entry = AnimationConfig.get(path)
					persistentOverrides[path] = copyValues(entry)
					applyConfigToCurrentQuins(path, entry)
				end
			end
		end

		-- Always export current full Luau registry
		local luauCode = data.luauCode or AnimationConfig.exportLuau()

		-- Attempt bridge persistence silently to bake to disk and Edit Mode if daemon is running
		local HttpService = game:GetService("HttpService")
		if not HttpService.HttpEnabled then pcall(function() HttpService.HttpEnabled = true end) end
		
		pcall(function()
			HttpService:PostAsync(
				"http://127.0.0.1:8765/save_animation_config",
				HttpService:JSONEncode({ luauCode = luauCode }),
				Enum.HttpContentType.ApplicationJson
			)
		end)
		
		-- Master native persistence: DataStoreService
		local dsOk, dsErr = persistOverrides()
		if dsOk then
			print("[AnimationLabServer] SUCCESS: Config permanently saved to DataStore / Production!")
			labEvent:FireClient(player, "SaveResult", {
				success = true,
				message = "Saved permanently to production."
			})
		else
			warn("[AnimationLabServer] DataStore Error:", dsErr)
			labEvent:FireClient(player, "SaveResult", {
				success = false,
				message = "DataStore Error: " .. tostring(dsErr)
			})
		end

	elseif action == "RequestConfigSnapshot" then
		labEvent:FireClient(player, "ConfigSnapshot", { updates = persistentOverrides })

	elseif action == "SetGameMode" then
		local mode = data.mode
		local GMM = _G.GameModeManager or shared.GameModeManager
		print("[AnimationLabServer] SetGameMode received: " .. tostring(mode))
		if mode == "1v1" then
			if GMM then
				if GMM.start1v1SparringMatch then
					GMM.start1v1SparringMatch()
				elseif GMM.startTestMode then
					GMM.startTestMode()
				end
			end
		elseif mode == "team" or mode == "2v2" then
			if GMM and GMM.startTeamBattle then
				local teamCount = tonumber(data.count) or 4
				print("[AnimationLabServer] Starting Team Battle with " .. tostring(teamCount) .. " per team (" .. tostring(teamCount * 2) .. " total).")
				GMM.startTeamBattle(teamCount)
			end
		elseif mode == "midair_clash" then
			if GMM and GMM.startMidAirClashMode then
				print("[AnimationLabServer] Starting Mid-Air Clash Mode!")
				GMM.startMidAirClashMode()
			end
		elseif mode == "ffa" then
			if GMM and GMM.startFreeForAll then
				GMM.startFreeForAll(tonumber(data.count) or 8)
			end
		elseif mode == "tournament" then
			if GMM and GMM.startTournament then
				GMM.startTournament()
			end
		elseif mode == "clean" then
			if _G.QuinSpawner and _G.QuinSpawner.cleanAll then
				_G.QuinSpawner.cleanAll()
			end
			Workspace:SetAttribute("CurrentMode", "None")
			Workspace:SetAttribute("MatchStarted", false)
		end
		labEvent:FireAllClients("GameModeChanged", { mode = mode, count = data.count })

	elseif action == "SetTestMode" then
		local testMode = data.mode
		print("[AnimationLabServer] SetTestMode received: " .. tostring(testMode))
		local GMM = _G.GameModeManager or shared.GameModeManager
		if testMode == "InfiniteStrafe" then
			local active = data.active == true
			Workspace:SetAttribute("InfiniteStrafeTest", active)
			print("[AnimationLabServer] InfiniteStrafeTest set to: " .. tostring(active))
			labEvent:FireAllClients("TestModeChanged", { mode = "InfiniteStrafe", active = active })
		elseif testMode == "AnimationLab" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			if GMM and GMM.startTestAnimationMode then
				GMM.startTestAnimationMode()
			end
			labEvent:FireAllClients("TestModeChanged", { mode = "AnimationLab", active = true })
		elseif testMode == "ProjectileJump" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			local style = tonumber(data.style) or 1
			if GMM and GMM.startJumpProjectileTestMode then
				GMM.startJumpProjectileTestMode(style)
			end
			labEvent:FireAllClients("TestModeChanged", { mode = "ProjectileJump", active = true, style = style })
		elseif testMode == "SmoothLanding" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			if GMM and GMM.startCleanSlateJumpState then
				GMM.startCleanSlateJumpState()
			end
			labEvent:FireAllClients("TestModeChanged", { mode = "SmoothLanding", active = true })
		elseif testMode == "Tournament" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			if GMM and GMM.startTournament then
				GMM.startTournament()
			end
			labEvent:FireAllClients("TestModeChanged", { mode = "Tournament", active = true })
		elseif testMode == "DeterministicTest" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			if GMM and GMM.startTestMode then
				GMM.startTestMode()
			end
			labEvent:FireAllClients("TestModeChanged", { mode = "DeterministicTest", active = true })
		elseif testMode == "BlockParryLab" then
			Workspace:SetAttribute("InfiniteStrafeTest", false)
			if GMM and GMM.startTestAnimationMode then
				GMM.startTestAnimationMode()
			end
			task.delay(0.5, function()
				local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
				local tester = quinServer:FindFirstChild("QuinA_Tester")
				local partner = quinServer:FindFirstChild("QuinB_SparringPartner")
				if tester and partner then
					local tHRP = tester:FindFirstChild("HumanoidRootPart")
					local pHRP = partner:FindFirstChild("HumanoidRootPart")
					if tHRP and pHRP then
						tHRP.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, -4), Vector3.new(0, 7.5, 4))
						pHRP.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, 4), Vector3.new(0, 7.5, -4))
					end
					partner:SetAttribute("IsGuarding", true)
					partner:SetAttribute("BlockChance", 0.75)
					partner:SetAttribute("TargetQuin", tester.Name)
					tester:SetAttribute("TargetQuin", partner.Name)
				end
			end)
			labEvent:FireAllClients("TestModeChanged", { mode = "BlockParryLab", active = true })
		end

	elseif action == "ToggleCombatMode" then
		local enabled = data.enabled == true
		local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		local tester = quinServer:FindFirstChild("QuinA_Tester")
		local partner = quinServer:FindFirstChild("QuinB_SparringPartner")

		if enabled then
			-- The UI can be opened before Test Animation Mode finishes spawning.
			-- Wait briefly so combat is never enabled against a missing Quin.
			local deadline = os.clock() + 5
			while (not tester or not partner) and os.clock() < deadline do
				task.wait(0.1)
				quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
				tester = quinServer:FindFirstChild("QuinA_Tester")
				partner = quinServer:FindFirstChild("QuinB_SparringPartner")
			end
			if not tester or not partner then
				labEvent:FireClient(player, "CombatModeChanged", {
					enabled = false,
					message = "Combat Mode needs both test Quins to spawn first.",
				})
				return
			end
			-- Activate Full Autonomous Combat
			-- 1. Position BOTH Quins to standoff circling distance (25 studs) FIRST
			local testerRoot = tester and tester:FindFirstChild("HumanoidRootPart")
			local partnerRoot = partner and partner:FindFirstChild("HumanoidRootPart")
			if testerRoot and partnerRoot then
				testerRoot.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, 0), Vector3.new(0, 7.5, 25))
				partnerRoot.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, 25), Vector3.new(0, 7.5, 0))
			end

			-- 2. Configure combat targets and humanoids
			if tester then
				tester:SetAttribute("IsTester", false)
				tester:SetAttribute("TargetQuin", partner and partner.Name or nil)
				local hum = tester:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = 16
					hum.Health = 100
				end
			end

			if partner then
				partner:SetAttribute("IsSparringPartner", false)
				partner:SetAttribute("TargetQuin", tester and tester.Name or nil)
				local hum = partner:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = 16
					hum.Health = 100
				end
			end

			-- 3. Clear ForceState so the AI handles its own states
			if tester then tester:SetAttribute("ForceState", "") end
			if partner then partner:SetAttribute("ForceState", "") end

			-- Continuous sparring health preservation loop
			_G.CombatBrawlActive = true
			task.spawn(function()
				while _G.CombatBrawlActive do
					task.wait(1.0)
					for _, name in ipairs({"QuinA_Tester", "QuinB_SparringPartner"}) do
						local q = quinServer:FindFirstChild(name)
						if q then
							local hum = q:FindFirstChildOfClass("Humanoid")
							if hum and hum.Health > 0 and hum.Health < 30 then
								hum.Health = 100
							end
						end
					end
				end
			end)

			print("[AnimationLabServer] NORMAL COMBAT MODE ACTIVATED: Quins are actively fighting!")
			labEvent:FireAllClients("CombatModeChanged", { enabled = true })

		else
			-- Restore Stationary Lab Mode
			_G.CombatBrawlActive = false

			if tester then
				stopAllTracks(tester, 0.1)
				tester:SetAttribute("IsTester", true)
				local hum = tester:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = 0
					hum.Health = 100
				end
				local hrp = tester:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CFrame = CFrame.new(0, 7.5, 0)
				end
				tester:SetAttribute("ForceState", "Idle")
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then
					playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true)
				end
			end

			if partner then
				stopAllTracks(partner, 0.1)
				partner:SetAttribute("IsSparringPartner", true)
				local hum = partner:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = 0
					hum.Health = 100
				end
				local hrp = partner:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CFrame = CFrame.new(0, 7.5, 5) * CFrame.Angles(0, math.rad(180), 0)
				end
				partner:SetAttribute("ForceState", "Idle")
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then
					playTrack(partner, idleData.id, idleData.speed, 0.15, "Idle", true)
				end
			end

			print("[AnimationLabServer] LAB MODE RESTORED: Quins reset to stationary positions.")
			labEvent:FireAllClients("CombatModeChanged", { enabled = false })
		end

	elseif action == "UpdateLocomotionConfig" then
		local key = data.key
		local value = data.value
		if key and value ~= nil and CombatConfig[key] ~= nil then
			CombatConfig[key] = value
			Workspace:SetAttribute(key, value)
			local tester = quinServer:FindFirstChild("QuinA_Tester")
			if tester then
				tester:SetAttribute(key, value)
			end
			print(string.format("[AnimationLabServer] LocomotionConfig %s = %s", tostring(key), tostring(value)))
			labEvent:FireAllClients("LocomotionConfigUpdated", { key = key, value = value })
		end

	elseif action == "ToggleFootIK" then
		local enabled = data.enabled == true
		local tester = quinServer:FindFirstChild("QuinA_Tester")
		if not tester then
			tester = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not tester then return end

		local hum = tester:FindFirstChildOfClass("Humanoid")
		local hrp = tester:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end

		CombatConfig.FootIK_Enabled = enabled
		tester:SetAttribute("FootIK_Enabled", enabled)
		Workspace:SetAttribute("FootIK_Enabled", enabled)

		if enabled then
			local leftUpLeg = tester:FindFirstChild("mixamorig:LeftUpLeg", true)
			local leftFoot = tester:FindFirstChild("mixamorig:LeftFoot", true)
			local rightUpLeg = tester:FindFirstChild("mixamorig:RightUpLeg", true)
			local rightFoot = tester:FindFirstChild("mixamorig:RightFoot", true)

			for _, name in ipairs({"LeftFootIK", "RightFootIK"}) do
				local old = hum:FindFirstChild(name)
				if old then old:Destroy() end
			end
			for _, name in ipairs({"LeftFootTargetAtt", "RightFootTargetAtt", "LeftKneePoleAtt", "RightKneePoleAtt"}) do
				local old = hrp:FindFirstChild(name)
				if old then old:Destroy() end
			end

			if leftUpLeg and leftFoot then
				local leftAtt = Instance.new("Attachment")
				leftAtt.Name = "LeftFootTargetAtt"
				leftAtt.Position = Vector3.new(-0.8, -2.6, 0)
				leftAtt.Parent = hrp

				local leftPole = Instance.new("Attachment")
				leftPole.Name = "LeftKneePoleAtt"
				leftPole.Position = Vector3.new(-0.8, -1.8, 2.5)
				leftPole.Parent = hrp

				local leftIK = Instance.new("IKControl")
				leftIK.Name = "LeftFootIK"
				leftIK.Type = Enum.IKControlType.Position
				leftIK.ChainRoot = leftUpLeg
				leftIK.EndEffector = leftFoot
				leftIK.Target = leftAtt
				leftIK.Pole = leftPole
				leftIK.Weight = 0
				leftIK.SmoothTime = 0.06
				leftIK.Parent = hum
			end

			if rightUpLeg and rightFoot then
				local rightAtt = Instance.new("Attachment")
				rightAtt.Name = "RightFootTargetAtt"
				rightAtt.Position = Vector3.new(0.8, -2.6, 0)
				rightAtt.Parent = hrp

				local rightPole = Instance.new("Attachment")
				rightPole.Name = "RightKneePoleAtt"
				rightPole.Position = Vector3.new(0.8, -1.8, 2.5)
				rightPole.Parent = hrp

				local rightIK = Instance.new("IKControl")
				rightIK.Name = "RightFootIK"
				rightIK.Type = Enum.IKControlType.Position
				rightIK.ChainRoot = rightUpLeg
				rightIK.EndEffector = rightFoot
				rightIK.Target = rightAtt
				rightIK.Pole = rightPole
				rightIK.Weight = 0
				rightIK.SmoothTime = 0.06
				rightIK.Parent = hum
			end

			if not _G.FootIKUpdaterConn then
				_G.FootIKUpdaterConn = RunService.Heartbeat:Connect(function()
					if not CombatConfig.FootIK_Enabled then return end
					local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
					local tModel = qServer:FindFirstChild("QuinA_Tester")
					if not tModel or not tModel.Parent then return end
					local tHRP = tModel:FindFirstChild("HumanoidRootPart")
					local tHum = tModel:FindFirstChildOfClass("Humanoid")
					if not tHRP or not tHum then return end

					local lAtt = tHRP:FindFirstChild("LeftFootTargetAtt")
					local rAtt = tHRP:FindFirstChild("RightFootTargetAtt")
					local lIK = tHum:FindFirstChild("LeftFootIK")
					local rIK = tHum:FindFirstChild("RightFootIK")
					if not lAtt or not rAtt or not lIK or not rIK then return end

					local rayDist = CombatConfig.FootIK_RayDistance or 6.8
					local hOffset = CombatConfig.FootIK_HeightOffset or 0.0
					local maxStepDown = CombatConfig.FootIK_MaxStepDown or 2.4
					local maxStepUp = CombatConfig.FootIK_MaxStepUp or 1.6
					local ledgeGripEnabled = CombatConfig.FootIK_LedgeGrip ~= false
					local nominalFloorDist = 5.36
					local ankleHeight = 0.45 + hOffset

					local rayParams = RaycastParams.new()
					rayParams.FilterDescendantsInstances = {tModel}
					rayParams.FilterType = Enum.RaycastFilterType.Exclude

					local rightVec = tHRP.CFrame.RightVector
					local lookVec = tHRP.CFrame.LookVector
					local leftOrigin = tHRP.Position + (rightVec * -0.85)
					local rightOrigin = tHRP.Position + (rightVec * 0.85)

					local leftHit = Workspace:Raycast(leftOrigin, Vector3.new(0, -rayDist, 0), rayParams)
					local rightHit = Workspace:Raycast(rightOrigin, Vector3.new(0, -rayDist, 0), rayParams)

					local function solveServerFoot(hit, hipOrigin, otherHit, isLeft, att, ik)
						if hit then
							local measuredDist = (hipOrigin - hit.Position).Magnitude
							local elevDelta = nominalFloorDist - measuredDist
							local isElevated = (math.abs(elevDelta) > 0.18) or (hit.Normal.Y < 0.92)

							if isElevated and elevDelta >= -maxStepDown and elevDelta <= maxStepUp then
								att.WorldPosition = hit.Position + Vector3.new(0, ankleHeight, 0)
								ik.Weight = math.clamp(ik.Weight + 0.15, 0, 1)
							elseif elevDelta < -maxStepDown and ledgeGripEnabled and otherHit then
								local inwardDir = isLeft and rightVec or -rightVec
								local edgeHit = Workspace:Raycast(hipOrigin - Vector3.new(0, nominalFloorDist * 0.6, 0), inwardDir * 1.5, rayParams)
								if edgeHit then
									att.WorldPosition = Vector3.new(edgeHit.Position.X, otherHit.Position.Y + ankleHeight, edgeHit.Position.Z)
									ik.Weight = math.clamp(ik.Weight + 0.15, 0, 0.85)
								else
									ik.Weight = math.clamp(ik.Weight - 0.15, 0, 1)
								end
							else
								-- Flat ground deadzone: fade IK weight out so clean animation plays!
								ik.Weight = math.clamp(ik.Weight - 0.15, 0, 1)
							end
						else
							if ledgeGripEnabled and otherHit then
								local inwardDir = isLeft and rightVec or -rightVec
								local edgeHit = Workspace:Raycast(hipOrigin - Vector3.new(0, nominalFloorDist * 0.6, 0), inwardDir * 1.5, rayParams)
								if edgeHit then
									att.WorldPosition = Vector3.new(edgeHit.Position.X, otherHit.Position.Y + ankleHeight, edgeHit.Position.Z)
									ik.Weight = math.clamp(ik.Weight + 0.15, 0, 0.85)
								else
									ik.Weight = math.clamp(ik.Weight - 0.15, 0, 1)
								end
							else
								ik.Weight = math.clamp(ik.Weight - 0.15, 0, 1)
							end
						end
					end

					solveServerFoot(leftHit, leftOrigin, rightHit, true, lAtt, lIK)
					solveServerFoot(rightHit, rightOrigin, leftHit, false, rAtt, rIK)
				end)
			end
			print("[AnimationLabServer] Foot IK ACTIVATED on QuinA_Tester.")
		else
			for _, name in ipairs({"LeftFootIK", "RightFootIK"}) do
				local ik = hum:FindFirstChild(name)
				if ik then ik:Destroy() end
			end
			for _, name in ipairs({"LeftFootTargetAtt", "RightFootTargetAtt"}) do
				local att = hrp:FindFirstChild(name)
				if att then att:Destroy() end
			end
			if _G.FootIKUpdaterConn then
				_G.FootIKUpdaterConn:Disconnect()
				_G.FootIKUpdaterConn = nil
			end
			print("[AnimationLabServer] Foot IK DEACTIVATED.")
		end
		labEvent:FireAllClients("FootIKToggled", { enabled = enabled })

	elseif action == "ToggleRagdoll" then
		local active = data.active == true
		local tester = quinServer:FindFirstChild("QuinA_Tester")
		if not tester then
			tester = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not tester then return end
		local hum = tester:FindFirstChildOfClass("Humanoid")
		local hrp = tester:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end

		if active then
			stopAllTracks(tester, 0.1)
			hum.PlatformStand = true
			
			local align = hrp:FindFirstChild("LabMuscleStabilizer")
			if not align then
				align = Instance.new("AlignOrientation")
				align.Name = "LabMuscleStabilizer"
				align.Mode = Enum.OrientationAlignmentMode.OneAttachment
				align.RigidityEnabled = false
				align.Responsiveness = 15
				align.MaxTorque = CombatConfig.Ragdoll_MuscleStiffness or 8000
				align.MaxAngularVelocity = 20
				align.CFrame = CFrame.new()

				local att = hrp:FindFirstChild("LabMuscleAtt") or Instance.new("Attachment")
				att.Name = "LabMuscleAtt"
				att.Parent = hrp

				align.Attachment0 = att
				align.Parent = hrp
			else
				align.MaxTorque = CombatConfig.Ragdoll_MuscleStiffness or 8000
			end
			tester:SetAttribute("IsActiveRagdoll", true)
			print("[AnimationLabServer] Active Ragdoll Mode ACTIVATED on QuinA_Tester.")
		else
			hum.PlatformStand = false
			local align = hrp:FindFirstChild("LabMuscleStabilizer")
			if align then align:Destroy() end
			local att = hrp:FindFirstChild("LabMuscleAtt")
			if att then att:Destroy() end
			tester:SetAttribute("IsActiveRagdoll", false)
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.CFrame = CFrame.new(0, 7.5, 0)
			local idleData = AnimationConfig.get("Movement.Idle")
			if idleData then
				playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true)
			end
			print("[AnimationLabServer] Active Ragdoll Mode DEACTIVATED on QuinA_Tester.")
		end
		labEvent:FireAllClients("RagdollModeChanged", { active = active })

	elseif action == "TestKnockbackLaunch" then
		local tester = quinServer:FindFirstChild("QuinA_Tester")
		if not tester then
			tester = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not tester then return end
		local hum = tester:FindFirstChildOfClass("Humanoid")
		local hrp = tester:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end

		task.spawn(function()
			stopAllTracks(tester, 0.05)
			hum.PlatformStand = true

			local style = data.style or "high_arc"
			local stiffness = CombatConfig.Ragdoll_MuscleStiffness or 8000
			local tumbleScale = CombatConfig.Ragdoll_TumbleScale or 1.0
			local recoveryDelay = CombatConfig.Ragdoll_RecoveryDelay or 0.40

			hrp.CFrame = CFrame.new(0, 7.5, -15) * CFrame.Angles(0, math.rad(180), 0)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.05)

			local align = hrp:FindFirstChild("LabMuscleStabilizer")
			if not align then
				align = Instance.new("AlignOrientation")
				align.Name = "LabMuscleStabilizer"
				align.Mode = Enum.OrientationAlignmentMode.OneAttachment
				align.RigidityEnabled = false
				align.Responsiveness = 12
				align.MaxTorque = stiffness
				align.MaxAngularVelocity = 25
				align.CFrame = CFrame.new()

				local att = hrp:FindFirstChild("LabMuscleAtt") or Instance.new("Attachment")
				att.Name = "LabMuscleAtt"
				att.Parent = hrp

				align.Attachment0 = att
				align.Parent = hrp
			else
				align.MaxTorque = stiffness
			end

			if style == "high_arc" then
				hrp.AssemblyLinearVelocity = Vector3.new(0, 55, 38)
				hrp.AssemblyAngularVelocity = Vector3.new(math.random(-18, 18), math.random(-10, 10), math.random(-18, 18)) * tumbleScale
			else
				hrp.AssemblyLinearVelocity = Vector3.new(0, 22, 60)
				hrp.AssemblyAngularVelocity = Vector3.new(math.random(-25, 25), math.random(-8, 8), math.random(-25, 25)) * tumbleScale
			end

			AudioModule.playImpact(hrp.Position, true)
			labEvent:FireAllClients("KnockbackTestLaunched", { style = style })

			task.wait(0.3)
			local deadline = os.clock() + 4.0
			local hasHitGround = false

			while os.clock() < deadline do
				local ray = Workspace:Raycast(hrp.Position, Vector3.new(0, -3.5, 0))
				if ray and hrp.AssemblyLinearVelocity.Y <= 2.0 then
					hasHitGround = true
					break
				end
				task.wait(0.05)
			end

			if hasHitGround then
				AudioModule.playImpact(hrp.Position, false)
				local friction = CombatConfig.Ragdoll_GroundFriction or 0.55
				hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * friction
				task.wait(recoveryDelay)

				align.MaxTorque = 40000
				align.Responsiveness = 25
				align.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + Vector3.new(0, 0, 1))
				task.wait(0.35)

				hum.PlatformStand = false
				align:Destroy()
				local att = hrp:FindFirstChild("LabMuscleAtt")
				if att then att:Destroy() end

				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then
					playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true)
				end
				labEvent:FireAllClients("KnockbackTestCompleted", { success = true })
			end
		end)

	elseif action == "RunLocomotionTest" then
		local testType = data.testType or "Sprint180"
		local tester = quinServer:FindFirstChild("QuinA_Tester")
		if not tester then
			tester = getOrSpawnTesterRigs(false)
			quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		end
		if not tester then return end
		local hum = tester:FindFirstChildOfClass("Humanoid")
		local hrp = tester:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end

		task.spawn(function()
			stopAllTracks(tester, 0.05)
			hum.PlatformStand = false
			hum.WalkSpeed = 0
			labEvent:FireAllClients("LocomotionTestStarted", { testType = testType })

			if testType == "Sprint180" then
				hrp.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, -35), Vector3.new(0, 7.5, 35))
				task.wait(0.1)

				local runData = AnimationConfig.get("Movement.Run")
				local strideBase = CombatConfig.RunStrideBase or 38.0
				local sprintSpeed = 50.0
				local animSpeed = (runData and runData.speed or 1.15) * (sprintSpeed / strideBase)
				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", animSpeed, 0.08, "Movement", true)

				local startTime = os.clock()
				while os.clock() - startTime < 1.2 do
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, sprintSpeed)
					task.wait(0.03)
				end

				local turnData = AnimationConfig.get("Movement.RunTurn180")
				if turnData then
					playTrack(tester, turnData.id, turnData.speed or 1.35, 0.04, "Action3", false)
				end
				for i = 1, 10 do
					hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(18), 0)
					task.wait(0.02)
				end

				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", animSpeed, 0.08, "Movement", true)
				local backTime = os.clock()
				while os.clock() - backTime < 1.0 do
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, -sprintSpeed)
					task.wait(0.03)
				end

				hrp.AssemblyLinearVelocity = Vector3.zero
				stopAllTracks(tester, 0.1)
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end

			elseif testType == "ArcRun" then
				local runData = AnimationConfig.get("Movement.Run")
				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", 1.4, 0.08, "Movement", true)
				local radius = 28.0
				local angle = 0
				local arcSpeed = 44.0
				local angSpeed = arcSpeed / radius
				local startTime = os.clock()

				while os.clock() - startTime < 3.2 do
					local dt = 0.03
					angle = angle + angSpeed * dt
					local x = math.cos(angle) * radius
					local z = math.sin(angle) * radius
					local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)).Unit
					local rollAngle = math.rad(math.clamp(CombatConfig.TorsoBankingMaxRoll or 12.0, 0, 35))

					hrp.CFrame = CFrame.lookAt(Vector3.new(x, 7.5, z), Vector3.new(x, 7.5, z) + tangent) * CFrame.Angles(0, 0, -rollAngle)
					hrp.AssemblyLinearVelocity = tangent * arcSpeed
					task.wait(dt)
				end

				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + hrp.CFrame.LookVector * Vector3.new(1,0,1))
				stopAllTracks(tester, 0.1)
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end

			elseif testType == "SprintBrake" then
				hrp.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, -30), Vector3.new(0, 7.5, 30))
				local runData = AnimationConfig.get("Movement.Run")
				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", 1.45, 0.08, "Movement", true)

				local startTime = os.clock()
				while os.clock() - startTime < 1.3 do
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 52.0)
					task.wait(0.03)
				end

				local brakeData = AnimationConfig.get("Movement.BrakingStop")
				if brakeData then
					stopAllTracks(tester, 0.04)
					playTrack(tester, brakeData.id, brakeData.speed or 1.65, 0.04, "Action3", false)
				end
				for i = 1, 8 do
					hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.5
					task.wait(0.04)
				end
				hrp.AssemblyLinearVelocity = Vector3.zero
				task.wait(0.4)
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end

			elseif testType == "PlantTurn90" then
				hrp.CFrame = CFrame.lookAt(Vector3.new(0, 7.5, -25), Vector3.new(0, 7.5, 25))
				local runData = AnimationConfig.get("Movement.Run")
				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", 1.4, 0.08, "Movement", true)

				local startTime = os.clock()
				while os.clock() - startTime < 1.0 do
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 48.0)
					task.wait(0.03)
				end

				-- Execute 90-degree athletic plant cut
				local turnData = AnimationConfig.get("Movement.RunTurn90Right")
				if turnData then
					stopAllTracks(tester, 0.04)
					playTrack(tester, turnData.id, turnData.speed or 1.65, 0.04, "Action3", false)
				end
				for i = 1, 6 do
					hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(-15), 0)
					hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.8
					task.wait(0.03)
				end

				-- Phase-locked sprint along new 90-degree vector
				playTrack(tester, runData and runData.id or "rbxassetid://109090784752055", 1.4, 0.08, "Movement", true)
				local cutTime = os.clock()
				local exitHeading = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
				while os.clock() - cutTime < 1.0 do
					hrp.AssemblyLinearVelocity = exitHeading.Unit * 48.0
					task.wait(0.03)
				end

				hrp.AssemblyLinearVelocity = Vector3.zero
				stopAllTracks(tester, 0.1)
				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end

			elseif testType == "LedgeStepTest" then
				local oldBlock = Workspace:FindFirstChild("IK_Test_Ledge_Block")
				if oldBlock then oldBlock:Destroy() end

				local block = Instance.new("Part")
				block.Name = "IK_Test_Ledge_Block"
				block.Size = Vector3.new(16, 1.8, 16)
				block.Position = Vector3.new(0, 2.9, 0) -- Top surface at Y = 3.8 (1.8 studs above arena ground Y = 2.0)
				block.Anchored = true
				block.CanCollide = true
				block.Color = Color3.fromRGB(70, 95, 135)
				block.Material = Enum.Material.SmoothPlastic
				block.Parent = Workspace

				-- Position QuinA_Tester on edge lip: left foot on block, right foot overhanging drop
				hrp.CFrame = CFrame.lookAt(Vector3.new(0.6, 9.16, 7.4), Vector3.new(0.6, 9.16, 20))
				hrp.AssemblyLinearVelocity = Vector3.zero
				task.wait(0.1)

				local idleData = AnimationConfig.get("Movement.Idle")
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end

				-- Hold pose for 1.2s to inspect ledge lip grip & pelvis dip
				task.wait(1.2)

				-- Take slow athletic steps forward off the ledge onto lower ground
				local walkData = AnimationConfig.get("Movement.WalkConfident")
				if walkData then
					stopAllTracks(tester, 0.08)
					playTrack(tester, walkData.id, walkData.speed or 1.1, 0.08, "Movement", true)
				end

				local stepTime = os.clock()
				while os.clock() - stepTime < 1.6 do
					hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 14.0)
					task.wait(0.03)
				end

				hrp.AssemblyLinearVelocity = Vector3.zero
				stopAllTracks(tester, 0.1)
				if idleData then playTrack(tester, idleData.id, idleData.speed, 0.15, "Idle", true) end
				task.wait(0.4)

				if block and block.Parent then block:Destroy() end
			end

			labEvent:FireAllClients("LocomotionTestEnded", { testType = testType })
		end)
	end
end

-- Connect to Client Remote
labEvent.OnServerEvent:Connect(handleLabAction)

-- Expose Server Bindable & Dispatch for diagnostic tools and tests
local serverBindable = Events:FindFirstChild("AnimationLabServerEvent")
if not serverBindable then
	serverBindable = Instance.new("BindableEvent")
	serverBindable.Name = "AnimationLabServerEvent"
	serverBindable.Parent = Events
end
serverBindable.Event:Connect(function(action, data)
	handleLabAction(nil, action, data)
end)

_G.AnimationLabServer_DispatchAction = function(action, data)
	return handleLabAction(nil, action, data)
end
shared.AnimationLabServer_DispatchAction = _G.AnimationLabServer_DispatchAction

print("[AnimationLabServer] Initialized with AnimationModule cache, leak-free playback & Server Dispatch.")
