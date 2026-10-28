--// QuinTimeline (ModuleScript)
-- Reading a Quin at a moment of the flight recorder (QuinRecorder): its attributes, its pose and
-- clips, the changes around it, and the before / after card and plain-text report of one change.
-- Shared by the frozen inspector (GodPauseClient) and the replay (QuinReplay), which hand the
-- result to the debug menu's Inspect tab (QuinDebugHUD, shared.DebugDock).
--   track  = a recorder track { events, base }      frames = the recorder's frames
--   t      = os.clock() time of the recording        refT   = the time shown as 0 ("now")

local QuinTimeline = {}

-- the state line, in this order
QuinTimeline.KEYS = { "CurrentState", "TacticalState", "Task", "TaskWhy", "PaceGear", "PaceWhy", "CurrentTarget",
	"ObstacleAwareness", "LookMode", "ReactionType", "StrikeResult" }

-- how far either side of a change the card looks
local BEFORE, AFTER = 0.2, 0.3

local function escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
QuinTimeline.escape = escape

function QuinTimeline.attributesAt(track, t)
	if not track then return {} end
	local values = table.clone(track.base or {})
	for _, event in ipairs(track.events) do
		if event.t > t then break end
		if event.kind == "attr" then values[event.name] = event.value end
	end
	return values
end

-- the last recorded pose of that Quin at or before t
function QuinTimeline.poseAt(frames, name, t)
	if not frames or #frames == 0 then return nil end
	local lo, hi = 1, #frames
	if frames[1].t > t then return frames[1].quins[name] end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if frames[mid].t <= t then lo = mid else hi = mid end
	end
	local pick = frames[hi].t <= t and frames[hi] or frames[lo]
	return pick.quins[name]
end

local function horizontalSpeed(pose)
	local v = pose and pose.velocity
	return v and Vector3.new(v.X, 0, v.Z).Magnitude
end

-- "State Fight · Tactical PRESSING · ..." (rich: values coloured)
function QuinTimeline.stateLine(values, pose, rich, color)
	local parts = {}
	for _, key in ipairs(QuinTimeline.KEYS) do
		local v = values[key]
		if v ~= nil and v ~= "" then
			table.insert(parts, rich and ("%s <font color='%s'>%s</font>"):format(key, color or "#3CAAFF", escape(v)) or (key .. " " .. tostring(v)))
		end
	end
	if pose and pose.humanoidState then table.insert(parts, "Humanoid " .. pose.humanoidState) end
	local speed = horizontalSpeed(pose)
	if speed then table.insert(parts, ("speed %.1f"):format(speed)) end
	return table.concat(parts, rich and "  ·  " or " · ")
end

-- "Movement.Run 0.82 (0.31/0.47s x1.35) · ..." from a recorded pose
function QuinTimeline.clipsLine(pose, rich, limit)
	local parts = {}
	for index, clip in ipairs(pose and pose.clips or {}) do
		if limit and index > limit then break end
		table.insert(parts, rich
			and ("%s <font color='#FFFFFF'>%.2f</font> (%.2f/%.2fs x%.2f)"):format(escape(clip.name), clip.weight, clip.time, clip.length, clip.speed)
			or ("%s %.2f (%.2f/%.2fs x%.2f)"):format(clip.name, clip.weight, clip.time, clip.length, clip.speed))
	end
	return #parts > 0 and table.concat(parts, rich and "  ·  " or " · ") or "none"
end

-- An event worth a row: a clip start, or an attribute that switches (text or true/false: numbers
-- drift every few frames and the *At/*Until are clocks; the trace lines and the target's reason
-- with its distance change every few frames too)
local NOT_A_ROW = { Mind = true, TraceLog = true, TraceBreadcrumb = true, TargetReason = true }
local function worthARow(event)
	if event.kind == "clip" then return true end
	return not NOT_A_ROW[event.name] and (type(event.value) == "string" or type(event.value) == "boolean")
end

local function eventText(event, rich)
	if event.kind == "clip" then
		return rich and ("▶ clip %s"):format(escape(event.name)) or ("clip " .. event.name)
	end
	return rich and ("%s → <font color='#3CAAFF'>%s</font>"):format(escape(event.name), escape(event.value))
		or (event.name .. " -> " .. tostring(event.value))
end

-- rows { t, text } of the changes up to upTo (all of them when nil), oldest first
function QuinTimeline.rows(track, refT, upTo)
	local rows = {}
	for _, event in ipairs(track and track.events or {}) do
		if upTo and event.t > upTo then break end
		if worthARow(event) then
			table.insert(rows, {
				t = event.t,
				text = ("<font color='#AAAAAA'>%+.2f</font>  %s"):format(event.t - refT, eventText(event, true)),
			})
		end
	end
	return rows
end

local function changesBetween(track, from, to, rich)
	local lines = {}
	for _, event in ipairs(track and track.events or {}) do
		if event.t > to then break end
		if event.t >= from and worthARow(event) then table.insert(lines, eventText(event, rich)) end
	end
	return lines
end

-- The before / after card of the change at t (rich), and the same as plain text for a report
function QuinTimeline.card(track, frames, name, t, refT, rich)
	local before, after = t - BEFORE, t + AFTER
	local b = QuinTimeline.attributesAt(track, before)
	local a = QuinTimeline.attributesAt(track, after)
	local poseB, poseA = QuinTimeline.poseAt(frames, name, before), QuinTimeline.poseAt(frames, name, after)
	local lines = {}
	local function add(text) table.insert(lines, text) end
	if rich then
		add(("<b>%s</b>  at <font color='#FFC83C'>%+.2f s</font>"):format(escape(name), t - refT))
		add(("<font color='#AAAAAA'>BEFORE (%.1f s earlier)</font>"):format(BEFORE))
		add(QuinTimeline.stateLine(b, poseB, true, "#FF9A5A"))
		add("Clips: " .. QuinTimeline.clipsLine(poseB, true, 4))
		add(("<font color='#AAAAAA'>CHANGES</font>  %s"):format(table.concat(changesBetween(track, before, after, true), "  ·  ")))
		add(("<font color='#AAAAAA'>AFTER (%.1f s later)</font>"):format(AFTER))
		add(QuinTimeline.stateLine(a, poseA, true, "#5AE6A0"))
		add("Clips: " .. QuinTimeline.clipsLine(poseA, true, 4))
		return table.concat(lines, "\n")
	end
	add(("%s at %+.2f s"):format(name, t - refT))
	add(("BEFORE (%.1f s earlier): %s"):format(BEFORE, QuinTimeline.stateLine(b, poseB, false)))
	add("  clips: " .. QuinTimeline.clipsLine(poseB, false, 4))
	add("CHANGES: " .. table.concat(changesBetween(track, before, after, false), " | "))
	add(("AFTER (%.1f s later): %s"):format(AFTER, QuinTimeline.stateLine(a, poseA, false)))
	add("  clips: " .. QuinTimeline.clipsLine(poseA, false, 4))
	return table.concat(lines, "\n")
end

return QuinTimeline
