---
name: combat-animation-guide
description: Owner-approved marker naming convention + full combat clip list live in QUINCORE_BACKUP/COMBAT_ANIMATION_GUIDE.md; owner is authoring markers himself and will reorganise combat later
metadata:
  node_type: memory
  type: project
  originSessionId: 067aa4a4-9c77-4da6-812b-ce8bdf098393
  modified: 2026-10-03T00:05:05.176Z
---

2026-10-03: the owner loved the combat breakdown and had it saved as `QUINCORE_BACKUP/COMBAT_ANIMATION_GUIDE.md` (commit 7f3960e, README §12). It holds:
- marker names: `Windup` / `Plant` / `Whoosh` / `HitStart` / `HitEnd` / `Hit` / `Cancel` / `Recover`, `GuardUp` / `ParryStart` / `ParryEnd` / `GuardDown`, `EvadeStart` / `EvadeEnd`, `Impact`, `GrabStart` / `GrabEnd` / `Release`, `Footstep`(Left/Right), `Sound`, `Vfx`;
- current clip IDs, with the shared ones flagged (jab asset 113219639247452 is 6 moves; the light flinch = braking skid 83869147275692);
- the full needed list of strikes, blocks, dodges and reactions.

**Why:** the owner places markers in the Animation Editor themselves ("leave 8 for me") instead of the code guessing `impactRatio`. They plan a combat reorganisation later: frame data, limb-following hitboxes, reaction choice by hit location/side/weight, Combat Lab test mode, marker checker.

**How to apply:** use these exact names when writing the marker reader. Don't rename clips or markers without updating the guide. When the owner sends new clip IDs, map them to the guide's Part 3 names in AnimationConfig. Hit reactions today are a random pick of 2 clips in `DamageModule.apply` (to be replaced).

Related: [[quin-test-modes]], [[quin-animation-authoring-plan]]

**2026-10-06, Pass 71 (`d1e4cf1`):** the owner authored 8 strike clips with markers and published them; AnimationConfig.Attacks is now ONLY those (Punches.LeftPunch/RightPunch, Kicks.LowKick/HighKick/WheelDrive Right+Left) plus `Attacks.Special.ProceduralSmackDown`. Owner wants no borrows inside Attacks. Specials/finisher/desperate counter point at the new kicks/punch from outside Attacks; beam struggle is `Transition.BeamStruggle`. impactRatio/cancelRatio derived from the markers (interim). NEXT: the marker reader (only Footstep/Landing/Jump/ProjectileJump are read today).
- Mirroring a clip for the owner: KeyframeSequenceProvider / RBX_ANIMSAVES KeyframeSequence, rig rest frames from `workspace.QUINTESTMALE.Alpha_Surface` bones (Mixamo, symmetric to 0.001), mirror each bone's model-space delta across the Left/Right plane, swap names, rebuild local Transforms; save as "<name> (mirrored)" in RBX_ANIMSAVES; the owner publishes. Owner names saves "<Move> Right" / "<Move> Left".

**Pass 72 (2026-10-06):** marker reader is IN. `Modules/StrikeMarkers` (preloaded in Server.server.lua) reads HitStart/HitEnd/Recover; FightState.executeAttack checks contact every frame of the window and frees the Quin at Recover; switch `Combat_UseStrikeMarkers`; attribute `StrikeTiming`. 16v16: hit 71 %, whiff 6 %, strikes +29 %. Owner said: no Whoosh sound yet. Not yet: Windup/Cancel, limb-following hitbox, counters/clash/specials timing.

**2026-10-11, Part 5 (`a08aa4c`): the range plan clip list.**
- What it holds: the owner's chosen three ranges as an ordered shot list.
  - mid: FightStance, StepIn, StepOut, Sidestep, Backpedal, LegCheck;
  - point blank: Knee, Elbow, ShortHook, PushOff, ShoulderBump, Clinch;
  - long: DashIn, FlyingKnee/Kick, StanceCircle.
- Clips are made in Cascadeur, one side only, then run through [[cascadeur-to-quin-converter]] (it mirrors).
- SIDESTEP is the first one.
- The code side is not started: move database, range layer on Reach, selector. Wait for the owner's go.
