# 16v16 Baseline Match — Observation Record (2026-10-01)

No game code was changed for this record. Baseline code is commit `85a4963`
(branch `audit/16v16-baseline-20261001`, `studio_snapshot/`). In-Studio copy:
`ServerStorage.backup_pre_16v16audit_20261001`.

## Method

- Match started through `ArenaNetwork.StartMatch` (same remote as the Arena UI):
  `{ Mode = "TeamBattle", TeamSize = 16 }`, default durations.
- A read-only server recorder sampled every AI Quin at 20 Hz for the whole match:
  FSM state (`CurrentState`), target attributes, planar velocity, root yaw, humanoid
  state, playing AnimationTracks (priority/weight, mapped to AnimationConfig paths),
  eye-height line of sight to the current target (ray from root +3.2 studs, Quins
  excluded), displacement per second, `Attacking`, `LocomotionAction`.
- 201.5 Quin-minutes sampled. Script errors during the match: **0**.

Timeline: ARENA_OPEN 6.4s → GENERATION 16.5s → PREPARATION_ROOM 31.7s →
TELEPORTING 61.9s → PRE_GAME 72.1s → IN_GAME 77.1s → WINNER (Team Alpha,
elimination) 466.9s → POST_GAME 475.1s. Combat lasted ~390s.

## Headline numbers (whole match)

| Metric | Value |
|---|---|
| State transitions | 42.8 per Quin-minute (one every ~1.4s) |
| A→B→A state flips within 2s | 659 (3.3 per Quin-minute) |
| Target changes / quick flip-backs (<3s) | 5.1 per Quin-minute / 101 |
| Stop/start cycles (speed <2 then >6) | 13.3 per Quin-minute |
| Time share by state | Circling 26%, **Idle 24%**, Chase 22%, Fight 14%, Knockback 6%, Recovery 5%, Retreat 2% |
| Heading snaps (>60° yaw in 50 ms) | Fight 16.8/min, ReEntry 12.1/min, WallRun 106/min, Knockback 6.6/min, Chase 2.2/min |
| Circling radius to target | p10 10.9 / median 23.5 / p90 45.1 studs |
| Circling speed spent changing radius | 49% (0% = true orbit) |
| Chase time without eye-level LOS | 6% of 2408s |
| Ground loop (walk/jog/run) visible while airborne | 8.7s total |
| Attacks started / cancelled <0.25s | 1704 / 17 |
| Knockbacks / slides / airborne events | 1135 / 735 / 420 |
| Retreat episodes | 193, median 1.3s, avg 42 studs; exits: Fight 138, Knockback 24, Circling 20 |

Top flip patterns: Recovery→Knockback→Recovery ×139, Knockback→Recovery→Knockback ×133,
Fight→Chase→Fight ×132, Circling→Fight→Circling ×58, Fight→Retreat→Fight ×57,
Circling→Chase→Circling ×33, Retreat→Fight→Retreat ×26, Chase→Fight→Chase ×25.

Example (Quin_TypeB_8C2B, 77s–111s): Chase→Fight→Knockback→Recovery→Chase→Circling→
Chase→Fight→Circling→Chase→Circling→Fight→Chase→Circling→Fight→Circling→Chase→Circling→
Knockback→Recovery→Circling→Knockback→Recovery→Circling→Fight→Chase→Fight→Idle — roughly
one state change per second for 30 seconds.

## Deficiencies (observed → verified cause)

### D1. Quins stand idle mid-battle (24% of all time)
- Observed: Fight→Idle 237 times, Idle→Chase 223 times (first 300s). Mid-match Idle stays:
  median 0.4s, p90 1.8s, max 4.2s. Snapshot: an Idle Quin, `InCombat=true`, WalkSpeed 0,
  visible enemy 25 studs away.
- Cause (verified in code):
  - `FightState.update` re-selects `TargetingModule.getNearest` **every tick**
    (FightState.lua ~line 454) — no target commitment.
  - "Target Transition Buffer" (~line 470): if the nearest enemy changed and is
    > 1.5×CombatRange away, return **IdleState** to "survey".
  - `IdleState.enter` is the match-opening "wave" logic: it rolls a new reaction delay
    (1.2–4.2s for most personalities, IdleState.lua lines 27–56) and holds WalkSpeed 0
    until it elapses (lines 95–100). The clock resets on every re-entry, so every
    mid-match Idle replays the opening hesitation.

### D2. Two target attributes disagree
- Observed: an Idle Quin had `TargetQuin = Quin_TypeB_25D0` and `CurrentTarget = Quin_TypeD_9214`.
- Cause: Idle, Fight and Circling write `CurrentTarget` from `getNearest` (prefers the nearest
  enemy with eye-level LOS, else the nearest overall; no memory); Retreat and other systems
  write `TargetQuin`, which `getNearest` honors as an explicit override. Which attribute each consumer reads is not
  consistent. (Full consumer map: not yet audited — UNKNOWN.)

### D3. Fight snaps heading ~17 times per minute
- Observed: 463 yaw snaps >60°/50 ms in Fight; Fight shows no locomotion clip for 230s
  while moving forward >6 studs/s.
- Cause (verified): `FightState` writes `rootPart.CFrame = rootPart.CFrame:Lerp(lookCF, 0.5)`
  every tick (~line 525) while AutoRotate / steer also rotate the body; combined with the
  per-tick target re-selection (D1), the look target itself jumps between enemies.
- Movement without a clip in Fight: body pushed by `KnockbackModule.applySlide`
  (lunges, melee spacing) while no locomotion clip plays.

### D4. Circling is not an orbit, and the clip disagrees with the motion
- Observed: radius median 23.5 studs (p90 45); 49% of speed is radial. Visible clip in
  Circling: StrafeRightWalk 32%, `Tactics.RetreatBackstep` 32% (see note), StrafeRun L/R 8%
  each, ArcRun30RearRight 6%. Motion vs clip: "moving left / clip backward" 644s,
  "moving forward / clip right" 269s, "moving forward / clip backward" 171s,
  "moving backward / clip right" 141s.
- Causes (verified in CirclingState.lua):
  1. Facing fight: Circling sets `AutoRotate = false` and faces the target with a
     `CirclingGyro` AlignOrientation, but steers through `LocomotionModule.steer`, which sets
     `humanoid.AutoRotate = true` every call. Humanoid rotation and the gyro fight.
  2. Clip choice compares desired move direction against a mix of the desired facing
     (`lookCF`) and the actual `rootPart.CFrame.RightVector` — never actual velocity vs
     actual facing (lines 397–421).
  3. Radius control: ideal radius 16–36 studs, correction gain 0.1 clamped ±1, then center
     pull, edge push, flank offset and tactical overrides are summed into the direction
     (lines 256–358).
  4. Strafe clips play at fixed 1.0× regardless of speed (~16 studs/s at walk tension).
  5. Feint direction reversals pass through `steer`, whose 180° skid logic (speed drop + smoke)
     fires on a sideways reversal (skid logic from the 2026-09-30 locomotion change; it was
     designed for forward running).
  6. Every Circling tick stops all Action+ tracks with a 0s fade (lines 195–202), cutting off
     hit reactions and attacks instantly.
- Note: `Tactics.RetreatBackstep` is the name my recorder resolved for an AnimationId; two
  config paths may share that id (e.g. an ArcRun rear clip). Which config path Circling
  actually requested there is UNKNOWN.

### D5. Chase keeps replaying the push-off; slides are very frequent
- Observed: visible clip in Chase — `Movement.StartSprint` 31%, Run 16%, Slide 13%,
  RunTurn90Right 10%, Jog 9%. 735 slides (~3.6 per Quin-minute).
- Cause (partly verified): Chase re-enters constantly (D1, D6), and each entry at low speed
  selects the push-off clip; tactical slide rolls 18–45% every eligible tick when
  18–35 studs from target (ChaseState ~line 561). Per-entry breakdown: not measured.

### D6. Retreat = "run a bit, stop, fight"
- Observed: 193 retreats, median 1.3s / 42 studs; 138 ended in Fight.
- Cause (verified candidates in RetreatState.lua 183–337): four early exits to Fight are
  allowed after 0.20–0.30s — last stand (EscapeFeasibility < 0.2), pursuer "overshot"
  (`toThreat:Dot(look) > 0.4`, true whenever the runner still faces the threat, e.g. after the
  opening backstep), "reached allies" (any ally within 16 studs — nearly always true in a 16v16),
  and cornered. `minCommitDuration` (1.2s) is declared but unused by these exits.
  Which exit dominates: UNKNOWN (branch not instrumented).
- Retreat movement is a per-tick direction away from threats (`getSafeRetreatDirection`),
  not a destination/route; no pathfinding is involved.

### D7. Knockback ↔ Recovery ping-pong
- Observed: ~270 Knockback↔Recovery flips.
- Cause (verified): RecoveryState never returns to Knockback itself; Quins are re-hit during
  get-up (no protection window). Recovery also lifts the root +1.2 studs, zeroes velocity,
  and always exits to Circling, even with an enemy in melee range.

### D8. Three Quins disappeared before combat (match was not 16v16) — RESOLVED
- Observed: Quin_TypeB_58F8, Quin_TypeD_09F0 (Beta) and Quin_TypeC_8F38 (Alpha) spawned at
  ~31.7s (PREPARATION_ROOM) and were never sampled again; they did not die (no Health ≤ 0
  observed). Orchestrator later counted Beta correctly as eliminated.
- Cause (confirmed by the user): "Play As Quin" three times during the match. `Possess`
  (Server.server.lua) took over the spectated or any living tournament fighter as
  `player.Character`; `Release` then set `player.Character = nil` and reloaded the avatar,
  which removed that fighter from the match.
- Fix (2026-10-01): Play As Quin is now a costume outside the tournament.
  `QuinSpawner.spawn(..., options)` gained `options.costume` (no `Quin`/`AI_Fighter`/team
  tags, no AI `Main`, `IsCostume = true`, parented to `Workspace.PlayerCostumes`).
  `Possess` always spawns the player's own costume at the spawn location (copying the
  spectated fighter's type/element if one is named); `Release` and `PlayerRemoving` destroy
  only that costume. `HitboxModule.cast` only connects hits within the same world
  (fighter↔fighter, costume↔costume). Verified in play: costume untagged, not in QuinServer,
  not targeted, no hits either way; fighters unaffected by put-on/take-off; no errors.

### D9. Minor
- Ground loop visible while airborne: 8.7s total over the match (mostly short).
- Stuck (wants to move, <1 stud displacement/s, grounded, no action clip): 63 samples,
  mostly Circling (17 logged) and Chase (6).
- Eye-level LOS blocked while chasing: 6% of chase time. Chase currently targets by
  nearest-without-LOS; there is no path or last-known-position behavior to inspect yet.

## Not observable in this run (no instrumentation exists yet)
- Perception (FOV, rays, what each Quin believes it sees), target memory / last-known
  position, navigation paths, IK state (`FootIK_Enabled = false`), stopping distance vs
  stop clip, decision reasons. These need the debugger work before they can be audited.
