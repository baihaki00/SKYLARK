--// LanternOrbClient.client.lua
-- The Lantern Siege orb in the carrier's hand (owner 2026-10-27: "make the lantern a bit small
-- like an orb, place it around their hands"). The server holds the orb by the carrier's right
-- side (welded to the root: the server does not see the animated hand); on this screen that copy
-- is hidden and an orb is drawn in the palm of the animated right hand every frame. Cosmetic,
-- client-only.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HAND = "mixamorig:RightHand"
local PALM = CFrame.new(0, 0.35, 0.12) -- from the hand bone: along the fingers, a little out of the palm
local COLOR = Color3.fromRGB(255, 190, 80)

local orb = nil
local handCache = setmetatable({}, { __mode = "k" }) -- carrier model -> its hand bone

local function makeOrb()
	local p = Instance.new("Part")
	p.Name = "LanternOrbView"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.1, 1.1, 1.1)
	p.Material = Enum.Material.Neon
	p.Color = COLOR
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	local light = Instance.new("PointLight")
	light.Color = COLOR
	light.Range = 12
	light.Brightness = 3
	light.Parent = p
	p.Parent = Workspace.CurrentCamera
	return p
end

local function handOf(model)
	local bone = handCache[model]
	if bone and bone.Parent then return bone end
	bone = model:FindFirstChild(HAND, true)
	handCache[model] = bone
	return bone
end

RunService:BindToRenderStep("LanternOrb", Enum.RenderPriority.Camera.Value + 2, function()
	local folder = Workspace:FindFirstChild("LanternSiege")
	local lantern = folder and folder:FindFirstChild("Lantern")
	local state = lantern and lantern:GetAttribute("State")
	local carrierName = lantern and lantern:GetAttribute("Carrier")
	local carrier = carrierName and Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(carrierName)
	local hand = carrier and (state == "Carried" or state == "Planting") and handOf(carrier)
	if hand then
		lantern.LocalTransparencyModifier = 1
		orb = orb or makeOrb()
		orb.CFrame = hand.TransformedWorldCFrame * PALM
	else
		if lantern then lantern.LocalTransparencyModifier = 0 end
		if orb then
			orb:Destroy()
			orb = nil
		end
	end
end)
