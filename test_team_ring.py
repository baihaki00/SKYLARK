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

if not quin then
    return "No Quin found in workspace"
end

-- Test adding team ring at feet
local hrp = quin:FindFirstChild("HumanoidRootPart")
if not hrp then return "No HRP" end

local existingRing = quin:FindFirstChild("TeamRing")
if existingRing then existingRing:Destroy() end

local ring = Instance.new("Part")
ring.Name = "TeamRing"
ring.Shape = Enum.PartType.Cylinder
ring.Size = Vector3.new(0.3, 5.5, 5.5)
ring.CFrame = hrp.CFrame * CFrame.new(0, -2.8, 0) * CFrame.Angles(0, 0, math.rad(90))
ring.Material = Enum.Material.Neon
ring.Color = Color3.fromRGB(0, 170, 255)
ring.Transparency = 0.3
ring.CanCollide = false
ring.Massless = true
ring.CastShadow = false
ring.Parent = quin

local weld = Instance.new("WeldConstraint")
weld.Part0 = hrp
weld.Part1 = ring
weld.Parent = ring

-- Also test PointLight
local light = ring:FindFirstChild("TeamLight") or Instance.new("PointLight")
light.Name = "TeamLight"
light.Color = ring.Color
light.Range = 8
light.Brightness = 1.5
light.Parent = ring

return "Added TeamRing and PointLight successfully to " .. quin.Name
"""
res = c.execute_luau(code, "Edit")
print("Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
