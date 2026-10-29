# Get-up slide, run-up spin, quick evade, run strafe off, bug bookmarks

2026-10-29, Studio (QUIN_COMBATV4). Built from the owner's two inspect cards (Quin_Female_3020: a foot slide in Recovery; Quin_Male_C9AA: spinning on the spot in Chase) and three requests:
- the quick evade should stay in place;
- the run strafe clips should be disabled;
- a better bug report for me to work from.

**Waiting on:** the owner's eye.

## 1. Get-up while still skidding (foot slide)

**Cause.** `RecoveryState.enter` played the get-up clip at once, while the knockback skid was still carrying the body. The card shows GetUpBackFastNinja 0.47 s in, at 57 studs/s.

**Fix.** If the body is moving faster than `Recovery_GetUpMaxSpeed` (8 studs/s), the get-up clip is held on its first frame, down on the ground. It rises once the body has slowed, or after `Recovery_SkidWaitMax` (1 s) at most. The state's timer starts from the rise.
- Switch: `Recovery_WaitForSkid = false`.
- Probe attribute: `GetUpHeldForSkid`.

**Measured:**
- The first bookmark showed GetUpFrontFast held at speed 0 while the body went 51 → 23 → 15 studs/s, then rising.
- 66 held get-ups in 70 s of a 16v16.

## 2. Spinning on the spot ("Backing off for a run-up")

**Cause.**
- Two climbs (`ChaseState/Climb`'s jump onto a perched target, and `ChaseState/Obstacles`' high-ground climb) re-decided the back-off every frame.
- It turned away from the ledge and ran. Once far enough, it turned back toward the ledge at a run, which carried it too close again.
- Meanwhile "Going round", "Run-up for a jump" and the other branches took over in between: up to 9 flips per 50 s, 10 a second at its worst.

**Fix.** `Climb.runUpBackOff`, shared by both climbs:
1. It backs off to a spot fixed when the back-off starts (`RunUp_BackOffStuds`, 14).
2. On that spot it brakes and turns to face the ledge (the Facing turner, holder "Idle").
3. Only then is the run-up and jump the caller's again.

A back-off under way is seen through first, at the top of `Climb.update`, so no other branch takes the body in between. It gives up after `RunUp_BackOffMaxTime` (4 s).
- Switch: `RunUp_Committed = false`.
- Probe attribute: `RunUpBackOffs`.

**Measured:** 1 back-off and 1 flip in 70 s. Back-offs are rare per match; judge by eye on a map with high platforms.

## 3. The quick evade stays in place

**Cause.** The quick evade clip is an in-place lean, but three places pushed the body under it:
- **Instinct's slip:** 35 studs/s for 0.25 s, about 8 studs.
- **Fight's dodge, when no strike is coming:** 12 studs/s, about 3 studs.
- **`Evasion.evade`:** the clip's sway driven by physics, about 1.4 studs at about 10 studs/s.

**Fix (`QuickEvade_InPlace = true`):**
- No push.
- The sway is driven at 0, so the evade holds the body where it stands against drift along the lean.
- The speed the body came in with is stopped at the start of the evade.

Set `QuickEvade_InPlace = false` for the old behaviour.

**Measured (body speed while the evade clip plays, 60 s 16v16):**

| | Before | Sway off | + stop on start |
|---|---|---|---|
| Mean speed | 9.9 studs/s | 7.3 | **5.4** |
| Frames over 6 studs/s | — | — | 32% |

What's left is likely other movers during the lean (the strike's spacing, a hit). Not traced further.

## 4. Run strafe clips off

`CombatConfig.Strafe_RunClips = false` (owner: "just disable it"). Turned off in three places:
- `GaitModule`'s strafe mode;
- `GaitModule`'s diagonal blend (`toRun` = 0), which still mixed them in after the first switch;
- `CirclingState`'s run pace, which becomes the walk pace.

**Measured:** 0 frames with a run strafe clip at weight > 0.3 (was 1921 in 70 s).

**The cost:**
- Quins moving sideways faster than the walk strafe can step (its 1.6× cap is about 11.7 studs/s) now slide their feet.
- That is 22% of the walk strafe frames (1303 of 6031), mostly in Fight (794) and Chase (220).
- Fix options: cap sideways speed in a fight at the walk strafe's pace, or polish and turn the run clips back on.

## 5. Bug bookmarks (debugger)

Press **N** in Studio Play: the recorder saves the last 6 s of the spectated Quin (or the one nearest the middle of the screen) as text. The report holds:
- where it stands and on what part;
- its target;
- the state at the start;
- a timeline every 0.1 s: state, speed, fall speed, facing, turn rate, humanoid state, top 3 clips;
- every change, with its time.

Bookmarks are numbered and kept in `PlayerScripts.QuinRecorder.Bookmarks` until Play stops. Tell Claude "bookmark 3" before stopping Play, and it reads them directly.
- `BookmarkSeconds` changes the length.
- Test trigger: `QuinRecorder.Query:Invoke("bookmark")`.
- **Not built:** the range-select slider.

## 6. Sideways speed capped in Fight (follow-up, same day)

The owner said "cap it". `CombatConfig.Fight_MaxStrafeSpeed = 11.5` (the walk strafe at its 1.6× cap). It only applies while `Strafe_RunClips` is off, and only to the Quin's own motion: a push through ImpulseModule (hit, knockback, a strike's lunge) is left alone.
- **`LocomotionModule` steer driver** (every frame, in Fight): the driven speed is limited to cap ÷ sin(angle between heading and facing).
- **`FightState`** (each tick): any leftover sideways speed above the cap is trimmed off the root's velocity.

**Measured (50 s 16v16), Fight frames with the walk strafe moving faster than 13 studs/s:**

| | Before the cap | Trim in FightState only | + steer driver |
|---|---|---|---|
| Share of Fight walk-strafe frames | 30% | 28% | **21%** |
| Of those, under a push | 452 of 848 | 401 of 728 | 333 of 579 |

- The rest is mostly being pushed (hits, knockbacks, lunges), and the cap leaves that alone on purpose.
- **Hit rate:** 61% (320 of 526). It was 60–66% in earlier runs.
- **Server frame, mean:** 25.8 ms.
- **Errors:** none.
- **Strikes per 50 s:** 526 vs 725 in the run before. Could be run-to-run variance or slower approaches: re-measure if fights feel slower.

## 7. Range comments on the pause timeline (QuinReplay)

The owner's idea: "select the range then write a comment ... per quin ... stays as long as I'm on pause".

**How it works:**
1. A strip sits under the scrubber: "drag here to mark a range and say what's wrong in it".
2. Dragging across it marks a range of the followed Quin, shown in gold on the strip and over the timeline.
3. On release, a comment box opens with focus. Enter or **Save** keeps it; Esc or **Cancel** drops it.
4. A saved range becomes a bookmark: `QuinRecorder.report(name, from, to, note)`, the same report as N plus an `OWNER'S NOTE:` line, cut to the range. The time label says which number to give Claude.
5. Saved ranges stay drawn (numbered, with their note) on that Quin's strip while paused. Closing the pause clears the drawings; the reports stay until Play stops.

Ranges shorter than 0.05 s are ignored. With no Quin followed, the strip asks for a click on a Quin first.

**Test handle:** `QuinReplay.Control:Invoke("mark", { from = 0..1, to = 0..1, comment = "..." })`. Tested once: the range was drawn and bookmark 1 carried the note and a 4.5 s timeline. Not tried by hand: the drag and the typing need the owner's mouse.

## 8. Report clean-up, Space playback, fly fix (same day)

**Bookmark report:**
- The target line shows the target at the end of the range, with "(it started on X)" when it changed.
- CHANGES leaves out MatchScore, InterestPos, EscapeFeasibility, OccupiedQuadrants and numeric `…At` / `…Until` / `…Since` timestamps.
- N pressed during a pause now cuts the range to the last recorded frame. Before this the report was empty, because the recorder stops while frozen.
- The floor line no longer reads the replay ghost's own clothes.

Tested in a 16v16: 45 timeline rows and 54 changes from N while paused; a range comment showed the end target and the start target.

**Space in the pause:** plays the recording on at normal speed from the white line; Space again stops it, and it stops by itself at the pause. Measured: the cursor moved about 1.05 s per second and stopped at the end. Space also lifts the free camera (SmoothCamera, not touched).

**F fly (`TheArchitectCode`):** the hover ray pointed up and hit the flyer's own head, so the body rose every frame, and it took seconds to glide to a stop. With `flyHoldStill = true`, the ray looks down past the body and only lifts off the ground, and letting go stops the body dead. Measured: 0.01 studs of drift in 4 s with no keys. Setting `false` gives the old behaviour.

## 9. No spinning during a strike (owner's bookmarks 2-6)

**What the bookmarks showed:**
- Quin_Female_F4AB punched while turning 450–730°/s. The Fight facing gyro (`FightState.faceTarget`, responsiveness 22, 45 in a rear turn) follows the current target at full speed, even while the Quin's own strike plays.
- The hit box (`HitboxModule.castInFront`) and the knockback direction (`applyHitOutcome`: `rootPart.CFrame.LookVector`) both use the facing at contact. So a punch swung round hit Quin_Male_1481, who stood behind her, and threw him the way she had turned.

**Fix:**
- `FightState.throwStrike` records the line the strike is thrown along: the body's facing at the throw, and the Quin it was thrown at.
- Until the strike's cancel point (`data.actionEndTime`, which the hit-stop extends), `faceTarget` holds that line. It turns after the struck Quin at no more than `Fight_StrikeTurnRate` (180°/s) and never after a new target. The rear-threat turn and target switches take the body only after that.
- Switch: `Fight_StrikeFacingLock = false`. Both tunables are read with defaults in code; CombatConfig has no new lines.

**Measured (50 s 16v16, lock on), strike frames in Fight:**
- 21,793 frames: 1.6% over 300°/s, 0.5% over 500°/s, max 880°/s.
- 631 StrikeSeq ticks.
- What's left is likely the root carried by other movers (hits, knockback), not the gyro.

**Not measured:** the same numbers with the lock off. The run timed out and the Studio connection got stuck. Probe: ServerStorage `StrikeTurnProbe(seconds, tag)`, result in the Workspace attribute `StrikeTurnProbe_<tag>`.

## 10. Late knockback reaction (owner's bookmarks 3-4)

**Cause.** It's not the hit-stop, which only holds clips for 0.045–0.1 s. The server sets the launch velocity at the contact, and it is at full speed on the first Heartbeat. But the client draws server physics through its interpolation buffer, while clips and attributes arrive at once. Measured over 32 launches, the root started moving on the client 0.18 s after the launch on average (0.10–0.31 s). So the hit landed, the body stood still, then it flew.

**Fix.**
- `KnockbackModule.applyKnockback` and `applyLaunch` publish `LaunchVel`.
- `AIGhostHandler` (Direct mode) has a launch lead, next to `smoothTeleport`. From the frame the launch arrives, the mesh is drawn on the flight path through `RootJoint.C0`: LaunchVel plus gravity, with a ray that stops it short of collidable parts. Once the real root moves (or after 0.45 s), the lead drains over 0.5 s.
- It is off in Death, MidAirClash and ReEntry.
- Switch: Workspace `LaunchLeadOff = true`.
- Client probe attribute `LaunchLeads`.

**Measured (16v16, client, the drawn mesh moving 1 stud after the launch arrives):**

| | Lead off | Lead on |
|---|---|---|
| Mean | 0.148 s | **0.043 s** |
| Later than 0.1 s | 29 of 38 | **2 of 54** |
| Largest frame step | 7.5 studs | 10.7 studs (2 launches over 8) |

No errors.

**Not covered:**
- Ground skids (`applyGroundSkid`, a mover): same buffer, no lead.
- The draining lead makes the body travel a bit slower than the real flight for 0.5 s; judge by eye.
- Ghost render mode (QuinGhost) has no lead.

## 11. Air knockback scaled by the hit (owner: "yup scale it")

**Before:** every air knockback was at least `Combat_LaunchMinForce` 60 × 1.5, then ×1.5 again in `applyKnockback`. So nearly all of them hit the cap, 110 studs/s sideways and 75 up: a jab threw a body as far as a finisher.

**Now:** `Strike.launchForce` sets the launch speed from the move's `knockback` (ComboModule):
- between `Knockback_LightForce` 18 (Jab) at `Knockback_LightLaunch` 45 studs/s and `Knockback_HeavyForce` 105 (PowerPunch) at `Knockback_HeavyLaunch` 110;
- a crit or a hit from behind counts `Knockback_CritWeight` 0.25 heavier;
- the upward part stays min(speed, 75);
- weight and knockback resist still apply in `applyKnockback`;
- other launch paths are unchanged: clash, uppercut launch, specials, rival finisher.

Switch: `Knockback_ScaleByHit = false`. Probe: ServerStorage `ThrowProbe`, plus the `LaunchMove` attribute.

**Measured (50 s 16v16 each, distance from launch to the start of Recovery):**

| | Before | After |
|---|---|---|
| Air launches | 55 | 46 |
| Mean launch speed | 100 studs/s | 47 |
| Median throw | 86 studs | **24** |
| Under 20 / 20–40 / 40–60 / 60–80 / 80+ | 7 / 3 / 4 / 4 / 37 | 21 / 22 / 1 / 0 / 2 |

By move, after:

| Move | Throws | Speed | Distance |
|---|---|---|---|
| Jab | 18 | 38 studs/s | 18 studs |
| Cross | 2 | 48 | 17 |
| DesperateCounter | 20 | 53 | 27 |
| Uppercut | 1 | 58 | 36 |
| Other paths | 5 | 55 | 50 |

- **No finisher launched in this run.** PowerPunch and OverheadSlam still get the full 110 by the formula.
- **Strikes:** 573 StrikeSeq ticks (631 in the strike-lock run). No errors.

## 12. No strikes across height or through boxes (owner's bookmarks, round 2: 1-2)

**Cause.**
- Quin_Male_EB23 stood on a box, 7 studs above Quin_Male_5832, about 4 studs apart sideways. They traded strikes for more than 2 s, and some hits landed.
- `NavigationModule.isReachable` allows `Nav_MaxHeightOnFoot` 7 studs of height (a walk-up), and they were exactly 7 apart. So Chase handed over to Fight, and Fight kept them there.
- The hit check (`Strike.inReach`) measured only sideways distance and never looked for anything solid in the way.

**Fix:**
- **`NavigationModule.canStrikeAt`:** a strike can land only when the target is at most `Fight_StrikeMaxRise` 4.5 studs above and `Fight_StrikeMaxDrop` 5 below (5 matches Chase's "target below → leave the platform"), with no collidable part on the line between the chests (Quins ignored).
- **FightState:** no strike without it (`StrikeHeld` attribute = above / below / wall). It hands over to Chase after the existing 0.5 s grace, unless the target is merely in the air.
- **ChaseState:** "reachable" also needs `canStrikeAt`, so it doesn't hand back to Fight. `Climb` takes the stone climb when the target is above and out of strike height.
- **Strike's hit check:** the limb's landing height (root + clip `height`) must fall within the body (3 below to 2.5 above, ± `Hits_HeightSlack` 1), and the chest-to-chest line must be clear.
- Walking (`isReachable`) is unchanged.
- Switch: `Fight_StrikeHeightCheck = false`.

**Measured (60 s 16v16, check on):**
- 954 strikes in Fight: **0** at a target out of height or behind a wall.
- 820 hits by a Fight attacker: **1** out of height or behind a wall.
- 20 Fight → Chase → Fight flips within 1.5 s.
- A strike held on 2.2% of Quin-frames.
- No errors.

**Not measured:** the same numbers with the check off. Play got stuck on the second run; the probe's temporary "off" edit was reverted. Probe: ServerStorage `HeightStrikeProbe`.

**Not checked yet:** whether Quins now climb onto the box or drop off it smoothly. Watch by eye near boxes.

## 13. Fist and flight in sync (owner's bookmarks, round 2: 4-5)

**Cause.** With the launch lead (section 10), the struck body flies on the client from the moment the hit arrives. Bookmark 4 showed the attacker's clip on the client at 41% when the server struck at 60%.

**Measured:** on average the client's clip is level with the server's (0.003 s). But in 10% of hits (40 of 409) it was still short of the contact frame 2 frames after the hit arrived, so the body flew first.

**Fix.**
- At a landed hit, `Strike` publishes where in its clip it connected: `StrikeContactClip` / `StrikeContactPos` / `StrikeContactAt`.
- `AIGhostHandler.syncStrikeContact` jumps the attacker's clip on the client to that frame if it is more than 0.02 s short. It runs before the launch lead, every frame.
- Switch: Workspace `StrikeSyncOff = true`. Client probe attribute `StrikeSyncLag`.

**Measured (16v16, client, 40 s each):** clip still short 2 frames after the hit: sync off 40 of 409, sync on **0 of 390**. No errors.

**Where the server's contact falls (40 s, clip time):**

| Clip | impactRatio | Hits | Contact (avg, range) |
|---|---|---|---|
| RightPunch (as DesperateCounter) | 0.4 | 43 | 0.62 (0.47–1.00) |
| LeftPunch | 0.6 | 31 | 0.59 (0.48–1.00) |
| HighKickLeft | 0.43 | 20 | 0.34 (0.24–0.36) |
| HighKickRight | 0.43 | 9 | 0.34 (0.28–0.35) |
| LowKickLeft | 0.43 | 23 | 0.50 (0.40–1.17) |
| LowKickRight | 0.43 | 16 | 0.49 (0.47–0.51) |
| WheelDriveLeft | 0.47 | 22 | 0.53 (0.19–0.58) |
| WheelDriveRight | 0.47 | 11 | 0.55 (0.49–0.60) |

None of these clips has HitStart markers, so contact follows `impactRatio`. If a fist still looks short at contact, the fix is the clip's contact point: a HitStart marker (owner authors) or `impactRatio` in AnimationConfig.

## 14. A kick dropped half-way, then a sideways slide (owner's bookmark 8, round 2)

**Cause.**
- Quin_Male_315E kicked out of a 40 studs/s run at a target moving off.
- Fight's "too far" exit (Reach: `ReachBand` sighted) handed over to Chase mid-kick.
- Chase's steer driver then turned the body from the old target toward its new way at 380°/s. Meanwhile the gait played the walk strafe for the sideways motion at 26–30 studs/s. The sideways cap from section 6 only applied in Fight.

**Fix.**
- **FightState:** neither "too far" nor "out of reach" ends the fight while its own strike is before its cancel point (`midStrike`). Switch: `Fight_FinishStrike = false`.
- **LocomotionModule steer driver:** the sideways cap (`Fight_MaxStrafeSpeed` 11.5) now applies in every driven state except Circling and reversals. A body still turning slows to what the walk strafe can step until it faces its way. Switch: `Strafe_CapAllStates = false`.

**Measured (16v16, with the fix):**
- 154 Fight exits in 45 s; only 22 came before the strike's contact frame:
  - 14 knocked back;
  - 3 Retreat;
  - 2 with the target down (Circling);
  - 1 Idle;
  - **2 to Chase.**
- Chase, 50 s: 2.8% of grounded frames sideways faster than 13 studs/s (own motion, no ImpulseLV); mean Chase speed 21.3 studs/s.
- No errors.
- **Not measured:** the same numbers before the fix (the Play restarts keep getting stuck). Probes: ServerStorage `Bookmark8Probe`, `B8b`.

## Not touched

- `QuinDebugHUD` and `SmoothCamera`: another session's work.
- No errors in three 16v16 runs (60–70 s each). Frame time not measured.
