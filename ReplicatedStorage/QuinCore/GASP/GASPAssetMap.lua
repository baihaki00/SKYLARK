--// GASPAssetMap.lua
-- Authoritative asset mapping for Unreal Engine 5.8 Game Animation Sample locomotion port.
-- All 33 clips are retargeted from UE 5.8 GameAnimationSample and bone-aligned to Quin's 52-bone mixamorig rig.

return {
    -- QUARANTINED 2026-09-29: imported retarget set has verified lower-leg excursions and malformed runtime poses.
    -- Re-enable only after retargeted clips pass the isolated pose audit.
    Enabled = false,
    SourceProject = "GameAnimationSample",
    SourceEngine = "Unreal Engine 5.8",
    RetargetSkeleton = "Quin (Mixamo 52 bones)",
    
    Clips = {
        -- ==========================================
        -- 1. IDLE & IN-PLACE TURNS (5 clips)
        -- ==========================================
        ["GASP_Stand_Idle_Loop"]                = "rbxassetid://131253594617114",
        ["GASP_Stand_Turn_090_L"]               = "rbxassetid://115475064380723",
        ["GASP_Stand_Turn_090_R"]               = "rbxassetid://85020175845135",
        ["GASP_Stand_Turn_180_L"]               = "rbxassetid://138637295967600",
        ["GASP_Stand_Turn_180_R"]               = "rbxassetid://131464428102564",

        -- ==========================================
        -- 2. WALK LOCOMOTION (8 clips)
        -- ==========================================
        ["GASP_Walk_Loop_F"]                    = "rbxassetid://101323140399164",
        ["GASP_Walk_Loop_B"]                    = "rbxassetid://84386972020987",
        ["GASP_Walk_Loop_FL"]                   = "rbxassetid://86289006859313",
        ["GASP_Walk_Loop_FR"]                   = "rbxassetid://94622148200646",
        ["GASP_Walk_Start_FL_Lfoot"]            = "rbxassetid://121824501714526",
        ["GASP_Walk_Start_FR_Rfoot"]            = "rbxassetid://121070497972959",
        ["GASP_Walk_Stop_FL_Lfoot"]             = "rbxassetid://108542062875214",
        ["GASP_Walk_Stop_FR_Rfoot"]             = "rbxassetid://118642181408397",

        -- ==========================================
        -- 3. RUN LOCOMOTION (10 clips)
        -- ==========================================
        ["GASP_Run_Loop_F"]                     = "rbxassetid://133242293786083",
        ["GASP_Run_Loop_B"]                     = "rbxassetid://91916103408731",
        ["GASP_Run_Loop_FL"]                    = "rbxassetid://89479252564570",
        ["GASP_Run_Loop_FR"]                    = "rbxassetid://116942222826338",
        ["GASP_Run_Start_FL_Lfoot"]             = "rbxassetid://77240991154105",
        ["GASP_Run_Start_FR_Rfoot"]             = "rbxassetid://131814659524351",
        ["GASP_Run_Stop_FL_Lfoot"]              = "rbxassetid://131409314701475",
        ["GASP_Run_Stop_FR_Rfoot"]              = "rbxassetid://94283730931120",
        ["GASP_Run_Turn_L_180_Lfoot"]           = "rbxassetid://117292668985031",
        ["GASP_Run_Turn_R_180_Rfoot"]           = "rbxassetid://106745386153032",

        -- ==========================================
        -- 4. SPRINT LOCOMOTION (3 clips)
        -- ==========================================
        ["GASP_Sprint_Loop_F"]                  = "rbxassetid://140081550582670",
        ["GASP_Sprint_Start_FL_Lfoot"]          = "rbxassetid://88499916096108",
        ["GASP_Sprint_Stop_FL_Lfoot"]           = "rbxassetid://123663421729965",

        -- ==========================================
        -- 5. GAIT TRANSITIONS (4 clips)
        -- ==========================================
        ["GASP_Transition_Walk_to_Run_Lfoot"]   = "rbxassetid://91937245437831",
        ["GASP_Transition_Run_to_Walk_Lfoot"]   = "rbxassetid://113389139258402",
        ["GASP_Transition_Run_to_Sprint_Lfoot"] = "rbxassetid://72846618106938",
        ["GASP_Transition_Sprint_to_Run_Lfoot"] = "rbxassetid://79084439429235",

        -- ==========================================
        -- 6. JUMP & LANDING (3 clips)
        -- ==========================================
        ["GASP_Jump_F_Start_Across_Lfoot"]      = "rbxassetid://119446545898467",
        ["GASP_Jump_F_Off_Run_Lfoot"]           = "rbxassetid://125263783852636",
        ["GASP_Jump_F_Land_Roll_Lfoot"]         = "rbxassetid://87533858487954",
    },
}
