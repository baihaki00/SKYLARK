--// ClothingPreload.client.lua
-- Loads every baked clothes mesh (ReplicatedStorage.ClothingBaked) a few at a time when the player
-- joins, so Quins never show up with an item missing. Asking for hundreds of meshes at once (32
-- dressed Quins arriving together) left ~15 of them failed for the whole session (2026-10-26);
-- a failed one is asked for again, up to RETRIES times.
-- Readout: player attribute ClothingPreload = "loaded/total failed:<n>" (and the failed names in
-- ClothingPreloadFailed).

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BATCH = 8
local GAP = 0.1 -- seconds between batches
local RETRIES = 3

local player = Players.LocalPlayer
local root = ReplicatedStorage:WaitForChild("ClothingBaked", 30)
if not root then
	return
end

local parts = root:GetChildren()
local ok = {}
local function load(list)
	for i = 1, #list, BATCH do
		local batch = {}
		for j = i, math.min(i + BATCH - 1, #list) do
			table.insert(batch, list[j])
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, batch, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				for _, p in ipairs(batch) do
					if ContentProvider:GetAssetFetchStatus(p.MeshId) == Enum.AssetFetchStatus.Success then
						ok[p] = true
					end
				end
			end
		end)
		task.wait(GAP)
	end
end

local left = parts
for _ = 0, RETRIES do
	load(left)
	local still = {}
	for _, p in ipairs(parts) do
		if not ok[p] and ContentProvider:GetAssetFetchStatus(p.MeshId) == Enum.AssetFetchStatus.Success then
			ok[p] = true
		end
		if not ok[p] then
			table.insert(still, p)
		end
	end
	left = still
	if #left == 0 then
		break
	end
	task.wait(1)
end

local names = {}
for _, p in ipairs(left) do
	table.insert(names, p.Name)
end
player:SetAttribute("ClothingPreload", ("%d/%d failed:%d"):format(#parts - #left, #parts, #left))
player:SetAttribute("ClothingPreloadFailed", table.concat(names, " "))
if #left > 0 then
	warn(("[ClothingPreload] %d clothes meshes did not load: %s"):format(#left, table.concat(names, " ")))
end
