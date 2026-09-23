--// DebugManager.server.lua
-- Handles global debug toggle requests from clients

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Initialize default states
Workspace:SetAttribute("Debug_Rays", false)
Workspace:SetAttribute("Debug_Orientation", false)
Workspace:SetAttribute("Debug_HealthBars", false)
Workspace:SetAttribute("Debug_StateLabels", false)

-- Create or get RemoteEvent
local toggleEvent = ReplicatedStorage:FindFirstChild("DebugToggleEvent")
if not toggleEvent then
	toggleEvent = Instance.new("RemoteEvent")
	toggleEvent.Name = "DebugToggleEvent"
	toggleEvent.Parent = ReplicatedStorage
end

toggleEvent.OnServerEvent:Connect(function(player, action)
	-- In a real game, verify if player is an admin. For dev sandbox, we just trust.
	
	if action == "ToggleAxes" then
		local enabled = not Workspace:GetAttribute("Debug_Axes")
		Workspace:SetAttribute("Debug_Axes", enabled)
		print("[Debug] Axes toggled:", enabled)
		
		local CollectionService = game:GetService("CollectionService")
		for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
			for _, child in ipairs(quin:GetDescendants()) do
				if child:IsA("BasePart") or child:IsA("MeshPart") then
					if child.Name == "HumanoidRootPart" then
						child.Transparency = enabled and 0.5 or 1
						
						if enabled and not child:FindFirstChild("DebugAxes") then
							local folder = Instance.new("Folder")
							folder.Name = "DebugAxes"
							folder.Parent = child
							
							local function createAxis(color, size, cframeOffset)
								local p = Instance.new("Part")
								p.Size = size
								p.Color = color
								p.Anchored = false
								p.CanCollide = false
								p.Massless = true
								p.Material = Enum.Material.Neon
								local w = Instance.new("WeldConstraint")
								w.Part0 = child
								w.Part1 = p
								p.CFrame = child.CFrame * cframeOffset
								p.Parent = folder
								w.Parent = p
							end
							
							createAxis(Color3.new(1,0,0), Vector3.new(2,0.1,0.1), CFrame.new(1,0,0)) -- X Right Red
							createAxis(Color3.new(0,1,0), Vector3.new(0.1,2,0.1), CFrame.new(0,1,0)) -- Y Up Green
							createAxis(Color3.new(0,0,1), Vector3.new(0.1,0.1,2), CFrame.new(0,0,-1)) -- Z Forward Blue
						elseif not enabled and child:FindFirstChild("DebugAxes") then
							child.DebugAxes:Destroy()
						end
					elseif child.Name ~= "Root" and child.Name ~= "KB_UprightGyro" then
						if enabled then
							if not child:GetAttribute("OrigTrans") then
								child:SetAttribute("OrigTrans", child.Transparency)
							end
							child.Transparency = 1
						else
							local trans = child:GetAttribute("OrigTrans")
							if trans then child.Transparency = trans end
						end
					end
				end
			end
		end
		
	elseif action == "ClearAndRespawn" then
		local CollectionService = game:GetService("CollectionService")
		local quins = CollectionService:GetTagged("Quin")
		for _, q in ipairs(quins) do
			q:Destroy()
		end
		print("[Debug] Cleared all Quins. Spawner will respawn them.")
		
	elseif action == "ToggleRays" then
		Workspace:SetAttribute("Debug_Rays", not Workspace:GetAttribute("Debug_Rays"))
		print("[Debug] Rays toggled:", Workspace:GetAttribute("Debug_Rays"))
		
	elseif action == "ToggleOrientation" then
		Workspace:SetAttribute("Debug_Orientation", not Workspace:GetAttribute("Debug_Orientation"))
		print("[Debug] Orientation toggled:", Workspace:GetAttribute("Debug_Orientation"))
		
	elseif action == "ToggleHealthBars" then
		Workspace:SetAttribute("Debug_HealthBars", not Workspace:GetAttribute("Debug_HealthBars"))
		print("[Debug] HealthBars toggled:", Workspace:GetAttribute("Debug_HealthBars"))
		
	elseif action == "ToggleStateLabels" then
		Workspace:SetAttribute("Debug_StateLabels", not Workspace:GetAttribute("Debug_StateLabels"))
		print("[Debug] StateLabels toggled:", Workspace:GetAttribute("Debug_StateLabels"))
		
	elseif action == "AllOff" then
		Workspace:SetAttribute("Debug_Rays", false)
		Workspace:SetAttribute("Debug_Orientation", false)
		Workspace:SetAttribute("Debug_HealthBars", false)
		Workspace:SetAttribute("Debug_StateLabels", false)
		print("[Debug] All debug visuals turned OFF")
	end
end)

local CollectionService = game:GetService("CollectionService")
CollectionService:GetInstanceAddedSignal("Quin"):Connect(function(quin)
	task.delay(0.5, function()
		if not quin.Parent then return end
		if Workspace:GetAttribute("Debug_Axes") then
			for _, child in ipairs(quin:GetDescendants()) do
				if child:IsA("BasePart") or child:IsA("MeshPart") then
					if child.Name == "HumanoidRootPart" then
						child.Transparency = 0.5
						if not child:FindFirstChild("DebugAxes") then
							local folder = Instance.new("Folder")
							folder.Name = "DebugAxes"
							folder.Parent = child
							
							local function createAxis(color, size, cframeOffset)
								local p = Instance.new("Part")
								p.Size = size
								p.Color = color
								p.Anchored = false
								p.CanCollide = false
								p.Massless = true
								p.Material = Enum.Material.Neon
								local w = Instance.new("WeldConstraint")
								w.Part0 = child
								w.Part1 = p
								p.CFrame = child.CFrame * cframeOffset
								p.Parent = folder
								w.Parent = p
							end
							
							createAxis(Color3.new(1,0,0), Vector3.new(2,0.1,0.1), CFrame.new(1,0,0))
							createAxis(Color3.new(0,1,0), Vector3.new(0.1,2,0.1), CFrame.new(0,1,0))
							createAxis(Color3.new(0,0,1), Vector3.new(0.1,0.1,2), CFrame.new(0,0,-1))
						end
					elseif child.Name ~= "Root" and child.Name ~= "KB_UprightGyro" then
						if not child:GetAttribute("OrigTrans") then
							child:SetAttribute("OrigTrans", child.Transparency)
						end
						child.Transparency = 1
					end
				end
			end
		end
	end)
end)
