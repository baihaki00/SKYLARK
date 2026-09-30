--// InterceptionState.lua
local InterceptionState = { name = "Interception" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))

local DEBUG = false
local interceptRange = 20

function InterceptionState.enter(fighter, humanoid, rootPart)
	fighter:SetAttribute("InterceptionStartTime", os.clock())
	humanoid.WalkSpeed = 0
	AnimationModule.play(humanoid, AnimationIds.Idle, Enum.AnimationPriority.Idle, true, 1, 0.2)

	if DEBUG then
		local sphere = Instance.new("Part")
		sphere.Name = "Debug_InterceptRange_" .. fighter.Name
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.new(interceptRange * 2, interceptRange * 2, interceptRange * 2)
		sphere.Color = Color3.new(0, 1, 1) 
		sphere.Transparency = 0.5
		sphere.Material = Enum.Material.ForceField
		sphere.CanCollide = false
		sphere.Massless = true
		sphere.Anchored = false
		sphere.CastShadow = false

		local yOffset = -(humanoid.HipHeight / 2)
		sphere.CFrame = rootPart.CFrame * CFrame.new(0, yOffset, 0)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = sphere
		weld.Parent = sphere

		sphere.Parent = rootPart -- Parent to the root so it gets destroyed if the Quin dies
		fighter:SetAttribute("InterceptSphere", sphere.Name)
	end

	local target, _ = TargetingModule.getNearest(rootPart, 1000)
	if target then
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			-- (IK tracking logic has been removed as requested)
		end
	end

	local awareTimer = Random.new():NextNumber(0.1, 0.3)

	task.delay(awareTimer, function()
		if fighter:GetAttribute("CurrentState") ~= "Interception" then return end

		local rollMidAirOrGround = math.random(0, 1)

		if rollMidAirOrGround == 0 then
			local rollBlockOrEvade = math.random(0, 1)

			if rollBlockOrEvade == 0 then 
				local blockSuccessRate = 0.75 
				if math.random() <= blockSuccessRate then
					fighter:SetAttribute("IsBlocking", true)
				else
					fighter:SetAttribute("IsBlocking", false)
				end
			elseif rollBlockOrEvade == 1 then
				local evadeTarget, _ = TargetingModule.getNearest(rootPart, 1000)
				local dashDir = -rootPart.CFrame.LookVector 

				if evadeTarget then
					local tHRP = evadeTarget:FindFirstChild("HumanoidRootPart")
					if tHRP then
						local offset = tHRP.Position - rootPart.Position
						local toTarget = offset.Magnitude > 0.001 and offset.Unit or Vector3.new(0, 0, 1)

						-- Protect against Cross Product returning (0,0,0) if target is exactly above/below
						local crossVec = Vector3.new(0, 1, 0):Cross(toTarget)
						if crossVec.Magnitude < 0.001 then
							crossVec = Vector3.new(1, 0, 0) -- fallback safe right vector
						end
						local rightVector = crossVec.Unit

						local evadeChoice = math.random(1, 3)
						if evadeChoice == 1 then dashDir = rightVector
						elseif evadeChoice == 2 then dashDir = -rightVector
						else dashDir = -toTarget end
					end
				end

				local att = Instance.new("Attachment")
				att.Name = "Evade_Att"
				att.Parent = rootPart

				local lv = Instance.new("LinearVelocity")
				lv.Name = "Evade_DashForce"
				lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
				lv.MaxAxesForce = Vector3.new(250000, 0, 250000)
				lv.VectorVelocity = dashDir * 200
				lv.Attachment0 = att
				lv.Parent = rootPart

				task.delay(0.2, function()
					if lv and lv.Parent then lv:Destroy() end
					if att and att.Parent then att:Destroy() end
				end)
			end

		elseif rollMidAirOrGround == 1 then 
			local clashTarget, _ = TargetingModule.getNearest(rootPart, 1000)

			if clashTarget then
				local targetHRP = clashTarget:FindFirstChild("HumanoidRootPart")
				if targetHRP then
					local offset = targetHRP.Position - rootPart.Position
					local dashDir = Vector3.new(0,0,1)
					if offset.Magnitude > 0.001 then
						dashDir = offset.Unit
						-- Prevent CFrame.lookAt from throwing NaN if axes align perfectly
						local upVector = Vector3.new(0,1,0)
						if math.abs(dashDir.Y) > 0.99 then upVector = Vector3.new(1,0,0) end
						rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + dashDir, upVector)
					end

					local att = Instance.new("Attachment")
					att.Name = "MidAirIntercept_Att"
					att.Parent = rootPart

					local lv = Instance.new("LinearVelocity")
					lv.Name = "MidAirIntercept_DashForce"
					lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
					lv.MaxForce = 350000
					lv.VectorVelocity = dashDir * 400 
					lv.Attachment0 = att
					lv.Parent = rootPart

					task.delay(0.25, function()
						if lv and lv.Parent then lv:Destroy() end
						if att and att.Parent then att:Destroy() end
					end)
				end
			end
		end
	end)
end

function InterceptionState.exit(fighter, humanoid, rootPart)
	if rootPart then
		local ev = rootPart:FindFirstChild("Evade_DashForce")
		if ev then ev:Destroy() end
		local ea = rootPart:FindFirstChild("Evade_Att")
		if ea then ea:Destroy() end
		local mi = rootPart:FindFirstChild("MidAirIntercept_DashForce")
		if mi then mi:Destroy() end
		local ma = rootPart:FindFirstChild("MidAirIntercept_Att")
		if ma then ma:Destroy() end
	end
	AnimationModule.stop(humanoid, AnimationIds.Idle, 0.2)

	local sphereName = fighter:GetAttribute("InterceptSphere")
	if sphereName then
		local sphere = workspace:FindFirstChild(sphereName)
		if sphere then sphere:Destroy() end
		fighter:SetAttribute("InterceptSphere", nil)
	end

	local evadeForce = rootPart:FindFirstChild("Evade_DashForce")
	if evadeForce then evadeForce:Destroy() end

	local interceptForce = rootPart:FindFirstChild("MidAirIntercept_DashForce")
	if interceptForce then interceptForce:Destroy() end

	fighter:SetAttribute("IsBlocking", false)
	fighter:SetAttribute("InterceptionStartTime", nil)

	local QuinData = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("QuinData"))
	local stats = QuinData.getStats(fighter:GetAttribute("QuinType") or "TypeB")
	humanoid.WalkSpeed = stats and stats.Speed or 28
end

function InterceptionState.update(fighter, humanoid, rootPart)
	local startTime = fighter:GetAttribute("InterceptionStartTime") or os.clock()
	if os.clock() - startTime >= 1.0 then
		local target, distance = TargetingModule.getNearest(rootPart, 100)
		if target and distance <= 25 then
			return require(script.Parent:WaitForChild("FightState"))
		else
			return require(script.Parent:WaitForChild("ChaseState"))
		end
	end
	return InterceptionState
end

return InterceptionState
