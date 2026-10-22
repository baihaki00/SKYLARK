--// AvatarTidy.lua
-- Small fixes for Roblox avatars built by the game (the NPC crowd, NPC owners and their friends).
--
--   blockHands(model): Roblox's current default R15 hand is a C-shaped claw mesh that reads as a
--     pirate hook (owner); each hand MeshPart becomes a plain block the same size and colour, with
--     its attachments and joints carried over.

local AvatarTidy = {}

function AvatarTidy.blockHands(model)
    for _, name in ipairs({ "LeftHand", "RightHand" }) do
        local hand = model:FindFirstChild(name)
        if hand and hand:IsA("MeshPart") then
            local block = Instance.new("Part")
            block.Name = name
            block.Size = hand.Size * Vector3.new(0.85, 0.8, 0.85)
            block.CFrame = hand.CFrame
            block.Color = hand.Color
            block.Material = hand.Material
            block.TopSurface = Enum.SurfaceType.Smooth
            block.BottomSurface = Enum.SurfaceType.Smooth
            block.Anchored = hand.Anchored
            block.CanCollide = hand.CanCollide
            block.CanTouch = hand.CanTouch
            block.CanQuery = hand.CanQuery
            block.CastShadow = hand.CastShadow
            block.Massless = hand.Massless
            block.CollisionGroup = hand.CollisionGroup
            for _, child in ipairs(hand:GetChildren()) do
                if child:IsA("BaseWrap") or child:IsA("SurfaceAppearance") then
                    child:Destroy() -- (MeshPart-only: layered clothing's wrap, a mesh's surface)
                else
                    child.Parent = block -- (attachments, the wrist joint, scale values)
                end
            end
            for _, j in ipairs(model:GetDescendants()) do
                if j:IsA("JointInstance") then
                    if j.Part0 == hand then
                        j.Part0 = block
                    end
                    if j.Part1 == hand then
                        j.Part1 = block
                    end
                end
            end
            block.Parent = hand.Parent
            hand:Destroy()
        end
    end
end

return AvatarTidy
