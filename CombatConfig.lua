--// CombatConfig.lua
-- Global combat tuning parameters
-- Tweak these to change the feel of ALL fighters at once

local CombatConfig = {

	--// KNOCKBACK
	KnockbackHorizontalForce = 200, -- Reduced by 20%
	KnockbackVerticalForce = 20,
	KnockbackDuration = 0.3,

	--// LAUNCH (uppercut sends enemy flying horizontally now)
	LaunchVerticalForce = 8,
	LaunchHorizontalForce = 224, -- Reduced by 20%
	LaunchDuration = 0.5,

	--// SLAM (air slam to ground)
	SlamDownForce = 176, -- Reduced by 20%
	SlamImpactRadius = 14,
	SlamImpactDuration = 0.2,

	--// COMBO
	ComboWindowTime = 0.8,
	ComboDamageBonus = 0.10,
	ComboSpeedBonus = 0.05,

	--// HITBOX
	DefaultHitboxSize = Vector3.new(5, 5, 5),
	DefaultHitboxOffset = Vector3.new(0, 0, -3),
	HitboxLifetime = 0.3,

	--// STUN
	BaseStunDuration = 1.5,
	HeavyStunDuration = 3.5,

	--// AIR PURSUIT
	AirPursuitJumpForce = 150,
	AirPursuitMaxHeight = 80,
	AirSlamDownVelocity = 200,

	--// SLIDE / DASH
	DashSpeed = 110,
	DashMinDistance = 15,
	DashMaxDistance = 60,
	SlideSpeed = 56,
	SlideDuration = 0.42,
	SlideCooldown = 2.5,
	SlideMinEnergy = 12,
	SlideGapMaxHeight = 3.8,
	SlideGapMinHeight = 0.8,

	--// WALL RUNNING (Phase 6 Parkour Traversal)
	WallRunSpeed = 48,
	WallRunMaxDuration = 1.25,
	WallRunCooldown = 5.0,
	WallRunMinSpeed = 18,
	WallRunMinEnergy = 15,
	WallRunMinHeight = 3.0,
	WallRunRayDistance = 4.8,
	WallRunMinAngle = 25, -- degrees incident to wall plane
	WallRunMaxAngle = 78,
	WallKickOutwardImpulse = 28,
	WallKickForwardImpulse = 34,
	WallKickUpwardImpulse = 18,
	WallRunTiltDegrees = 18,

	--// PROJECTILE FIGHT (Ablation / Fallback Toggle: set to false to disable)
	EnableProjectileJump = true,
	ProjectileJumpMinDistance = 25,
	ProjectileJumpMaxDistance = 800,
	ProjectileJumpChance = 0.35,

	--// RANGES
	CombatRange = 8.2,
	ChaseRange = 800,
	DetectionRange = 300,
	BlastRange = 40,

	--// AI DECISIONS
	AttackCooldownMin = 0.3,
	AttackCooldownMax = 1.0,
	SpecialMoveChance = 0.15,
	DashAttackChance = 0.20,
	CounterChance = 0.10,

	--// CRITICAL HITS
	CriticalDamageMultiplier = 2.0,

	--// DEATH
	DeathFadeTime = 3,
	DeathCleanupDelay = 3,

	--// GAME MODE DEFAULTS
	DefaultMode = "TestAnimationMode",
	DefaultTeamSize = 4,
	TournamentRounds = 3,
	RespawnDelay = 5,
	MaxQuinsPerSide = 16,
	
	--// VFX
	VfxStylizedHits = true,
	
	--// SPECTATOR
	EnableSpectatorMode = true,
	
	--// ENERGY / FATIGUE (Mana Economy)
	MaxEnergy = 100,
	EnergyDrain_Sprint = 2,        -- per second while sprinting
	EnergyDrain_Attack = 2,         -- per swing
	EnergyDrain_Dash = 20,          -- per athletic dash (costs meaningful mana!)
	EnergyDrain_ProjectileJump = 40, -- per projectile jump (major tactical commitment!)
	EnergyDrain_Special = 15,       -- per special move
	DashMinEnergy = 25,            -- required mana to initiate dash
	ProjectileJumpMinEnergy = 40,  -- required mana to initiate projectile jump
	EnergyRecovery_Idle = 16,        -- per second while idle
	EnergyRecovery_Walk = 10,        -- per second while walking / tactical pacing
	EnergyRecovery_Cooldown = 8,     -- per second during cooldown chase
	FatigueThreshold = 25,          -- below 25 mana, quins must walk/circle to regenerate mana
	
	--// LOCOMOTION & KINETIC WEIGHT (Phase 1)
	LocomotionAcceleration = 70,    -- studs/s^2 (builds up 0 -> 40 studs/s in ~0.57s)
	LocomotionDeceleration = 130,   -- studs/s^2 (brakes 40 -> 0 studs/s in ~0.31s)
	WalkBrakingThreshold = 6.0,     -- speed below which braking stops are triggered

	--// TARGET TRANSITION BUFFER (Phase 1)
	TargetTransitionDurationMin = 0.40, -- seconds (high aggression / urgent alert)
	TargetTransitionDurationMax = 0.85, -- seconds (cautious survey / breathing reset)

	--// DIRECTIONAL AWARENESS & 360 THREAT PERCEPTION (Phase 2)
	RearThreatDetectionRange = 22.0,   -- studs (max range for high-awareness quins to detect rear flankers)
	RearThreatCriticalRange = 10.0,    -- studs (range where rear threats trigger reactive turn/parry)
	SurroundedQuadrantThreshold = 3,   -- quadrants occupied to constitute true surrounded state
	BulliedFocusThreshold = 2,         -- enemies targeting self to trigger 'BeingBullied' state

	--// SIMULATION SPEED
	DefaultGameSpeed = 1.0,        -- 1.0x standard speed by default

	--// INTELLIGENT RETREAT & SAFE HAVEN (Phase 3)
	RetreatSearchRadius = 30.0,         -- studs (radial scan distance for safe haven evaluation)
	RetreatEnemyRepulsionWeight = 1.5,  -- how strongly retreat avoids enemy centroid
	RetreatAllyAttractionWeight = 0.8,  -- how strongly retreat seeks allied cluster
	RetreatBoundaryPenalty = 1.2,       -- penalty for retreating toward arena edge
	RetreatObstaclePenalty = 1.0,       -- penalty for retreating into obstacles/walls
	RetreatCenterBias = 0.3,            -- gentle pull toward arena center during retreat
	CorneredScoreThreshold = 0.15,      -- below this retreat quality score = cornered (triggers counter-strike for aggressive quins)
	CorneredCounterThreshold = 0.65,    -- aggression above this = cornered beast counter-strikes instead of retreating

	--// SURVIVAL DECISION & CONTINUOUS TACTICAL PURSUIT (Phase 13)
	EscapeFeasibilityThreshold = 0.20,    -- below this feasibility, escape is abandoned in favor of last stand / counterattack
	LastStandAggressionBonus = 0.50,      -- attack/counter utility boost when in Last Stand
	JukeTriggerDistance = 14.0,           -- studs (distance to closing pursuer that triggers sharp 90-135 deg lateral cut)
	JukeClosingSpeedThreshold = 5.0,      -- studs/s (closing velocity towards runner required to trigger juke)
	JukeDuration = 0.35,                  -- seconds (duration of lateral juke evasion cut)
	JukeCooldown = 1.8,                   -- seconds (min interval between sharp jukes)
	PredictiveLeadMaxTime = 1.2,          -- seconds (maximum forward extrapolation time for chaser interception)
	PredictiveLeadMinTime = 0.2,          -- seconds (minimum forward extrapolation time for chaser interception)
	DefendDelayDistance = 35.0,           -- studs (proximity of reinforcing ally for defend-and-delay behavior)
	PursuerOverextendWhiffDistance = 10.0, -- studs (distance within which a chaser whiff triggers immediate counter-strike)

	--// VERTICAL NAVIGATION & FLOATING PLATFORM (Phase 4)
	ElevatedPlatformThreshold = 6.0,     -- studs above arena floor to classify as elevated OB platform
	PlatformDismountRayRange = 12.0,     -- studs (ledge search sweep radius for dismount direction)
	PlatformDismountRayCount = 12,       -- candidate directions swept for platform ledge
	VerticalStuckThreshold = 0.8,        -- studs (movement progress over 1.2s below this = stuck against vertical face)
	VerticalUnstickJumpHeight = 9.0,     -- studs (vertical hop when unstick triggered)

	--// PROJECTILE JUMP GROUND SLAM & RECOVERY (Phase 5)
	SlamRecoveryDuration = 0.50,          -- seconds (impact absorption hold before re-engaging)
	SlamRecoveryDurationJitter = 0.10,    -- seconds (organic +/- variance on recovery hold)
	SlamShockwaveRadius = 14.0,           -- studs (radius within which victims are stumbled/knocked back)
	SlamStumbleForce = 90.0,              -- knockback force at shockwave epicenter
	SlamStumbleDuration = 0.35,           -- seconds (ground slide duration for stumbled victims)

	--// PARKOUR & OB UTILIZATION (Phase: vertical navigation)
	HighGroundJumpReach = 14.0,           -- studs (max vertical reach to climb an overhead platform)
	HighGroundJumpCooldown = 6.0,         -- seconds (min interval between high-ground climbs)
	HighGroundLowHpThreshold = 0.35,      -- hp ratio below which a Quin seeks high ground for safety
	PositioningJumpMaxReach = 80.0,       -- studs (max platform height for a positioning projectile-jump)
	PositioningJumpCooldown = 10.0,       -- seconds (min interval between positioning PJs)
	PositioningJumpClearance = 40.0,      -- studs (extra apex height so the arc clears the platform edge and lands ON TOP)
	SlideUnderGapMin = 0.8,               -- studs (min gap height to slide under)
	SlideUnderGapMax = 3.5,               -- studs (max gap height to slide under)
	SlideUnderSpeed = 40.0,               -- studs/s (slide horizontal speed)
	SlideUnderCooldown = 4.0,             -- seconds (min interval between slides)

	--// DECISION-DRIVEN BEHAVIOR (wire tactical decision → FSM; ablation-friendly)
	RetreatBreakoffCooldown = 3.0,        -- seconds min between retreat break-offs (prevents state thrash)
	PursueEngageDistance = 20.0,          -- studs beyond which a Pursue decision forces a chase

	--// SURVIVAL INSTINCT (retreat calibration)
	RetreatCriticalHealth = 0.20,         -- hp ratio below which near-death survival instinct triggers
	RetreatConfidenceThreshold = 0.70,    -- confidence below which a near-death Quin retreats (else it fights back)

	--// PHASE 12 SPECTACLE: DYNAMIC BEAM STRUGGLES, AURA FARMING & RIVAL FINISHERS
	BeamStruggle_PowerUpDurationMin = 0.50, -- min seconds charging wind-up before beam fire
	BeamStruggle_PowerUpDurationMax = 0.85, -- max seconds charging wind-up before beam fire
	BeamStruggle_ReactionDelayMin = 0.04,   -- organic execution delay before opponent counter-beam
	BeamStruggle_ReactionDelayMax = 0.12,   -- organic execution delay before opponent counter-beam
	BeamStruggle_ContinuousManaTick = 0.10, -- seconds per continuous mana tick
	BeamStruggle_ContinuousManaDrain = 2.0, -- -2 mana consumed every 0.10s (~20 mana/s)
	BeamStruggle_SurgeManaCost = 5.0,       -- -5 mana per tactical surge decision
	BeamStruggle_SurgePushForce = 35.0,     -- push force spike when surging forward
	BeamStruggle_DesperateBurstCost = 8.0,  -- mana for emergency counter-surge when near death
	BeamStruggle_DesperateBurstForce = 55.0,-- push force spike for emergency counter-surge
	BeamStruggle_FatalDamage = 55.0,        -- significant damage on beam breakthrough
	BeamStruggle_FatalKnockbackForce = 36.0, -- knockback impulse force (~25 studs travel)
	BeamStruggle_MinDuration = 1.2,       -- min seconds before breach resolution
	BeamStruggle_ClashRange = 80.0,       -- max studs separation for opposing specials to lock (45-80 studs threshold)
	BeamStruggle_ClashRangeMin = 45.0,    -- min studs for ranged beam struggle engagement
	BeamStruggle_ClashRangeMax = 80.0,    -- max studs for ranged beam struggle engagement
	BeamStruggle_BreachDwellTime = 0.60,  -- seconds winner beam sustains and drives into loser during breach
	BeamStruggle_BobAmplitude = 0.75,     -- studs vertical sinusoidal floating amplitude (opposite-phase seesaw)
	BeamStruggle_BobFrequency = 3.2,      -- Hz vertical bobbing frequency
	BeamStruggle_ShakeAmplitude = 0.20,   -- studs physical micro-shake displacement (kinetic strain/weight)
	BeamStruggle_ShakeFrequency = 25.0,   -- Hz micro-vibration frequency
	BeamStruggle_ArcOrbitSpeed = 0.45,    -- radians/s orbital axis rotation rate (switching places in mid-air)
	BeamStruggle_ElemAdvantageMult = 1.35,-- +35% push force multiplier for dominant elemental matchup

	AuraFarm_SuperGainPerSec = 15.0,      -- SuperMeter charged per second
	AuraFarm_EnergyGainPerSec = 20.0,     -- Energy regenerated per second
	AuraFarm_MinEnemyDist = 25.0,         -- minimum studs from closest enemy to initiate aura farm
	AuraFarm_CompletionDuration = 2.2,    -- seconds required to complete aura farm and trigger AuraSurge
	AuraFarm_VulnerabilityMultiplier = 1.15, -- +15% damage received if struck while showboating

	RivalFinisher_KnockbackForce = 140.0, -- studs/s physical knockback impulse (~20-25 studs travel)
	RivalFinisher_KnockbackDuration = 0.40, -- seconds knockback travel

	-- Phase 13: Tactical Survival, Evaluated Escape, & Juke System
	EscapeFeasibilityThreshold = 0.20,       -- Below this, Quin determines escape is suicidal and enters Last Stand
	LastStandAggressionBonus = 0.50,         -- +50% aggression multiplier during desperate last stand
	JukeTriggerDistance = 14.0,              -- Max studs distance behind to trigger lateral juke cut
	JukeClosingSpeedThreshold = 5.0,         -- Min pursuer closing speed (studs/s) to trigger juke
	JukeDuration = 0.35,                     -- Seconds a juke lateral cut vector is sustained
	JukeCooldown = 2.0,                      -- Cooldown between successive jukes
	PredictiveLeadMaxTime = 1.2,             -- Max seconds lead time for chaser intercept steering
	DefendDelayDistance = 35.0,              -- Studs range for approaching ally to trigger defend & delay
	PursuerOverextendWhiffDistance = 10.0,   -- Max studs distance to counterattack on pursuer whiff
	CorneredScoreThreshold = 0.22,           -- Below this retreat score, Quin is considered cornered
	RetreatObstaclePenalty = 2.2,            -- Weight for obstacle collision avoidance in retreat

	-- Locomotion & Physicality Parameters (Rule 2 & Rule 6)
	Locomotion_Acceleration = 80.0,          -- studs/s^2 forward drive acceleration
	Locomotion_BrakingDeceleration = 140.0,   -- studs/s^2 committed braking deceleration
	Locomotion_TractionSlipFactor = 0.35,     -- slip traction multiplier during sharp 180° direction reversals
	Locomotion_MaxTurnRate = 18.0,            -- rad/s maximum angular turn rate
	Locomotion_JumpImpulse = 56.0,           -- studs/s single vertical ballistic jump impulse
	Locomotion_JumpDebounce = 1.0,           -- seconds minimum between successive jumps
	Locomotion_LandingRetention = 0.88,      -- ratio of horizontal velocity preserved on landing (88%)
	Locomotion_SkidSpeedThreshold = 20.0,    -- studs/s minimum speed to trigger dynamic braking skid
	EnableOpeningProjectileJump = false,     -- Permanently ban start-of-match projectile jumps; grounded charges first

	-- Melee Sweet-Spot & Transitions (Single Source of Truth)
	Melee_SweetSpotMin = 4.5,                -- studs min melee engagement range
	Melee_SweetSpotMax = 8.5,                -- studs max melee sweet spot before stepping forward
	Melee_LungeSpeed = 32.0,                 -- studs/s physical lunge impulse
	Melee_SlideSpeed = 10.0,                 -- studs/s micro-slide spacing adjustment

	-- Continuous Locomotion Synthesis & Stride Scaling (Step 1 & 2)
	WalkStrideBase = 16.0,                   -- studs/s baseline stride speed for WalkConfident
	RunStrideBase = 38.0,                    -- studs/s baseline stride speed for Run
	TorsoBankingMaxRoll = 12.0,              -- degrees max lateral roll bank into turns
	TorsoBankingResponsiveness = 10.0,       -- lerp responsiveness for centripetal roll

	-- Procedural Foot IK & Ledge Gripping (Step 3)
	FootIK_Enabled = true,                   -- global toggle for procedural foot planting
	FootIK_RayDistance = 6.8,                -- studs down from hip to detect ground (HRP is ~5.36 studs above floor)
	FootIK_MaxStepDown = 2.4,                -- max vertical drop a foot will conform to before treating as ledge
	FootIK_MaxStepUp = 1.6,                  -- max vertical step up a foot will climb
	FootIK_AnkleAlignment = true,            -- align foot orientation to terrain surface normal
	FootIK_LedgeGrip = true,                 -- detect ledge lip and apply toe flexion
	FootIK_HipsDipScale = 0.50,              -- pelvis vertical drop ratio (0.0 to 1.0)
	FootIK_HeightOffset = 0.0,               -- fine vertical foot adjustment (studs)
	FootIK_GaitModulation = true,            -- modulate IK weight during sprint/walk swing phases
	FootIK_ToeFlexion = true,                -- procedural anti-penetration toe roll/flexion on ground contact
	FootIK_ToeSoleThickness = 0.14,          -- studs sole thickness below toe bone (prevents toe clipping)
	VisualGhostHeightOffset = 0.02,          -- vertical calibration offset (studs) ensuring visual shoe sole rests flush on terrain without bone deformation

	-- Active Muscle Ragdoll & Spectacle Knockback (Step 4)
	Ragdoll_MuscleStiffness = 8000,          -- AlignOrientation torque for active core tension
	Ragdoll_Damping = 120,                   -- damping factor for ragdoll joints
	Ragdoll_TumbleScale = 1.0,               -- multiplier for hit impact angular tumble velocity
	Ragdoll_AirDrag = 0.85,                  -- aerodynamic drag alignment factor during flight
	Ragdoll_GroundFriction = 0.55,           -- ground momentum slide retention on impact
	Ragdoll_RecoveryDelay = 0.40,            -- seconds before initiating get-up from prone/supine
}

return CombatConfig