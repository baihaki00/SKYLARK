local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local Trajectory = require(script.Parent.GASPTrajectory)
local StateGraph = require(script.Parent.GASPStateGraph)
local MotionDatabase = require(script.Parent.GASPMotionDatabase)
local Manifest = require(script.Parent.GASPAnimationManifest)

local GASPRuntime = {}
GASPRuntime.__index = GASPRuntime

function GASPRuntime.new(fighter, rootPart, overrides)
    local forward = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
    forward = Vector3.new(forward.X, 0, forward.Z).Unit
    local initialAngle = math.atan2(forward.X, -forward.Z)

    local self = setmetatable({
        fighter = fighter,
        rootPart = rootPart,
        trajectory = Trajectory.new(rootPart.CFrame, overrides),
        database = MotionDatabase.new(Manifest),
        mode = "Idle",
        action = "Loop",
        direction = "Neutral",
        previousMode = "Idle",
        previousAction = "Loop",
        actionStartTime = os.clock(),
        lastClip = "GASP_Stand_Idle_Loop",
        lastScore = 0,
        time = 0,
        wasAirborne = false,
        lockedQuery = nil,
        lockedUntil = 0,
        lastFacingAngle = initialAngle,
        stationaryHeading = initialAngle,
    }, GASPRuntime)
    return self
end

local function isFighterGrounded(fighter, rootPart)
    if not rootPart then return false end
    local humanoid = fighter and fighter:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local floorMat = humanoid.FloorMaterial
        if floorMat and floorMat ~= Enum.Material.Air then
            return true
        end
    end
    return SpatialModule.isGrounded(rootPart)
end

function GASPRuntime:step(intent, dt)
    if not self.rootPart or not self.rootPart.Parent then return nil end
    dt = math.clamp(tonumber(dt) or 1/60, 1/240, 1/10)
    self.time += dt
    local now = os.clock()

    -- 1. Authoritative Physical Grounding & Linear Velocity
    local isGrounded = isFighterGrounded(self.fighter, self.rootPart)
    self.trajectory.grounded = isGrounded
    Trajectory.step(self.trajectory, intent, dt)

    local linVel = self.rootPart.AssemblyLinearVelocity
    local flatVel = Vector3.new(linVel.X, 0, linVel.Z)
    local currentSpeed = flatVel.Magnitude
    local vertVel = linVel.Y

    -- 2. Character Facing Orientation (Ground Plane)
    local cf = self.rootPart.CFrame
    local forward = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
    forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
    right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)
    local currentFacingAngle = math.atan2(forward.X, -forward.Z)

    -- In-place stationary turning detection
    local inPlaceTurnAngle = 0
    if currentSpeed < 1.0 and (not intent or not intent.direction or intent.direction.Magnitude < 0.05) then
        local delta = (currentFacingAngle - self.stationaryHeading + math.pi) % (2 * math.pi) - math.pi
        inPlaceTurnAngle = math.deg(delta)
    else
        self.stationaryHeading = currentFacingAngle
    end

    -- Landing detection
    local justLanded = self.wasAirborne and isGrounded
    self.wasAirborne = not isGrounded

    -- 3. Resolve State Machine Query
    local timeInAction = now - self.actionStartTime
    local isLocked = self.lockedQuery ~= nil and now < self.lockedUntil

    local query = StateGraph.resolve({
        speed = currentSpeed,
        grounded = isGrounded,
        verticalVelocity = vertVel,
        intent = intent,
        characterForward = forward,
        characterRight = right,
        previousMode = self.mode,
        previousAction = self.action,
        timeInAction = timeInAction,
        inPlaceTurnAngle = inPlaceTurnAngle,
        landing = justLanded,
        lockedAction = isLocked,
        lockedDuration = (self.lockedUntil - self.actionStartTime),
        lockedQuery = self.lockedQuery,
    })

    -- 4. Query Motion Matching Database
    local clip, score = self.database:select(query)
    local selectedLabel = clip and clip.label or self.lastClip

    -- Update action state tracking
    if query.action ~= self.action or query.mode ~= self.mode then
        self.previousMode = self.mode
        self.previousAction = self.action
        self.mode = query.mode
        self.action = query.action
        self.direction = query.direction or "Forward"
        self.actionStartTime = now

        if query.lockDuration and query.lockDuration > 0 then
            self.lockedQuery = query
            self.lockedUntil = now + query.lockDuration
        else
            self.lockedQuery = nil
            self.lockedUntil = 0
        end
    end

    -- Reset stationary heading once turn completes
    if query.action == "Turn" and query.mode == "Idle" and now >= self.lockedUntil then
        self.stationaryHeading = currentFacingAngle
    end

    self.lastClip = selectedLabel
    self.lastScore = score

    if self.fighter then
        self.fighter:SetAttribute("GASPState", self.mode)
        self.fighter:SetAttribute("GASPAction", self.action)
        self.fighter:SetAttribute("GASPDirection", query.direction or "Forward")
        self.fighter:SetAttribute("GASPClip", self.lastClip or "")
        self.fighter:SetAttribute("GASPSelectionScore", tonumber(self.lastScore) or 0)
    end

    return self:snapshot()
end

function GASPRuntime:snapshot()
    return {
        state = self.mode,
        action = self.action,
        mode = self.mode,
        direction = self.direction,
        clip = self.lastClip,
        score = self.lastScore,
        phase = Trajectory.phase(self.trajectory),
        position = self.trajectory.position,
        velocity = self.trajectory.velocity,
        acceleration = self.trajectory.acceleration,
        forward = self.trajectory.forward,
        predicted = Trajectory.predict(self.trajectory, {}, nil, nil),
        database = self.database:debug(),
    }
end

return GASPRuntime
