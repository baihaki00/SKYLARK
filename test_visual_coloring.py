from Tools.Utilities.roblox_client import RobloxStudioClient

c = RobloxStudioClient()
code = r"""
local quin = workspace:FindFirstChild("QuinTest")
if not quin then
    for _, ch in ipairs(workspace:GetChildren()) do
        if ch:FindFirstChild("Humanoid") then
            quin = ch
            break
        end
    end
end
if not quin then return "No Quin" end

local hrp = quin:FindFirstChild("HumanoidRootPart")
if not hrp then return "No HRP" end

-- Clean previous test
local oldRing = quin:FindFirstChild("TeamRing")
if oldRing then oldRing:Destroy() end
local oldHl = quin:FindFirstChild("ElementHighlight")
if oldHl then oldHl:Destroy() end

-- 1. Team Ground Ring
local ring = Instance.new("Part")
ring.Name = "TeamRing"
ring.Shape = Enum.PartType.Cylinder
ring.Size = Vector3.new(0.2, 5.0, 5.0)
ring.CFrame = hrp.CFrame * CFrame.new(0, -2.7, 0) * CFrame.Angles(0, 0, math.rad(90))
ring.Material = Enum.Material.Neon
ring.Color = Color3.fromRGB(0, 170, 255)
ring.Transparency = 0.35
ring.CanCollide = false
ring.Massless = true
ring.CastShadow = false
ring.Parent = quin

local weld = Instance.new("WeldConstraint")
weld.Part0 = hrp
weld.Part1 = ring
weld.Parent = ring

local light = Instance.new("PointLight")
light.Name = "TeamLight"
light.Color = ring.Color
light.Range = 9
light.Brightness = 1.6
light.Parent = ring

-- 2. Subtle wash Highlight (NO OUTLINE!)
local hl = Instance.new("Highlight")
hl.Name = "ElementHighlight"
hl.FillColor = ring.Color
hl.FillTransparency = 0.68
hl.OutlineTransparency = 1.0 -- Pure fill wash, zero highlighter outline!
hl.DepthMode = Enum.HighlightDepthMode.Occluded
hl.Adornee = quin
hl.Parent = quin

return "Successfully applied TeamRing + Outline-free Highlight wash to " .. quin.Name
"""
res = c.execute_luau(code, "Edit")
print("Visual Test Result:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
