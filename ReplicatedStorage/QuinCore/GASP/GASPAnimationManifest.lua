local assetMap = require(script.Parent:WaitForChild("GASPAssetMap"))

local METADATA = {
    ["GASP_Stand_Idle_Loop"]                = { mode = "Idle",   action = "Loop",       direction = "Neutral",  speed = 0,  duration = 10.00, rootMotion = true },
    ["GASP_Stand_Turn_090_L"]               = { mode = "Idle",   action = "Turn",       direction = "Left",     speed = 0,  duration = 2.00,  turnAngle = 90,  turnSide = "L", rootMotion = true },
    ["GASP_Stand_Turn_090_R"]               = { mode = "Idle",   action = "Turn",       direction = "Right",    speed = 0,  duration = 2.00,  turnAngle = 90,  turnSide = "R", rootMotion = true },
    ["GASP_Stand_Turn_180_L"]               = { mode = "Idle",   action = "Turn",       direction = "Left",     speed = 0,  duration = 2.17,  turnAngle = 180, turnSide = "L", rootMotion = true },
    ["GASP_Stand_Turn_180_R"]               = { mode = "Idle",   action = "Turn",       direction = "Right",    speed = 0,  duration = 2.17,  turnAngle = 180, turnSide = "R", rootMotion = true },

    ["GASP_Walk_Loop_F"]                    = { mode = "Walk",   action = "Loop",       direction = "Forward",  speed = 12, duration = 4.00,  rootMotion = true },
    ["GASP_Walk_Loop_B"]                    = { mode = "Walk",   action = "Loop",       direction = "Backward", speed = 10, duration = 4.03,  rootMotion = true },
    ["GASP_Walk_Loop_FL"]                   = { mode = "Walk",   action = "Loop",       direction = "Left",     speed = 12, duration = 4.00,  rootMotion = true },
    ["GASP_Walk_Loop_FR"]                   = { mode = "Walk",   action = "Loop",       direction = "Right",    speed = 12, duration = 4.00,  rootMotion = true },
    ["GASP_Walk_Start_FL_Lfoot"]            = { mode = "Walk",   action = "Start",      direction = "Forward",  speed = 12, duration = 3.10,  foot = "Left",  rootMotion = true },
    ["GASP_Walk_Start_FR_Rfoot"]            = { mode = "Walk",   action = "Start",      direction = "Forward",  speed = 12, duration = 2.77,  foot = "Right", rootMotion = true },
    ["GASP_Walk_Stop_FL_Lfoot"]             = { mode = "Walk",   action = "Stop",       direction = "Forward",  speed = 0,  duration = 4.70,  foot = "Left",  rootMotion = true },
    ["GASP_Walk_Stop_FR_Rfoot"]             = { mode = "Walk",   action = "Stop",       direction = "Forward",  speed = 0,  duration = 5.10,  foot = "Right", rootMotion = true },

    ["GASP_Run_Loop_F"]                     = { mode = "Run",    action = "Loop",       direction = "Forward",  speed = 24, duration = 2.50,  rootMotion = true },
    ["GASP_Run_Loop_B"]                     = { mode = "Run",    action = "Loop",       direction = "Backward", speed = 18, duration = 2.57,  rootMotion = true },
    ["GASP_Run_Loop_FL"]                    = { mode = "Run",    action = "Loop",       direction = "Left",     speed = 24, duration = 2.50,  rootMotion = true },
    ["GASP_Run_Loop_FR"]                    = { mode = "Run",    action = "Loop",       direction = "Right",    speed = 24, duration = 2.50,  rootMotion = true },
    ["GASP_Run_Start_FL_Lfoot"]             = { mode = "Run",    action = "Start",      direction = "Forward",  speed = 24, duration = 2.53,  foot = "Left",  rootMotion = true },
    ["GASP_Run_Start_FR_Rfoot"]             = { mode = "Run",    action = "Start",      direction = "Forward",  speed = 24, duration = 2.60,  foot = "Right", rootMotion = true },
    ["GASP_Run_Stop_FL_Lfoot"]              = { mode = "Run",    action = "Stop",       direction = "Forward",  speed = 0,  duration = 3.43,  foot = "Left",  rootMotion = true },
    ["GASP_Run_Stop_FR_Rfoot"]              = { mode = "Run",    action = "Stop",       direction = "Forward",  speed = 0,  duration = 3.60,  foot = "Right", rootMotion = true },
    ["GASP_Run_Turn_L_180_Lfoot"]           = { mode = "Run",    action = "Turn",       direction = "Left",     speed = 16, duration = 3.43,  turnAngle = 180, turnSide = "L", foot = "Left",  rootMotion = true },
    ["GASP_Run_Turn_R_180_Rfoot"]           = { mode = "Run",    action = "Turn",       direction = "Right",    speed = 16, duration = 3.40,  turnAngle = 180, turnSide = "R", foot = "Right", rootMotion = true },

    ["GASP_Sprint_Loop_F"]                  = { mode = "Sprint", action = "Loop",       direction = "Forward",  speed = 32, duration = 2.00,  rootMotion = true },
    ["GASP_Sprint_Start_FL_Lfoot"]          = { mode = "Sprint", action = "Start",      direction = "Forward",  speed = 32, duration = 2.43,  foot = "Left",  rootMotion = true },
    ["GASP_Sprint_Stop_FL_Lfoot"]           = { mode = "Sprint", action = "Stop",       direction = "Forward",  speed = 0,  duration = 4.70,  foot = "Left",  rootMotion = true },

    ["GASP_Transition_Walk_to_Run_Lfoot"]   = { mode = "Transition", action = "Transition", direction = "Forward", speed = 20, duration = 3.83, fromMode = "Walk",   toMode = "Run",    foot = "Left", rootMotion = true },
    ["GASP_Transition_Run_to_Walk_Lfoot"]   = { mode = "Transition", action = "Transition", direction = "Forward", speed = 14, duration = 4.47, fromMode = "Run",    toMode = "Walk",   foot = "Left", rootMotion = true },
    ["GASP_Transition_Run_to_Sprint_Lfoot"] = { mode = "Transition", action = "Transition", direction = "Forward", speed = 28, duration = 3.13, fromMode = "Run",    toMode = "Sprint", foot = "Left", rootMotion = true },
    ["GASP_Transition_Sprint_to_Run_Lfoot"] = { mode = "Transition", action = "Transition", direction = "Forward", speed = 26, duration = 3.37, fromMode = "Sprint", toMode = "Run",    foot = "Left", rootMotion = true },

    ["GASP_Jump_F_Start_Across_Lfoot"]      = { mode = "Jump",   action = "Start",      direction = "Forward",  speed = 24, duration = 2.10,  foot = "Left",  rootMotion = true },
    ["GASP_Jump_F_Off_Run_Lfoot"]           = { mode = "Jump",   action = "Loop",       direction = "Forward",  speed = 24, duration = 1.60,  foot = "Left",  rootMotion = true },
    ["GASP_Jump_F_Land_Roll_Lfoot"]         = { mode = "Jump",   action = "Stop",       direction = "Forward",  speed = 12, duration = 3.37,  foot = "Left",  rootMotion = false },
}

local clips = {}
for label, assetId in pairs(assetMap.Clips or {}) do
    if type(assetId) == "string" and string.match(assetId, "%d+") then
        local meta = METADATA[label] or {}
        clips[tostring(label)] = {
            id = assetId,
            mode = meta.mode or "Unknown",
            action = meta.action or "Loop",
            direction = meta.direction or "Forward",
            speed = meta.speed or 1,
            phase = meta.phase or 0,
            contact = meta.contact or "Unknown",
            duration = meta.duration,
            rootMotion = meta.rootMotion == true,
            turnAngle = meta.turnAngle,
            turnSide = meta.turnSide,
            foot = meta.foot,
            fromMode = meta.fromMode,
            toMode = meta.toMode,
        }
    end
end

return {
    Version = 1,
    Enabled = assetMap.Enabled == true,
    SourceProject = assetMap.SourceProject or "GameAnimationSample",
    SourceEngine = assetMap.SourceEngine or "Unreal Engine 5.8",
    RetargetSkeleton = assetMap.RetargetSkeleton or "Quin (Mixamo 52 bones)",
    Clips = clips,
    Metadata = METADATA,
}
