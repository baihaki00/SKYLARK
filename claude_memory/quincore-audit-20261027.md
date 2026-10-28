---
name: quincore-audit-20261027
description: "Full QuinCore audit (duplicates, transitions, bugs) and its 7-step refactor order; Beam Struggle deleted by owner; which steps are done"
metadata:
  node_type: memory
  type: project
  originSessionId: 11e382ae-5247-4176-93d5-d6257bc05aff
  modified: 2026-10-27T10:14:00.224Z
---

Owner asked 2026-10-27 for a full sweep of QuinCore ("every letter compared"), Quin only, not the whole project. Result: QUINCORE_BACKUP/QUINCORE_AUDIT_20261027.md (merge/delete/keep verdicts, transition graph, bug list B1-B11, order). Re-runnable scripts were in the session scratchpad (audit.py, dupes3.py, concepts.py): token-shingle function similarity + 6-line window hashing + primitive-per-file map.

- Owner: "delete beam struggle" -> removed entirely (commit a4b5ea5). Don't bring it back.
- Step 1 done (7262ce9): FightState reads Pers_Aggression/Pers_SpecialPreference; LastAttackerName in TeamCoordination; DamageModule.chip for clash/momentum chip damage; Main `order()` never overwrites a pending ForceState.
- Knockback mana refill removed (7011985). ProjectileFight + Interception test cinematic deleted (04e62ff).
- Stats: QuinSpawner.applyStats copies every QuinData stat onto the model in a loop (literal-name greps miss it). Owner picked "vary from condition and training" (53b6b5c): QuinCare.applyToModel applies drills then wear; Instinct scales hop/slip by DodgeChance and guard by BlockChance vs QuinData base; Trainer has a DRILLS tab (Guard/Footwork/Toughness/Precision 0..10, quin.Drills). Trainer UI not yet seen by the owner in Play.
- Step 2 done (f05d003): Modules/Pers.get (one default table, DefensePreference derived), QuinRoster.byName, CombatConfig duplicate keys removed + fallbacks set to real values (took values from Studio require: local regex also matched nested tables/prefixed cfg() helpers - never trust it for config).
- Step 3 done (ccae64f, -990 lines): TacticalPerception, QuinAccessoryModule, 26 uncalled fns, per-state mana blocks, MidAirClash flurry. Kept on purpose: FightState pre-Instinct guard rolls (live under Ablate_Instinct), dev/telemetry getters, SpatialModule.predictIntercept (for the brain step).
- Step 4 done: Modules/StateRequest (ask/take, priority ladder, why) + Modules/States registry (States.X); QuinCore never writes ForceState directly any more; match-control server scripts still do (always win).
- Step 5a done: Modules/Facing (held turner per Quin, holder tag + TUNE table, Main drops on state change). Step 5b done: measured pushers barely overlap (42 Quin-frames/40 s); real conflict was AutoRotate on 70% while Fight held Facing -> Facing.hold owns facing (AutoRotate+SteerFacing off). Step 5c done, no change: WalkSpeed 17683 writes/40 s, only 132 double-writes, 1 flip; PlatformStand on in a standing state with no pusher = 40 stretches/45 s, all <=0.18 s with KnockbackType=air (hit lands a frame before Knockback takes over), not a leftover. Step 6 done (794e7e0): Modules/Brain.tick = Cognition -> TaskChoice -> Targeting -> retarget facts -> DecisionSystem -> orders (moved out of Main); fixed action weighed vs last tick target (117 switch ticks/30 s). Open for 6b: cognition upgrades (predictIntercept into Memory; DecisionSystem could lean on the Task). Step 6b done (0a1316d): DecisionSystem leans on the Task (field job: no AuraFarm/Pursue, less Retreat; Rescue/Hunt pursue); predictIntercept deleted (Chase already leads). Step 7 done (f181118, +7b): child modules under States/ChaseState (Climb, Obstacles, Steer), FightState (Strike, Decide), ProjectileJumpState (Flight, Clips), moved as-is; PJ enter/update still big. Split tools: scratchpad freenames.py/splitter.py/movefuncs.py (lost with session). Trap: child modules sit one level deeper, script.Parent.Parent paths break (infinite yield). AUDIT 7 STEPS COMPLETE.
- Far-floor checker flicker: CastShadow=false did NOT fix it (owner); restored to true. Owner: Roblox shadow limitation, not important now.
- Next steps in order: 4 done -> StateRequest + registry -> 5 body claim (Facing/Impulse/humanoid flags, ~20 files) -> 6 one Brain tick -> 7 split giant states.

**Why:** owner wants pristine modular code and a smarter brain, but [[owner-overwhelm-small-steps]] and [[quins-improve-in-general]] still apply: one commit per step, 16v16 measured.
**How to apply:** pick up at the next undone step; check the audit doc for exact sites.
