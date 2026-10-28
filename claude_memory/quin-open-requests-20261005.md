---
name: quin-open-requests-20261005
description: "Owner's 25-item list of 2026-10-05 after the body-layer port (falls, edges, platforms, obstacles, projectile jump, walls, death/teleport VFX, mind panel, combo moves, indecision audit) with status"
metadata:
  node_type: memory
  type: project
  originSessionId: 1e4a917c-c0cd-44ea-b073-34aa1ddbc6d9
  modified: 2026-10-06T19:04:40.059Z
---

Pasted by the owner on 2026-10-05 after Pass 42. Owner's framing: the arena is NOT a scripted scene; scenes must emerge from overlapping conditions. IK/body layers are "pretty stable, leave that for now" (kick feet look odd with the layers: combat optimisation, later).

**Bugs / behaviour**
1. Fall clips: FallFront / FallBack should trigger by body orientation; owner mostly sees the Ninja fall. Check all fall and landing clips actually trigger.
2. Idling on edges.
3. Quins go to the EDGES of higher platforms like a snap point; they should land around the centre and use platforms freely as jumping points.
4. Stuck under obstacles lower than their height (body rotation bug): require a slide under, and if they end up there, know they cannot stand and get out.
5. Jumping at a platform while standing UNDER it (hits the underside, retries): must realise and change direction.
6. On platforms they seem to see through the platform to below.
7. Getting off a platform: several tries, LandingSoft clip repeating.
8. Projectile jump: trajectory slows mid-dive; must be smooth.
9. Projectile jump style that changes direction after the apex: same treatment as a dive (dive fx, dive, dive fx, dive to ground/target).
10. Kick feet look weird (IK layers) - parked by the owner.
11. Avoid wall edges; give them awareness "I'm near the edge".
12. Visual bug: laggy after touching a wall.
13. ArenaWall becomes playable (wall run, walk, run, fight on it) but it is a penalty: time on the wall vs on ArenaGround tracked dynamically (wall may overlap the ground).
14. Mind panel: improve, "we miss a lot".
15. Death animation clips through the ground; do not turn anything off until the animation event finishes; add holographic glitch effect (check VfxModule, may exist).
16. Teleport Quins only during aria_teleporting; glitch hologram VFX; not one batch: one by one at random on both sides over about 5 s. Also "instant match" as an Arena menu feature.
17. General QuinCore audit: what can be improved.

**Emergent combination moves wanted**
18. Normal jump then immediately dash (to target or to move).
19. Wall run then dash off the wall (attack or move).
20. Wall run is liked but too shallow: raise the max.
21. Slide tackle vs a timed jump over it; or the tackle hits the legs and the victim falls forward rotating ~180 deg (ragdoll-like).

**Indecision**
22. Quins look "chaotic and indecisive": back-and-forth after a hit, quick 180 then recommit. Owner asks my opinion, a stress test of the conditions (race conditions), maybe target lock-on / persistence.

**Done so far (Pass 43):** item 22 first step: target commitment in `TargetingModule.selectTarget` (`Targeting_MinHold` / `SwitchMargin` / `UrgentMargin`): target switches 29 -> 16 per Quin-minute, flips back 41% -> 29%, Idle blips 145 -> 44. Twelve writers of `CurrentTarget` exist; eleven still bypass the commitment (next step). Fight back-and-forth is mostly knockback physics (every hit skids the victim 10-18 studs), owner's call. Item 1 answered: no FallFront/FallBack clips exist in AnimationConfig; FallStraight is never played; only GetUpBackFast seen.

**Pass 44:** item 1 done: FallBack (88441309301154) / FallFront (80583167665730) by the side it is thrown (`FallSide` attribute), get-ups by side: instant = GetUpBackFastNinja or a landing clip; knocked flat = GetUpBackFast/Slow, GetUpFrontFast/Slow (slow under 35% health). The owner's three new get-up clips have no hips vertical travel (lie 4 studs in the air): covered by `ClipCorrections` `ground = true`; owner told to re-export. Before pushing AnimationConfig, check Studio's copy compiles: the owner's Studio copy had regressed to a pre-pass-36 version with a typo.

**Pass 45:** owner asked for the foot solver off during strikes: `StrikeFeetFree` layer (planting, conform and knee-over-toe let go while `Attacking`); verify with `FootDebug` / `FootDbg`, NOT `IKControl.Weight`. Items 3, 5, 7 first pass: jumps land toward the middle of platforms (`PlatformCatalogue.landingDepth`), high-ground climb goes out from under a platform first (unseen in play), dive-off only when the leap clears the ledge. Remaining in the group: 2, 4, 6, 11, 12.

**Added by the owner (Pass 46):** `LandingSoft` is the unhurried one: never in Recovery ("looks funny"); only for a drop with ~zero movement across the ground, e.g. a confident Quin casually stepping off a ledge and walking on ("nonchalant ledge drop, aura farming"). Done: Recovery no longer uses it; platform drops pick soft/hard by across-speed at touchdown (`Landing_SoftMaxSpeed` 8); walked-off drops get it in GaitModule's ground contract; calm confident Quins walk off instead of diving. OPEN: after the soft landing they run off (14.6 studs/s after 0.4 s) instead of standing through it and walking on. Item 4 baseline: 1.97% of standing samples are under a ceiling lower than the Quin (mostly in Fight), none tipped.

**Pass 47:** soft landing now reads as wanted: stands through it, walks ~2.5 s (`CasualUntil`), then runs again; the earlier "runs off" average was skewed by outliers (trace individual cases before believing a mean). Item 4 first pass: `Modules/HeadroomAwareness` + a rule in Main (Quin with no room to stand gets out; `LowCeiling` attribute). The stuck/rotating bug itself was NOT reproduced. Owner tip: test obstacle/platform behaviour in a generated arena (`ArenaGenDevCommand "run 4"` then `DevCommand "team:16"`). Remaining in the group: 2 (edge idling), 6 (seeing through platforms), 11, 12.

**Pass 48:** item 6: LookController now checks sight itself (ray head to head; hidden target -> looks at last seen spot) and does not look into the floor it stands on; switch `LookSight`, debug `LookDebug`/`LookDbg`. Rules engage (53% last-seen on hidden targets) but no change in final head direction was measurable (clips pitch the head; last-seen is near the target): needs the owner's eye. Server `TargetHasLoS` is unreliable (59% wrong vs a head ray). Item 2 (edge idling) NOT reproduced: ask the owner which state/where. Items 11, 12 go with 13 (playable ArenaWall). Lesson: compare on/off inside one match; two different generated arenas differ more than a fix does.

**Owner's clarifications (2026-10-05, after Pass 48):**
- Item 6: it is about KNOWING, not only the head: what a Quin knows of an enemy under a platform should depend on seen / last seen / memory, later "common sense" (1v1 and it hears running below: that is its target). Common sense is a later step.
- Item 20 (wall run): both further and higher, but physically plausible, "not Spiderman, not stick to the wall". Must work in pursuit: a Quin can chase one that retreats along a wall.
- Item 13 (arena wall / out of the arena): penalty = performance score deduction AND forced back after N seconds. Knocking an opponent out of the arena floor is allowed; the knocked-out Quin is brought back after N seconds or projectile-jumps back in itself; the Quin who knocked it out gets a score deduction.
- Item 2 (edge idling): platform rim; low priority, ignore for now.
- Item 22 skid length: leave, "combat optimization" later.
- Item 11 (wall edges): not answered; I read it as the rim of the arena wall's top.
- My proposed order, not objected to: arena wall (13 + 11 + 12), death/teleport FX (15, 16), projectile jump (8, 9), combination moves, written audit last.

**Pass 49:** item 13 first pass: `Modules/ArenaTrespass` (Ground / Wall / Outside from the surface under the Quin; `MatchPenalty` 0.2/s after 1 s; forced ReEntry after 8 s on the wall or 4 s outside; thrower charged 1 point; subtracted from `SocialLeaders.standing` and `SocialRespect.contribution`, since no single performance score exists in code; numbers are my guesses, owner has not set them). The old "within 5 studs of the floor edge = out of bounds" rule is gone. Still open: 20 (wall run further/higher, physical, usable in chase/retreat), 11, 12, AI choosing to use or leave the wall.

**Pass 50:** item 20 first pass: wall run is now an arc from the arrival speed (`WallRun_ClimbRatio` 0.5, `WallRun_GravityScale` 0.10, `WallRun_Drag` 5, `WallRun_SinkSpeed` 20): 98 studs along and 16 up from 48 studs/s (was 60 along at a fixed 3.5). A chaser may follow a wall-running target onto the wall without cooldown. Only one full run measured; not seen in natural play; staging wall runs by hand is flaky (test hook attribute `WallRunEntrySpeed`). Still open from the wall group: 11, 12.

**Pass 51:** items 15 and 16 first pass. Death: body held at stand height (dead Humanoid dropped its root -> feet 3 studs under the floor), clip plays to the end and holds, 0.6 s rest, hologram glitch 1.1 s, then removed. `VfxModule.holoGlitch(model, duration, "in"|"out")` is new (none existed for Quins). Teleport: fighters arrive one by one, shuffled across both sides, over `ArenaConfig.Teleport.Window` (5 s) with the glitch. `InstantMatch` toggle in the Arena menu (fight starts in ~3 s). Arena flow can be driven in tests with Workspace `ArenaDevCommand = "start <json>"` / `"stop"`. Remaining: 8, 9 (projectile jump), 11, 12, 14 (mind panel), 17 (audit), 18, 19, 21 (combo moves), rest of 22.

**Pass 52 (`ddf18c4`):** items 8 and 9 done.
- Every dive leg flies at `ProjectileJump_SlamSpeed` from its first frame to the floor.
- The style 5 swoop is flown along its Bezier at one speed. It went from 25/132/797 studs/s (min/median/max through the middle of the dive) to 428/480/480.
- Turns after the apex (styles 4 and 6) are dive legs, each with the clip, boom and vapour cone, chained frame-exact with no stop. The low point at a turn went from 27 avg / 0 min to about 470.
- Measured with a forced-style driver (`JumpStyle` + `ForceState "ProjectileJump"`) and a Heartbeat probe on `PJPhase` and speed.
- Not yet checked by the owner's eye.

Remaining: 11, 12, 14 (mind panel), 17 (audit), 18, 19, 21 (combo moves), rest of 22.

**Pass 53 (`add4cf1`):** items 18 and 19 first pass. `Modules/AirDash` is called from ChaseState while airborne, once per airtime. It dashes:
- at a target 8-36 studs away (45 off a wall), with a chance from dash preference and aggression;
- on to a ledge a platform jump is falling short of (the jump records its aim via `noteJump`);
- after a target 45-90 studs away, off a wall.

Physics: one ImpulseModule push plus one vertical set, then gravity. A Quin only dashes with at least 0.3 s of air left after the flatten; gravity here is Roblox's default 196.2 studs/s² (checked 2026-10-07; an earlier note said ~210, which was wrong), so hops land too soon.

Debug: `AirDashSkip`, `WallKickReason`, Workspace `AirDashStats`; Studio switch `AirDashAlways`.

Measured:
- Natural 2 min: 7 attack dashes.
- Staged: the gap closes to about 9 studs, and off a full wall run to 5-6 studs into Fight.
- "Ledge" and "chase" paths never happened yet.

Gotchas:
- Staged wall runs (`WallRunEntrySpeed` + `ForceState`) lose the wall in 0.13 s most times; natural ones last 0.6-1.2 s.
- `execute_luau` gets its own module cache: setting CombatConfig values or calling module functions from a test script does not reach the running game. Use Workspace attributes as test switches instead.

**Status:** see the newest audit notes in `QUINCORE_BACKUP/audits/` (pass 43 onward). Work in batches, measure first. Related: [[quin-open-requests-20261002]], [[social-layer]], [[quincore-shared-loop-ownership]].

**Pass 54 (`a876a85`), item 21: slide tackle.** `Modules/SlideTackle` is called from ChaseState's gap-close slide; LocomotionModule.slide gained the `aim` / `maxTurn` / `onGlide` options.
- **Slide:** aimed at the target's predicted spot. The window is 8–19 studs (the glide covers about 17); the slide waits until the run lines up.
- **Sweep:** an enemy in the lane with its feet low takes damage, then a launch and a frame-driven 180° turn-over, and gets up from its back.
- **Hurdle:** a reflex hop, 0.35 × (0.5 + mobility), only when facing the slide.
- **Bug fixed:** ChaseState's hand-over to Fight stopped the slide clip, which cut every slide about 10 studs short. ChaseState now holds a Quin while `LocomotionAction == "Slide"`.
- **Natural 100 s, 16v16:** 29 slides, 11 sweeps, 3 hurdles.
- **Demos shown to the owner:** tackle, hurdle, air dash, wall run → dash. Method: 2v2 (`DevCommand "team:2"`) on the strip by the straight arena wall (inner face z≈-736), Workspace `CameraOverrideActive` / `CamPos*` / `CamLook*`, anchor the target until the slider is close.
- **Found, not fixed:** `WallRunState.enter` falls back to "wall on the left" when `detectWallRunSurface` fails, so a wall on the right is lost in 0.1 s (`WallEnd`). Stage wall runs with the wall on the Quin's left.

Remaining: 11, 12, 14 (mind panel), 17 (audit), rest of 22. Owner still to judge the moves by eye.

**Pass 55 (`63f7912`), wall run look and feel.** The owner said it looked "funky, not physical, slow" and wanted the hand touching the wall.
- `WallRunState`: `wallBeside` probes both sides (the wall-on-the-right bug is fixed); no wall at all drops the run (`NoWall`); the clip rate follows |along, rise| ÷ 29.5.
- Arc: gravity 0.20, climb 0.75, drag 3, sink 22. Now 1.35 s / 51 along / 13 up (was 2.3 s / 98 / 16).
- `WallRunTiltDegrees` 30: the wall-side toe is now 0.3 studs off the wall.
- New client layer `Procedural/WallHand` (two-bone arm IK to a point on the wall, sway with the stride, fingers forward-up; `Layer_WallHand`): the hand is 0.49 studs from the wall.
- Client pose probe: the Quins are drawn from the replicated `workspace.QuinServer` models themselves (no separate ghost models); use `execute_luau` with `datamodel_type "Client"`.
- Owner to judge by eye. The run is shorter than Pass 50 by design.

**Pass 56 (`ba3316b`):**
- The owner found the 180° sweep flip odd.
  - Cause: Pass 54 spun the root 180° and the Quin landed on its head, then RecoveryState torqued the root upright under a get-up clip that starts lying down, so it got up twice.
  - Rule: knockdowns keep the root upright and let fall clips lay the body down. Never spin the root for a fall.
  - Fix: the sweep picks `SweepFallSide` from the topple against the sweep plus the victim's momentum (runner head-on falls forward). KnockbackState plays FallBack/FallFront at once.
- Air dash pose: `Movement.AirDash` borrows `ProjectileJump.NinjaJump` (cut after the burst); 0.4 s vapour cone; shockwave puff.
- Demo method the owner liked: loop with only two Quins (`DevCommand "team:1"`), camera free, Workspace `DemoLoop`.
  - The tackle demo is head-on (both chase each other).
  - Anchoring a still target fails: unanchor pops its feet, and an earlier release lets it walk off.

**Pass 57 / 57b (`37c4506`, `07f03dc`):**
- Wall dash sound: borrowed clips carry markers (NinjaJump's `ProjectileJump` marker played the launch sound); that marker sound is now gated to the ProjectileJump state.
- The sweep is a drop: the get-up clip for the side, held on its lying frame and blended over 0.35 s; down 0.8 s with `PlatformStand` off; Recovery continues the same clip (`GetUpClipOverride`).
  - The fall clips are air poses (1.5 s loops), not falls to the ground; there is no trip/fall-to-ground clip in the library.
  - Clips not yet loaded show nothing for about 0.4 s: preload the ones that must start instantly.
- Hop reflex is timed from the closing speed.
- When MCP `start_stop_play` is stuck, ask the owner to press F5; `execute_luau` on the Server works in their Play session.
- Demo loop (owner's format): two Quins, hurdle / sweep / wall run / wall run + dash; switches `TackleOutcome`, `AirDashAlways`, `DemoLoop`.

**Pass 58 (`bd79f89`):** finished the work a session ran out on.
- Sweep, owner's wording: "use the FallAirKnockback animation, flip it, then play the fallback or fallfront, or they land properly like superhero landing". So for the sweep the root IS flipped (360 degrees in 0.44 s, frame-driven, back upright before touchdown); flail -> fall pose for its side at 0.27 s -> normal Recovery landing. This overrides the Pass 56 "never spin the root" rule for the sweep only; Pass 57's drop-into-get-up is gone.
- Wall run is sprint-only ("why can they jog or walk wall run?"): `WallRun_MinEntrySpeed` 32, kick-off under 26, clip rate >= 1.15. The check is `WallRunState.fastEnough`, asked by Chase and Retreat before choosing the state.
- `AnimationModule.preload()` (Server + AIGhostHandler) fetches every Registry clip at session start: any clip first played in a session was blank for ~0.4 s. Do not add per-feature preloads.
- Demo loop restarted for the owner (`team:1`, `DemoLoop`). Remaining list: 11, 12, 14 (mind panel), 17 (audit), rest of 22.

**Item 17 done (`e6b7dce`):** `audits/2026-10-05_quincore_general_audit.md` (target ownership, 10 Hz update vs per-frame writers on one mover, knowledge record for item 6, 86 config fallbacks that differ from the config + 13 keys read but never defined, three clocks, keep the probes).

**Pass 59:** rest of item 22. Every target change goes through `TargetingModule` (`setTarget(fighter, target, reason)` for states; attribute `TargetChangedBy`). Measured causes: the Chase "Distraction" rule ping-ponged (41 % flip-backs) and 22 % of changes happened in Knockback/Recovery/ProjectileJump. Fixed: distraction respects the hold, no selection in those states (`NO_RETARGET_STATES` in Main), a held target out of near view is kept. 19.9 -> 13.9 changes per Quin-minute, flip-backs 3.9 -> 2.65. Left: Select -> Select flips between two enemies both hunting the Quin (owner's call: rear-threat / hunted scores). `getNearest`'s own distance selector is NOT a cause (3 changes a minute). Do not call `get_console_output` in a 16v16: it returns pages of BattleEvent logs.

Remaining list: 11, 12 (wall rim awareness, lag after touching a wall), 14 (mind panel; can now show `TargetChangedBy`), item 6 knowledge record.

**Pass 60:** owner saw a front get-up floating. Cause: the body layer's floor ray (`ikRayParams`) accepted non-solid effect parts (landing dust, shockwave, ground marks sit right under a landed body) as the floor, so the `ground` clip correction did nothing: body 4 studs up. Fixed with `RespectCanCollide = true`. LESSON for probes: every "floor" raycast near a landing must set `RespectCanCollide = true`, or it hits effect parts (my probe reported bodies 5 studs underground because of it). Item 12 measured but not changed: wall-run arc is stepped at 10 Hz (4 studs/s steps) and the kick jumps vertical speed -21 -> +18 in one frame then holds flat 0.22 s; plan: integrate per frame, gravity from the kick's first frame.

**Pass 61:** tackle "stuck in mid air" + strafe on the wall.
- TRAP: writing a part's CFrame every frame on the server replicates outside the physics stream; when the writes stop the CLIENT holds the body in place ~0.17 s (server looks fine). Turn bodies with a constraint whose target is stepped (sweep flip now uses rigid AlignOrientation `SweepFlip`). Always check motion on the Client datamodel, not only the server.
- A state can set `tickInterval` (Main reads it); Knockback uses 0.03 so touchdown is caught at once.
- `SpatialModule.isGrounded` now ignores other Quins and non-solid parts.
- `ClipCorrections` `settle` on FallFront/FallBack lowers the fall pose to the floor over the last 6 studs (not for feet landings); unconfirmed by measurement.
- WallRunState.enter stops the gait and all looped Movement clips: only Run plays on a wall.

**Pass 62:** owner asked for perf, wall bounce, team colors, glitch tweaks.
- PERF: 16v16 frame 23.1 ms -> 9.8 ms. The cost was NOT the IK/body layers (1.6 ms): `QuinDebugHUD` rebuilt 32 rich-text cards every frame even when closed (10.7 ms), and Main built a debug label per Quin every 0.03 s. Method that found it: disable client scripts one at a time (`PlayerScripts.<name>.Disabled = true`) and time RenderStepped. Left: AIGhostHandler 6 ms (4.4 with all layers off), server sends ~400 kbps of attributes.
- Bounce: `KnockbackModule.wallAhead` + rule in KnockbackState (any solid upright surface incl. ArenaWall; restitution 0.55, max 2).
- `CombatConfig.BodyColorBy = "Team"` / `TeamColors` (owner: "for now" in team games).
- holoGlitch: no outline, flicker 0.016-0.04 s.
- Item 12 done: wall-run arc per frame, gravity from the kick's first frame.
Remaining list: 11 (wall rim awareness), 14 (mind panel), item 6 knowledge record.

**Pass 63:** owner's diagram: Quins should get anywhere by normal jump (red), projectile arc (blue) or any style (yellow), "free to move wherever and however they choose".
- `ProjectileJump_ChargeTime` 1.0: `Charge` phase before attacking PJs (not spot hops, not intercepts), QUIN_CHARGEUP + aura; verified 72/72 at ~1.05 s.
- Fall sounds: `playFallOnGround(position, soft)` = QUIN_FALLHARD / QUIN_FALLSOFT (asset ids in AudioModule; volumes are guesses, unheard).
- `Jump_MaxReach` 25 (was 12); all other limits derive from it. Raising it did nothing until ChaseState's order changed: jump first, stepping stones after 5 s; run at the edge instead of the vantage back-off; wide stones (>= 10) jumped on to. Verified jumps of 12 and 15 studs landing; 18-25 not observed.
- Sounds live in `ReplicatedStorage.QuinCore.Assets` (find new ones there by name).
- Server `loadstring` is NOT available in Play (only in Edit); paste probe code inline. When `ExecutePlayModeAsync` says "a previous one is still in progress", use MCP `start_stop_play is_start=true`.
- OPEN: leaving a platform by a chosen jump (the diagram's other half); list items 11, 14, 6.

**Pass 63b (owner's verdict on 63):** charge-up before projectile jumps REMOVED ("I don't like it") - do not re-add. Fall sounds reverted to the old FALL_ON_THE_GROUND pair ("its fine already"); QUIN_FALLHARD/FALLSOFT/CHARGEUP unused. HIT_POWERFUL (90318464419858) removed from heavy hit, slam and clash; heavy hits use the light impact set lower-pitched (my choice). Jump reach 25 stays.

**Pass 64:** `Movement.StopRun` plays only when braking from >= `StopRun_TopSpeedShare` (0.9) of the Quin's `Speed` (owner: "only after the quin reached top speed").
**Pass 65 (item 14):** mind panel now voices target changes with the reason (`TargetChangedBy`), traversal (mapped from `ObstacleAwareness` lines via `MOVE_PATTERNS` in ThoughtVoice: add a pattern when a state publishes a new line), thrown/swept/getting up, trespass. Left column unchanged.
Remaining list: 11 (wall rim awareness), item 6 knowledge record, platform dismount by chosen jump (Pass 63 diagram).

**Pass 66:** male Quins looked darker: QuinMale's `Alpha_Surface` has `MaterialVariant = "Roblox Grid"` (female has none); FXService now clears it when painting. (Checked and ruled out: vertex colors, normals, texture; EditableMesh works in Edit mode for reading meshes.) Items 11 + 2: the "idling on edges" was Overwatch lookouts (`Overwatch_EdgeInset` 3 -> 5); new `Modules/EdgeAwareness` publishes `NearEdge` and steps a Quin in when Idle or on the arena wall (rule never fired in tests). OPEN: nothing uses `NearEdge` in Fight/Circling yet; item 6 knowledge record; platform dismount by chosen jump.

**Pass 67 (item 6):** the knowledge model ALREADY EXISTS: `QuinCore/Cognition` (Senses sight/hearing/touch, Memory tracks, ally reports, rumour; `Cognition.contactFor(quin, enemy)`). Do not build another. Fixed: `TargetHasLoS` had two partial writers (50 % wrong on hidden targets) -> Main writes `TargetHasLoS` + `TargetKnownBy` each tick from the contact (3 % wrong); `SpatialModule.checkLineOfSight` now RespectCanCollide. Mind panel says how it knows. "Common sense" still later. Remaining: platform dismount by chosen jump (Pass 63 diagram); `NearEdge` unused in Fight/Circling.

**Pass 68:** jump down off a platform: `TraversalModule.solveJumpDown` (arc grows with the distance, lands ~7 studs in front of the target, only when it clears the ledge); `LocomotionModule.jump(..., flightTime)` holds the launch speed in the air (the chase's braking pace used to cut jumps 40 % short). Staging trap: a calm confident Quin is `casual` and WALKS off ledges (Pass 46); to test dives set `SocialUrgency` 1 every frame. `DiveSkip` attribute says why no jump. The 25-item list of 2026-10-05 is now through its first pass on every item; open follow-ups: `NearEdge` unused in Fight/Circling, "common sense" knowledge, natural-play check of jumps down, owner's by-eye review of everything since Pass 51.

**Pass 70 (`99e2f19`):** owner's demo loop (hurdle / sweep / wall run / wall run + dash) now 8/8.
- Dash off the wall happens at the TOP of the run (`AirDash.fromWall`, asked once by WallRunState at rise<=0, >= `AirDash_WallMinHeight` up). The end-of-arc kick leaves from floor height (Pass 62 per-frame arc), no air for a dash.
- TRAP: `TargetingModule.getNearest` is NOT a query: it assigns targets and CLEARS the Quin's target when nobody is in range. Use `getEnemiesInRange(rootPart, r)[1]` for a look. WallRun and Airborne both wiped their target this way (fixed); other states still call getNearest on purpose as their selector.
- WallRun added to Main `NO_RETARGET_STATES`. `SlideTackle_Width` 3.0. Forced `TackleOutcome="hurdle"` skips facing/busy.
- Demo staging: wall-dash target at 55 studs along the wall, 21 out (80 was past WallRange at the apex).
