---
name: fight-programme
description: "Owner-approved fighting plan 2026-10-29 (QUINCORE_BACKUP/FIGHT_PROGRAMME.md), steps 0-9; step 0 baseline done (audits/2026-10-29_fight_step0_baseline.md); probe how-to and traps"
metadata:
  node_type: memory
  type: project
  originSessionId: 39f307c0-e7ae-44a5-b9b9-669ff151cd89
  modified: 2026-10-29T02:35:41.782Z
---

Plan: `QUINCORE_BACKUP/FIGHT_PROGRAMME.md`. Five parts: body channels, procedural hits, tagged moves, rules and openings, mind. Ten gated steps, each mapped to files.
- Every step is judged in a 1v1 by the owner's eye, then the 16v16, piloted feel and fps.
- Every piece gets a switch.

**Step 0 done 2026-10-29:** see `audits/2026-10-29_fight_step0_baseline.md`.
- Probes: `scripts/fight_probe_server.lua` and `scripts/fight_probe_client.lua` (new), plus `flow_probe.lua` re-run unchanged.
- Key numbers:
  - roots under 3 studs: about 9% of engaged time;
  - drawn torsos overlapping: 4-9%; limbs inside a body: 3-5%, about 0.45 studs deep;
  - same clip repeated: 22%;
  - phrases: about 1 s; re-entries: about 12 per pair-minute.
- Still open:
  - the tempo split (83-92% "fast") is provisional; calibrate it against the owner's recordings;
  - frame times (16v16 server 21.8 ms) need a clean recheck;
  - the owner's recorded fights are still wanted in `QUINCORE_BACKUP/baseline/`.

**Step 1 built 2026-10-29:** see `audits/2026-10-29_fight_step1_spacing.md`.
- Changes: new `Modules/Spacing` (Heartbeat loop from Server, holds the closing part of motion through an ImpulseModule "space" request), `ImpulseModule.cancelToward`, `reach` per Attacks clip, Strike stops at `StrikeStopGap`, a riposte room limit, `CombatConfig.Spacing_*`, `Ablate_Spacing`.
- Results: roots under 3 studs went 8.9% to 2.0% (1v1) and 9.0% to 3.6% (16v16); torsos 6.7% to 3.1%; hits flat; frame times flat.
- Bodies already collide through CollisionBody, so there is no "real collision" switch.
- The owner approved it by eye on 2026-10-29. Not committed.

**Step 2 built 2026-10-29:** see `audits/2026-10-29_fight_step2_channels.md`.
- The AnimationConfig `channel` field (Body/Arms/Legs), with `AnimationModule.channelOf`. In the stop rule, Arms and Legs coexist.
- The Strike publishes `StrikeChannel`. FightState doesn't plant during Arms strikes and drives the gait instead. PCRC keeps the feet planted during them.
- `Modules/ChannelLab` makes arms-only copies (Hips weight 0, legs removed) with temporary Studio ids (RegisterKeyframeSequence works on both server and client in a Studio playtest).
- Test switch: Workspace `Test_ArmsOnlyPunches`. No real clip has a channel yet.
- Waiting for the owner's eye. Then they publish the copies via `saveArmsOnlyPunches()`, or author proper arms clips.

- Round 3: the arms-only copy folds the hips' rotation into the Spine key; it was punching into the air.

**Step 3 round 1 built 2026-10-29:** see `audits/2026-10-29_fight_step3_hits.md`. The owner said hit clips played far too much on weak contact.
- Strike counts a body only within reach + 0.72 + `Hits_ContactSlack`.
- DamageModule plays the hit clip only for heavy, crit, finisher, back hits or posture ≤ 40 (`Hits_ClipOnLight` restores the old behaviour).
- `Spacing_LookAheadMax` 0.75 caps step 2's look-ahead, which was stopping lunges 6 studs out.
- 16v16: hits 64%, whiffs 10%, hit clips on 15% of hits.
- `Reactions.HitLight` is a placeholder that borrows BrakingStop.
- Next in step 3: zones (head/body/legs), the owner's base hit clips, posture as balance.

**Step 3 round 2 built 2026-10-29** (same report). Awaiting the owner's eye.
- Strike `zoneOf`: the AnimationConfig `height` per clip (estimates: punch 1.1, low kick −2.8, high/wheel 1.7) against the target's root, with `Hits_HeadAbove` 1.5 and `Hits_LegsBelow` −1.0.
- `ImpactZone` attribute → PCRC `triggerImpact(..., zone)`:
  - Head: a new head-snap spring.
  - Body: the chest folds in and the hips dip.
  - Legs: the hips drop and the body tips over the struck side.
- `DamageModule.posture()` / `wearPosture()`: lazy recovery of 6/s from `PostureAt`; a whiff costs 6; legs wear 1.6×.
- `Hits_ClipBelowPosture` 40 → 20: recovery made worn bodies common, which doubled the clip rate.
- 16v16: hits 60%, whiffs 6%, interrupted 28% (up from 24, watch it); clips 21% of impacts; frame 21.9 ms.
- Trap: a `multi_edit` with `replace_all` reported success but changed nothing in AnimationConfig. Verify edits by reading the source back.

**Look-back foot slide fixed 2026-10-29** (owner's inspect card: LookingBehind at weight 1 while running at 35 studs/s).
- The cause: `Awareness.RearThreatGlance`, which borrows LookingBehind, is a full-body clip about 3 s long. ChaseState and FightState "anticipate" checked the speed only at its start.
- Now `LocomotionModule.glanceBack` plays it only below `Glance_ClipMaxSpeed` (3) and fades it out the moment the body moves, with `GlanceBackUntil` (head and shoulders) taking over for the rest of the look.
- 16v16, 80 s: 6 glances, the fastest frame held during the fade was 9 studs/s.

**Patterns, navigation and strike height, 2026-10-29:** see `audits/2026-10-29_fight_patterns_nav.md`. Awaiting the owner's eye.
- Knockdowns: `FightState.downedReaction` (press / hold / circle / switch, weighted by personality; attribute `DownedReaction`; `Fight_DownedChoice`).
- `RecoveryState` can step straight back into the fight (`Recovery_ReengageChoice`).
- `Climb` keeps moving between stone hops.
- `nextStone` now requires a real top and checks leaves and the ceiling; stones it failed to land on are remembered for 20 s.
- `QuinSpawner` spawns "Defeated" copies inert from the start.
- `chooseStrike` weighs each clip by height (`Answers_HeightAware`).
- Probe: ServerStorage `PatternProbe`.
- Open: ChaseState's random hand-off to Circling (30% / 20%); strikes thrown from ledges whiff (step 6).

**Strike facing lock (2026-10-29, from the owner's bookmarks 2-6):** the Fight gyro followed the current target at full speed during a strike. Bodies whipped 450-730°/s mid-punch, and because the hit box and the knockback use the facing at contact, a Quin behind got hit. Now `throwStrike` records the facing at the throw, and `faceTarget` holds it until `actionEndTime`, turning after the struck Quin at no more than `Fight_StrikeTurnRate` 180°/s. Switch: `Fight_StrikeFacingLock`. Lock on: 1.6% of strike frames over 300°/s. The lock-off baseline was not measured. Probe: ServerStorage `StrikeTurnProbe`. Still open from the same bookmarks:
- late knockback: FIXED 2026-10-29. It was the client's physics buffer, not the hit-stop: launch lead, see [[server-cframe-teleport-snap]]. Force scaled 2026-10-29 (owner "yup scale it"): `Strike.launchForce` maps the move's knockback (Jab 18 → 45 studs/s, PowerPunch 105 → 110; crit or from behind +0.25 weight). Switch: `Knockback_ScaleByHit`. Median throw 86 → 24 studs; no finisher launched in the sample. Awaiting the owner's eye;
- a Dash pick runs at 22 studs/s into the body without striking;
- the recorder had no clips or speed for Quin_Male_1481;
- the reports need match time so bookmarks can be aligned, and filters for TraceLog / TargetReason / RetreatScore / ClosestRearThreatDist.

**Strike height and wall check (2026-10-29, owner's bookmarks round 2):** `NavigationModule.canStrikeAt` allows a strike only within +4.5 / −5 studs of height with a clear chest line. Fight holds strikes without it (`StrikeHeld`) and hands over to Chase. Chase's "reachable" and Climb's stone climb also use it. Strike's hit check tests the limb's landing height and line of sight. Switch: `Fight_StrikeHeightCheck`. Result: 0 of 954 strikes and 1 of 820 hits across height or a wall; 20 quick Fight-Chase flips per 60 s. Still open from round 2 (audit sections 2-6):
- fist vs flight sync: FIXED 2026-10-29. `Strike` publishes `StrikeContactClip/Pos/At`; `AIGhostHandler.syncStrikeContact` jumps a lagging client clip to the contact frame. Late fists went from 40 of 409 to 0 of 390. Switch: Workspace `StrikeSyncOff`. On average the client clip is NOT behind (0.003 s); only ~10% lag. Contact frames follow `impactRatio` (no HitStart markers on the punches or kicks); a fist that still looks short needs the owner's marker;
- Fight→Chase drops a kick mid-swing: FIXED 2026-10-29. Fight stays until the cancel point (`Fight_FinishStrike`); the sideways cap now covers every driven state but Circling (`Strafe_CapAllStates`). Only 2 of 154 exits now go to Chase before contact;
- the owner asked (2026-10-29) about leg IK for more natural legs, "especially during state transitions". The IK Lab verdict stands (clips + a small foot layer; QuinCore has its own foot solver in PCRC). Proposed next: measure the transition foot slide first (ToeBase speed while planted: idle↔walk, Fight footwork, Recovery→Chase), then fix the gait blend and add a foot lock. MEASURED 2026-10-29 (`audits/2026-10-29_transition_foot_slide.md`). Planted toes slide (> 2 studs/s) 79% at starts, 70% at Recovery exit, 62% on turns, 47% at stops, versus 2% still. The main cause is strike lunges with the feet held by the clip, then Recovery's move clips running in place, then strafe pace. Proposed: foot lock first, then the speed-matched gait blend. Probe trap: FightIdle is always weight 1 (Idle priority), so pick the top clip above Idle. FOOT LOCK BUILT 2026-10-29, the same audit: three new PCRC layers, StrikeStance / PlantGlide / PlantLowHold (each `Layer_*` attribute, default on). Sliding went 59% → 37% overall; strikes 69 → 44, starts 70 → 37, stops 36 → 18. Awaiting the owner's eye. Not committed. GAIT BLEND step (same day): GaitModule already speed-matches; a 0.18 s presentation delay on its velocity was tried, measured null (starts 50 → 50, stops worse) and REVERTED byte for byte. Legs moving while still are mostly strike and get-up clips (authored), plus ~13% walk/run in place. Starts now slide because a pinned ankle's toe still moves (lock at full weight slides 47% at starts: turnDampen above 4 rad/s, plus toe yaw). TOE FIX BUILT (same day): two PCRC layers. PinnedYaw holds a pinned foot's direction (60° cap, eases back after release). PlantTurnHold keeps full lock weight below 6 studs/s through fast turns. Sliding 40% → 33% (starts 50 → 33, stops 23 → 12, Recovery exit 46 → 22). Across all three steps: 59% → 33%. OWNER APPROVED by eye 2026-10-29 ("it looks fireee finally!!"); committed and pushed to GitHub the same day. Keep these foot layers on. Open: turns on the spot, steady-run creep. Use the PCRC `FootDebug` reasons (armed / waitLift / lock) to diagnose. Lua trap: `x and nil or false` is always false;
- idle→walk leg shuffle (walk clip at full weight before the body moves);
- a kick clip frozen at its end, maybe from the F4 resume;
- dive landings showing below the ground. FIXED 2026-10-29 (`audits/2026-10-29_pj_landings_below_ground.md`). The real cause is the landing clip NinjaLanding (92021932752253): its crouch takes the hips about 3.6 studs under a standing pose while the body is at standing height. Fix: the `floorFeet` clip correction (PCRC `applyFloorFeet`, CombatConfig.ClipCorrections). Switch: Workspace `ClipFloorFeetOff`. NinjaLanding feet under the floor went 39% -> 0%; landing p90 depth 2.5 -> 1.4. The server stand lift (`PJStandLiftOff`) was tried and taken out: the server root is at standing height about 99% of the time. Trap: the server-side 'sunk' theory was wrong, so measure the client's drawn hips relative to the root and the top clip first. Still open: a few frames from other clips; case B (hips 8 under the root at the Init take-off, Run clip); dives into the floor at speed (kept). Awaiting the owner's eye;

**Probe traps (hits):**
- `AnimationIds.Hits` is a metatable proxy, so `ipairs` sees nothing; match the clip ids instead (83869147275692 light/knockback/braking, 82096408080514 heavy).
- A dev-command match needs `"InstantMatch":true`, or it runs the full 2-minute pre-match show.

**Edit traps:**
- The tail of CombatConfig uses `CombatConfig.X = v` statements, not table fields.
- CombatConfig uses CRLF line endings. Appending to a matched line lands after the `\r` and breaks the file.
- An MCP execute_luau gets its own copy of required modules (its own ImpulseModule tables). Observe instances or attributes, not module state.

**Probe traps:**
- `ArenaDevCommand start` keeps the previous Mode unless `"Mode"` is passed.
- The Server has no loadstring: put the source in a new ModuleScript in ServerStorage and require it.
- The default render mode is Direct (no QuinGhost folder): `WaitForChild("QuinGhost")` on the client hangs the MCP call and can drop the Studio connection.
- A client probe's result lands a few seconds after the server's.

Related: [[quin-creature-vision]], [[no-refactor-spiral]], [[combat-whiff-audit]], [[visual-bug-testing]]
