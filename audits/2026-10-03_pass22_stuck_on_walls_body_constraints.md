# Pass 22: body constraints, starting with Quins "stuck on tall walls like a spider"

Base: pass 21f (`debb367`). Plan: `plans/cached-orbiting-flurry.md`, items A-G.

## A. Stuck at high obstacles

### Measured (16v16, 2 min, server; Quins more than 20 studs up, by the OB part under them)
Quins dived onto the **tops of the arena's tall thin walls** and stayed there in Overwatch:
- 7 × 18 wall tops at 57 and 107 studs up;
- an 8 × 36 slab top at 80 studs up.

Each perch lasted **15-30 s**. Seen from the ground, that is a Quin stuck up a wall.

### Cause
- `OverwatchState.heldPlatform` accepted any `PlatformCatalogue` platform at least 12 studs above the floor.
- The catalogue's minimum top width is 5 studs, so wall and pillar tops counted as lookouts worth holding.

### Fixes
- **Overwatch** only holds tops at least `Overwatch_MinTopWidth` (10) studs wide in both directions. A Quin landing on a narrower top goes on chasing and drops down.
- **ProjectileJump dive (every style except 5):** the dive had no path check and no time limit, so a dive line crossing a tall obstacle pressed the body into the wall face with unlimited force, indefinitely. Not caught in a run, but it is a real failure mode in the code. Three guards:
  - **wall probe:** the dive probes ahead along its line (`ProjectileJump_DashWallProbeTime`). A wall (|normal.Y| < 0.5) goes to Impact, which drops the body, easing off the wall face;
  - **stall guard:** a driven phase that moves less than 1.5 studs in 0.4 s comes down (`ProjectileJump_StallTime`, `_StallDistance`);
  - **hard cap:** a whole jump lasts at most `ProjectileJump_MaxStateTime` (8 s).
  - The debug attribute `PJGuard` shows which guard fired.

### After (16v16, 2 min)
- Narrow tops (7 × 18, 7 × 25, 2 × 8 × 36): left within about 1 s (Chase).
- Overwatch now held only the big tops (47 × 59 block, 70 × 77 slabs).
- 107 projectile jumps; the stall guard fired once; 0 errors.

### Found during regression (Play As Quin)
- **Every punch errored:** `executePlayerAttack` passed an options table to `AnimationModule.play`, which takes positional arguments ("Unable to assign property Priority"). Fixed.
- **Release fired 21 times:** `Release` yields on the server while the per-frame loop, seeing the costume gone, called release again every frame. Each call reloaded the avatar, which could undo the next possession. The session now stops locally first, then releases once.
- **Verified:** possess → punches (no error) → release (once) → possess again. Arena System 4v4 reaches IN_GAME with 8 Quins and 0 errors.

## B. One-frame T-pose blips (Circling)

### Measured (client; a frame counts when 90%+ of a visible Quin's bones are at identity)
- FFA 32: 5 blips in 9 s, all in Circling.
- 16v16: 0 in about 27k Quin-frames (rare).
- **In the blip frame** only two tracks were left, both fading to 0: the fight-idle loop (asset 109837817595150, WeightTarget 0) and a finished punch.

### Cause
- `Attacks.Specials.BeamStruggle` and `Awareness.AssessTarget` use the **same asset as the fight idle**. AnimationModule caches one track per asset id, so they *are* the fight-idle track.
- `stopCategory("Attacks")`, run on entering Circling and Fight, therefore stopped the base idle itself.
- The body had no pose until the 0.1 s no-pose watchdog restarted the idle.
- The Survey/FightIdle shared track (the pass-15 suspect) is the same family of bug: playing SurveyIdle turned the idle into a one-shot.

### Fixes (AnimationModule, AnimationConfig)
- `stopCategory` (both copies in the module) never stops an Idle-priority track.
- **Own tracks for entries that share an asset:**
  - a config entry with `trackKey` gets its own track (`id#trackKey`, loading the same asset);
  - used by `SurveyIdle`, `AssessTarget` and `BeamStruggle`;
  - all path-based play/stop resolution goes through it.
- `ensureBaseIdle`'s duplicate-track prune no longer destroys a track the module caches under another key.

### After
- FFA 32: **0 blips** in 2 × 9 s (about 4,500 Circling Quin-frames).
- 0 server errors.

## C. Feet sliding in Fight and Chase

### Metric
16v16, 45 s, server. A frame "slides" when the Quin is moving more than 2 studs/s and has had no clean planted foot for 0.4 s. The clip on the legs is the highest-*priority* track above 0.3 weight.

### Before
- **Overall:** Fight 31.4%, Chase 29.6%.
- **By cause:**
  - action clips on top of a moving body;
  - walk and jog speeds;
  - the strafe-run at mid speed.

### Causes found and fixed
1. **Start-run push-off overlay** (`Movement.IdleToRun1/2`, Retreat's `StartSprint`; one asset).
   - It played full-body over an accelerating body and slid on ~65% of its frames at *any* speed: 1,710 sliding frames, about 19% of all sliding.
   - The gait starts from rest on its own, so `Chase_PushOffOverlay = false`.
2. **Steering during a strike:** Fight kept steering at up to 40 studs/s under the punch clip, and punches on the run slid on 56-59% of frames. The body now brakes while its own strike plays (`Fight_PlantWhileStriking`); the strike's lunge is the step.
3. **Jog authored speed wrong:** `Gait_JogAuthoredSpeed` was 8.4. The pose lab measures the stance foot at **9.85** studs/s (walk 7.04 and run 29.29 match their config). The jog cycled 17% fast, so the feet ran backward through the jog band.
4. **Gait updated too rarely:** states drive it at 10 Hz and the base-layer fill ran at 20 Hz.
   - At 80 studs/s² the speed moved 4-8 studs/s between updates, so the blend trailed it by 2-3 studs/s (walk still weighted at 12 studs/s).
   - The fill now runs every frame (`Gait_AutoDriveInterval` 0).
   - The blend fades are shorter: `Gait_StartFade` 0.06, `Gait_WeightFade` 0.04.
   - Server heartbeat 13.7 ms with 32 Quins.

### After (excluding clips meant to glide: run-slide, jump, fall, dash, hit flinch)

| | before | after |
|---|---|---|
| Chase | 29.6% | **13.0%** |
| Fight | 31.4% | **21.0%** |

- **Per-speed slip:** run speeds (18-40 studs/s) within ±2 studs/s.
- **Left:**
  - the 10-13 band during hard acceleration (fade lag);
  - in Fight, strike lunges: the lunge mover pauses the gait and the punch clip owns the legs (the designed step into the punch);
  - in Fight, the strafe-run at mid speed (87%), which goes to item D.
- 0 errors. Arena System and Play As Quin pass.

## D. Diagonal blending (forward + strafe)

### Before
`GaitModule.update` hard-switched the legs by the motion's angle off the facing:
- under 50°, the forward cycle (crabwise between about 25° and 50°);
- 50-130°, a full strafe clip;
- over 130°, the forward cycle played in reverse.

The strafe clip ran on its own clock, not in step with the forward set.

### Pose lab (Edit, the rig clone)
- **Strafe authored speeds:** the lateral stance-foot speed is walk **7.3** (config said 6.5) and run **18.9** (config said 18.5). Both are corrected; Circling uses them too.
- **Plant phases were inconsistent.**
  - Measured as the centre of the left toe's stance window (mid-stance), the forward clips' left foot is at walk 0.550, jog 0.433 and run 0.479.
  - Config said 0.31, 0.34 and 0.46, i.e. three different stance points. Walk sat about a quarter cycle off the others.
  - All plant phases are now mid-stance. The strafes are at L-walk 0.562, L-run 0.521, R-walk 0.529 and R-run 0.575.

### Change (`Gait_DiagonalBlend`, live A/B: Workspace attribute `GaitDiagonal`)
One continuous blend replaces the switches: the forward set plus the strafe set of the side the body moves toward (walk→run strafe blended by speed, 8-13 studs/s).

With the motion split into a forward part `a = s·|cos|` and a sideways part `b = s·sin`, and the per-cycle stride of each set `S_f`, `S_s`:
- `cadence = a/S_f + b/S_s`;
- `w_fwd = (a/S_f)/cadence`, `w_side = 1 − w_fwd` (exact under linear pose blending);
- every clip plays at cadence × its length on one canonical phase;
- reversed forward clips run that phase mirrored, so the left foot still lands with the strafe's;
- the side flips with 0.75 studs/s of hysteresis.

Bug found on the way: `hasForeignLocomotion` saw the blend's own strafe tracks as foreign and switched the base-layer fill off under every diagonal. They now count as the gait's own.

### Result
16v16, 4 min, alternating on/off every 10 s:

| | mean planted-foot slip (studs/s), off → on | sliding frames %, off → on |
|---|---|---|
| Chase 25-50° | 17.0 → 15.4 | 37.3 → 34.3 |
| Chase 70-110° | 25.8 → **18.2** | 36.7 → 27.6 |
| Circling 50-70° | 16.0 → **12.4** | 44.8 → 43.4 |
| Circling 70-110° | 8.0 → 6.3 | 20.0 → 21.4 |
| Fight 50-70° | 18.7 → 15.8 | 29.2 → 30.1 |
| Fight 70-110° | 18.8 → 16.6 | 29.9 → 28.6 |
| Chase all | 7.3 → 7.2 | 18.0 → **14.6** |
| Fight all | 16.4 → 15.9 | 19.4 → 20.4 |

- In the diagonal bands, the planted foot skates 10-30% slower. The pop at 50° is gone (not visible in these numbers; owner to check on screen).
- How often a foot slides at all is about unchanged in Fight. What is left in those bands comes with the body turning while a foot is planted (item F's foot pin), not from the clip choice.
- Before the mid-stance phases, the blend was *worse* than the switches (Fight 29.0% vs 22.3%). The out-of-step feet were the cause.
- 0 server errors. Arena System reached IN_GAME. P to possess works.
