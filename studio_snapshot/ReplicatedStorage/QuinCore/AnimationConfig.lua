--// AnimationConfig.lua
-- Centralized Single Source of Truth for Animation IDs and Tuning Knobs
-- Production Hot-Swapping and Persistence Enabled

local AnimationConfig = {}

AnimationConfig.Registry = {
	Attacks = {
		Kicks = {
			HighKick = { id = "rbxassetid://84162023451491", speed = 1.20, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.80, name = "High Kick" },
			LowKick = { id = "rbxassetid://71573540671127", speed = 1.35, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.45, cancelRatio = 0.80, name = "Low Kick" },
			PowerKick = { id = "rbxassetid://87872094663324", speed = 1.35, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.45, cancelRatio = 0.80, name = "Power Kick" },
			WheelDrive = { id = "rbxassetid://89487629068473", speed = 1.40, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.85, name = "Wheeldrive" },
		},
		Punches = {
			CrossLeft = { id = "rbxassetid://79937990476934", speed = 1.30, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.35, cancelRatio = 0.70, name = "Cross Left" },
			CrossRight = { id = "rbxassetid://99362983788110", speed = 1.30, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.35, cancelRatio = 0.70, name = "Cross Right" },
			-- (Hook Punch 135206101877204 removed: a re-upload of 118776942028972, which the owner dropped)
			Punch1 = { id = "rbxassetid://113219639247452", speed = 1.30, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.35, cancelRatio = 0.70, name = "Lead Jab" },
			Uppercut = { borrows = "Attacks.Punches.Punch1", speed = 1.20, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.30, cancelRatio = 0.60, name = "Uppercut" },
		},
		Special = {
			Slam = { borrows = "Attacks.Kicks.WheelDrive", speed = 1.10, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.75, name = "Slam" },
			Special1 = { borrows = "Attacks.Kicks.PowerKick", speed = 1.00, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.45, cancelRatio = 0.80, name = "Special1" },
		},
		Specials = {
			Slam = { borrows = "Attacks.Punches.Punch1", speed = 1.10, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.80, name = "Ground Slam" },
			SlamImpact = { borrows = "Attacks.Punches.Punch1", speed = 1.20, fadeTime = 0.04, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.80, name = "Ground Slam Impact" },
			SlamRecovery = { borrows = "Reactions.GetUpBackFast", speed = 1.50, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.90, name = "Ground Slam Recovery Rise" },
			Special1 = { borrows = "Attacks.Punches.Punch1", speed = 1.00, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.35, cancelRatio = 0.70, name = "Special Move 1" },
			Uppercut = { borrows = "Attacks.Punches.Punch1", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.75, name = "Uppercut" },
			RivalFinisher = { borrows = "Attacks.Kicks.PowerKick", speed = 1.15, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.85, name = "Rival Decisive Finisher" },
			BeamStruggle = { trackKey = "Beam", borrows = "Idles.FightIdle", speed = 1.00, fadeTime = 0.10, priority = "Action4", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Beam Struggle Channel" },
			ProceduralSmackDown = { id = "rbxassetid://71743026406362", speed = 1.25, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.45, cancelRatio = 0.80, name = "AOE Arc Jump Smack Down" },
		},
	},
	Idles = {
		DefaultIdle = { id = "rbxassetid://81038616654818", speed = 1.00, fadeTime = 0.20, priority = "Idle", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "IDLE_DEFAULT" },
		ReadyStance = { id = "rbxassetid://123350689285769", speed = 1.00, fadeTime = 0.20, priority = "Idle", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "IDLEREADY_STANCE" },
		FightIdle = { id = "rbxassetid://109837817595150", speed = 1.00, fadeTime = 0.20, priority = "Idle", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "IDLEFIGHT_STANCE" },
		CombatIdle = { borrows = "Idles.FightIdle", speed = 1.00, fadeTime = 0.20, priority = "Idle", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "IDLEFIGHT_STANCE" },
		SurveyIdle = { trackKey = "Survey", borrows = "Idles.FightIdle", speed = 1.20, fadeTime = 0.15, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Target Assessment Survey" },
	},
	Movement = {
		ArcRun30Rear = { id = "rbxassetid://89227245782124", speed = 1.20, fadeTime = 0.10, priority = "Movement", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "30-Degree Arc Run Rear" },
		ArcRun30RearLeft = { borrows = "Movement.ArcRun30Rear", speed = 1.20, fadeTime = 0.10, priority = "Movement", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "30-Degree Arc Run Left" },
		ArcRun30RearRight = { borrows = "Movement.ArcRun30Rear", speed = 1.20, fadeTime = 0.10, priority = "Movement", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "30-Degree Arc Run Right" },
		BrakingStop = { id = "rbxassetid://83869147275692", speed = 1.65, fadeTime = 0.08, priority = "Movement", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Kinetic Braking Skid" },
		Dash = { id = "rbxassetid://133182359318358", speed = 1.00, fadeTime = 0.05, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Dash Burst" },
		Fall = { id = "rbxassetid://79340771026707", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Airborne Descent" },
		FallAirKnockback = { id = "rbxassetid://88475997278069", speed = 1.00, fadeTime = 0.10, priority = "Action3", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Air Knockback Flailing" },
		FallBack = { id = "rbxassetid://88441309301154", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Fall, Back To The Ground" },
		FallFront = { id = "rbxassetid://80583167665730", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Fall, Face To The Ground" },
		Idle = { borrows = "Idles.DefaultIdle", speed = 1.00, fadeTime = 0.20, priority = "Idle", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "IDLE_DEFAULT" },
		StartRun = { id = "rbxassetid://113571639405597", speed = 1.15, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "START RUN" },
		IdleToRun1 = { borrows = "Movement.StartRun", speed = 1.15, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "START RUN" },
		IdleToRun2 = { borrows = "Movement.StartRun", speed = 1.15, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "START RUN" },
		Jump = { id = "rbxassetid://85622241844167", speed = 1.00, fadeTime = 0.05, priority = "Movement", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Jump Launch" },
		Jog = { id = "rbxassetid://91301995989516", speed = 1.00, fadeTime = 0.15, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Jog Loop" },
		Run = { id = "rbxassetid://109090784752055", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Sprint / Chase Run" },
		RunTurn90Left = { borrows = "Movement.RunTurn180", speed = 1.65, fadeTime = 0.04, startCut = 0.00, endCut = 0.38, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "90-Degree Plant Cut Left" },
		RunTurn90Right = { borrows = "Movement.RunTurn180", speed = 1.65, fadeTime = 0.04, startCut = 0.00, endCut = 0.38, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "90-Degree Plant Cut Right" },
		RunTurn180 = { id = "rbxassetid://129355316172688", speed = 1.35, fadeTime = 0.05, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "180 Run Turn Pivot" },
		RunTurn180Left = { borrows = "Movement.RunTurn180", speed = 1.35, fadeTime = 0.05, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "180 Run Turn Left" },
		RunTurn180Right = { borrows = "Movement.RunTurn180", speed = 1.35, fadeTime = 0.05, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "180 Run Turn Right" },
		StartSprint = { borrows = "Movement.StartRun", speed = 1.15, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "START RUN" },
		Slide = { id = "rbxassetid://115642161658755", speed = 1.15, fadeTime = 0.12, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Run Slide (run -> slide -> run)" },
		StopRun = { id = "rbxassetid://89237107000987", speed = 1.15, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "STOP RUN" },
		WalkConfident = { id = "rbxassetid://117985748552966", speed = 1.00, fadeTime = 0.15, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Confident Walk" },
		WalkThug = { borrows = "Movement.WalkConfident", speed = 0.90, fadeTime = 0.15, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Aggressive Walk" },
	},
	Transition = {
		AssessTarget = { trackKey = "Assess", borrows = "Idles.FightIdle", speed = 1.20, fadeTime = 0.15, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Target Assessment Survey" },
	},
	Awareness = {
		LookingBehind = { id = "rbxassetid://98616724907377", speed = 1.20, fadeTime = 0.10, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Looking Behind Glance" },
		RearThreatGlance = { borrows = "Awareness.LookingBehind", speed = 1.40, fadeTime = 0.08, priority = "Action2", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Rear Threat Glance" },
		Turn180Pivot = { borrows = "Movement.RunTurn180", speed = 1.50, fadeTime = 0.05, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "180 Degree Turn Pivot" },
	},
	Tactics = {
		DesperateCounter = { borrows = "Attacks.Punches.CrossRight", speed = 1.35, fadeTime = 0.06, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.75, name = "Cornered Desperate Counter" },
		ProceduralEvade1 = { id = "rbxassetid://131563762426355", speed = 1.30, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Procedural Evade 01" },
		ProceduralEvade2 = { id = "rbxassetid://135253684509200", speed = 1.30, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Procedural Evade Enemy 02" },
		RetreatBackstep = { borrows = "Strafe.StrafeLeftWalk", speed = 1.30, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Tactical Backstep Hop" },
	},
	Parkour = {
		LandingHard = { id = "rbxassetid://110436967972328", speed = 1.20, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.35, cancelRatio = 0.85, name = "Landing Style Hard" },
		LandingSoft = { id = "rbxassetid://136234480688142", speed = 1.20, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.30, cancelRatio = 0.85, name = "Landing Style Soft" },
		LandingSuperHero = { id = "rbxassetid://94804914683754", speed = 1.15, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.40, cancelRatio = 0.90, name = "SUPERHERO LANDING" },
		LedgeDropLanding = { borrows = "Parkour.LandingSoft", speed = 1.40, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.35, cancelRatio = 0.85, name = "Platform Ledge Drop Landing" },
		ProceduralJump1 = { id = "rbxassetid://90546747503310", speed = 1.25, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Procedural Jump / Evade 01" },
		ProceduralSlide1 = { id = "rbxassetid://73976796270777", speed = 1.30, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Procedural Slide 01" },
		ProceduralSlide2 = { id = "rbxassetid://101210294612380", speed = 1.30, fadeTime = 0.08, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Procedural Slide 02" },
		SkidOverOB = { id = "rbxassetid://82934009896094", speed = 1.30, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Skid Over Obstacle 5x3" },
		VaultObstacle = { borrows = "Movement.Jump", speed = 1.25, fadeTime = 0.06, priority = "Action", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Obstacle Hurdle Vault" },
	},
	Reactions = {
		Block = { id = "rbxassetid://81580688159305", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.05, cancelRatio = 0.50, name = "Block Front" },
		BlockFront = { borrows = "Reactions.Block", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.05, cancelRatio = 0.50, name = "Block Front" },
		BlockLeft = { id = "rbxassetid://71555510097974", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.05, cancelRatio = 0.50, name = "Block Left" },
		BlockRight = { id = "rbxassetid://81446994688965", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.05, cancelRatio = 0.50, name = "Block Right" },
		Death = { id = "rbxassetid://80496269227852", speed = 1.10, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.30, cancelRatio = 1.00, name = "Standard Defeat Collapse" },
		DeathCollapse = { borrows = "Reactions.Death", speed = 1.10, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.30, cancelRatio = 1.00, name = "Defeat Collapse" },
		DeathOnTheSpot = { id = "rbxassetid://122802842451487", speed = 1.15, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 1.00, name = "Decisive Finisher Knockout" },
		FallAirKnockback = { borrows = "Movement.FallAirKnockback", speed = 1.00, fadeTime = 0.10, priority = "Action4", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Fall Air Knockback" },
		GetUpBackFastNinja = { id = "rbxassetid://95406088712190", speed = 1.45, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.90, name = "Instant Recovery From The Back (Ninja Kip-Up)" },
		GetUpBackSlow = { id = "rbxassetid://119670118817591", speed = 1.10, fadeTime = 0.10, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.90, name = "Get Up From The Back (Slow)" },
		GetUpFromCrouch = { id = "rbxassetid://108624065264351", speed = 1.30, fadeTime = 0.08, priority = "Action4", looped = false, impactRatio = 0.40, cancelRatio = 0.90, name = "Get Up From Crouch" },
		GetUpBackFast = { id = "rbxassetid://79207866638803", speed = 1.50, fadeTime = 0.10, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.90, name = "Get Up From The Back (Fast)" },
		GetUpFrontFast = { id = "rbxassetid://82896239168564", speed = 1.50, fadeTime = 0.10, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.90, name = "Get Up From The Front (Fast)" },
		GetUpFrontSlow = { id = "rbxassetid://90997656474712", speed = 1.10, fadeTime = 0.10, priority = "Action4", looped = false, impactRatio = 0.50, cancelRatio = 0.90, name = "Get Up From The Front (Slow)" },
		HitHeavy = { id = "rbxassetid://82096408080514", speed = 1.40, fadeTime = 0.14, priority = "Action4", looped = false, impactRatio = 0.15, cancelRatio = 0.60, name = "Heavy Hit Recoil" },
		HitLight = { borrows = "Movement.BrakingStop", speed = 1.65, fadeTime = 0.01, priority = "Action4", looped = false, impactRatio = 0.10, cancelRatio = 0.40, name = "Light Hit Flinch" },
		Knockback = { borrows = "Movement.BrakingStop", speed = 1.00, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "Knockback" },
		KnockbackAir = { borrows = "Movement.FallAirKnockback", speed = 0.90, fadeTime = 0.02, priority = "Action4", looped = false, impactRatio = 0.20, cancelRatio = 0.80, name = "Airborne Tumble" },
		KnockdownBehind = { id = "rbxassetid://131344167080457", speed = 1.20, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.20, cancelRatio = 0.80, name = "Knockdown from Behind 01" },
		SlammedDown = { borrows = "Movement.FallAirKnockback", speed = 1.00, fadeTime = 0.05, priority = "Action4", looped = false, impactRatio = 0.20, cancelRatio = 0.80, name = "Slam Shockwave Blast" },
	},
	Strafe = {
		StrafeLeftRun = { id = "rbxassetid://123318024844911", speed = 1.20, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Left Sprint" },
		StrafeLeftTired = { id = "rbxassetid://91032818959845", speed = 0.80, fadeTime = 0.15, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Left (Fatigued)" },
		StrafeLeftWalk = { id = "rbxassetid://71421932655009", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Left Walk" },
		StrafeRightRun = { id = "rbxassetid://107962284182266", speed = 1.20, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Right Sprint" },
		StrafeRightTired = { id = "rbxassetid://110691224052109", speed = 0.80, fadeTime = 0.15, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Right (Fatigued)" },
		StrafeRightWalk = { id = "rbxassetid://82291519563301", speed = 1.00, fadeTime = 0.10, priority = "Movement", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Strafe Right Walk" },
	},
}

-- Projectile jump kits: each jump picks one. Launch -> airborne loop -> DiveFly for the dive
-- -> a landing from the shared random list (RecoveryState). These six clips were authored
-- facing backwards and the Ninja ones with hip translation 10x too large: corrected on the
-- client (CombatConfig.ClipCorrections).
AnimationConfig.Registry.ProjectileJump = {
	NinjaJump = { id = "rbxassetid://90572410559809", speed = 1.00, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "NINJA PROJECTILE JUMP" },
	NinjaAirLoop = { id = "rbxassetid://107304638987317", speed = 1.00, fadeTime = 0.15, priority = "Action3", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "NINJA AIRBORNE LOOP" },
	NinjaLanding = { id = "rbxassetid://92021932752253", speed = 1.10, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.35, cancelRatio = 0.85, name = "NINJA CONFIDENT LANDING" },
	StandardJump = { id = "rbxassetid://121127010274438", speed = 1.00, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.00, cancelRatio = 1.00, name = "PROJECTILE JUMP" },
	StandardAirLoop = { id = "rbxassetid://122361647744311", speed = 1.00, fadeTime = 0.15, priority = "Action3", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "PROJECTILE JUMP AIRBORNE LOOP" },
	StandardLanding = { id = "rbxassetid://105219213466134", speed = 1.10, fadeTime = 0.06, priority = "Action3", looped = false, impactRatio = 0.35, cancelRatio = 0.85, name = "PJ JUMP STYLE LANDING" },
	DiveFly = { id = "rbxassetid://120414990498875", speed = 1.00, fadeTime = 0.08, priority = "Action3", looped = true, impactRatio = 0.00, cancelRatio = 1.00, name = "Flying (dive)" },
}

-- Social body language (SocialSystem.playSlot). Blank until clips exist: a blank slot is skipped
-- and the Quin falls back to stillness, head looks and pace. Paste an id to switch one on.
AnimationConfig.Registry.Social = {
	Nod = { id = "", speed = 1.00, fadeTime = 0.10, priority = "Action2", looped = false, name = "Social: nod (the head nod is procedural without it)" },
	HoldBack = { id = "", speed = 1.00, fadeTime = 0.15, priority = "Action2", looped = false, name = "Social: hand up, hold back / cool down" },
	Beckon = { id = "", speed = 1.00, fadeTime = 0.15, priority = "Action2", looped = false, name = "Social: beckon / come on" },
	Kneel = { id = "", speed = 1.00, fadeTime = 0.25, priority = "Action2", looped = true, name = "Social: kneel" },
	Sit = { id = "", speed = 1.00, fadeTime = 0.30, priority = "Action2", looped = true, name = "Social: sit and watch" },
	Lean = { id = "", speed = 1.00, fadeTime = 0.30, priority = "Action2", looped = true, name = "Social: lean and watch" },
	Crouch = { id = "", speed = 1.00, fadeTime = 0.25, priority = "Action2", looped = true, name = "Social: crouch and watch" },
	Celebrate = { id = "", speed = 1.00, fadeTime = 0.15, priority = "Action2", looped = false, name = "Social: celebrate" },
	Exhausted = { id = "", speed = 1.00, fadeTime = 0.30, priority = "Action2", looped = true, name = "Social: exhausted, catching breath" },
	LookUp = { id = "", speed = 1.00, fadeTime = 0.30, priority = "Action2", looped = false, name = "Social: look up" },
}

function AnimationConfig.get(dotPath)
	if dotPath == "Combat.DesperateCounter" then
		return AnimationConfig.Registry.Tactics and AnimationConfig.Registry.Tactics.DesperateCounter
	end
	local current = AnimationConfig.Registry
	for segment in string.gmatch(dotPath, "[^%.]+") do
		if type(current) ~= "table" then return nil end
		current = current[segment]
	end
	return current
end

-- Placeholders. An entry with `borrows = "Some.Path"` has no clip of its own yet: it plays the
-- clip of the entry it names, with its own speed, fade and priority. Every asset id is written
-- once, on the entry that owns it. Give a placeholder its own `id` (here or in the Animation Lab)
-- and it stops borrowing. AnimationConfig.placeholders() lists them.
function AnimationConfig.resolveBorrowed()
	local function walk(tbl)
		for _, v in pairs(tbl) do
			if type(v) == "table" then
				if v.borrows then
					local owner = AnimationConfig.get(v.borrows)
					v.id = owner and owner.id or ""
				elseif v.id == nil then
					walk(v)
				end
			end
		end
	end
	walk(AnimationConfig.Registry)
end

function AnimationConfig.update(dotPath, newValues)
	local current = AnimationConfig.Registry
	local segments = {}
	for segment in string.gmatch(dotPath, "[^%.]+") do
		table.insert(segments, segment)
	end
	for i = 1, #segments - 1 do
		local seg = segments[i]
		if type(current[seg]) ~= "table" then current[seg] = {} end
		current = current[seg]
	end
	local targetKey = segments[#segments]
	local entry = current[targetKey]
	if type(entry) == "table" then
		-- a placeholder given a clip of its own stops borrowing
		if entry.borrows and newValues.id ~= nil and newValues.id ~= "" and newValues.id ~= entry.id then
			entry.borrows = nil
		end
		for k, v in pairs(newValues) do entry[k] = v end
	else
		current[targetKey] = newValues
	end
	AnimationConfig.resolveBorrowed() -- (an owner's new clip reaches the entries that borrow it)
end

function AnimationConfig.getAllPaths()
	local paths = {}
	local function recurse(tbl, prefix)
		local keys = {}
		for k in pairs(tbl) do table.insert(keys, k) end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local v = tbl[k]
			local currentPath = prefix == "" and k or (prefix .. "." .. k)
			if type(v) == "table" and v.id then
				table.insert(paths, {
					path = currentPath,
					category = prefix,
					name = v.name or k,
					entry = v,
				})
			elseif type(v) == "table" then
				recurse(v, currentPath)
			end
		end
	end
	recurse(AnimationConfig.Registry, "")
	table.sort(paths, function(a, b) return a.path < b.path end)
	return paths
end

-- { path = "Tactics.RetreatBackstep", borrows = "Strafe.StrafeLeftWalk" }, in path order
function AnimationConfig.placeholders()
	local list = {}
	for _, item in ipairs(AnimationConfig.getAllPaths()) do
		if item.entry.borrows then
			table.insert(list, { path = item.path, borrows = item.entry.borrows })
		end
	end
	return list
end

function AnimationConfig.exportLuau()
	local function serializeVal(v)
		if type(v) == "string" then
			return string.format("%q", v)
		elseif type(v) == "number" then
			return string.format("%.2f", v)
		elseif type(v) == "boolean" then
			return tostring(v)
		else
			return "nil"
		end
	end

	local function serializeReg(tbl, indent)
		local ind = string.rep("\t", indent)
		local lines = { "{\n" }
		local keys = {}
		for k in pairs(tbl) do table.insert(keys, k) end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local v = tbl[k]
			local keyStr = tostring(k)
			if type(v) == "table" and v.id ~= nil then
				local parts = {}
				local fieldKeys = {"id", "borrows", "speed", "fadeTime", "priority", "looped", "impactRatio", "cancelRatio", "startCut", "endCut", "name"}
				for _, fk in ipairs(fieldKeys) do
					if v[fk] ~= nil and not (fk == "id" and v.borrows) then
						table.insert(parts, fk .. " = " .. serializeVal(v[fk]))
					end
				end
				for fk, fv in pairs(v) do
					local isKnown = false
					for _, defk in ipairs(fieldKeys) do
						if defk == fk then isKnown = true; break end
					end
					if not isKnown then
						table.insert(parts, fk .. " = " .. serializeVal(fv))
					end
				end
				table.insert(lines, ind .. "\t" .. keyStr .. " = { " .. table.concat(parts, ", ") .. " },\n")
			elseif type(v) == "table" then
				table.insert(lines, ind .. "\t" .. keyStr .. " = " .. serializeReg(v, indent + 1) .. ",\n")
			else
				table.insert(lines, ind .. "\t" .. keyStr .. " = " .. serializeVal(v) .. ",\n")
			end
		end
		table.insert(lines, ind .. "}")
		return table.concat(lines)
	end

	return serializeReg(AnimationConfig.Registry, 0)
end

AnimationConfig.resolveBorrowed()

return AnimationConfig