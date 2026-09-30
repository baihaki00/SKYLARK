--// RuntimeTracer.lua
-- Lightweight runtime execution tracer for Quin artificial organisms.
-- Records meaningful state transitions, function checkpoints, and combat/animation events.
-- Uses Luau's debug.info reflection to provide exact source script and line numbers.
-- Single Source of Truth: ReplicatedStorage.QuinCore.Modules.RuntimeTracer

local Workspace = game:GetService("Workspace")

local RuntimeTracer = {}

-- Global toggle: cheap enough for dev, can be set to false in production to disable all overhead
RuntimeTracer.ENABLED = true

-- Maximum trace history kept per fighter
local MAX_HISTORY = 6
local DISPLAY_LOG_COUNT = 3
local DISPLAY_BREADCRUMB_COUNT = 3

-- Cache: traceBuffers[model] = { entries = { ... } }
local traceBuffers = {}

-- Helper to extract the character Model instance from various parameter types
local function resolveModel(fighter)
	if not fighter then return nil end
	if typeof(fighter) == "Instance" then
		if fighter:IsA("Model") then
			return fighter
		elseif fighter.Parent and fighter.Parent:IsA("Model") then
			return fighter.Parent
		end
	elseif type(fighter) == "table" then
		if fighter.model and typeof(fighter.model) == "Instance" and fighter.model:IsA("Model") then
			return fighter.model
		elseif fighter.character and typeof(fighter.character) == "Instance" and fighter.character:IsA("Model") then
			return fighter.character
		elseif fighter.rootPart and typeof(fighter.rootPart) == "Instance" and fighter.rootPart.Parent and fighter.rootPart.Parent:IsA("Model") then
			return fighter.rootPart.Parent
		end
	end
	return nil
end

-- Formats a debug.info source string into a clean, canonical filename:line representation
-- e.g. "ServerScriptService.QuinCore.States.KnockbackState" -> "KnockbackState.lua:142"
function RuntimeTracer.formatSource(source, line)
	if not source or source == "" then
		return string.format("Unknown.lua:%d", line or 0)
	end

	-- Remove leading chunk markers if any (e.g. "=script", "@")
	local clean = source:gsub("^[=@]", "")

	-- Split by dots or slashes to get the script basename
	local segments = string.split(clean, ".")
	local base = segments[#segments]
	if not base or base == "" then
		local pathSegments = string.split(clean, "/")
		base = pathSegments[#pathSegments]
	end

	if not base or base == "" then
		base = clean
	end

	-- Append .lua if not present
	if not base:find("%.lua$") then
		base = base .. ".lua"
	end

	return string.format("%s:%d", base, line or 0)
end

-- Formats current clock time into MM:SS.mmm
local function formatTimestamp()
	local now = os.clock()
	local mins = math.floor(now / 60) % 60
	local secs = now % 60
	return string.format("%02d:%06.3f", mins, secs)
end

-- Record a meaningful execution checkpoint
-- @param fighter: Model, fighter instance table, or rootPart
-- @param eventDesc: Short human-readable event description (e.g. "GroundContact → IMPACT")
-- @param stackLevel: Optional caller stack depth (default: 2)
function RuntimeTracer.checkpoint(fighter, eventDesc, stackLevel)
	if not RuntimeTracer.ENABLED then return end

	local model = resolveModel(fighter)
	if not model then return end

	local level = (stackLevel or 2)
	local src, line, funcName = debug.info(level, "sln")
	local loc = RuntimeTracer.formatSource(src, line)
	local timestamp = formatTimestamp()

	local entry = {
		time = timestamp,
		loc = loc,
		func = (funcName and funcName ~= "") and funcName or nil,
		desc = tostring(eventDesc or ""),
	}

	-- Circular buffer management
	local buf = traceBuffers[model]
	if not buf then
		buf = { entries = {} }
		traceBuffers[model] = buf
		-- Cleanup when model despawns
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				traceBuffers[model] = nil
			end
		end)
	end

	table.insert(buf.entries, entry)
	if #buf.entries > MAX_HISTORY then
		table.remove(buf.entries, 1)
	end

	-- Construct breadcrumb flow: e.g. "KnockbackState.lua:142 → RecoveryState.lua:27 → AnimationModule.lua:91"
	local total = #buf.entries
	local breadcrumbParts = {}
	local startBread = math.max(1, total - DISPLAY_BREADCRUMB_COUNT + 1)
	for i = startBread, total do
		table.insert(breadcrumbParts, buf.entries[i].loc)
	end
	local breadcrumbStr = table.concat(breadcrumbParts, " → ")

	-- Construct formatted multi-line trace log for HUD display:
	-- "04:12.381 | KnockbackState.lua:142 | GroundContact → IMPACT"
	local logLines = {}
	local startLog = math.max(1, total - DISPLAY_LOG_COUNT + 1)
	for i = startLog, total do
		local e = buf.entries[i]
		table.insert(logLines, string.format("%s | %s | %s", e.time, e.loc, e.desc))
	end
	local logStr = table.concat(logLines, "\n")

	-- Replicate efficiently via model attributes
	model:SetAttribute("TraceBreadcrumb", breadcrumbStr)
	model:SetAttribute("TraceLog", logStr)
	model:SetAttribute("LastTraceTime", timestamp)
end

-- Clear trace buffer for a fighter
function RuntimeTracer.clear(fighter)
	local model = resolveModel(fighter)
	if model then
		traceBuffers[model] = nil
		model:SetAttribute("TraceBreadcrumb", nil)
		model:SetAttribute("TraceLog", nil)
	end
end

return RuntimeTracer
