--// ArenaConfig.lua
-- Single Source of Truth for Arena System Orchestrator: Phases, Timings, Game Modes, Playlists, ARIA Lines & Toggles

local ArenaConfig = {}

-- Phase Definitions & Default Durations (in seconds)
-- NOTE: Fully configurable at runtime and in UI
ArenaConfig.DefaultDurations = {
    ArenaOpen           = 10,   -- Arena opening fanfare, fireworks, music & announcer (10s)
    ArenaGeneration     = 15,   -- Procedural terrain / obstacle setup (15s)
    PreparationRoom     = 30,   -- Staging / warm-up in team staging pads (30s)
    TeleportingQuins    = 10,   -- Teleport quins to designated combat area (10s)
    PreGame             = 5,    -- Final 5-4-3-2-1 stadium countdown (drones launch at 4)
    GameTime            = 600,  -- 10 Minutes max game duration
    WinnerDetermination = 8,    -- Victory celebration & winner fireworks
    PostGame            = 180,  -- 3 Minutes: Post-game closure, spectators leaving arena
}

-- Fast Test Durations Preset (for rapid developer iteration)
ArenaConfig.FastTestDurations = {
    ArenaOpen           = 2,
    ArenaGeneration     = 2,
    PreparationRoom     = 3,
    TeleportingQuins    = 2,
    PreGame             = 5,
    GameTime            = 20,
    WinnerDetermination = 3,
    PostGame            = 20,   -- Allows observing 15s jet outro climb + arena closure
}

-- Game Modes
ArenaConfig.GameModes = {
    ["1vs1"] = {
        Id = "1vs1",
        Name = "1 vs 1 Duel",
        Description = "Direct two-Quin duel. High stakes standoff, anticipation, and kinetic combo exchanges.",
        DefaultTeamSize = 1,
        SupportedSizes = { 1 },
        IsProcedural = false,
    },
    ["FFA"] = {
        Id = "FFA",
        Name = "Free-For-All (FFA)",
        Description = "Chaotic survival brawl. Every Quin for itself in the arena.",
        DefaultTeamSize = 8,
        SupportedSizes = { 4, 8, 16 },
        IsProcedural = false,
    },
    ["TeamBattle"] = {
        Id = "TeamBattle",
        Name = "Team Battle",
        Description = "Coordinated squad combat: Team Alpha vs Team Beta. Scales from skirmishes to full-scale Arena War.",
        DefaultTeamSize = 4,
        SupportedSizes = { 2, 4, 8, 16 },
        IsProcedural = false,
    },
    ["GrandArena"] = {
        Id = "GrandArena",
        Name = "Grand Arena (8 vs 8)",
        Description = "Massive 16-Quin battle across procedural terrain, dynamic vertical hurdles, and multi-tier obstacles.",
        DefaultTeamSize = 8,
        SupportedSizes = { 8 },
        IsProcedural = true,
        IsFutureImplementation = true,
    }
}

-- Sound System & Speaker Acoustic Settings
ArenaConfig.AudioSettings = {
    BaselineVolume = 1.0,           -- Standard baseline volume across all tracks so Bai can tweak in Edit mode
    DuckingMultiplier = 0.20,       -- Music volume attenuates to 20% while ARIA speaks
    DuckTweenTime = 0.35,           -- Smooth fade down time
    UnduckTweenTime = 0.65,         -- Smooth restore time
    SpeakerMinDistance = 10,
    SpeakerMaxDistance = 1500,
    SpeakerRollOffMode = Enum.RollOffMode.Inverse,
    Echo = {
        Delay = 1.0,
        DryLevel = -45.8,
        Feedback = 0.12,
        WetLevel = 8.2,
    },
    Reverb = {
        DecayTime = 4.279,
        Density = 1.0,
        Diffusion = 1.0,
        DryLevel = 2.0,
        WetLevel = 6.0,
    }
}

-- Music Playlists (Default fallbacks if Workspace folder is unavailable; live UI dynamically scans Workspace.argoniaonion.ArenaOne.Music)
ArenaConfig.PreGamePlaylist = {
    { Id = "rbxassetid://99750260128110",  Name = "365" },
    { Id = "rbxassetid://133121268471992", Name = "GUTU ONLY_Master" },
    { Id = "rbxassetid://126291069838831", Name = "TOMA FUNK PHONK" },
    { Id = "rbxassetid://133867258789343", Name = "ts - butterflyeffect live" },
    { Id = "rbxassetid://103937504170019", Name = "SYSTEMMUSIC" },
    { Id = "rbxassetid://83342518250258",  Name = "SPLICEMUSIC" },
    { Id = "rbxassetid://106739257785158", Name = "LALUATEST" },
}

ArenaConfig.InGamePlaylist = {
    { Id = "rbxassetid://99750260128110",  Name = "365" },
    { Id = "rbxassetid://133121268471992", Name = "GUTU ONLY_Master" },
    { Id = "rbxassetid://133867258789343", Name = "ts - butterflyeffect live" },
    { Id = "rbxassetid://83342518250258",  Name = "SPLICEMUSIC" },
    { Id = "rbxassetid://106739257785158", Name = "LALUATEST" },
}

ArenaConfig.PostGamePlaylist = {
    { Id = "rbxassetid://106739257785158", Name = "LALUATEST" },
    { Id = "rbxassetid://139341117198830", Name = "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2" },
}

ArenaConfig.ProceduralMusic = {} -- Reserved for future procedural generation

-- ARIA AI Stadium Announcer Voice Sequences
-- Each category contains an array of 1-3 clips to allow randomized selection.
-- Empty arrays gracefully no-op.
ArenaConfig.AriaVoiceLines = {
    ARIA_ArenaOpen = {
        { Id = "rbxassetid://111233857607492", Name = "ARIA_ArenaIsOpen1", Subtitle = "Arena gates are open! Welcome to the battlefield." },
        { Id = "rbxassetid://117951721866687", Name = "ARIA_ArenaIsOpen2", Subtitle = "The arena is now open. Combatants, prepare yourselves." },
    },
    ARIA_AnnouncementPreparationRoomGuide = {
        { Id = "rbxassetid://105606408923571", Name = "ARIA_Annoucement_PreparationRoomGuide", Subtitle = "All combatants, proceed immediately to designated preparation zones." },
    },
    ARIA_ArenaGenerationCommence = {
        { Id = "rbxassetid://89916411096443", Name = "ARIA_ArenaIsGenerating", Subtitle = "Arena generation commencing. Stand clear of combat sector hazards." },
    },
    ARIA_ArenaGenerationCompleted = {
        { Id = "rbxassetid://92509748412290", Name = "ARIA_ArenaGenerationComplete1", Subtitle = "Arena generation complete. Field calibrated for battle." },
        { Id = "rbxassetid://70625793891633", Name = "ARIA_ArenaGenerationComplete2", Subtitle = "Battleground configuration finished. All systems active." },
    },
    ARIA_TeleportingQuinsToDesignatedAreas = {
        { Id = "rbxassetid://91468162088021", Name = "ARIA_TeleportingQuinsToDesignatedAreas", Subtitle = "Teleporting Quins to designated deployment staging areas." },
    },
    ARIA_54321GameCountdown = {
        -- Blank / placeholder for future voice lines
    },
    ARIA_AnnounceWinner = {
        -- Blank / placeholder for future voice lines
    },
    ARIA_ArenaClosing = {
        { Id = "rbxassetid://101847151661997", Name = "ARIA_ArenaIsNowClosing", Subtitle = "The arena is now closing. Match officially concluded." },
    },
    ARIA_Please = {
        -- Blank / placeholder for future voice lines
    },
    ARIA_LeaveTheArenaGuide = {
        { Id = "rbxassetid://78159893663395", Name = "ARIA_LeaveTheArenaGuide", Subtitle = "Spectators and personnel, please proceed orderly to the arena exits." },
    },
    ARIA_SkylarkClosure = {
        { Id = "rbxassetid://112194526998234", Name = "ARIA_SkylarkClosure", Subtitle = "Skylark Isles arena protocols closing down. Thank you for your presence." },
    },
}

-- Default Toggle Settings
ArenaConfig.DefaultToggles = {
    Announcer           = true,
    TimerPreGame        = true,
    Screen              = true,
    Referee             = false, -- Reserved / Later
    Fireworks           = true,
    ProceduralMusic     = true,
    CrowdFX             = false, -- Reserved / Later
    ProceduralTerrain   = false, -- If false, uses existing edit-mode parts
}

return ArenaConfig
