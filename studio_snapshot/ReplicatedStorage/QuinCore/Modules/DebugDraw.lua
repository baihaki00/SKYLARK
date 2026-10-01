--// DebugDraw.lua
-- Debug drawing channel: what the Quins sense and plan, shown on a spectator's screen.
--
-- The Quins reason on the server; the spectator watches on a client. Reasoning code submits
-- primitives (lines, spheres, text) to a named layer. Nothing is recorded or sent unless some
-- spectator has that layer switched on for that Quin, so the calls cost a table lookup when
-- debugging is off.
--   server : DebugDraw.line / sphere / text / raycast  -> batched to the clients that asked
--   client : RuntimeVisualizer draws what arrives (and its own client-side layers)
-- Layers and the spectated Quin are chosen in the Spectator HUD (DebugDraw.configure).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DebugDraw = {}

-- Every layer the HUD offers, in display order.
-- source = "client": computed by RuntimeVisualizer from replicated state.
-- source = "server": submitted through this module by the Quin's own reasoning code.
DebugDraw.Layers = {
	{ id = "Label", label = "Overhead label", source = "client" },
	{ id = "Target", label = "Target + line of sight", source = "client" },
	{ id = "Memory", label = "Last seen position", source = "client" },
	{ id = "Velocity", label = "Velocity + facing", source = "client" },
	{ id = "Trajectory", label = "Flight prediction", source = "client" },
	{ id = "Vision", label = "Senses: cone + what it notices", source = "server" },
	{ id = "Attention", label = "Attention: focus list", source = "server" },
	{ id = "Tracks", label = "Memory: remembered enemies", source = "server" },
	{ id = "Rays", label = "Raycasts", source = "server" },
	{ id = "Steer", label = "Steering goal + heading", source = "server" },
	{ id = "Pursuit", label = "Pursuit / intercept", source = "server" },
	{ id = "Jump", label = "Jump plans", source = "server" },
	{ id = "Retreat", label = "Retreat options", source = "server" },
	{ id = "Decision", label = "Decision scores", source = "server" },
}

DebugDraw.Kind = { Line = 1, Sphere = 2, Text = 3 }

local IS_SERVER = RunService:IsServer()
local FLUSH_INTERVAL = 0.1 -- seconds between batches to the clients
local MAX_PENDING = 4000 -- primitives kept between flushes (beyond this the rest are dropped)
local MAX_PER_BATCH = 700 -- primitives per client per batch
local DEFAULT_TTL = 0.2 -- seconds a primitive stays on screen (reasoning ticks at 10 Hz)

local RAY_HIT_COLOR = Color3.fromRGB(255, 70, 70)
local RAY_MISS_COLOR = Color3.fromRGB(80, 255, 140)

local layerIndex = {}
for index, layer in ipairs(DebugDraw.Layers) do
	layerIndex[layer.id] = index
end

local event = script.Parent.Parent:WaitForChild("DebugDrawEvent")

-- Who is watching what. Server: one entry per player. Client: the single local entry.
local viewers = {} -- [key] = { layers = { [layerId] = true }, all = boolean, spectated = string? }
local watchers = {} -- [layerId] = number of viewers with the layer on
local pending = {} -- server: { ownerName, primitive } waiting for the next batch
local live = {} -- client: { expires, primitive } being shown

local function recountWatchers()
	table.clear(watchers)
	for _, viewer in pairs(viewers) do
		for layerId in pairs(viewer.layers) do
			watchers[layerId] = (watchers[layerId] or 0) + 1
		end
	end
end

local function ownerName(owner)
	if typeof(owner) ~= "Instance" then return nil end
	if owner:IsA("Model") then return owner.Name end
	return owner.Parent and owner.Parent.Name or nil
end

local function viewerWants(viewer, layerId, name)
	return viewer.layers[layerId] == true and (viewer.all or (name ~= nil and name == viewer.spectated))
end

-- True when somebody is watching this layer for this Quin (owner: its Model or any of its parts).
-- Use it to skip building expensive debug geometry.
function DebugDraw.isActive(layerId, owner)
	if not watchers[layerId] then return false end
	local name = ownerName(owner)
	for _, viewer in pairs(viewers) do
		if viewerWants(viewer, layerId, name) then return true end
	end
	return false
end

local function submit(layerId, owner, primitive)
	if not DebugDraw.isActive(layerId, owner) then return end
	if IS_SERVER then
		if #pending < MAX_PENDING then
			table.insert(pending, { ownerName(owner), primitive })
		end
	else
		table.insert(live, { os.clock() + primitive[6], primitive })
	end
end

-- Primitive layout (kept as an array to stay small on the wire):
-- { kind, layerIndex, a, b | radius, color, ttl, text }

function DebugDraw.line(layerId, owner, from, to, color, ttl)
	submit(layerId, owner, { DebugDraw.Kind.Line, layerIndex[layerId], from, to, color, ttl or DEFAULT_TTL })
end

function DebugDraw.sphere(layerId, owner, position, radius, color, ttl)
	submit(layerId, owner, { DebugDraw.Kind.Sphere, layerIndex[layerId], position, radius, color, ttl or DEFAULT_TTL })
end

function DebugDraw.text(layerId, owner, position, text, color, ttl)
	submit(layerId, owner, { DebugDraw.Kind.Text, layerIndex[layerId], position, 0, color, ttl or DEFAULT_TTL, text })
end

-- Workspace:Raycast that also shows itself on the "Rays" layer: red to the hit point, green
-- for the full length when nothing was hit.
function DebugDraw.raycast(owner, origin, direction, params)
	local result = Workspace:Raycast(origin, direction, params)
	if watchers.Rays and DebugDraw.isActive("Rays", owner) then
		if result then
			DebugDraw.line("Rays", owner, origin, result.Position, RAY_HIT_COLOR)
			DebugDraw.sphere("Rays", owner, result.Position, 0.25, RAY_HIT_COLOR)
		else
			DebugDraw.line("Rays", owner, origin, origin + direction, RAY_MISS_COLOR)
		end
	end
	return result
end

if IS_SERVER then
	-- A client says which layers it wants and for whom
	event.OnServerEvent:Connect(function(player, layerIds, all, spectated)
		if typeof(layerIds) ~= "table" then return end
		local layers = {}
		for _, layerId in ipairs(layerIds) do
			if layerIndex[layerId] then layers[layerId] = true end
		end
		if next(layers) == nil then
			viewers[player] = nil
		else
			viewers[player] = { layers = layers, all = all == true, spectated = typeof(spectated) == "string" and spectated or nil }
		end
		recountWatchers()
	end)

	Players.PlayerRemoving:Connect(function(player)
		viewers[player] = nil
		recountWatchers()
	end)

	local sinceFlush = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceFlush += dt
		if sinceFlush < FLUSH_INTERVAL then return end
		sinceFlush = 0
		if #pending == 0 then return end
		for player, viewer in pairs(viewers) do
			local batch = {}
			for _, entry in ipairs(pending) do
				if viewerWants(viewer, DebugDraw.Layers[entry[2][2]].id, entry[1]) then
					table.insert(batch, entry[2])
					if #batch >= MAX_PER_BATCH then break end
				end
			end
			if #batch > 0 then
				event:FireClient(player, batch)
			end
		end
		table.clear(pending)
	end)
else
	event.OnClientEvent:Connect(function(batch)
		local now = os.clock()
		for _, primitive in ipairs(batch) do
			table.insert(live, { now + primitive[6], primitive })
		end
	end)

	local lastSent = nil

	-- Client: choose the layers (set of ids), whether to watch every Quin, and the spectated
	-- Quin's name. Tells the server only when something changed.
	function DebugDraw.configure(layers, all, spectated)
		local ids = {}
		for layerId, on in pairs(layers) do
			if on and layerIndex[layerId] then table.insert(ids, layerId) end
		end
		table.sort(ids)
		local signature = table.concat(ids, ",") .. "|" .. tostring(all) .. "|" .. tostring(spectated)
		if signature == lastSent then return end
		lastSent = signature

		local set = {}
		for _, layerId in ipairs(ids) do set[layerId] = true end
		viewers.localViewer = #ids > 0 and { layers = set, all = all == true, spectated = spectated } or nil
		recountWatchers()
		event:FireServer(ids, all == true, spectated)
	end

	-- Client: visit every primitive still on screen (expired ones are dropped)
	function DebugDraw.forEachLive(visit)
		local now = os.clock()
		local kept = 0
		for i = 1, #live do
			local entry = live[i]
			if entry[1] > now then
				kept += 1
				live[kept] = entry
				visit(entry[2])
			end
		end
		for i = #live, kept + 1, -1 do
			live[i] = nil
		end
	end

	function DebugDraw.clearLive()
		table.clear(live)
	end
end

return DebugDraw
