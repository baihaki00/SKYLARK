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
	SlideCooldown = 8.0,
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
	WallRunTiltDegrees = 18,                 -- whole-body lean away from the wall during the run
	WallRunHeight = 3.5,                     -- studs the run climbs above the floor it started from
	WallRunMinRunway = 24,                   -- studs of wall that must lie ahead before a run starts (0.5s at run speed)

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
	AttackCooldownMin = 0.2,
	AttackCooldownMax = 0.7,
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
	DecisionHysteresisScoreDelta = 15.0,  -- utility score margin required to switch recommended action
	StateDwellMin_Chase = 0.8,            -- seconds minimum commitment before voluntary chase state exit
	StateDwellMin_Retreat = 1.2,          -- seconds minimum commitment before voluntary retreat state exit
	StateDwellMin_Circling = 1.0,         -- seconds minimum commitment before voluntary circling state exit
	StateDwellMin_Fight = 0.6,            -- seconds minimum commitment before voluntary fight state exit
	QuinEyeHeight = 3.0,                  -- studs above HRP center for 8-stud tall Quin eye-level raycasts

	--// SURVIVAL INSTINCT (retreat calibration)
	RetreatCriticalHealth = 0.20,         -- hp ratio below which near-death survival instinct triggers
	RetreatConfidenceThreshold = 0.70,    -- confidence below which a near-death Quin retreats (else it fights back)
	RetreatSafeDistance = 85.0,           -- studs minimum distance from nearest threat to consider retreat successful
	RetreatMinDuration = 2.5,             -- seconds minimum before allowing safe haven transition to defensive stance

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
	Locomotion_Acceleration = 55.0,          -- studs/s^2 forward drive acceleration (rest to sprint in ~0.7s: three or four strides)
	Locomotion_BrakingDeceleration = 95.0,    -- studs/s^2 smooth braking deceleration (natural 1-2 step decel plant)
	Locomotion_TractionSlipFactor = 0.35,     -- slip traction multiplier during sharp 180° direction reversals
	Locomotion_MaxTurnRate = 22.0,            -- rad/s maximum angular turn rate
	Locomotion_GroundTurnResponse = 16.0,      -- rad/s response for continuous grounded arcs (GTA V / Watch Dogs responsiveness)
	Locomotion_ForwardTurnLateralScale = 1.00, -- Pure isotropic 360° input (zero angular distortion)
	Locomotion_JumpImpulse = 56.0,           -- studs/s single vertical ballistic jump impulse
	Locomotion_JumpDebounce = 1.0,           -- seconds minimum between successive jumps
	Locomotion_LandingRetention = 0.88,      -- ratio of horizontal velocity preserved on landing (88%)
	Locomotion_SkidSpeedThreshold = 14.0,    -- studs/s minimum speed to trigger dynamic braking skid
	Locomotion_TurnRateSlow = 10.0,          -- rad/s heading-change ceiling at walking pace (nimble pivots)
	Locomotion_LateralGrip = 90,             -- studs/s^2 sideways a running body can lean into: turn rate = grip / speed (2.2 rad/s at 40)
	Locomotion_TurnRateFast = 2.2,           -- rad/s heading-change ceiling at full sprint (momentum widens the arc)
	Locomotion_TurnRateSlowSpeed = 8.0,      -- studs/s at or below which the slow-pace ceiling applies
	Locomotion_TurnRateFastSpeed = 44.0,     -- studs/s at or above which the sprint ceiling applies
	EnableOpeningProjectileJump = false,     -- Permanently ban start-of-match projectile jumps; grounded charges first

	-- Melee Sweet-Spot & Transitions (Single Source of Truth)
	Melee_SweetSpotMin = 4.5,                -- studs min melee engagement range
	Melee_SweetSpotMax = 8.5,                -- studs max melee sweet spot before stepping forward
	Melee_LungeSpeed = 32.0,                 -- studs/s physical lunge impulse
	Melee_SlideSpeed = 10.0,                 -- studs/s micro-slide spacing adjustment

	-- Continuous Locomotion Synthesis & Stride Scaling (Step 1 & 2)
	WalkStrideBase = 18.5,                   -- legacy tuning reference (banking speed ratio, AnimationLab); NOT the clip's stride speed
	RunStrideBase = 50.0,                    -- legacy tuning reference (banking speed ratio, AnimationLab); NOT the clip's stride speed

	-- Shared Gait Blend Space (GaitModule): Walk -> Jog -> Run. Authored speeds and plant phases
	-- are measured by sampling each clip on the Quin rig (planted-foot velocity at 1.0x, and the
	-- normalized time of the left-foot plant). Re-measure if a clip or the rig scale changes.
	Gait_WalkAuthoredSpeed = 6.90,           -- studs/s ground speed of Movement.WalkConfident at 1.0x
	Gait_JogAuthoredSpeed = 9.85,            -- studs/s ground speed of Movement.Jog at 1.0x (pose lab, stance-foot median; 8.4 cycled the legs 17% fast: feet ran backward through the jog band)
	Gait_RunAuthoredSpeed = 29.5,            -- studs/s ground speed of Movement.Run at 1.0x (stance-foot travel measured on the rig: 28.7-31.6)
	Gait_WalkPlantPhase = 0.550,             -- normalized time of the left foot's mid-stance in Walk (pose lab pass 22D; was 0.31, a touchdown-ish point)
	Gait_JogPlantPhase = 0.433,              -- likewise in Jog (was 0.34: the three clips were aligned on different stance points)
	Gait_RunPlantPhase = 0.479,              -- likewise in Run (was 0.46)
	Gait_WalkToJogStart = 7.5,               -- studs/s where Jog starts blending in over Walk
	Gait_WalkToJogEnd = 10.0,                -- studs/s where the blend is fully Jog
	Gait_JogToRunStart = 11.0,               -- studs/s where Run starts blending in over Jog (Jog tops out near 12.6)
	Gait_JogToRunEnd = 18.0,                 -- studs/s where the blend is fully Run (Run plays at ~0.67x there)
	Gait_MinPlayRate = 0.60,                 -- cadence floor for the dominant clip (avoids slow-motion legs)
	Gait_MaxPlayRate = 1.50,                 -- cadence ceiling for the dominant clip (above this the feet slide a little instead of flailing)
	Gait_IdleBlendSpeed = 3.0,               -- studs/s by which the gait fully covers the idle pose underneath

	-- Player pilot gait speeds (Z toggles walk, default jog, hold Shift to run)
	Player_WalkSpeed = 7.5,                  -- studs/s walking (Walk clip ~1.1x)
	Player_JogSpeed = 12.0,                  -- studs/s jogging (Jog clip ~1.43x)
	Player_RunSpeed = 40.0,                  -- studs/s running (Run clip ~1.36x)

	-- Run Slide (Movement.Slide). Times are in clip seconds at 1.0x, read from the clip's markers
	-- and pose profile: run stride -> StartSlide drop -> low glide -> SlideStop rise -> run strides.
	Slide_AnimRate = 1.15,                   -- playback rate of the slide clip
	Slide_DropTime = 0.10,                   -- clip time of the StartSlide marker (body leaves the run)
	Slide_StopTime = 1.07,                   -- clip time of the SlideStop marker (body rises out of the glide)
	Slide_ExitTime = 1.38,                   -- clip time at which the gait takes back over (clip is in run strides here)
	Slide_ExitGaitPhase = 0.35,              -- canonical gait phase that matches the clip pose at Slide_ExitTime
	Slide_ExitFade = 0.18,                   -- crossfade from the slide clip back into the gait
	Slide_MinEntrySpeed = 30.0,              -- studs/s the glide starts at even from a jog
	Slide_EntryBoost = 1.10,                 -- multiplier on current speed when the glide starts
	Slide_EndSpeedRatio = 0.55,              -- fraction of glide start speed left at SlideStop (friction)
	Slide_MinStartSpeed = 8.0,               -- studs/s minimum ground speed to start a slide
	TorsoBankingMaxRoll = 15.0,              -- degrees max lateral roll bank into turns
	TorsoBankingResponsiveness = 14.0,       -- lerp responsiveness for centripetal roll
	TurnMassDropMax = 0.20,                  -- max pelvis dip (studs) during sharp turns
	SkidMassDropAmount = 0.16,               -- max pelvis dip (studs) during 180° procedural turf plant
	Locomotion_SkidCooldown = 0.45,          -- seconds minimum between 180° turnaround skids
	Locomotion_SkidLockout = 0.35,           -- seconds duration of procedural skid plant before accelerating into sprint

	-- Procedural Foot IK & Ledge Gripping (Step 3)
	FootIK_Enabled = true,                   -- Calibrated stance-phase foot pinning with dynamic weight smoothing
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
	FootIK_ToeMaxFlexDegrees = 50,           -- most the toe bends up at the ball of the foot
	FootIK_Plant = true,                     -- hold a foot that is down where it touched the ground until the clip lifts it (no skating)
	FootIK_PlantContact = 0.15,              -- studs above its rest height at which a foot counts as down
	FootIK_PlantLift = 0.35,                 -- ... and as lifted again
	FootIK_PlantMaxDrift = 1.4,              -- studs the clip may pull a planted foot away before it lets go
	FootIK_MaxHipsDip = 0.6,                 -- studs the pelvis may sink so the lower foot reaches its ground
	FootIK_Step = true,                      -- a pinned foot the clip does not lift steps after the body (arc step); workspace FootPlant=false switches plant+step off
	FootIK_StepDuration = 0.28,              -- seconds a step takes at a walk (shorter when faster, 0.14 at least)
	FootIK_StepLead = 0.1,                   -- seconds of body travel a step lands ahead of the clip's foot
	FootIK_PlantDriftPerSpeed = 0.04,        -- extra drift allowance per stud/s of body speed (3 studs at a 40 stud/s sprint)
	FootIK_StepMaxSpeed = 12,                -- studs/s above which no procedural step is taken (the clip steps)
	FootIK_PlantWhenStill = true,            -- plant a foot only once the clip has stopped it (workspace PlantWhenStill overrides)
	FootIK_PlantStillMin = 3,                -- studs/s of clip foot travel over the ground below which it counts as stopped...
	FootIK_PlantStillPerSpeed = 0.35,        -- ...or this fraction of the body's speed, whichever is larger (a sprint's planted foot creeps)
	FootIK_OverreachSlack = 0.3,             -- studs a pinned foot may sit beyond the clip's own leg extension before it counts as out of reach
	FootIK_PivotPin = true,                  -- hold the planted foot fully through a plant-and-pivot reversal (no turn attenuation); workspace PivotPin overrides
	FootIK_PivotMaxDrift = 0.7,              -- studs a pinned foot may fall behind in a pivot before it steps (the turn swings the clip's feet round fast)
	FootIK_PivotStepDuration = 0.16,         -- seconds a pivot step takes (two steps fit a ~0.45 s 180)
	VisualGhostHeightOffset = 0.02,          -- vertical calibration offset (studs) ensuring visual shoe sole rests flush on terrain without bone deformation

	-- Active Muscle Ragdoll & Spectacle Knockback (Step 4)
	Ragdoll_MuscleStiffness = 8000,          -- AlignOrientation torque for active core tension
	Ragdoll_Damping = 120,                   -- damping factor for ragdoll joints
	Ragdoll_TumbleScale = 1.0,               -- multiplier for hit impact angular tumble velocity
	Ragdoll_AirDrag = 0.85,                  -- aerodynamic drag alignment factor during flight
	Ragdoll_GroundFriction = 0.55,           -- ground momentum slide retention on impact
	Ragdoll_RecoveryDelay = 0.40,            -- seconds before initiating get-up from prone/supine

	-- Procedural Full-Body Active Ragdoll & Knockback IK
	AirKnockback_ProceduralRagdollEnabled = true, -- velocity-driven body lean layered on the authored FallAirKnockback clip; false = clip only
	Ragdoll_BodyLeanDegrees = 50,                -- whole-body lean along the travel direction at full knockback speed
	Ragdoll_BodyLeanFullSpeed = 90,              -- studs/s of planar speed at which the lean is complete

	-- High Ground & Platform Traversal Intent
	HighGround_DiveDropEnabled = true,           -- allows perched Quins to leap down onto lower ground enemies
	HighGround_PerchDetectThreshold = 5.0,       -- vertical elevation difference to qualify as high ground platform
	HighGround_InterceptJumpMinReach = 8.0,      -- min vertical gap to trigger high-ground jump from below
	HighGround_InterceptJumpMaxReach = 35.0,     -- max vertical gap for standard high-ground jump
	HighGround_InterceptJumpEnergyCost = 20,     -- reduced mana cost for tactical high-ground climb hops

	-- 3D Debug Visualizers (LoS, LKP, Trajectories, Platform Intent)
	DebugVisualizers_Enabled = true,             -- enable 3D visualizer subsystem (toggled via HUD or 'V' key)
	DebugVisualizers_ShowAllNearby = false,      -- true to show all nearby Quins; false for spectated Quin only
}

-- Strafe clips: ground speed of the planted foot at 1.0x, measured on the rig. Circling strafes
-- at exactly these paces so the feet stay planted (it used 10 / 20 / 30 studs/s before).
CombatConfig.Strafe_TiredPace = 0.65 -- a tired Quin strafes at this fraction of the walk-strafe clip's pace
CombatConfig.Strafe_WalkAuthoredSpeed = 7.3 -- lateral stance-foot speed of the walk strafes at 1.0x (pose lab pass 22D: 7.30-7.32)
CombatConfig.Strafe_RunAuthoredSpeed = 18.9 -- likewise for the run strafes (18.88-18.90)
CombatConfig.Strafe_MinPlayRate = 0.6
CombatConfig.Strafe_MaxPlayRate = 1.35
CombatConfig.Circling_MaxFacingBias = 60 -- degrees the body may turn off its target to keep a strafe exactly sideways (35 limited strafes to a narrow band of directions)

-- Motion continuity (16v16 movement audit)
CombatConfig.Knockback_MaxLaunchHorizontal = 110.0 -- studs/s cap on an air-knockback launch (uncapped finishers reached 220+ and threw victims out of the arena)
CombatConfig.Knockback_MaxLaunchVertical = 75.0    -- studs/s cap on the upward part of an air-knockback launch (~14 stud apex)
-- RunTurn90Left/Right share one clip (a 177 degree hip pivot) and ArcRun30RearLeft/Right share one
-- clip (a single-sided lean). Played over a 60-105 degree cut they spin the body the wrong way and
-- snap back. Keep these off until mirrored, correctly sized clips exist; the gait carries the turn.
CombatConfig.Chase_TurnCutOverlayEnabled = false
CombatConfig.Chase_ArcRunOverlayEnabled = false
-- Awareness.Turn180Pivot uses the same 177 degree hip-pivot clip. It needs root-motion handling
-- (hold the root during the clip, rotate it 180 as the clip ends) before it can be used; until
-- then rear turns go through the facing gyro.
CombatConfig.Turn180PivotClipEnabled = false

-- === Melee hit outcomes (DamageModule.resolveOutcome, FightState) ===
-- A landed strike makes the victim flinch and slide back on its feet. Finishers knock it back
-- along the ground instead. Any of them can launch the victim into the air, by chance.
CombatConfig.Combat_FinisherLaunchChance = 0.40        -- chance a combo finisher sends the victim flying
CombatConfig.Combat_DevastatingBlowChance = 0.05       -- chance any other clean hit does (the one-punch launch)
CombatConfig.Combat_CritLaunchMultiplier = 2.0         -- launch chance multiplier on a critical hit
CombatConfig.Combat_BackAttackLaunchMultiplier = 1.5   -- ... on a hit from behind
CombatConfig.Combat_BrokenPostureLaunchBonus = 0.8     -- ... up to +80% as the victim's posture runs out
CombatConfig.Combat_LaunchMinForce = 60                -- launch force floor, so a jab that launches still throws
CombatConfig.Combat_FlinchSlideStuds = 2.5             -- studs a flinching victim slides back
CombatConfig.Combat_FlinchSlidePerComboStep = 0.4      -- extra studs per combo step
CombatConfig.Combat_HeavyFlinchSlideBonus = 1.5        -- extra studs on a heavy hit
CombatConfig.Combat_BlockSlideStuds = 1.5              -- studs a defender slides when its guard holds
CombatConfig.Combat_CounterSlideStuds = 4.5            -- studs the victim of a counter-punch slides
CombatConfig.Combat_GroundKnockbackMinStuds = 10       -- ground knockback skid distance range
CombatConfig.Combat_GroundKnockbackMaxStuds = 18
CombatConfig.Combat_GroundKnockbackTime = 0.6          -- seconds the skid takes
CombatConfig.Combat_StrikeRange = 9.0              -- a strike is only thrown at a target within this (the step-in covers the rest)
CombatConfig.Combat_TradeWindow = 0.08               -- a strike this close to landing still comes out when its thrower is hit (a trade)
CombatConfig.Combat_LungeMaxSpeed = 60             -- studs/s ceiling of the step-in; its real speed is whatever closes the gap
CombatConfig.Combat_LungeStopDistance = 4.8            -- an attack lunge stops this far from the target (outside Melee_SweetSpotMin; a jab reaches 6.5)
CombatConfig.Combat_GuardStrength = 0.70               -- chance a raised guard holds against a frontal strike
CombatConfig.Combat_DesperateCounterCooldown = 6.0     -- seconds between a Quin's cornered counter-strikes
CombatConfig.Combat_ComboBreakChance = 0.25            -- chance per incoming combo strike to get a guard up (scaled 0.5-1.5x by defense preference)

-- === Projectile jump from a chase (ChaseState) ===
CombatConfig.ProjectileJump_ChaseFirstCheck = 2.0      -- seconds into a chase before the first check (+-30%)
CombatConfig.ProjectileJump_ChaseCheckInterval = 4.0   -- seconds between checks while the target stays far (+-30%)
CombatConfig.ProjectileJump_ChanceAggression = 0.30    -- chance per check contributed by aggression (0-1)
CombatConfig.ProjectileJump_ChanceMobility = 0.20      -- ... by mobility preference (0-1)
CombatConfig.ProjectileJump_Cooldown = 14.0            -- seconds between a Quin's projectile jumps (x0.75 when aggressive)
CombatConfig.Combat_MeetJumpChance = 0.5                -- times aggression: chance a Quin answers an incoming projectile jump with its own
CombatConfig.MidAirClash_TriggerDistance = 40          -- studs between two jumpers at which they clash in the air
CombatConfig.MidAirClash_MinHeight = 12                -- ... and this high above the floor at least
CombatConfig.Jump_MaxReach = 12.0                       -- studs of height a jump can gain; anything higher needs a projectile jump

-- === Projectile jump flight ===
CombatConfig.ProjectileJump_SlamSpeed = 480            -- studs/s of the dive onto the target (styles 3, 6 and 7 dive 15% faster)

-- === Escape and pursuit at arena scale (RetreatTacticsModule, RetreatState, ChaseState) ===
CombatConfig.Retreat_EscapeDistanceRatio = 0.5         -- open-ground escape run, as a fraction of the arena radius (60-220 studs)
CombatConfig.Retreat_SearchRangeRatio = 0.4            -- range searched for cover and platforms, same basis (40-160 studs)
CombatConfig.Retreat_SafeDistanceRatio = 0.4           -- got away once this far from the nearest threat, same basis
CombatConfig.Retreat_OpenGroundProbe = 60              -- studs probed in each direction when choosing the open-ground heading
CombatConfig.Retreat_AllyMinDistance = 40              -- allies nearer than this are in the same fight, not an escape
CombatConfig.Retreat_PlanHold = 4.0                    -- seconds an escape plan is kept before it is reconsidered
CombatConfig.Retreat_ArriveDistance = 10               -- studs from the destination at which the plan is fulfilled
CombatConfig.Retreat_LostSightTime = 2.5               -- seconds out of the pursuer's sight to count as having lost it
CombatConfig.Retreat_LostSightMinDistance = 40         -- ... and at least this far from it
CombatConfig.Retreat_FleeAgainDistance = 40            -- a Quin keeping away runs again when its target comes this close
CombatConfig.Chase_TrailGiveUpConfidence = 0.6         -- memory confidence below which an unseen target is given up (minus 0.5 x persistence)
CombatConfig.Chase_SearchLegDistance = 45              -- studs searched onward along the target's last heading, per leg
CombatConfig.Chase_DistractionCommitment = 0.6         -- a hunter above this commitment ignores passers-by that are not after it
CombatConfig.Targeting_HuntedScore = 60                -- target utility of the enemy hunting this Quin (times awareness)

-- === Circling ===
CombatConfig.Circling_TiredEnergyRatio = 0.35          -- below this energy the Quin drags its strafe
CombatConfig.Circling_ProwlThreshold = 0.6             -- aggression or mobility at which it prowls at the run strafe
CombatConfig.Circling_DurationScale = 0.7              -- scale on the standoff length
CombatConfig.Circling_OpeningMinTime = 0.5             -- seconds in the standoff before an opening can be taken
CombatConfig.Chase_StalkWalkMaxTime = 2.5            -- seconds a ConfidentWalk / WalkThenSprint chase walks before it commits to a run
CombatConfig.Circling_OpeningChancePerTick = 0.35      -- per tick, times aggression, to take a turned back

-- === Force lean and per-Quin style (ProceduralCombatReactionController, client) ===
CombatConfig.Locomotion_ForceLeanEnabled = true        -- upper body leans into the acceleration it is under
CombatConfig.Locomotion_ForceLeanFullAcceleration = 60 -- studs/s^2 at which the lean is full
CombatConfig.Locomotion_ForceLeanPitchDegrees = 14     -- forward / back lean at full acceleration
CombatConfig.Locomotion_ForceLeanRollDegrees = 12      -- sideways lean at full acceleration
CombatConfig.ProceduralStyle_Enabled = false           -- experiment: each Quin leans / twists / carries weight a little differently (HUD switch overrides)

-- === Whole-body tilt (ProceduralCombatReactionController): lean from the feet into acceleration ===
-- === Directional gait (GaitModule): strafe and backpedal when moving off the facing ===
CombatConfig.Gait_Directional = true
CombatConfig.Gait_StrafeAngle = 50       -- degrees off the facing from which the strafe clips play
CombatConfig.Gait_BackpedalAngle = 130   -- degrees from which the forward cycle plays in reverse
CombatConfig.Gait_StrafeRunSpeed = 10    -- studs/s above which the run strafe is used
-- Diagonal blend (pass 22D): forward and strafe clips mixed continuously by the motion's angle
-- off the facing, on one phase, instead of the hard 50/130 degree switches above
CombatConfig.Gait_DiagonalBlend = true
CombatConfig.Gait_DiagonalBlendStart = 20  -- degrees off the facing (or off straight back) where the strafe set starts to blend in
CombatConfig.Gait_DiagonalBlendFull = 40   -- degrees where the blend is fully by stride (below Start: the forward cycle alone)
CombatConfig.Gait_DiagonalSideHysteresis = 0.75 -- studs/s of opposite lateral motion before the strafe side flips
CombatConfig.Gait_StrafeWalkToRunStart = 8      -- studs/s where the run strafe starts blending in over the walk strafe
CombatConfig.Gait_StrafeWalkToRunEnd = 13       -- studs/s where the strafe blend is fully run
-- Left-foot mid-stance phases of the strafe clips (pose lab: centre of the left toe's stance window)
CombatConfig.Gait_StrafeLeftWalkPlantPhase = 0.562
CombatConfig.Gait_StrafeLeftRunPlantPhase = 0.521
CombatConfig.Gait_StrafeRightWalkPlantPhase = 0.529
CombatConfig.Gait_StrafeRightRunPlantPhase = 0.575

CombatConfig.BodyTilt_Enabled = true            -- workspace attribute BodyTilt overrides (A/B)
CombatConfig.BodyTilt_Scale = 0.6               -- share of the physical lean angle atan(a / g)
CombatConfig.BodyTilt_MaxDegrees = 16           -- cap
CombatConfig.BodyTilt_RunLeanDegrees = 7        -- forward lean at full run speed
CombatConfig.BodyTilt_RunLeanFullSpeed = 40     -- studs/s at which the run lean is full
CombatConfig.BodyTilt_Response = 7              -- 1/s smoothing

-- === Secondary motion (ProceduralCombatReactionController): the arms carry a little weight ===
CombatConfig.SecondaryMotion_Enabled = true          -- workspace attribute SecondaryMotion overrides (A/B)
CombatConfig.SecondaryMotion_Frequency = 6           -- Hz of the spring each arm tip follows the clip with
CombatConfig.SecondaryMotion_Damping = 0.75          -- below 1: a slight overshoot as it settles (0.55 whipped at every run-cycle swing)
CombatConfig.SecondaryMotion_MaxUpperArmDegrees = 14 -- most an upper arm trails its clip pose
CombatConfig.SecondaryMotion_MaxForearmDegrees = 20  -- ... a forearm
CombatConfig.SecondaryMotion_FastClipSpeed = 12      -- studs/s of clip arm motion relative to the body above which it fades out (strikes)
-- === Clip corrections (applied on the client before the procedural layers) ===
-- yaw: degrees the body is turned about the root's vertical axis while the clip plays (clips
-- authored facing backwards); translationScale: hip translation multiplier (clips exported with
-- their root motion 10x too large). Measured in a pose lab: hips facing vs the idle pose.
CombatConfig.ClipCorrections = {
	["90572410559809"] = { yaw = 180, translationScale = 0.1 },  -- NINJA PROJECTILE JUMP
	["107304638987317"] = { yaw = 180, translationScale = 0.1 }, -- NINJA AIRBORNE LOOP
	["92021932752253"] = { yaw = 180, translationScale = 0.1 },  -- NINJA CONFIDENT LANDING
	["121127010274438"] = { yaw = 180 },                         -- PROJECTILE JUMP
	["122361647744311"] = { yaw = 180 },                         -- PROJECTILE JUMP AIRBORNE LOOP
	["105219213466134"] = { yaw = 180 },                         -- PJ JUMP STYLE LANDING
}

CombatConfig.SecondaryMotion_Spine = true            -- the spine follows too
CombatConfig.SecondaryMotion_Neck = false            -- neck and head springs: off (they doubled head jitter in Chase; the head turns on LookController's own spring). Workspace SecondaryMotionTorso = none|spine|all for A/B
CombatConfig.SecondaryMotion_MaxSpineDegrees = 5     -- per spine segment
CombatConfig.SecondaryMotion_MaxNeckDegrees = 7      -- neck and head

-- === Ground VFX (VfxModule) ===
CombatConfig.Vfx_LandingDust = true                    -- smoke burst where a body lands (jumps, knockdowns, projectile-jump impacts)
CombatConfig.Vfx_SlideSmoke = true                     -- smoke trailing a slide
CombatConfig.Vfx_GroundMarks = true                    -- fading scuffs on the turf: slide streaks, skid marks, sprint footprints (max 60 at once)

-- === Projectile jump landing ===
-- The horizontal part of the arrival speed carries the body along the ground: a steep dive
-- stops where it lands, a shallow one skids. The body lays back against the skid and rights
-- itself as it runs out.
CombatConfig.ProjectileJump_LandingSlideFactor = 0.03   -- studs of slide per stud/s of horizontal arrival speed
CombatConfig.ProjectileJump_LandingSlideMax = 14        -- studs, longest slide
CombatConfig.ProjectileJump_LandingSlidePreciseMax = 2  -- ... when landing on a chosen spot (a platform)
CombatConfig.ProjectileJump_LandingSlideDuration = 0.5  -- seconds from touchdown to full stop
CombatConfig.ProjectileJump_LandingLeanDegrees = 22     -- whole-body tilt at full slide speed
CombatConfig.ProjectileJump_LandingLeanFullSpeed = 40   -- studs/s of slide at which the tilt is full

-- === Mid-air clash outcomes ===
CombatConfig.MidAirClash_ImmediateSmashChance = 0.3     -- chance there is no brawl: the faster one smashes the other down at once
CombatConfig.MidAirClash_SmashSpeed = 260               -- studs/s the loser is thrown down at

-- === Sky intercept (Modules/AirInterceptModule) ===
CombatConfig.Intercept_MinHeight = 40          -- studs an airborne enemy must be above the Quin
CombatConfig.Intercept_MaxRange = 200          -- studs
CombatConfig.Intercept_ChanceBase = 0.03       -- chance to go up after a jumper it has seen
CombatConfig.Intercept_ChanceAggression = 0.15 -- ... plus this times aggression
CombatConfig.Intercept_RollInterval = 3.0      -- seconds before the same Quin is considered again
CombatConfig.Intercept_ContactDistance = 15     -- studs at which an interceptor has reached its jumper (clash starts)
CombatConfig.Intercept_ClaimTime = 3.0           -- seconds a jumper is left to the Quin that went up after it
CombatConfig.Intercept_MaxTargetFallSpeed = 100   -- studs/s: a jumper falling faster than this (diving) is not gone up after
CombatConfig.MidAirClash_HelplessSmashChance = 0.75 -- an intercepted Quin that is not jumping itself is smashed down at once
CombatConfig.MidAirClash_Cooldown = 3.0              -- seconds after a clash before either Quin can clash again

-- === Overwatch (States/OverwatchState): holding a high platform ===
CombatConfig.Overwatch_Enabled = true
CombatConfig.Overwatch_MinHeight = 12          -- studs above the arena floor for a platform to be worth holding
CombatConfig.Overwatch_WatchMin = 4            -- seconds on watch before diving back in (aggressive Quins)
CombatConfig.Overwatch_WatchMax = 12           -- ... (patient Quins)
CombatConfig.Overwatch_MaxWatch = 25           -- seconds after which it comes down whatever happens
CombatConfig.Overwatch_WalkSpeed = 10          -- studs/s along the edge
CombatConfig.Overwatch_JogSpeed = 14           -- studs/s on a jog loop round the top
CombatConfig.Overwatch_LoopMinRadius = 4       -- studs: a platform needs this much room inside the inset for a jog loop
CombatConfig.ProjectileJump_SmackDownChance = 0.5  -- share of arc jumps (style 1) flown with the one smack-down clip instead of a kit
CombatConfig.SkidOver_MaxRise = 5                 -- studs: tallest obstacle skidded over (hand on top)
CombatConfig.SkidOver_MinRise = 3                 -- studs: lower obstacles get a short hop instead (the skid reads wrong on a 1-2 stud lip)
CombatConfig.Locomotion_StepHeight = 1.5          -- studs: lips lower than this are walked over
CombatConfig.SkidOver_MaxLength = 16              -- studs: longest low obstacle cleared in one skid-over (the flight and clip stretch with it)
CombatConfig.SkidOver_MaxFlightRise = 9           -- studs: a skid-over that would need a higher arc than this (slow, long) is vaulted instead
CombatConfig.Hurdle_MaxRise = 11                 -- studs: thin obstacles (up to 7 deep) up to this high are hurdled with a timed, solved arc
CombatConfig.Nav_StoneMinClimb = 8               -- studs a target must stand above before stepping stones are used (NavigationModule.nextStone)
CombatConfig.Nav_StoneMaxHop = 60                -- studs: longest single hop onto a stepping stone
CombatConfig.Nav_StoneMaxRise = 40               -- studs: highest single hop (a spot jump)
CombatConfig.Locomotion_FacingFollowsMotion = true -- the body faces its actual motion while steering (false: AutoRotate faces the steer heading)
CombatConfig.Locomotion_FacingIntoTurn = 0.3     -- share of the way from the motion toward the steer heading (a runner looks into its turn)
CombatConfig.Locomotion_FacingResponsiveness = 35 -- AlignOrientation responsiveness of the steering facing
CombatConfig.Locomotion_FacingMotionMinSpeed = 6 -- studs/s: below this it faces the steer heading (turning on the spot, starting off)
CombatConfig.Locomotion_FacingLeadTime = 0.11     -- seconds of the motion's turn the facing target leads by (the facing constraint's own lag)
-- Camera shake master volume (every VfxModule.shakeScreen call; each keeps its own intensity).
-- 0.3 = 70% less than authored. Live override: Workspace attribute CameraShakeMultiplier.
CombatConfig.CameraShake_Multiplier = 0.3

-- Camera motion blur (StarterPlayerScripts.CameraMotionBlur): a BlurEffect that follows how
-- fast the view turns / travels. Live: Workspace attributes MotionBlur (false = off), MotionBlurScale.
CombatConfig.MotionBlur_Enabled = true
CombatConfig.MotionBlur_MaxSize = 8       -- BlurEffect size at full motion (0-56)
CombatConfig.MotionBlur_TurnStart = 90    -- deg/s of view turn where the blur begins
CombatConfig.MotionBlur_TurnFull = 540    -- deg/s for full blur
CombatConfig.MotionBlur_SpeedStart = 60   -- studs/s of camera travel where the blur begins
CombatConfig.MotionBlur_SpeedFull = 200   -- studs/s for full blur
CombatConfig.MotionBlur_Attack = 20       -- 1/s rise
CombatConfig.MotionBlur_Release = 8       -- 1/s fall

-- Projectile jump guards: a dive stops at a wall in its line, a driven phase that stops moving
-- comes down, and no jump lasts longer than the cap
CombatConfig.ProjectileJump_DashWallProbeTime = 0.15 -- seconds of dive travel probed ahead for a wall
CombatConfig.ProjectileJump_StallTime = 0.4         -- seconds without progress...
CombatConfig.ProjectileJump_StallDistance = 1.5     -- ...of less than this many studs ends the phase
CombatConfig.ProjectileJump_MaxStateTime = 8        -- seconds: hard cap on a whole jump
CombatConfig.ProjectileJump_SetDownLatch = true -- once the touchdown guard starts setting a dive down, no update re-aims it (pass 22E: the dive bob)
CombatConfig.ProjectileJump_SetDownSnap = true -- a dive whose floor is within the next frame's travel is placed on it at standing height (pass 22E: velocity set-downs overshot into the floor)
-- Foot slide (pass 22C). The start-run push-off clip (Movement.IdleToRun / StartSprint) played over
-- an accelerating body slid on ~65% of its frames at any speed - the gait starts from rest on its
-- own (true brings the overlay back). Fight plants the body while its own strike plays.
CombatConfig.Chase_PushOffOverlay = false
CombatConfig.Fight_PlantWhileStriking = true
-- Overwatch holds only tops at least this wide both ways (pillar and wall tops are not lookouts)
CombatConfig.Overwatch_MinTopWidth = 10

-- Circling strafe facing: the orbit's turn is led so the motion stays straight sideways
CombatConfig.Circling_FacingLeadTime = 0.25       -- seconds (10 Hz tick + gyro lag)
CombatConfig.Circling_GyroResponsiveness = 35

-- Reversals (> 115 degrees at a run): brake along the line, pivot near a standstill, drive out
CombatConfig.Combat_FacingMaxTurnRate = 14          -- rad/s cap on the Fight and Circling facing gyros (the locomotion facing uses the same)
CombatConfig.Locomotion_ReversalPivot = true       -- false: the old running U-turn (speed dropped to 40%, then turned at grip)
CombatConfig.Locomotion_ReversalBrake = 150        -- studs/s^2 deceleration of the brake phase
CombatConfig.Locomotion_ReversalPivotSpeed = 6     -- studs/s held while the body turns round
CombatConfig.Locomotion_ReversalTurnRate = 7       -- rad/s heading turn of the pivot (0.45 s for a half turn)
CombatConfig.Locomotion_ReversalAlignedCos = 0.9   -- the pivot ends once heading (and body, 0.1 looser) face the goal this closely
CombatConfig.SecondaryMotion_TorsoFrequency = 3.5 -- Hz: spine/neck spring (heavier and slower than the arms' SecondaryMotion_Frequency)
CombatConfig.SecondaryMotion_TorsoDamping = 1.0   -- spine/neck spring damping ratio (1 = settles without overshoot)
CombatConfig.SecondaryMotion_Inertia = 1.0        -- scale on the body acceleration the springs feel (they run in the body's frame)
CombatConfig.SecondaryMotion_MaxAcceleration = 80 -- studs/s^2: body acceleration the springs feel is capped (jump launches, knockbacks)
CombatConfig.SecondaryMotion_Leash = 1.5          -- studs a spring may lag its bone tip; held there beyond (no reset flicker)
CombatConfig.SecondaryMotion_AccelerationResponse = 6 -- 1/s: low-pass on the body acceleration the springs feel (replicated velocity arrives in steps)
CombatConfig.Overwatch_EdgeInset = 3           -- studs kept from the edge
CombatConfig.Overwatch_EngageRange = 30        -- an enemy this close at the same height is fought up there
CombatConfig.Retreat_RendezvousValue = 15      -- extra worth of a platform per ally already on it (up to 3)

-- === Cognition (QuinCore.Cognition) ===
-- Senses / Attention / Memory are the layers that can be switched off for comparison; the
-- value here is the default, the Spectator HUD changes it live (workspace Cognition_<Name>).
CombatConfig.Cognition = {
	Senses = true,                 -- vision cone + hearing + touch (off: every living enemy is noticed)
	Attention = true,              -- limited focus (off: everything noticed is attended)
	Memory = true,                 -- remember / forget / share (off: knows only what it attends this tick)

	VisionRange = 260,             -- studs a Quin can see with a clear line of sight
	VisionHalfAngle = 100,         -- degrees each side of its facing (200 degree field of view)
	HearingRangeMin = 12,          -- studs it hears a noisy Quin at awareness 0
	HearingRangeMax = 40,          -- ... at awareness 1
	NoiseSpeed = 12,               -- studs/s above which a moving Quin can be heard
	ProximityRange = 10,           -- studs within which a Quin is always felt
	VisionVerticalHalfAngle = 35,  -- degrees above and below where the head points (Cognition.Gaze)
	GazeMaxPitch = 75,             -- degrees the head can follow a target up or down
	GazeSkyPitch = 45,             -- degrees up for a glance at the sky
	GazeDownPitch = -35,           -- degrees down when looking over the edge of high ground
	GazeHighGround = 12,           -- studs above the arena floor from which a Quin looks down
	GazeGlanceIntervalMin = 2.5,   -- seconds between glances at awareness 1
	GazeGlanceIntervalMax = 7.0,   -- ... at awareness 0
	GazeGlanceDuration = 0.8,      -- seconds a glance lasts

	AttentionCapacityMin = 2,      -- enemies kept track of at awareness 0
	AttentionCapacityMax = 6,      -- ... at awareness 1
	AttentionEngagedPenalty = 2,   -- capacity lost while fighting, times aggression (tunnel vision)

	MemoryRetentionMin = 4,        -- seconds for a track's confidence to fall to 37% at awareness 0
	MemoryRetentionMax = 14,       -- ... at awareness 1
	MemoryForgetConfidence = 0.15, -- a track below this is forgotten
	MemoryPredictionHorizon = 1.5, -- seconds a lost enemy is assumed to keep moving as last seen
	ReportRange = 60,              -- studs within which allies pass on what they see
	ReportInterval = 0.5,          -- seconds between taking over allies' sightings
	ReportConfidence = 0.7,        -- confidence of a second-hand sighting
	RumourFallback = true,         -- with no contact at all, the team's rough idea of the nearest enemy
	RumourConfidence = 0.3,
}

return CombatConfig