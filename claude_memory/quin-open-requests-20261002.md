---
name: quin-open-requests-20261002
description: "Owner's 18-item list + animation changes after pass 14 (2026-10-02); track which are done"
metadata:
  node_type: memory
  type: project
  originSessionId: a09c85bc-3f6b-44cf-9250-484840397f07
  modified: 2026-10-01T16:44:00.321Z
---

Owner's list after pass 14 (2026-10-02). Owner cares MOST about #4 (feet not moving while the Quin moves = shuffle, "cringe").

1. T-poses during the match (condition unknown)
2. Legs glitchy, esp. during sliding and rapid 180 turns with small radius
3. Backward sliding
4. Feet not moving while Quin moves (shuffle) - TOP PRIORITY
5. Dive after projectile jump: some Quins stuck oscillating up/down on Y rapidly
6. Projectile jump body should face the trajectory direction
7. Quin stuck below a platform running in circles when the enemy is on the platform
8. Snappy around corners
9. Normal jumps snappy / "locking"; test jumps + basic movement on MovementTestArena
10. Small studs (small obstacles) not handled with small jumps
11. Physically inaccurate body movements
12. "a lot actually"
13. Face-offs too long: fight idle, staring, no punches landed
14. On high platforms: walk around, back and forth, jog in circles
15. Head turns look abnormal: normalize transitions / limit angle
16. Spine + head secondary motion
17. Re-audit the locomotion system
18. Movement inputs robotic (W then A); want natural key combinations / arcs

Animation changes requested:
- ProceduralSmackDown AOE attack 71743026406362: randomize for ARC jump (style 1) only; time-scale the one clip to the arc flight + landing
- ProceduralSkidOverOB 100662167599815: parkour over 5x3 OB; allow lengths beyond 5-7 studs, time-scaled
- Remove 118776942028972 (hook punch) and any duplicate clips of it
- Flying 120414990498875: play during the dive (before the smash)
- Some animations may be inverted (forward/back) - check
- Two PJ styles, randomized: Ninja (airborne loop 107304638987317, jump 90572410559809, landing 92021932752253) and Standard (jump 121127010274438, airborne loop 122361647744311, landing 105219213466134). Both landings join the randomized landing list (superhero etc.)

**Status after pass 15 (commit `f115c80`):** done/first pass: #1 (spawn hide + no-pose watchdog), #4 partly (shuffle 30%->11% with planting; frozen hit-stop bug fixed), #5 mostly (dives always descend; 2% left), #6, #15, #16 (spine only; neck/head springs off - jitter), hook removed, DiveFly, Ninja/Standard kits (clips were backwards; Ninja root motion 10x -> CombatConfig.ClipCorrections). Not done: #2,#3,#7-#14,#17,#18, AOE smack-down, skid-over (clip did not load in Edit-mode pose lab).

**Status after pass 16 (commit `488ed18`):** body tilt (owner loves it, see [[body-tilt-keep]]), directional gait (strafe 50-130 deg, backpedal >130; crab-running 27%->6%), #3 backward slide mostly (flinch/spacing now stepped), #7/#13 partly (NavigationModule reachability + path detours), #10 hurdle timing, MovementTestArena fixed (bounds per mode, spawn points). Skid-over id now 82934009896094. Left for batch 3: #13 face-offs/passive ConfidentWalk pacing, #14 platform roaming, AOE smack-down (arc jump), skid-over time-scaling; sideways sliding in Circling 23%.

**Status after pass 17 (commit `a84134a`):** #13 done (cause: Fight dead zone 9-10.2 studs where a Quin neither struck nor closed, 21% -> 2-3%; stalk walks capped 2.5 s), #14 done (Overwatch loop/pace/lookout routines), #7 done (Circling hands unreachable targets to Chase), AOE smack-down done (id 71743026406362, 50% of arc jumps, rate fitted to touchdown, landing carried into Recovery), skid-over done (low obstacles <=4.5 high up to ~16 long, both-edge arc solve, timed takeoff). Left: #2, #8, #11, #17, #18 polish; sideways slide in Circling 23%; diagonal blending; Survey/FightIdle shared track.

**2026-10-03 (pass 18, `627c2c9`):** owner rules: skid only for 3-5 stud obstacles, Y locked during skid (owner idea), jumps for the rest; courses JUMPLANE/SKIDLANE/VAULTUNDERLANE/JUMPONOBSTACLES all pass with no falls (floor is lava); stepping stones via spot hops; slide-under any gap 2.5-8.5. Open: facing leads motion 9-17 deg on curves (needs body-tilt A/B), not visually checked by owner yet.

**2026-10-03 (pass 19, `572354c`):** facing now follows motion on curves (SteerFacing align, 9-17 deg -> ~0.1); owner-reported torso-to-head shiver fixed (secondary-motion springs moved to body frame, capped accel, torso spring 3.5 Hz critically damped; head-vs-root reversals 3.9->1.2/s). Next in the turning batch: sharp pivots/180s (#2), sideways slide in Circling.

**Why:** owner reviews by watching matches; motion quality is the main complaint.
**How to apply:** work in batches, one backup/commit/audit per batch (see [[quincore-phased-plan-20261001]]); mark items done here as they land.

**2026-10-03 (pass 20, `9bb3308` + `88280ce`):** #2 reversals done (plant-and-pivot: brake/pivot/drive-out, `ReversalPhase` debug attr, 16v16 mean 0.43 s; pivot foot slip remains until a turn clip exists). Owner's extra list: camera shake master volume `CameraShake_Multiplier` 0.3 (+ live attr), join camera bleed fixed (ReplicatedFirst.JoinCameraCover: default camera at origin before character), motion blur (CameraMotionBlur BlurEffect by view speed, MotionBlur_* config). NOT reproduced: "ghost T-shirt accessories at Arena One Quin spawn" - asked owner for screenshot/location. Stray `Workspace.ybotdark` T-pose rig and empty `Workspace.Model` noted, untouched. Next: sideways slide in Circling.

**2026-10-03 (pass 21, `a0274a9` + `72e5810`):** Circling sideways slide 41.8% -> 17.3% (strafe facing leads the orbit; directional gait in Circling travel form). Arena System fixed: orchestrator rewritten (anthem called a missing function and killed the match; panel timings were ignored; skip only skipped sub-waits; FFA crashed), panel layout/hotkey/badge fixed, ArenaGlobe ring rebuilt as one continuous LED ticker that appears 1 s after the globe (globe+screen at T+5 of Arena Open). Owner's timings: Open 10, Gen 15, Prep 30, Teleport 10, Anthem 60, Game 600, Victory 8, Post 180. Procedural terrain generator does not exist (toggle marked "not built yet").
**Pass 21c (2026-10-03):** camera flash = Quin Manager "Action Cam" (MenuController) defaulted ON and set CameraSubject for one frame on every MidAirClash; now off by default and routed via SpectatedQuin. "Ghost shirts" = T-posed Quin torsos buried in ArenaGround at spawn (orchestrator spawned at pad y -0.95+2); QuinSpawner now grounds every spawn by ray, AIGhostHandler keeps un-animated bodies hidden. Ghosts not reproduced in the fixed build - ask owner to confirm.
**Pass 21d:** ghost torsos actual cause = instance streaming (StreamingEnabled, Quin models ModelStreamingMode Default: parts streamed separately, orphan body mesh left in bind pose on clients). Fix: QuinSpawner sets ModelStreamingMode.Persistent. Earlier "spawn height" theory was wrong (getSpawnPositions adds +5).
**Pass 21e:** ghost torsos REAL cause = QuinMale template had Model.LevelOfDetail = StreamingMesh (engine draws grey low-poly bind-pose stand-ins); set Disabled on templates (place file - owner must save) and in QuinSpawner. Earlier streaming/spawn-height theories were partial/wrong. Awaiting owner confirmation.
**2026-10-03:** owner CONFIRMED ghosts gone after 21e/21f (LevelOfDetail Disabled on templates) and saved the place. Still open from this batch: drone yellow lines in normal view (owner didn't ask), Quins chasing in a single-file "conga" line in FFA (not yet checked), anthem window shorter than the 45 s anthem extends the phase.
**Pass 22 (2026-10-03, plan `~/.claude/plans/cached-orbiting-flurry.md`, items A-G):** owner batch = body constraints. A done `67cddb1` (Quins perched on 7-wide wall tops via Overwatch -> Overwatch_MinTopWidth 10; PJ dive wall probe/stall guard/8 s cap; Play As Quin punch error + release storm fixed). B done `429278d` (single-frame T-poses: stopCategory("Attacks") stopped the fight idle because BeamStruggle/AssessTarget share its asset; trackKey own tracks). C done `c50660c` (slide Chase 29.6->13.0%, Fight 31.4->21.0%: push-off overlay off, plant while striking, Gait_JogAuthoredSpeed 9.85 measured, gait driven every frame). D done `8f18001` (continuous forward+strafe blend `Gait_DiagonalBlend`/attr `GaitDiagonal`; all plant phases re-measured as left mid-stance - old ones were 3 different stance points; strafe authored 7.3/18.9; hasForeignLocomotion now counts gait's own strafe layer; diagonal-band slip -10..30%, slide% ~unchanged - rest is body-turn, F). E done `28b9fd4` (dive bob = sink-and-pop: velocity set-downs overshot 2-7 studs into floor; now set-down SNAP at touchdown (`ProjectileJump_SetDownSnap`, attr `PJSetDownSnap`) + feet probe along flight + Impact drop cap; 0/218 sinks). For G: Chase stalls on JUMPONOBSTACLES top at the 5-stud block (x-249) or 14-stud block (x-149) when target is past it. F done `218e7ea` (pivot foot pin: no turn attenuation during ReversalPhase pivot, pivot steps at 0.7 stud drift / 0.16 s, let-go unchanged; `FootIK_PivotPin`, attr `PivotPin`; foot held 16-22% -> 38-54% of the turn; turn rate 4 rad/s holds 61-73% but pivot 0.68 s vs 0.39 s - kept 7, owner's call). G partial `a27ff32` (2026-10-03): Studio was throttled to ~15 fps (background window; HeartbeatTimeMs 12), so per-frame measures were skipped; frame-independent probes clean (0 bodies inside block parts in FFA 32, ~0 stuck in air, 0 errors); top-of-course Chase stall NOT reproduced (4 runs); seen once: 5 s creep along the base of JUMPONOBSTACLES while 'Going round'. G per-frame sweep done (2026-10-03): fix = FightGyro/CirclingGyro had no MaxAngularVelocity (bodies whipped at 18-26 rad/s; A/B bursts 55 -> 1), now `Combat_FacingMaxTurnRate` 14; riposte turns via gyro. Velocity jumps = air launches (by design). Leftovers fixed after: FightGyro responsiveness reset, IdleGyro cap. Not bugs: reversal brake timing (server is at 6 studs/s when the pivot starts; client sees the flag early), slow spells in a far chase = Stalk:AlternatingPace pacing (ask owner whether stalking should only happen near the target). Still left: client-side measures (bind pose, on-screen foot slide), pivot foot drag (needs a turn clip). Pass 22 plan A-G complete. Note: Quins live in workspace.QuinServer; LogService history is capped - use MessageOut. Export: one file per call if the escaped JSON could pass 100k (output silently truncates at ~100k).

**Pass 23 (2026-10-03, see git log, audit `2026-10-03_pass23_head_shake_walk_feet_footsteps.md`):** owner watched the stalk-walk demo; decided KEEP the stalking walk (pace 7.5 + WalkConfident, only when target is far). Fixed: head/spine shake = client pose layers re-applied on rendered frames with no animation step (owner's client runs ~235 fps; AIGhostHandler now edits once per PreAnimation; attr `PoseEditEveryFrame` = old); walk feet = solver 'out of reach' rule tripped by straight-leg heel strike (`FootIK_OverreachSlack` 0.3); footsteps doubled = Footstep markers of near-zero-weight gait clips (silent below weight 0.35).
**Pass 23b:** male left leg 'broken' while walking = foot solver pinned the left heel at first touch while the clip still reached forward (walk frames 2-6); now plants only when the clip foot has stopped (`FootIK_PlantWhenStill`, attr `PlantWhenStill`); left shin off the clip 51-53 -> 1-7 deg at frames 4-11. Diagonal blend dead band <20 deg (`Gait_DiagonalBlendStart/Full`). Open: backward walk slide unverified (stance metric unreliable across rigs).

**Pass 24 (2026-10-03, audit `2026-10-03_pass24_camera_ground_vfx_spectator.md`):** owner's 8-item list. 24a `8e5546d`: motion blur off (Roblox BlurEffect = full-screen haze), camera shake = trauma^2 + Perlin, squared falloff, frame-rate independent (`CameraShake_*`); footprints/streaks/cracks are SurfaceGui drawings on invisible carriers in `workspace.GroundDecals` (Top-face canvas width runs along part Z: carrier X along the mark, facing -forward); boot sole under the real foot (Footstep marker param Left/Right); `createLandingImpact` replaces Part debris + neon ring. Owner will supply images: `Vfx_FootprintImage(Left)`, `Vfx_LandingCrackImage`. 24b `99f79de`: Fly Spectator default (B walk / R fly, avatar parked+hidden), mouse-look always (middle mouse or L frees cursor; menus free it), first person on zoom-in while possessing, streaming focus follows camera (block at end of ServerScriptService.Server, RemoteEvent CameraFocus). Camera attrs SpectatorMode/FirstPerson for tests. Item 8 (animation hit events) = owner authoring markers per COMBAT_ANIMATION_GUIDE.md.
