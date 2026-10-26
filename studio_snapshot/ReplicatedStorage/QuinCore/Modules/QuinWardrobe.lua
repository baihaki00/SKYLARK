--// QuinWardrobe (ReplicatedStorage.QuinCore.Modules.QuinWardrobe)
-- Clothes on Quins: Roblox layered clothing (a WrapTarget on the body, a WrapLayer per item).
-- The items live in ReplicatedStorage.Clothing.<Slot>.<asset> as Accessories made from the
-- clothing pipeline's export (D:\SKYLARK\QUIN_DESIGN\clothing\CLOTHING_PIPELINE.md, section 13):
--   asset name  <SKU>_<variant letter>_<slug>    e.g. TOP00001_T_tee_plain
--   attributes  SKU, Slug, DisplayName, Slot, Fit (Unisex/Male/Female), Variant (B/T/U/H/C), Order,
--               MadeOn, Covers, Hides (space separated slots), Swaps ("Hair=C"),
--               Offset_Male / Offset_Female (the Handle's place on that body's Alpha_Surface)
--   the body    QuinType templates' Alpha_Surface carry the WrapTarget "QuinBodyCage"
-- An outfit is { [slot] = "SKU" or "SKU:V" } (V = the variant letter; tops: T/U/H). It is saved on
-- the QuinInstance (Outfit) and worn at spawn; a Quin without one wears a random outfit.
-- Rules (resolve): fit must be Unisex or the Quin's gender; covers clear other slots (a dress
-- clears Bottom); hides clear slots (a helmet hides Hair); swaps change another slot's variant
-- (a hat makes the hair wear its C = capped asset). Team bands are client holograms (QuinHoloBands).
-- BAKED (performance plan step D, 2026-10-26): Quins in the world wear plain skinned MeshParts from
-- ReplicatedStorage.ClothingBaked (<asset>_M / <asset>_F, fitted to that body, no wraps: they bend
-- with the Quin's own bones). Snug items (hair, necklaces, hats...) also have an OVER copy
-- <asset>_MO / _FO, worn whenever an item from one of its OverWhen slots is on. Baked parts carry
-- their own Swaps (boots: Bottom=K, trousers tucked into the boots). The wardrobe preview
-- (QuinPreview) still dresses layered. Workspace attribute WardrobeLayered = true: layered everywhere.
-- MESH BUDGET: random outfits keep a fight at 60 different clothing meshes or fewer (a Roblox blink bug; see W.MESH_BUDGET).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local W = {}

W.SLOTS = { "Hair", "Headgear", "Face", "Neck", "Top", "Outer", "Bottom", "Waist", "Arms", "Feet", "Back" }
W.VARIANT_NAMES = { B = "", T = "Tucked", U = "Untucked", H = "Half-tucked", C = "Hat hair", K = "Booted" }
-- how often a random outfit fills each slot
W.RANDOM_CHANCE = { Hair = 0.95, Top = 1, Bottom = 1, Feet = 0.9, Outer = 0.3, Headgear = 0.3, Face = 0.1,
	Neck = 0.15, Waist = 0.15, Arms = 0.1, Back = 0.08 }
W.ENABLED = true -- (Workspace attribute WardrobeOff = true turns clothes off for new spawns)
W.TAG = "QuinWear" -- (attribute on every worn Accessory)
W.MOUNT = "QuinWearAttachment" -- (the attachment on Alpha_Surface every item hangs from)

local index -- { bySku = {[sku] = {[V] = acc}}, byAsset = {[name] = acc}, bySlot = {[slot] = {acc...}} }

local function folder()
	return ReplicatedStorage:FindFirstChild("Clothing")
end

local function build()
	index = { bySku = {}, byAsset = {}, bySlot = {} }
	local root = folder()
	if not root then
		return index
	end
	for _, acc in ipairs(root:GetDescendants()) do
		if acc:IsA("Accessory") and acc:GetAttribute("SKU") then
			local sku, v, slot = acc:GetAttribute("SKU"), acc:GetAttribute("Variant") or "B", acc:GetAttribute("Slot")
			index.bySku[sku] = index.bySku[sku] or {}
			index.bySku[sku][v] = acc
			index.byAsset[acc.Name] = acc
			index.bySlot[slot] = index.bySlot[slot] or {}
			table.insert(index.bySlot[slot], acc)
		end
	end
	for _, list in pairs(index.bySlot) do
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
	end
	return index
end

local function idx()
	return index or build()
end

local function words(s)
	local t = {}
	for w in string.gmatch(s or "", "%S+") do
		t[w] = true
	end
	return t
end

local function fits(acc, gender)
	local f = acc:GetAttribute("Fit")
	return f == "Unisex" or f == gender
end

-- the item behind an outfit entry ("SKU" or "SKU:V"), and its variant (the first one if V is missing)
function W.lookup(entry)
	if type(entry) ~= "string" then
		return nil
	end
	local sku, v = entry:match("^(%u%u%u%d%d%d%d%d):?(%u?)$")
	local variants = sku and idx().bySku[sku]
	if not variants then
		return nil
	end
	if v ~= "" and variants[v] then
		return variants[v], v
	end
	for _, pick in ipairs({ "B", "T", "U", "H" }) do
		if variants[pick] then
			return variants[pick], pick
		end
	end
	return nil
end

-- every item a gender can wear, by slot: { [slot] = { {sku, name, fit, variants = {"T","U","H"}} ... } }
function W.catalogue(gender)
	local out = {}
	for _, slot in ipairs(W.SLOTS) do
		local list, seen = {}, {}
		for _, acc in ipairs(idx().bySlot[slot] or {}) do
			local sku = acc:GetAttribute("SKU")
			if fits(acc, gender) and acc:GetAttribute("Variant") ~= "C" then
				if not seen[sku] then
					seen[sku] = { sku = sku, name = acc:GetAttribute("DisplayName"), fit = acc:GetAttribute("Fit"), variants = {} }
					table.insert(list, seen[sku])
				end
				table.insert(seen[sku].variants, acc:GetAttribute("Variant"))
			end
		end
		out[slot] = list
	end
	return out
end

-- an outfit cleaned to what this gender can wear, the rules applied: -> list of Accessories
function W.resolve(outfit, gender)
	local chosen = {} -- [slot] = acc
	for _, slot in ipairs(W.SLOTS) do
		local acc = W.lookup(outfit and outfit[slot])
		if acc and acc:GetAttribute("Slot") == slot and fits(acc, gender) then
			chosen[slot] = acc
		end
	end
	local hides, swaps = {}, {}
	for slot, acc in pairs(chosen) do
		for s in pairs(words(acc:GetAttribute("Covers"))) do
			if s ~= slot then
				hides[s] = true
			end
		end
		for s in pairs(words(acc:GetAttribute("Hides"))) do
			hides[s] = true
		end
		for s, v in string.gmatch(acc:GetAttribute("Swaps") or "", "(%a+)=(%u)") do
			swaps[s] = v
		end
	end
	local out = {}
	for _, slot in ipairs(W.SLOTS) do
		local acc = chosen[slot]
		if acc and not hides[slot] then
			if swaps[slot] then
				acc = idx().bySku[acc:GetAttribute("SKU")][swaps[slot]] or acc
			end
			table.insert(out, acc)
		end
	end
	return out
end

-- an outfit with only valid entries for this gender (what the server saves)
function W.clean(outfit, gender)
	local out = {}
	if type(outfit) ~= "table" then
		return out
	end
	for _, slot in ipairs(W.SLOTS) do
		local acc, v = W.lookup(outfit[slot])
		if acc and acc:GetAttribute("Slot") == slot and fits(acc, gender) and v ~= "C" then
			local sku = acc:GetAttribute("SKU")
			out[slot] = v == "B" and sku or (sku .. ":" .. v)
		end
	end
	return out
end

-- a random outfit for a gender (rng: a Random, optional)
function W.random(gender, rng)
	rng = rng or Random.new()
	local cat = W.catalogue(gender)
	local outfit = {}
	for _, slot in ipairs(W.SLOTS) do
		local list = cat[slot]
		if list and #list > 0 and rng:NextNumber() < (W.RANDOM_CHANCE[slot] or 0) then
			local item = list[rng:NextInteger(1, #list)]
			local v = item.variants[rng:NextInteger(1, #item.variants)]
			outfit[slot] = v == "B" and item.sku or (item.sku .. ":" .. v)
		end
	end
	return outfit
end

-- ---------------------------------------------------------------------------------------------
-- WEARING (server; the client preview uses it on its own copy)
-- ---------------------------------------------------------------------------------------------
local function surfaceOf(model)
	return model:FindFirstChild("Alpha_Surface") or model:FindFirstChild("Beta_Surface")
end

local function put(model, template, gender)
	local surf = surfaceOf(model)
	local offset = template:GetAttribute("Offset_" .. gender)
	if not (surf and offset) then
		return nil
	end
	local acc = template:Clone()
	acc:SetAttribute(W.TAG, true)
	local h = acc:FindFirstChild("Handle")
	h.Anchored = false
	h.Massless = true
	h.CanCollide, h.CanQuery, h.CanTouch = false, false, false
	h.CFrame = surf.CFrame * offset
	-- Held the Roblox way: a pair of attachments of one name, on the body and on the Handle; the
	-- Humanoid joins them itself (AccessoryRigidConstraint) when the model goes into the world.
	-- (A Weld of our own in the Handle is removed by the engine then, and a WeldConstraint is
	-- switched off: the clothes fell out of the map ~2 s after spawn.)
	local mount = surf:FindFirstChild(W.MOUNT)
	if not mount then
		mount = Instance.new("Attachment")
		mount.Name = W.MOUNT
		mount.Parent = surf
	end
	local grip = Instance.new("Attachment")
	grip.Name = W.MOUNT
	grip.CFrame = offset:Inverse() * mount.CFrame -- (Handle * grip = surface * mount)
	grip.Parent = h
	-- (The wrap is sent ON. Each client switches it off the moment it arrives and back on a few
	-- at a time, nearest Quins first: StarterPlayerScripts.QuinWardrobePacer. A wrap sent OFF from
	-- the server and switched on by the client was often never drawn - tested 2026-10-26.)
	acc.Parent = model
	return acc
end

local function strip(model, keepBands)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("BasePart") and c:GetAttribute(W.TAG) then
			c:Destroy() -- (a baked item)
		elseif c:IsA("Accessory") and c:GetAttribute(W.TAG) and not (keepBands and c:GetAttribute("Slot") == "System") then
			c:Destroy()
		end
	end
end

local function bakedFolder()
	return ReplicatedStorage:FindFirstChild("ClothingBaked")
end

-- one baked part on the model, lined up by the Hips bone (the mesh's rest Hips onto the body's)
local function putBaked(model, template)
	local surf = surfaceOf(model)
	local hips = surf and surf:FindFirstChild("mixamorig:Hips")
	local inMesh = template:GetAttribute("HipsInMesh")
	if not (hips and inMesh) then
		return nil
	end
	local p = template:Clone()
	p:SetAttribute(W.TAG, true)
	p.Anchored = false
	p.Massless = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CFrame = surf.CFrame * hips.CFrame * inMesh:Inverse()
	-- (a plain part, not an Accessory: the engine leaves this weld alone)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = surf, p
	weld.Parent = p
	p.Parent = model
	return p
end

-- the baked parts for a resolved outfit: [slot] = template (swaps and OVER copies applied)
local function bakedFor(list, gender)
	local root = bakedFolder()
	local g = gender == "Female" and "F" or "M"
	local parts, slotOf = {}, {}
	for _, acc in ipairs(list) do
		local p = root:FindFirstChild(acc.Name .. "_" .. g)
		if not p then
			return nil -- (not baked yet: the caller dresses layered)
		end
		local slot = acc:GetAttribute("Slot")
		parts[slot], slotOf[p] = p, slot
	end
	for _, p in pairs(parts) do -- swaps of the baked catalogue (boots: Bottom=K)
		for s, v in string.gmatch(p:GetAttribute("Swaps") or "", "(%a+)=(%u)") do
			local other = parts[s]
			if other then
				local sku, slug = other.Name:match("^(%u%u%u%d%d%d%d%d)_%u_(.+)_[MF]$")
				parts[s] = (sku and root:FindFirstChild(sku .. "_" .. v .. "_" .. slug .. "_" .. g)) or other
			end
		end
	end
	for slot, p in pairs(parts) do -- snug items over clothes: their OVER copy
		for s in pairs(words(p:GetAttribute("OverWhen"))) do
			if parts[s] and root:FindFirstChild(p.Name .. "O") then
				parts[slot] = root[p.Name .. "O"]
				break
			end
		end
	end
	return parts
end

-- put an outfit on a Quin model (replaces what it wore; the band stays). Baked parts unless
-- layered = true (the wardrobe preview) or Workspace WardrobeLayered.
function W.dress(model, outfit, layered)
	local gender = model:GetAttribute("Gender") or "Male"
	strip(model, true)
	local worn = {}
	local list = W.resolve(outfit, gender)
	local baked = not layered and not workspace:GetAttribute("WardrobeLayered") and bakedFolder() and bakedFor(list, gender)
	if baked then
		for _, slot in ipairs(W.SLOTS) do
			if baked[slot] and putBaked(model, baked[slot]) then
				table.insert(worn, baked[slot].Name)
			end
		end
	else
		for _, acc in ipairs(list) do
			if put(model, acc, gender) then
				table.insert(worn, acc.Name)
			end
		end
	end
	model:SetAttribute("Wearing", table.concat(worn, " "))
	return worn
end

-- The team bands are holograms each client draws on the wrist bones from the Team attribute
-- (StarterPlayerScripts.QuinHoloBands). The layered SYS band items never wrapped onto the arms
-- (they floated beside the Quins); this only clears one a model may still carry.
function W.band(model)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Accessory") and c:GetAttribute(W.TAG) and c:GetAttribute("Slot") == "System" then
			c:Destroy()
		end
	end
end

-- MESH BUDGET (2026-10-26). Roblox makes skinned meshes blink when a fight holds too many
-- DIFFERENT ones (an engine bug: 61 different clothing meshes clean, 80 blinking, in a 16v16 with
-- the crowd; CLOTHING_PIPELINE.md section 16). Random outfits keep the fight (Workspace.QuinServer)
-- at W.MESH_BUDGET different clothing meshes or fewer. Pieces still mix freely; once the budget is
-- close, a new Quin mixes pieces already worn in the fight. Saved outfits are never changed.
-- Workspace attribute ClothingMeshBudget overrides it (0 = no budget). Raise it when Roblox fixes the bug.
W.MESH_BUDGET = 60

-- the baked part names worn in the fight (Wearing attributes), and how many
local function wornInFight(except)
	local set, n = {}, 0
	local fight = workspace:FindFirstChild("QuinServer")
	for _, m in ipairs(fight and fight:GetChildren() or {}) do
		if m ~= except then
			for name in string.gmatch(m:GetAttribute("Wearing") or "", "%S+") do
				if not set[name] then
					set[name], n = true, n + 1
				end
			end
		end
	end
	return set, n
end

-- how many baked parts this outfit would add to the fight (nil: it can't be worn baked)
local function newMeshes(outfit, gender, worn)
	local parts = bakedFolder() and bakedFor(W.resolve(outfit, gender), gender)
	if not parts then
		return nil
	end
	local new = 0
	for _, p in pairs(parts) do
		if not worn[p.Name] then
			new += 1
		end
	end
	return new
end

-- a random outfit mixed only from items already worn in the fight (any variant letter
-- the wearer's other items swapped in, K/C, goes back to the item itself)
local function reuseOutfit(worn, gender, rng)
	local g = gender == "Female" and "F" or "M"
	local bySlot = {}
	for name in pairs(worn) do
		local p = bakedFolder():FindFirstChild(name)
		local sku, v = name:match("^(%u%u%u%d%d%d%d%d)_(%u)_.+_" .. g .. "O?$")
		if p and sku then
			local slot = p:GetAttribute("Slot")
			bySlot[slot] = bySlot[slot] or {}
			table.insert(bySlot[slot], (v == "B" or v == "K" or v == "C") and sku or (sku .. ":" .. v))
		end
	end
	local outfit = {}
	for _, slot in ipairs(W.SLOTS) do
		local list = bySlot[slot]
		if list and rng:NextNumber() < (W.RANDOM_CHANCE[slot] or 0) then
			outfit[slot] = list[rng:NextInteger(1, #list)]
		end
	end
	return outfit
end

-- a random outfit that keeps the fight inside the mesh budget
function W.fightOutfit(model, gender, rng)
	rng = rng or Random.new()
	local budget = workspace:GetAttribute("ClothingMeshBudget") or W.MESH_BUDGET
	if budget <= 0 or not bakedFolder() or workspace:GetAttribute("WardrobeLayered") then
		return W.random(gender, rng)
	end
	local worn, n = wornInFight(model)
	local best, bestNew = nil, math.huge
	local function try(outfit)
		local new = newMeshes(outfit, gender, worn)
		if new and new < bestNew then
			best, bestNew = outfit, new
		end
		return new and n + new <= budget
	end
	for _ = 1, 12 do -- free picks first
		if try(W.random(gender, rng)) then
			return best
		end
	end
	for _ = 1, 24 do -- then mixes of what the fight already wears
		if try(reuseOutfit(worn, gender, rng)) then
			return best
		end
	end
	return best or W.random(gender, rng) -- (the fewest new meshes found)
end

-- at spawn: the Quin's saved outfit, or a random one (the team band is drawn by each client)
function W.dressSpawn(model, quinInstance)
	if not W.ENABLED or workspace:GetAttribute("WardrobeOff") or not folder() then
		return
	end
	local gender = model:GetAttribute("Gender") or (quinInstance and quinInstance.Gender) or "Male"
	local outfit = quinInstance and quinInstance.Outfit
	if type(outfit) ~= "table" or next(outfit) == nil then
		outfit = W.fightOutfit(model, gender)
	end
	W.dress(model, outfit)
end

if folder() then
	folder().DescendantAdded:Connect(function()
		index = nil
	end)
end

return W
