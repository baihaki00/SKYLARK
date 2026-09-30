----// 🔹 Live Camera Feed (with Humanoids + Tagged Objects for Sir Bai)
----// ✅ Requires: cameraPart, screenPart, and optional "addToScreenTag" objects

--local RunService = game:GetService("RunService")
--local Players = game:GetService("Players")
--local Workspace = game:GetService("Workspace")
--local CollectionService = game:GetService("CollectionService")

--local player = Players.LocalPlayer

---- 🧩 Step 1: Get main parts
--local cameraPart = Workspace:WaitForChild("cameraPart")
--local screenPart = Workspace:WaitForChild("screenPart")

--if not (cameraPart and screenPart) then
--	warn("❌ Missing cameraPart or screenPart.")
--	return
--end

--print("✅ Found parts:", cameraPart.Name, "and", screenPart.Name)

---- 🧩 Step 2: Create SurfaceGui
--local surfaceGui = Instance.new("SurfaceGui")
--surfaceGui.Name = "CameraFeed"
--surfaceGui.Face = Enum.NormalId.Front
--surfaceGui.AlwaysOnTop = false
--surfaceGui.ResetOnSpawn = false
--surfaceGui.Adornee = screenPart
--surfaceGui.Parent = player:WaitForChild("PlayerGui")

---- 🧩 Step 3: Create ViewportFrame
--local viewportFrame = Instance.new("ViewportFrame")
--viewportFrame.Size = UDim2.new(1, 0, 1, 0)
--viewportFrame.BackgroundTransparency = 1
--viewportFrame.LightColor = Color3.new(1, 1, 1)
--viewportFrame.Ambient = Color3.new(1, 1, 1)
--viewportFrame.Parent = surfaceGui

---- 🧩 Step 4: Create Camera
--local viewportCamera = Instance.new("Camera")
--viewportCamera.FieldOfView = 70
--viewportCamera.Parent = viewportFrame
--viewportFrame.CurrentCamera = viewportCamera

--print("✅ Viewport camera ready.")

---- 🧩 Step 5: Prepare folder for cloned world
--local cloneFolder = Instance.new("Folder")
--cloneFolder.Name = "ViewportWorld"
--cloneFolder.Parent = viewportFrame

---- Helper function to safely clone (no Sounds)
--local function safeClone(obj)
--	local success, clone = pcall(function()
--		return obj:Clone()
--	end)
--	if success and clone then
--		for _, descendant in ipairs(clone:GetDescendants()) do
--			if descendant:IsA("Sound") then
--				descendant:Destroy()
--			end
--		end
--		clone.Parent = cloneFolder
--	end
--end

---- 🧩 Step 6: Clone all valid workspace objects
--for _, obj in ipairs(Workspace:GetChildren()) do
--	if (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder")) then
--		if obj ~= cameraPart and obj ~= screenPart and obj ~= Workspace.Terrain then
--			safeClone(obj)
--		end
--	end
--end

---- 🧩 Step 7: Clone all tagged objects
--for _, taggedObj in ipairs(CollectionService:GetTagged("addToScreenTag")) do
--	if taggedObj:IsDescendantOf(Workspace) then
--		safeClone(taggedObj)
--	end
--end

---- 🧩 Step 8: Clone all Player Characters (live)
--for _, plr in ipairs(Players:GetPlayers()) do
--	if plr.Character then
--		safeClone(plr.Character)
--	end
--	plr.CharacterAdded:Connect(function(char)
--		safeClone(char)
--	end)
--end

--print("✅ Cloned world + humanoids + tagged objects safely (no Terrain, no Sound).")

---- 🧩 Step 9: Sync viewport camera to cameraPart
--RunService.RenderStepped:Connect(function()
--	viewportCamera.CFrame = cameraPart.CFrame
--end)

--print("🎥 Live camera feed running — includes humanoids, tagged objects, no terrain or sound.")
