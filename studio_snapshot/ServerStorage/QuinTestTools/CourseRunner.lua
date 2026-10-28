--// CourseRunner (test tool, MovementTestArena)
-- Start play, GameCommand:FireServer("movement_test"), then from the server:
--   require(game.ServerStorage.QuinTestTools.CourseRunner).run(startXZ, endXZ, timeout)
-- Parks the anchored target at endXZ, puts the runner at startXZ facing it, and logs what the
-- runner does on the way: awareness/state changes, jumps (launch, landing, what it flew over,
-- feet clearance, which clip), rejected jumps, hard stops.
local CS = game:GetService("CollectionService")
local RS = game:GetService("RunService")

local CLIPS = { ["82934009896094"] = "SKID", ["85622241844167"] = "jumpclip" }
local GROUND = "ArenaGroundMovementTest"
local CourseRunner = {}

function CourseRunner.run(startPos, endPos, timeout, floorTop)
	floorTop = floorTop or 2
	local rootY = floorTop + 5.6
	local runner, target
	for _, q in CS:GetTagged("Quin") do
		if q.Name:find("Runner") then runner = q elseif q.Name:find("Target") then target = q end
	end
	if not runner or not target then return "missing quins (run movement_test first)" end
	target.Humanoid.Health = target.Humanoid.MaxHealth
	target.HumanoidRootPart.CFrame = CFrame.new(endPos.X, rootY - 0.2, endPos.Z)
	local t0 = os.clock()
	while runner:GetAttribute("CurrentState") ~= "Chase" and os.clock() - t0 < 6 do task.wait(0.1) end
	runner.Humanoid.Health = runner.Humanoid.MaxHealth
	runner:SetAttribute("Energy", 100)
	local look = Vector3.new(endPos.X, rootY, endPos.Z)
	-- Held at the start for a moment so its navigation forgets where it was before
	runner.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(startPos.X, rootY, startPos.Z), look)
	local holdUntil = os.clock() + 0.7
	while os.clock() < holdUntil do
		runner.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(startPos.X, rootY, startPos.Z), look)
		runner.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
		RS.Heartbeat:Wait()
	end
	runner.HumanoidRootPart.AssemblyLinearVelocity = (look - runner.HumanoidRootPart.Position).Unit * 30
	local animator = runner.Humanoid:FindFirstChildOfClass("Animator")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { runner, target }
	local ev, lastAw, wasAir, airStart, over, overMin, launchInfo = {}, nil, false, nil, nil, 99, nil
	local spHist = {}
	local fell = false
	local lastPlan = runner:GetAttribute("SkidPlan")
	local rejN = runner:GetAttribute("JumpRejectedCount") or 0
	local start = os.clock()
	local conn = RS.Heartbeat:Connect(function()
		local h = runner.HumanoidRootPart
		local p, v = h.Position, h.AssemblyLinearVelocity
		local sp = Vector3.new(v.X, 0, v.Z).Magnitude
		local t = os.clock() - start
		local aw = tostring(runner:GetAttribute("ObstacleAwareness")) .. "/" .. tostring(runner:GetAttribute("CurrentState"))
		if aw ~= lastAw then
			lastAw = aw
			table.insert(ev, string.format("%.1f [%s] (%.0f,%.0f) sp=%.0f", t, aw, p.X, p.Z, sp))
		end
		local plan = runner:GetAttribute("SkidPlan")
		if plan ~= lastPlan then
			lastPlan = plan
			if plan then table.insert(ev, string.format("%.1f PLAN %s at (%.0f,%.0f)", t, plan, p.X, p.Z)) end
		end
		local rn = runner:GetAttribute("JumpRejectedCount") or 0
		if rn ~= rejN then
			rejN = rn
			table.insert(ev, string.format("%.1f JUMP REJECTED: %s at (%.0f,%.0f)", t, tostring(runner:GetAttribute("JumpRejected")), p.X, p.Z))
		end
		local clip
		for _, tr in animator:GetPlayingAnimationTracks() do
			local id = tr.Animation.AnimationId:match("%d+")
			if CLIPS[id] and tr.WeightTarget > 0 then clip = CLIPS[id] .. string.format("@%.2f", tr.TimePosition) end
		end
		local below = workspace:Raycast(p, Vector3.new(0, -30, 0), params)
		local air = not below or (p.Y - 5.11 - below.Position.Y) > 0.7
		if air and not wasAir then
			airStart = t
			launchInfo = string.format("%.1f LAUNCH (%.0f,%.0f) sp=%.0f clip=%s", t, p.X, p.Z, sp, tostring(clip))
			overMin, over = 99, nil
		end
		if air then
			local hit = workspace:Raycast(p, Vector3.new(0, -14, 0), params)
			if hit and hit.Position.Y > floorTop + 0.3 then
				over = hit.Instance.Name .. string.format("(h%.0f)", hit.Position.Y - floorTop)
				overMin = math.min(overMin, (p.Y - 5.11) - hit.Position.Y)
			end
		end
		if wasAir and not air and airStart then
			local under = workspace:Raycast(p, Vector3.new(0, -8, 0), params)
			table.insert(ev, launchInfo .. string.format(" -> LAND (%.0f,%.0f)%s air=%.2fs over=%s feetClear=%s clipNow=%s",
				p.X, p.Z, (under and under.Position.Y > floorTop + 0.3) and (" ON " .. under.Instance.Name) or "", t - airStart,
				tostring(over), overMin < 99 and string.format("%.1f", overMin) or "-", tostring(clip)))
			airStart = nil
		end
		wasAir = air
		if p.Y < floorTop + 1 and not fell then
			fell = true
			table.insert(ev, string.format("%.1f FELL OFF at (%.0f,%.1f,%.0f) [%s]", t, p.X, p.Y, p.Z, aw))
		end
		table.insert(spHist, { t, sp })
		while #spHist > 0 and t - spHist[1][1] > 0.3 do table.remove(spHist, 1) end
		if spHist[1] and spHist[1][2] > 25 and sp < 8 and not air then
			table.insert(ev, string.format("%.1f STOP %.0f->%.0f at (%.0f,%.0f)", t, spHist[1][2], sp, p.X, p.Z))
			spHist = {}
		end
	end)
	local tt = os.clock()
	while os.clock() - tt < (timeout or 14) do
		task.wait(0.1)
		if fell then break end
		if (runner.HumanoidRootPart.Position - target.HumanoidRootPart.Position).Magnitude < 12 then
			table.insert(ev, string.format("%.1f REACHED target", os.clock() - start))
			break
		end
	end
	conn:Disconnect()
	return table.concat(ev, "\n")
end

return CourseRunner
