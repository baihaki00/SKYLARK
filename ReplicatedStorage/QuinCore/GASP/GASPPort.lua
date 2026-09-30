local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = script.Parent
local Manifest = require(root.GASPManifest)
local MotionDatabase = require(root.GASPMotionDatabase)
local Trajectory = require(root.GASPTrajectory)
local StateGraph = require(root.GASPStateGraph)
local AnimationManifest = require(root.GASPAnimationManifest)

local GASPPort = {}

function GASPPort.validate()
    return Manifest.validate(AnimationManifest)
end

function GASPPort.createTrajectory(rootCFrame, overrides)
    return Trajectory.new(rootCFrame, overrides)
end

function GASPPort.createDatabase()
    return MotionDatabase.new(AnimationManifest)
end

function GASPPort.resolveState(input)
    return StateGraph.resolve(input)
end

function GASPPort.status()
    local report = GASPPort.validate()
    local database = MotionDatabase.new(AnimationManifest)
    return {
        enabled = AnimationManifest.Enabled == true and report.ok,
        errors = report.errors,
        warnings = report.warnings,
        database = database:debug(),
    }
end

return GASPPort
