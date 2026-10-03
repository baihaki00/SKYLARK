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
    StadiumAnthem       = 60,   -- Anthem window: the anthem is back-timed to end 1s before it closes
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
    DuckingMultiplier = 0.60,       -- Music volume drops to 60% while ARIA speaks (a 40% duck; 20% was too much - owner)
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
    Drones              = true,  -- Spectator camera drones (launch at T-4 of the countdown, outro in post-game)
    ProceduralMusic     = true,
    CrowdFX             = true,  -- Procedural spatial crowd (ArenaCrowdManager, ArenaConfig.CrowdFX)
    ProceduralTerrain   = true,  -- Procedural arena layout (ArenaGenerator, ArenaConfig.ArenaGeneration); off = the edit-mode parts
}

ArenaConfig.AriaGapAfterGeneration = 5 -- seconds between ARIA's 'generation completed' and the preparation-room guide
-- Spectator drones' look (ArenaDroneManager): half see-through so they don't cover the arena
ArenaConfig.DroneVisuals = {
    PartTransparency = 0.5,   -- drone body
    TrailTransparency = 0.5,  -- flight trail (fades to nothing along its length)
    LabelMode = "fade",       -- name tags: "on" (always), "fade" (shown at launch, faded after LabelFadeAfter), "off"
    LabelFadeAfter = 3,       -- seconds
    LabelFadeTime = 1,        -- seconds
}
-- Procedural spatial crowd (ServerScriptService.ArenaCrowdManager). Sounds load from the CrowdFX
-- folder tree (<Group>/<Category>/<Sound>): every name below is a Category folder, never a sound id.
-- Emitters are spread along each stand part named EmitterPartName, so a row sounds like a row.
ArenaConfig.CrowdFX = {
    Folder = { "argoniaonion", "ArenaOne", "ArenaSoundFX", "CrowdFX" }, -- under Workspace
    EmitterPartName = "CrowdFX",
    EmitterSpacing = 110,     -- studs between emitters along a stand row
    MinEmitters = 2,
    MaxEmitters = 6,
    RollOffMin = 90,          -- full level within this distance of an emitter
    RollOffMax = 1100,
    -- (levels: the owner's baseline from the CROWD MIX sliders, 2026-10-03)
    Volume = 0.20,            -- crowd channel (ArenaCrowdChannel, under the arena master)
    DuckMultiplier = 0.15,    -- crowd level while ARIA speaks
    BedVolume = 0.31,         -- murmur loops, every emitter
    LayerVolume = 0.58,       -- mood loops (every other emitter), at full excitement
    ChantVolume = 0.37,
    ReactVolume = 0.61,       -- small/medium one-shots
    MajorVolume = 0.87,       -- big one-shots (eliminations, kick-off, winner)
    Crossfade = 2.5,          -- seconds for loop changes
    MaxOneShots = 12,         -- one-shots playing at once, whole stadium
    MinorGap = 0.5,           -- seconds between minor reactions, whole stadium
    SectionCooldown = 3.0,    -- seconds before a section reacts to a minor moment again
    PitchJitter = 0.04,       -- +/- playback speed per sound, so copies never phase
    AnthemStemScale = 0.25,   -- each section's copy of an anthem _CrowdFX / _DrumFX stem
    -- Excitement (0..1, per team): rises with the team's hits and decays to Rest
    ExcitementRest = 0.3,
    ExcitementDecay = 0.05,   -- per second
    HeavyHitFraction = 0.02,  -- damage / MaxHealth counted as a heavy hit
    TenseWhenAlive = 1,       -- tension once a team (or the FFA field) is down to this many (+1 in FFA)
    ChantEvery = { 22, 40 },  -- seconds between chants (IN_GAME)
    ChantLength = { 9, 15 },
    -- Murmur bed and mood layer per arena phase (Level scales BedVolume / LayerVolume)
    Phases = {
        ARENA_OPEN = { Bed = "CrowdMedium", Level = 0.8, Cue = "MediumApplause" },
        ARENA_GENERATION = { Bed = "CrowdMedium", Level = 0.6 },
        PREPARATION_ROOM = { Bed = "CrowdLow", Level = 0.7 },
        TELEPORTING_QUINS = { Bed = "CrowdMedium", Level = 0.9, Cue = "MediumCheer" },
        STADIUM_ANTHEM = { Bed = "CrowdLow", Level = 0.35 },
        PRE_GAME = { Bed = "CrowdBusy", Level = 1.0, Layer = "ExcitedCrowd", LayerLevel = 0.7 },
        IN_GAME = { Bed = "CrowdBusy", TenseBed = "CrowdTense", Level = 1.0, Cue = "HugeRoar", CueMajor = true },
        WINNER_DETERMINATION = { Bed = "CrowdBusy", Level = 1.0 },
        POST_GAME = { Bed = "CrowdMedium", Level = 0.6, Cue = "MediumApplause" },
    },
    -- Mood layers in play (by team excitement / tension)
    Moods = { Calm = "CalmCrowd", Excited = "ExcitedCrowd", Tense = "TenseCrowd", Angry = "AngryCrowd", Celebration = "CelebrationCrowd" },
    ExcitedAbove = 0.55,
    AngryTime = 8,            -- seconds a team's sections boo (AngryCrowd) after losing a fighter
    -- Reactions: For = sections backing the team that did it, Against = the other team's sections
    Reactions = {
        LightHit = { For = "ScatteredCheer", Chance = 0.10 },
        HeavyHit = { For = "MediumCheer", Against = "SmallGroan", Chance = 0.45 },
        Knockdown = { For = "MediumRoar", Against = "ShortGasp", Chance = 0.8 },
        Elimination = { For = "HugeCheer", Against = "MassiveDisappointment", Chance = 1.0, Major = true },
        -- FFA (every section neutral)
        NeutralHeavy = { For = "MediumCheer", Chance = 0.35 },
        NeutralKnockdown = { For = "ShortGasp", Chance = 0.6 },
        NeutralElimination = { For = "HugeRoar", Chance = 1.0, Major = true },
    },
    Chant = { Bed = "ChantBed", Phrase = "ShortChantPhrase" },
    Winner = { For = "MassiveCelebration", Against = "MassiveDisappointment", Draw = "MassiveShock" },
}

-- Procedural arena layout (ServerScriptService.ArenaGenerator), built during ARENA_GENERATION.
-- One half is generated and point-mirrored through the arena centre, so both sides are equal.
-- The edit-mode obstacles (EditLayoutNames) are only put aside and come back when the match ends.
ArenaConfig.ArenaGeneration = {
    MaxHeight = 400,          -- generation volume above ArenaGround (the scan sweeps this high)
    PlatformMaxHeight = 300,  -- highest platform top above the ground
    CenterClear = 200,        -- empty square in the middle (studs per side)
    WallMargin = 12,          -- studs kept free along the arena edge
    Spacing = 14,             -- studs between pieces (a Quin fits through; the route check guards the rest)
    VerticalClearance = 10,   -- studs between stacked pieces
    PlacementTries = 40,
    -- Spawn options (one per seed): TeamAlpha's anchor as a fraction of the half size (X, Z);
    -- TeamBeta's is the mirror. Two edges and two midpoints.
    SpawnOptions = {
        { Name = "Edge N-S", Alpha = { 0, 0.8 } },
        { Name = "Edge E-W", Alpha = { -0.8, 0 } },
        { Name = "Midpoint NW-SE", Alpha = { -0.55, 0.55 } },
        { Name = "Midpoint NE-SW", Alpha = { 0.55, 0.55 } },
    },
    SpawnClusterRadius = 30,  -- fighters spawn scattered inside this radius of their anchor
    SpawnSpacing = 7,
    SpawnClearRadius = 50,    -- no pieces this close to an anchor
    MaxSpawnPoints = 16,
    -- Platforms up to LadderMaxHeight get a spiral of stepping stones (each a normal jump);
    -- higher ones are projectile-jump perches
    LadderMaxHeight = 60,
    Stone = { Rise = 8, Hop = 13, Size = 10, Thickness = 2 },
    Pieces = {                -- per side; { min, max } ranges
        High = { Count = { 4, 7 }, LadderedShare = 0.5, MinHeight = 24, Width = { 40, 80 }, Thickness = { 3, 6 } },
        Float = { Count = { 3, 6 }, Width = { 12, 30 }, Thickness = { 2, 6 }, Underside = { 10, 40 } },
        Low = { Count = { 4, 7 }, Width = { 14, 36 }, Height = { 4, 10 } },
        Cover = { Count = { 10, 16 }, Width = { 6, 34 }, Height = { 4, 24 }, Depth = { 4, 26 } },
        Wall = { Count = { 3, 6 }, Length = { 30, 70 }, Thickness = { 3, 5 }, Height = { 12, 28 } },
    },
    -- Trees: clones of the edit-mode Workspace model named Template, on the ground and on the
    -- tops of wide platforms (mirrored like everything else)
    Trees = {
        Template = "Tree",
        Ground = { 4, 7 },          -- per side
        OnPlatformChance = 0.6,     -- per platform at least MinPlatformWidth wide
        MinPlatformWidth = 34,
        Scale = { 0.85, 1.2 },
        Footprint = 12,             -- studs kept free round a trunk
        Height = 45,                -- studs (template size; scaled)
        TrunkBlock = 8,             -- studs of trunk that block walking (route check)
    },
    -- Traversal check (grid flood fill from TeamAlpha's spawn)
    GridCell = 4,
    RouteWidth = 6,           -- studs a route must keep open
    UnderpassClearance = 9,   -- a piece this high off the ground can be walked under
    VaultHeight = 6.8,        -- a piece this low can be vaulted (TraversalModule.Config.VaultHeight)
    MinReachableShare = 0.97, -- share of the open floor that must be reachable (no closed pockets)
    -- Show (fractions of the ARENA_GENERATION phase)
    ScanShare = 0.1,
    ShuffleUntil = 0.62,
    SeedInterval = 0.14,      -- seconds between candidate seeds ("tutututu")
    MaxTries = 600,
    MaterializeTime = 3.0,
    FixedSeed = nil,          -- a number replays one layout
    HoloColor = Color3.fromRGB(0, 170, 255),
    HoloRejectColor = Color3.fromRGB(120, 90, 255),
    HoloMaterial = Enum.Material.Neon, -- (ForceField was nearly invisible from the stands)
    HoloTransparency = 0.55,
    GlitchShare = 0.25,       -- share of hologram pieces that jitter on each switch
    GlitchJitter = 4,
    GrassColors = { Color3.fromRGB(62, 104, 50), Color3.fromRGB(44, 82, 40) }, -- darker than ArenaGround so pieces read
    SolidMaterial = Enum.Material.SmoothPlastic,
    EditLayoutNames = { "OB", "highplatform" },
    EditLayoutModels = { "Tree" },
    -- Sounds (by name, in ArenaSoundFX or ArenaSoundFX/GenerationFX), played from the arena centre
    -- (where the generation happens), not the ArenaGlobe speaker
    Sounds = {
        Sweep = "ARENA_GENERATION1",  -- the generation run (10 s), from the scan
        Finish = "ARENA_GENERATION2", -- arena complete, when the last block is solid
        SeedTick = "SeedTick",        -- optional, per candidate switch
        SeedLock = "SeedLock",        -- optional, when the good seed locks
        Height = 25,                  -- studs above the floor
        RollOffMin = 200,
        RollOffMax = 1600,
        Volume = 1.0,
    }, -- edit-mode models on the arena floor, put aside the same way
    -- Seed-sweep FX: per-switch pop (transparency spread, tears, white flashes), flicker between
    -- switches, TV static inside every hologram block, scanlines across the volume
    HoloTransparencyRange = { 0.12, 0.85 },
    TearShare = 0.3,          -- share of blocks stretched sideways on a switch
    TearStretch = 0.35,
    FlashShare = 0.12,        -- share of blocks flashing white on a switch
    FlickerRate = 18,         -- per second, between switches
    FlickerShare = 0.15,
    StaticNoise = true,       -- ParticleEmitter snow inside each hologram block
    StaticRate = { 8, 45 },   -- particles per second (scaled by block volume)
    Scanlines = 3,            -- scanner frames (neon bars round the arena edge) jumping height on every switch
    ScanlineWidth = 0.8,
}

return ArenaConfig