--[[
build_quin_template.lua: an imported Quin body (Blender export → Studio 3D Importer) becomes the
game's Quin template. Run in the Edit DataModel (loadstring of this file); returns a report.

  IMPORT   the imported model in Workspace (e.g. "QuinMale_v3"): RootPart (with the Mixamo
           skeleton) + Quin_Shell + Quin_Joints (+ any other Quin_* zone meshes)
  TEMPLATE the template it becomes: "QuinMale" or "QuinFemale" (ReplicatedStorage.QuinType)

What it does:
  1. The current template is backed up (ServerStorage.QuinBodyBackups.<TEMPLATE>_<date-time>).
  2. A copy of it keeps its HumanoidRootPart, Humanoid, Sounds, AnimSaves and RootJoint (spawning,
     physics and the code see the same rig); its body meshes are removed (bones with them).
  3. The import is moved so its Hips land exactly where the template's Hips were (feet at the same
     depth under the root), its skeleton moves into the wood shell, which becomes `Alpha_Surface`
     (the part the game's code looks for); every other zone mesh is welded to it.
  4. Zone colours/materials (template attributes ShellColor/ShellMaterial/JointsColor/...;
     defaults: ivory lacquer and metal bronze), KeepBodyColors (no team paint), BodyVersion.
  5. The new template replaces the old one; a report (bones, hips offset, sole depth).
]]
local IMPORT = IMPORT or "QuinMale_v3"
local TEMPLATE = TEMPLATE or "QuinMale"

local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local folder = RS:WaitForChild("QuinType")
local current = folder:FindFirstChild(TEMPLATE)
local import = workspace:FindFirstChild(IMPORT)
assert(current, "no template ReplicatedStorage.QuinType." .. TEMPLATE)
assert(import, "no imported model Workspace." .. IMPORT)

local ZONES = { -- defaults when the template carries no colour attributes
	Shell = { color = "E8D3B5", material = "SmoothPlastic" },
	Joints = { color = "8A5A2E", material = "Metal" },
	Accent = { color = "2B2B2E", material = "SmoothPlastic" },
}

local function findBone(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Bone") and d.Name == name then return d end
	end
end
local function solesBelowRoot(model)
	local lowest = math.huge
	for _, n in ipairs({ "mixamorig:LeftToeBase", "mixamorig:RightToeBase" }) do
		local b = findBone(model, n)
		if b then lowest = math.min(lowest, b.WorldPosition.Y) end
	end
	return model.HumanoidRootPart.Position.Y - lowest
end

-- 1. backup
local backups = SS:FindFirstChild("QuinBodyBackups") or Instance.new("Folder")
backups.Name = "QuinBodyBackups"
backups.Parent = SS
local backup = current:Clone()
backup.Name = TEMPLATE .. "_" .. os.date("!%Y%m%d_%H%M%S")
backup.Parent = backups

-- 2. the rig shell of the current template
local tpl = current:Clone()
local oldHips = findBone(tpl, "mixamorig:Hips")
assert(oldHips, "the template has no mixamorig:Hips")
local oldHipsW = oldHips.WorldCFrame
local oldSoles = solesBelowRoot(tpl)
local physical = tpl:FindFirstChild("Alpha_Surface") or tpl:FindFirstChildWhichIsA("MeshPart")
local props = {
	CanCollide = physical.CanCollide, CanQuery = physical.CanQuery, CanTouch = physical.CanTouch,
	CollisionGroup = physical.CollisionGroup,
}
for _, c in ipairs(tpl:GetChildren()) do
	if c:IsA("MeshPart") then c:Destroy() end
end

-- 3. the import onto the rig
local imp = import:Clone()
local rootPart = imp:FindFirstChild("RootPart")
local impHips = rootPart and findBone(rootPart, "mixamorig:Hips") or findBone(imp, "mixamorig:Hips")
assert(impHips, "the import has no mixamorig:Hips (wait for the importer to finish)")
local T = oldHipsW * impHips.WorldCFrame:Inverse()
for _, p in ipairs(imp:GetDescendants()) do
	if p:IsA("BasePart") then p.CFrame = T * p.CFrame end
end
local meshes = {}
for _, c in ipairs(imp:GetChildren()) do
	if c:IsA("MeshPart") then table.insert(meshes, c) end
end
local shell
for _, m in ipairs(meshes) do
	if m.Name:find("Shell") then shell = shell or m end
end
shell = shell or meshes[1]
local hipsW = impHips.WorldCFrame
impHips.Parent = shell
impHips.CFrame = shell.CFrame:Inverse() * hipsW
local hrp = tpl.HumanoidRootPart
local zonesDone = {}
for _, m in ipairs(meshes) do
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("JointInstance") or c:IsA("WeldConstraint") then c:Destroy() end
	end
	local zone = (m == shell) and "Shell" or (m.Name:match("Quin_(%a+)") or "Accent")
	local z = ZONES[zone] or ZONES.Accent
	m:SetAttribute("Zone", zone)
	m.Color = Color3.fromHex(tpl:GetAttribute(zone .. "Color") or z.color)
	m.Material = Enum.Material[tpl:GetAttribute(zone .. "Material") or z.material]
	m.MaterialVariant, m.TextureID = "", ""
	local sa = m:FindFirstChildOfClass("SurfaceAppearance")
	if sa then sa:Destroy() end
	m.Anchored, m.Massless, m.CastShadow = false, false, true
	m.CanCollide, m.CanQuery, m.CanTouch, m.CollisionGroup = props.CanCollide, props.CanQuery, props.CanTouch, props.CollisionGroup
	m.RenderFidelity = Enum.RenderFidelity.Precise
	m.Parent = tpl
	if m ~= shell then
		local w = Instance.new("WeldConstraint")
		w.Name = m.Name .. "ToShell"
		w.Part0, w.Part1 = shell, m
		w.Parent = m
	end
	table.insert(zonesDone, ("%s=%s"):format(m.Name, zone))
end
shell.Name = "Alpha_Surface"
local rj = hrp:FindFirstChild("RootJoint")
assert(rj, "the template's HumanoidRootPart has no RootJoint")
rj.Part0, rj.Part1 = hrp, shell
rj.C1 = shell.CFrame:Inverse() * hrp.CFrame * rj.C0
imp:Destroy()

-- 4. attributes
tpl:SetAttribute("KeepBodyColors", true)
tpl:SetAttribute("BodyVersion", IMPORT)
for zone, z in pairs(ZONES) do
	tpl:SetAttribute(zone .. "Color", tpl:GetAttribute(zone .. "Color") or z.color)
	tpl:SetAttribute(zone .. "Material", tpl:GetAttribute(zone .. "Material") or z.material)
end

-- 5. swap in
tpl.Name = TEMPLATE
current:Destroy()
tpl.Parent = folder

local nb = 0
for _, d in ipairs(tpl.Alpha_Surface:GetDescendants()) do
	if d:IsA("Bone") then nb += 1 end
end
return ("%s is now %s | bones %d | zones %s | hips offset %.4f studs | soles below root %.3f (was %.3f) | scale %.3f | backup %s"):format(
	tpl:GetFullName(), IMPORT, nb, table.concat(zonesDone, ", "),
	(findBone(tpl, "mixamorig:Hips").WorldPosition - oldHipsW.Position).Magnitude,
	solesBelowRoot(tpl), oldSoles, tpl:GetScale(), backup:GetFullName())
