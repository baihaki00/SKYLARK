# QuinCore audit, 2026-10-27

Scope: `ReplicatedStorage/QuinCore` only (Main, Cognition, Modules, States; 609 functions).
Method: scripted. Every 6-line window of normalised code compared against every other; every
function compared with every other by 4-token phrases; every write of a body/combat primitive
mapped per file; every state change extracted into a graph. Then each hit read by hand.
Scripts: scratchpad `audit.py`, `dupes3.py`, `concepts.py` (re-runnable).

Verdicts: **MERGE** (same job twice, one owner), **DELETE** (dead), **FIX** (a bug), **KEEP**
(looks alike, does different jobs), **ASK** (design call for the owner).

## 1. Bugs found

| # | Where | What | Verdict |
|---|---|---|---|
| B1 | FightState:89, 93 | reads `Aggression` / `SpecialPreference`, never written: every Quin fights at 0.7 aggression, 0.3 specials. Personality ignored in fights | FIX |
| B2 | TeamCoordinationSystem:117 | reads `LastAttacker`; DamageModule writes `LastAttackerName` | FIX |
| B3 | ClashOrbit:926, Momentum:434, BeamStruggle:506, MidAirClash:316/318/477 | `TakeDamage` straight on the Humanoid: no LastAttackerName (victim's senses), no ImpactTime, no Drives, no kill credit, no stats. A beam loss (55) is invisible to the victim's brain | FIX: route through DamageModule |
| B4 | Main:676/698/744/754 | the brain writes `ForceState` (Idle/Retreat/Chase) *before* Main reads it; a Knockback / MidAirClash / BeamStruggle that another Quin set between ticks is overwritten and lost | FIX: state requests with priority |
| B5 | Main dwell check | ForceState counts as an interrupt, so the brain's Retreat/Chase orders skip the minimum dwell while a state's own Chase->Fight (not an interrupt) waits 0.8 s | FIX with B4 |
| B6 | SituationAwareness | target info was the nearest enemy with its true health | fixed (5d4d813) |
| B7 | NavigationModule.lowObstacle / IdleState | 2-stud step missed; stuck check fooled by written velocity | fixed (f03f76b) |
| B8 | IsAuraFarming, LockedCombatTarget, AnticipatedReaction, ComboStep | read, never written: features dead (TeamFocusTarget is live: it travels in the situation table) | DELETE or wire |
| B9 | KnockbackState:51 | "Adrenaline Surge": every knockback refilled mana to full | removed (owner) |
| B10 | Defense, CriticalHitChance, DodgeChance | CORRECTION: set by QuinSpawner.applyStats from QuinData (a loop the name search missed): same fair values for every Quin. Not a bug. Same loop also sets Aggression 0.65 / SpecialPreference 0.35, so B1 was 0.65 for everyone, not 0.7 | per-Quin variation is a design call |
| B11 | ProjectileFightState header | "only transitions to ... TestEndState": no such state | DELETE the claim / test state |

## 2. Duplicates: merge or keep

### Body control (the biggest overlap)
| Job | Done in | Verdict |
|---|---|---|
| Turn the body (AlignOrientation made) | 18 sites in 15 files (Locomotion x3, Idle x2, Circling, Fight, Knockback, Recovery, ReEntry, WallRun, Death, MidAirClash, ProjectileJump, ProjectileFight, Momentum, SlideTackle, SocialSystem, Evasion) | **MERGE** into one `Facing` owner per Quin (LocomotionModule.claimFacing already exists): `Facing.toward(q, point, stiffness, why)`, `Facing.upright(q)`, `Facing.release(q)`. Fixes two gyros fighting after a state change |
| Push the body | velocity written in 18 files (48 sites) + 12 files making their own movers; ImpulseModule says it is "the one force channel" | **MERGE** ground pushes into ImpulseModule as its header promises; air/ballistic (ProjectileJump, ClashOrbit, Momentum) KEEP their own mover but through one `Body.claim(q, owner)` so two systems never drive at once |
| PlatformStand / AutoRotate / WalkSpeed | 11 / 11 / 15 files | **MERGE** into the same body-claim: whoever owns the body sets them, release restores |
| Mana (Energy) writes | 17 files | KEEP costs where they happen, but one `Stamina.spend(q, n, why)` / `gain`, so carry-over, shaken and HUD see one place |
| Damage | DamageModule + 4 bypasses | **MERGE** (B3) |

### Who / where helpers
| Helper | Copies | Verdict |
|---|---|---|
| findModelByName | ChaseState, FightState (90% same) | **MERGE** -> QuinRoster.byName |
| getEntityHRP | RetreatTacticsModule, SpatialModule (identical) | **MERGE** -> SpatialModule.rootOf |
| rootOf / humOf / flatDist / bump / reset | 4 Social* files + TaskChoice + MomentumDuel | **MERGE** -> one QuinUtil |
| cfg() | 17 files, different fallbacks for 24 keys (CombatRange 7/8/8.2, ChaseRange 60/90/800/1000 ...) | **MERGE** -> CombatConfig.get(key) with the default in CombatConfig only |
| Personality reads | 100+ reads, defaults disagree (aggression 0.5/0.6/0.7) | **MERGE** -> Personality.of(q) |
| Roster scans | 22 sites in 13 files | **MERGE** knowledge scans into Cognition/TeamBoard; KEEP body-avoidance scans (physical, not knowledge) but through QuinRoster.near(pos, r) |

### State code
| Pair | Finding | Verdict |
|---|---|---|
| ChaseState 1370-1390 ~ RetreatState 486-505 | identical gait/overlay animation block | **MERGE** -> `GaitModule.drive(q, data, desiredAnim)` |
| Chase/Circling/Overwatch/Idle energy blocks | dead while Body_StaminaByEffort = true (it is) | **DELETE** the per-state blocks and the switch |
| IdleState x2 gyro, CirclingState.ensureGyro, SocialSystem.watch (61-72% same) | same "face a point while standing" | **MERGE** into Facing |
| LocomotionModule.claimFacing ~ ReEntry.faceCenter ~ Recovery.alignUpright (47-72%) | same | **MERGE** into Facing |
| Beam ~ MidAirClash headers, Airborne ~ Fight headers | only require lines | KEEP |
| Procedural layers' `new()` (ArmClear, SoftElbows, WallHand, Breath, SquareUp 64-71%) | same constructor shape | KEEP (a small base helper is optional; low value) |
| Evasion.readMarkers ~ StrikeMarkers.read (60%) | two marker readers | **MERGE** -> StrikeMarkers.read |
| CrowdChatter ~ OwnerChatter fill/conversation (63-83%) | same line filler | MERGE later (not combat) |

### Combat systems that overlap in purpose
| Systems | Finding | Verdict |
|---|---|---|
| FightState's own block/dodge chooser (lines ~105-200, 995) vs Instinct | FightState's branch only runs when Instinct is off; Instinct is on | **DELETE** FightState's branch, or keep only as Instinct's fallback in one place |
| Dodge moves: FightState dodge/dash, Evasion focus dash, Momentum roll, AirDash | different moves, but three deciders | KEEP the moves; **MERGE** the *choice* into one "answer a strike" picker (Instinct) |
| Mid-air: MidAirClashState + ClashOrbit (1030 lines) + old static flurry | MidAirClash_Orbit = true, so the static flurry is dead | **DELETE** the static flurry path |
| ProjectileFightState + InterceptionState | a test cinematic reached only by ForceState from GameModeManager | **ASK**: keep as a test scene outside QuinCore, or delete |
| Airborne (air combos) vs ProjectileJump's own air fight vs ClashOrbit | three air-fight owners | design later: one AirCombat owner |
| Momentum + MomentumDuel vs Chase/Fight | parallel movement + duel brain beside the FSM ("not a state") | KEEP (owner's direction) but it must use the shared body claim |
| DecisionSystem (Attack/Retreat/Pursue) vs TaskChoice vs TargetingModule | three deciders, run in a fixed order, not aware of each other | **MERGE** into one Brain tick: task -> target -> action, with the task passed to the action |
| TacticalPerception | 21-line pass-through of Cognition.update | **DELETE** |

## 3. Transitions

Graph (from code; `!X` = ForceState X written on someone):

```
Idle          -> Chase, Circling, Fight, ProjectileJump
Chase         -> Circling, Fight, Idle, ProjectileJump, Recovery, Retreat, WallRun
Circling      -> Chase, Fight, Idle, Recovery, Retreat
Fight         -> Airborne, Chase, Circling, Idle, Knockback, ProjectileFight, ProjectileJump, Recovery, Special, !Airborne, !Knockback
Retreat       -> Circling, Fight, Idle, Overwatch, ProjectileJump, Recovery, WallRun
Overwatch     -> Chase, Fight, ProjectileJump
Special       -> BeamStruggle, Chase, Fight, Recovery, !BeamStruggle, !Knockback
BeamStruggle  -> Fight, !BeamStruggle, !Fight, !Knockback
MidAirClash   -> Airborne, Knockback, !Knockback, !MidAirClash
ProjectileJump-> Fight, Idle, MidAirClash, Recovery, !Knockback
Airborne      -> Chase, Idle, MidAirClash
Knockback     -> Chase, Idle, Recovery
Recovery      -> Chase, Circling, Fight, Idle, Overwatch
WallRun       -> Chase, Fight, Idle
ReEntry       -> Chase, Circling, Fight, Idle        (entered only by Main's ForceState)
Interception  -> Chase, Fight                        (entered only from ProjectileFight)
Piloted/Death                                         (entered only by Main)
```

Findings:
- T1. Three ways to change state: 132 inline `return require(script.Parent:WaitForChild("XState"))`,
  7 aliases, 29 ForceState writes from 11 files (+ GameModeManager x14, SocialRespect, SocialTension,
  DamageModule, SlideTackle, Momentum). A typo in a state name is a runtime error that pcall turns
  into Idle with only a warn. **MERGE**: states return a name (`return "Chase"`) or `States.Chase`
  from one registry; external changes go through `StateRequest.ask(q, "Knockback", priority, why)`.
- T2. ForceState is one slot, last write wins, no priority, no reason (B4).
- T3. Dwell: Chase->Fight waits 0.8 s (not an interrupt) — a Quin in reach keeps chasing; ForceState
  orders skip dwell (B5). One rule: interrupts by priority, voluntary changes by dwell.
- T4. Main's own body overrides before the state runs (Headroom, Edge, Momentum busy, Piloted, hit
  owns legs, ProjectileJump ceiling check) are six special cases in Main's loop. **MERGE** into an
  ordered list of "guards" (each: applies? -> takes the tick) so the order is visible and testable.
- T5. Every exit is responsible for undoing what its enter did (gyros, movers, PlatformStand,
  WalkSpeed, AutoRotate). With the body claim (section 2) a state change releases everything the
  old owner held, so no state can leave a gyro or PlatformStand behind.

## 4. Cleanup (no behaviour change)
- 50 functions never called (e.g. SpatialModule.predictIntercept, LocomotionModule.checkAndJump,
  getTraversalProbe, 5 AudioModule sounds, 3 ProceduralReaction telemetry getters) — DELETE, or wire
  predictIntercept into Memory (it is the prediction the brain lacks).
- QuinAccessoryModule (484 lines) required by nothing — DELETE.
- 119 `tick()` in 35 files, 197 os.clock, 31 server time — one clock per purpose: server time for
  anything shared/attributes, os.clock for local timers; no tick().
- Two names for one target (`CurrentTarget`, `TargetQuin`); every situation value twice
  (`SelfHealthPercent`/`ownHealthRatio` ...) — one name each.
- Attributes written every tick and read by nobody in code (ClosingSpeed, TacticalDecision,
  TotalLivingAllies/Enemies, AttentionCapacity ...) — write on change, or DebugReadouts only.

## 5. Order (each one commit, 16v16 measured where behaviour changes)
1. Bugs B1-B4 (+B5). Small, high value.
2. Shared helpers: CombatConfig.get, Personality.of, QuinRoster.byName, SpatialModule.rootOf, QuinUtil.
3. Deletions: dead functions, QuinAccessoryModule, TacticalPerception, dead energy blocks, static
   flurry, FightState's pre-Instinct dodge chooser.
4. StateRequest + state registry (T1-T3).
5. Body claim: Facing + Impulse + humanoid flags (section 2, T5). Largest; touches 20 files.
6. One Brain tick (DecisionSystem / TaskChoice / TargetingModule), then the cognition upgrades.
7. Split ChaseState / FightState / ProjectileJumpState along the seams above.
