local TargetingModule = require(game:GetService("ReplicatedStorage"):FindFirstChild("QuinCore"):FindFirstChild("Modules"):FindFirstChild("TargetingModule"))
local CollectionService = game:GetService("CollectionService")

-- Setup seeker Quin
local seeker = Instance.new("Model")
seeker.Name = "SeekerQuin"
local sHRP = Instance.new("Part", seeker)
sHRP.Name = "HumanoidRootPart"
sHRP.Position = Vector3.new(0, 5, 0)
local sHum = Instance.new("Humanoid", seeker)
sHum.MaxHealth = 100
sHum.Health = 100
seeker:SetAttribute("Team", "Blue")
CollectionService:AddTag(seeker, "Quin")
seeker.Parent = workspace

-- Old distant target (800 studs away)
local distant = Instance.new("Model")
distant.Name = "DistantTarget"
local dHRP = Instance.new("Part", distant)
dHRP.Name = "HumanoidRootPart"
dHRP.Position = Vector3.new(0, 5, 800)
local dHum = Instance.new("Humanoid", distant)
dHum.MaxHealth = 100
dHum.Health = 100
distant:SetAttribute("Team", "Red")
CollectionService:AddTag(distant, "Quin")
distant.Parent = workspace

-- Close ambush target (25 studs away)
local closeAmbush = Instance.new("Model")
closeAmbush.Name = "CloseAmbushTarget"
local cHRP = Instance.new("Part", closeAmbush)
cHRP.Name = "HumanoidRootPart"
cHRP.Position = Vector3.new(0, 5, 25)
local cHum = Instance.new("Humanoid", closeAmbush)
cHum.MaxHealth = 100
cHum.Health = 100
closeAmbush:SetAttribute("Team", "Red")
CollectionService:AddTag(closeAmbush, "Quin")
closeAmbush.Parent = workspace

-- Crucial test: seeker has CurrentTarget set to "DistantTarget" (the legacy 800-stud blinders bug)
seeker:SetAttribute("CurrentTarget", "DistantTarget")

local nearestTarget, nearestDist = TargetingModule.getNearest(sHRP, 1000)

local results = {}
if nearestTarget == closeAmbush then
    table.insert(results, string.format("PASS: getNearest correctly picked CloseAmbushTarget (%.1f studs) instead of being locked to DistantTarget!", nearestDist))
else
    local chosenName = nearestTarget and nearestTarget.Name or "nil"
    table.insert(results, string.format("FAIL: getNearest picked %s (%.1f studs) instead of CloseAmbushTarget!", chosenName, nearestDist or -1))
end

-- Cleanup
seeker:Destroy()
distant:Destroy()
closeAmbush:Destroy()

return table.concat(results, "\n")
