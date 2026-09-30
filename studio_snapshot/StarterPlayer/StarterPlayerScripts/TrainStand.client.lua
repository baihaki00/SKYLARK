---- 🔹 Smooth Ride Handler – DEBUG BUILD for Sir Bai
---- ✅ Shows exactly what the raycast hits or doesn’t hit

--local Players = game:GetService("Players")
--local RunService = game:GetService("RunService")

--local player = Players.LocalPlayer
--local character = player.Character or player.CharacterAdded:Wait()
--local hrp = character:WaitForChild("HumanoidRootPart")
--local humanoid = character:WaitForChild("Humanoid")

--local CHECK_INTERVAL = 0.1
--local GROUND_VELOCITY_DAMP = 0.1

--local onTrain = false
--local lastTrainCFrame = nil

-------------------------------------------------------
---- 🔍 Debug helper
-------------------------------------------------------
--local function isStandingOnTrain()
--	local rayOrigin = hrp.Position
--	local rayDirection = Vector3.new(0, -6, 0)

--	local raycastParams = RaycastParams.new()
--	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
--	raycastParams.FilterDescendantsInstances = {character}

--	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

--	if result then
--		print(string.format(
--			"🟢 Ray hit: %s | Parent: %s | Pos: %s",
--			result.Instance.Name,
--			result.Instance.Parent and result.Instance.Parent.Name or "nil",
--			tostring(result.Position)
--			))

--		if result.Instance.Name == "TrainTarget" or result.Instance.Name == "MainBodyPart" then
--			return result.Instance
--		else
--			print("⚪ Hit something else, not the train.")
--		end
--	else
--		print("🔴 Raycast hit nothing under player.")
--	end

--	return nil
--end

-------------------------------------------------------
---- 🔁 Main loop
-------------------------------------------------------
--task.spawn(function()
--	while character.Parent do
--		local hit = isStandingOnTrain()

--		if hit and not onTrain then
--			onTrain = true
--			humanoid.AutoRotate = false
--			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
--			humanoid.PlatformStand = true
--			print("✅ Boarded train.")
--			lastTrainCFrame = hit.CFrame

--		elseif not hit and onTrain then
--			onTrain = false
--			humanoid.AutoRotate = true
--			humanoid.PlatformStand = false
--			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
--			print("🚶 Left train.")
--			lastTrainCFrame = nil
--		end

--		if onTrain and lastTrainCFrame then
--			local current = lastTrainCFrame:ToObjectSpace(hrp.CFrame)
--			hrp.CFrame = lastTrainCFrame * current
--			hrp.Velocity *= GROUND_VELOCITY_DAMP
--			hrp.RotVelocity = Vector3.zero
--		end

--		task.wait(CHECK_INTERVAL)
--	end
--end)
