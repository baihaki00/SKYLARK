# QuinCore general audit (item 17): what can be improved

Written after Pass 58. Every number below was counted from the code in `studio_snapshot/` at
commit `bd79f89`, or comes from a measurement in an earlier pass (named). Nothing here was
changed; this is a list to choose from. Where a cost was **not** measured, it says so.

## The short version

Ranked by how much each one explains things the owner has actually complained about:

1. **Who decides the target is not one place.** 19 writes of `CurrentTarget` in 7 files; only
   one of them goes through the commitment rule from Pass 43. This is the rest of item 22
   ("chaotic and indecisive").
2. **Two clocks at 10 Hz and 60 Hz write the same body.** The AI thinks ten times a second;
   everything that has to be exact grew its own per-frame loop. Where both write the same mover,
   there is a race. Two visible bugs so far came from this (dive "bob", Pass 22E; turn-leg stop
   or overshoot, Pass 52).
3. **What a Quin knows is not modelled.** The server's `TargetHasLoS` was wrong 59 % of the time
   against a head-to-head ray (Pass 48). Item 6 (seen / last seen / memory) has nothing reliable
   to stand on yet.
4. **The config lies in 86 places.** Code carries its own fallback numbers, and 86 of them differ
   from the real config value. 13 settings are used but never defined.
5. **Three time bases.** `tick()` 98 times, `os.clock()` 115, server time 12; 14 files mix two.
   One real bug already (wall run ended on its first update, elapsed = 1.7e9 s).
6. **No standing probes.** Every pass rewrites its measurement script. Regressions are only found
   when the owner sees them.

## 1. Target ownership (item 22, the remainder)

`SetAttribute("CurrentTarget", ...)` sites inside QuinCore:

| File | Writes | Through the commitment rule? |
|---|---|---|
| `TargetingModule` | 9 | `selectTarget` only (Pass 43) |
| `ChaseState` | 6 | no (re-acquire, distraction, rear threat, give-up) |
| `Main` | 1 | writes what `selectTarget` returned |
| `FightState` | 1 | no (rear threat) |
| `OverwatchState` | 1 | no (prey) |
| `AirInterceptModule` | 1 | no |

Pass 43 measured target switches falling from 29 to 16 per Quin-minute, with 29 % still flipping
straight back. The writers above are the likely remainder (not yet measured per writer).

**Improvement:** one door. `TargetingModule.setTarget(fighter, target, reason)` applies the hold
and the margins; a state *asks* with a reason ("rear threat", "distraction") and an urgency, and
gets yes or no. The reason goes to an attribute, so the mind panel can show *why* a Quin turned.
The same shape applies to `ForceState` (27 writers), though no complaint traces to it yet.

## 2. The 10 Hz mind and the per-frame body

`Main` updates a Quin's state every 0.1 s. Per-frame loops exist beside it: ImpulseModule, the
steer driver, the projectile-jump guard, the sweep flip, GaitModule's ground contract, the client
body layers.

That split is right. The trap is two writers on one mover:

- Pass 22E: a 10 Hz update re-applied slam speed on the frame the guard was setting the body
  down: 4–7 studs into the floor, sprung back.
- Pass 52: the guard zeroed a turn leg on time, the update re-applied it, then switched the
  force off: 1000 studs/s of drift, or a dead stop, depending on which ran first.
- Pass 52 also removed a third: the update wrote an upright facing during the dive, the guard a
  head-first one, alternating.

**Improvement:** a rule rather than a refactor: *in any phase, one loop owns each mover; the
other only changes the phase.* Worth checking against it: `KnockbackState` vs ImpulseModule,
`WallRunState` (10 Hz arc; its velocity is stepped ten times a second, which may be item 12's
"laggy after touching a wall": **not measured yet**), `LocomotionModule.slide`.

## 3. Knowledge (item 6)

- `TargetHasLoS` (server) disagreed with a head-to-head ray in 59 % of samples (Pass 48).
- `LookController` now does its own ray on the client, so the *head* is honest, but decisions
  on the server still use the unreliable flag or no sight test at all.
- There is `LastSeenTargetPosition`, written in a few places, cleared on target change.

**Improvement:** one small per-Quin record on the server, `{ seenNow, lastSeenAt, lastSeenPos,
heardAt }`, refreshed at the AI tick with one proper ray (head to head, platforms block), and
read by Chase / Targeting / Look. "Common sense" (1v1: the footsteps under the platform are the
target) is then one more writer of the same record. This is the base for item 6 and for item 11
(a Quin that knows it is near an edge is the same kind of fact).

## 4. Config

- 742 keys in `CombatConfig` (1033 lines).
- 440 inline fallbacks of the form `CombatConfig.X or <number>`.
- **86 of those differ from the configured value.** Harmless while the key exists, misleading
  when reading the code, and wrong the day a key is renamed. Examples: `ChaseRange or 60`
  (config 800), `BaseStunDuration or 0.5` (config 1.5), `AttackCooldownMax or 1.5` (config 0.7),
  `WallRun_SinkSpeed or 8` (config 22).
- **13 keys are read but never defined**, so they silently run on the fallback and cannot be
  tuned from the config: `Nav_AgentRadius`, `Nav_ClearHoldTime`, `Nav_MaxHeightOnFoot`,
  `Nav_OffPathDistance`, `Nav_PathRefresh`, `Nav_SweepHeight`, `Gait_AutoDriveInterval`,
  `Gait_StartFade`, `Gait_WeightFade`, `HighGround_VantageDistance`, `EnergyDrain_PointJump`,
  `BeamStruggle_MaxDuration`, `ProjectileJump_TurnLegSlope`.
- Many keys look unused (a text search finds ~290 with no reference), but that count is inflated
  by modules that build key names (`cfg("Chance")` → `AirDash_Chance`) and by nested tables. A
  true list needs a runtime check.

**Improvement:** define the 13 missing keys (zero behaviour change); then a Studio-only check at
start that warns for a key read but not defined. Fallbacks can be dropped file by file whenever a
file is touched anyway.

## 5. Time bases

14 files use both `tick()` and `os.clock()`. Attributes carry timestamps across modules
(`LaunchedAt` is `tick()`, `SweptAt` is `os.clock()`, `ImpactTime` is server time), and the
reader has to know which. **Improvement:** one rule: `os.clock()` for anything compared on the
same machine, server time only for what a client compares. Fix on touch.

## 6. Measurement

Probes written and thrown away so far: hit / whiff rate, target switches, strafe toe slide, knee
angles, projectile-jump speed by phase, sweep timeline, wall-run arc, death floor clearance.

**Improvement:** keep them. A Studio-only `Probes` module driven by a Workspace attribute
(`ProbeCommand = "pj_speed 60"`), each writing one result attribute. Then every pass can re-run
the earlier passes' numbers in a minute, and the layer on/off comparison the port plan asked for
(`layer_ablation`) is one of them.

## 7. Smaller things

- **Size.** `ChaseState` is 1498 lines: pursuit plus the decisions for slide, tackle, wall run,
  high ground, casual drop, intercept jump and projectile jump. `LocomotionModule` 1502,
  `ProceduralCombatReactionController` 1508. Not a bug; each traversal decision could be a small
  module asked in turn (as `SlideTackle`, `AirDash`, `HeadroomAwareness`, `ArenaTrespass` already
  are). Do it only when one of them is next changed.
- **Attributes as the bus.** 268 distinct attribute names are set inside QuinCore (722 set
  sites); all replicate to every client. Network cost **not measured**. A written contract exists
  only for the social layer. Debug-only attributes (`TackleView`, `AirDashSkip`, `LookDbg`,
  `FootDbg`) could be set only while a debug switch is on.
- **Allocations.** 47 `RaycastParams.new()`, 43 of them inside functions that run per tick or
  per frame. Earlier passes measured no frame-rate cost from the body layers; this was **not**
  measured separately. Low priority.
- **Lazy requires.** 138 `require(script.Parent...)` calls inside functions. Cheap after the
  first, but they hide which states depend on which (the state graph is circular by nature).
- **Animation library.** No trip / fall-to-the-ground clip; three get-up clips have no vertical
  hips travel (covered by a ground correction, Pass 44); borrowed clips bring their markers with
  them (Pass 57). All clips are now fetched at session start (Pass 58).
- **Repo.** 68 loose `.lua` files sit at the top of `QUINCORE_BACKUP/` beside `studio_snapshot/`
  (older copies of the same scripts). They are not what Studio runs. Worth moving to an
  `_old/` folder or deleting, the owner's call.
- 63 `print(` calls inside QuinCore; 1 "Temporarily disabled" block (`KnockbackState` air arc).

## 8. Still waiting for the owner's eye

Nothing below has been confirmed by looking, only by numbers: head sight rules (Pass 48), the
soft landing walk-on (47), trespass numbers (49, my guesses), death glitch and one-by-one
teleport (51), projectile-jump dives (52), air dash (53), slide tackle and sweep flip (54–58),
wall run look and the hand on the wall (55, 58), Footfall / loose wrists / breathing (42).

## Suggested order

1. Target ownership (finishes item 22; the mind panel, item 14, gets its "why").
2. The knowledge record (item 6), then edge awareness on top of it (items 11, 2).
3. Wall run stepped per frame, measured against item 12.
4. The 13 missing config keys and the Studio check.
5. The `Probes` module.
