--// ImpulseModule.lua
-- One horizontal force channel per Quin.
--
-- Every scripted push on the ground (attack lunge, hit flinch, dodge, dash, slide, ground
-- knockback) is a request on this module instead of its own LinearVelocity. A body therefore
-- has at most one mover, and the module decides what happens when requests disagree:
--   * requests with different tags add up (a flinch on top of a slide),
--   * a new request with the same tag replaces the old one, starting from the body's current
--     speed so a refresh does not pulse,
--   * requests that point against each other never run together: the higher priority wins,
--     and on a tie the newer one does. A body is never pushed back and forth.
-- Vertical motion is left to gravity; launches into the air are ballistic and do not use this.

local RunService = game:GetService("RunService")

local ImpulseModule = {}

local MOVER_NAME = "ImpulseLV"
local ATTACHMENT_NAME = "ImpulseAtt"
local DEFAULT_MAX_FORCE = 18000
local OPPOSING_DOT = -0.2 -- directions more than ~100 degrees apart contradict each other
local MAX_SPEED = 160 -- studs/s ceiling on the summed push

-- Reaction to being hit outranks the body's own motion
ImpulseModule.Priority = { SelfMotion = 1, Reaction = 2, Knockback = 3 }

-- Speed fraction over the request's life (p runs 0 -> 1 after the ramp-in)
local PROFILES = {
	-- Flinch: straight bleed-off to rest
	decay = function(p)
		return 1 - p
	end,
	-- Lunge: quick burst that eases out
	lunge = function(p)
		return (1 - p) * (1 - p)
	end,
	-- Skid on a slippery floor: fast at first, long tail, ends at endRatio
	friction = function(p, endRatio)
		local q = 1 - p
		return endRatio + (1 - endRatio) * q * q
	end,
	-- Slide / dash: full speed, eased down over the last 40%
	hold = function(p, endRatio)
		if p <= 0.6 then return 1 end
		local e = (p - 0.6) / 0.4
		return 1 - (1 - endRatio) * e * e
	end,
}

-- Mean speed fraction of each profile (distance = speed * duration * mean)
local function profileMean(profile, endRatio)
	if profile == "decay" then return 0.5 end
	if profile == "lunge" then return 1 / 3 end
	if profile == "friction" then return endRatio + (1 - endRatio) / 3 end
	return 0.6 + 0.4 * (1 - (1 - endRatio) / 3)
end

local bodies = {} -- [model] = { root, mover, attachment, requests = { [tag] = request } }
local stepConnection = nil
local sessionLoop = false -- true once ImpulseModule.start() owns the loop: it then runs all session

local function release(model)
	local body = bodies[model]
	if not body then return end
	bodies[model] = nil
	if body.mover.Parent then body.mover:Destroy() end
	if body.attachment.Parent then body.attachment:Destroy() end
end

local function requestFactor(request, now)
	local t = now - request.startTime
	if t < request.rampIn then
		local first = PROFILES[request.profile](0, request.endRatio)
		return request.startFactor + (first - request.startFactor) * (t / request.rampIn)
	end
	local p = (t - request.rampIn) / math.max(request.duration - request.rampIn, 0.01)
	return PROFILES[request.profile](math.clamp(p, 0, 1), request.endRatio)
end

local function step()
	local now = os.clock()
	for model, body in pairs(bodies) do
		if not model.Parent or not body.root.Parent or not body.mover.Parent then
			release(model)
		else
			local velocity = Vector3.zero
			local force = 0
			local topPriority = 0
			for tag, request in pairs(body.requests) do
				if now - request.startTime >= request.duration then
					body.requests[tag] = nil
				else
					velocity += request.direction * (request.speed * requestFactor(request, now))
					force = math.max(force, request.maxForce)
					topPriority = math.max(topPriority, request.priority or 1)
				end
			end
			-- Published for the client's foot placement: the body's own moves (a lunge, a
			-- spacing step back) are stepped, being shoved (flinch, knockback) is slid
			if body.mover:GetAttribute("Priority") ~= topPriority then
				body.mover:SetAttribute("Priority", topPriority)
			end
			if next(body.requests) == nil then
				release(model)
			else
				if velocity.Magnitude > MAX_SPEED then
					velocity = velocity.Unit * MAX_SPEED
				end
				body.mover.MaxAxesForce = Vector3.new(force, 0, force)
				body.mover.VectorVelocity = velocity
			end
		end
	end
	if next(bodies) == nil and stepConnection and not sessionLoop then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

-- A connection dies with the script that made it. Pushes come from Main, which is cloned into
-- each Quin: the loop used to belong to whichever Quin pushed first, and when that Quin was
-- removed (knocked out, a new match) it stopped for everyone and was never restarted. Every
-- lunge, step back, flinch and skid then did nothing: Quins stood 7-8 studs apart striking at
-- air (1042 whiffs of 1046 strikes in 30 s). So the loop is checked, never assumed.
local function ensureLoop()
	if not stepConnection or not stepConnection.Connected then
		stepConnection = RunService.Heartbeat:Connect(step)
	end
end

-- Run the loop from a script that lives all session (Server). Call once at start-up.
function ImpulseModule.start()
	sessionLoop = true
	if stepConnection then stepConnection:Disconnect() end -- (one made by a Quin's script: replaced by ours)
	stepConnection = RunService.Heartbeat:Connect(step)
end

local function bodyFor(model, root)
	local body = bodies[model]
	if body and body.root == root and body.mover.Parent then
		return body
	end
	if body then release(model) end

	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root

	local mover = Instance.new("LinearVelocity")
	mover.Name = MOVER_NAME
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	mover.MaxAxesForce = Vector3.zero -- never counteracts gravity; X/Z set by the active requests
	mover.VectorVelocity = Vector3.zero
	mover.Attachment0 = attachment
	mover.Parent = root

	body = { root = root, mover = mover, attachment = attachment, requests = {} }
	bodies[model] = body
	ensureLoop()
	return body
end

-- Push a body along the ground.
--   tag       names the source ("lunge", "flinch", "slide", "knockback"); one request per tag
--   speed     peak studs/s; duration seconds
--   opts      { profile = "decay" | "lunge" | "friction" | "hold" (default "hold"),
--               endRatio = fraction of speed left at the end (friction / hold),
--               priority = ImpulseModule.Priority.*, maxForce = newtons per axis,
--               rampIn = seconds to reach the profile from the current speed (default: derived) }
-- Returns false when a contradicting, higher-priority push is already moving the body.
function ImpulseModule.push(model, tag, direction, speed, duration, opts)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root or not speed or speed <= 0 or not duration or duration <= 0 then return false end
	opts = opts or {}

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.001 then return false end
	flat = flat.Unit

	local profile = PROFILES[opts.profile] and opts.profile or "hold"
	local priority = opts.priority or ImpulseModule.Priority.SelfMotion
	local existing = bodies[model]
	if existing then
		for otherTag, other in pairs(existing.requests) do
			if otherTag ~= tag and other.direction:Dot(flat) < OPPOSING_DOT then
				if other.priority > priority then
					return false
				end
				existing.requests[otherTag] = nil
			end
		end
	end

	-- Start from what the body is already doing along the push, so nothing snaps
	local along = root.AssemblyLinearVelocity:Dot(flat)
	local startFactor = math.clamp(along / speed, -1, 1)
	local rampIn = opts.rampIn
	if not rampIn then
		rampIn = startFactor >= 0.9 and 0 or math.min(0.03 + 0.05 * (1 - startFactor), duration * 0.4)
	end

	local body = bodyFor(model, root)
	body.requests[tag] = {
		direction = flat,
		speed = speed,
		duration = duration,
		profile = profile,
		endRatio = opts.endRatio or 0.12,
		priority = priority,
		maxForce = opts.maxForce or DEFAULT_MAX_FORCE,
		rampIn = rampIn,
		startFactor = startFactor,
		startTime = os.clock(),
	}
	return true
end

-- Peak speed that makes a push of this profile travel `distance` studs on a free floor
function ImpulseModule.speedForDistance(distance, duration, profile, endRatio)
	return distance / (math.max(duration, 0.01) * profileMean(profile or "hold", endRatio or 0.12))
end

-- Stop one tagged push, or every push on the body when tag is nil
function ImpulseModule.cancel(model, tag)
	local body = bodies[model]
	if not body then return end
	if tag then
		body.requests[tag] = nil
		if next(body.requests) ~= nil then return end
	end
	release(model)
end

function ImpulseModule.isActive(model, tag)
	local body = bodies[model]
	if not body then return false end
	if tag then return body.requests[tag] ~= nil end
	return next(body.requests) ~= nil
end

return ImpulseModule
