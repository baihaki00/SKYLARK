# Fight patterns, the tree loop, idle chasers, KO'd chasers, strike height

2026-10-29, Studio (QUIN_COMBATV4). Built from five of the owner's reports:
- the knockback → circling → strafe pattern;
- a Quin standing idle in Chase;
- a KO'd Quin in the prep room still chasing;
- a Quin looping and jumping under a tree;
- punches thrown at a Quin standing at the puncher's feet.

**Waiting on:** the owner's eye.

## 1. Knockdown → always Circling (looked hardcoded)

**Cause.** In `States/FightState`, a target that was down (Knockback / Airborne / Recovery / GetUpProtection) always returned `States.Circling`, with no choice. The victim, once up in standoff range, also always circled (`RecoveryState`).

**Fix.**
- **Who decides:** `FightState.downedReaction` makes the choice once per knockdown. It is picked again after `Fight_DownedRepick` (3 s).
- **The four reactions, weighted by personality:**
  - **press:** walks in and stands over the body, `Fight_DownedPressGap` (6 studs) away, with no strikes. Weighted by aggression and confidence; less likely when the body is 18+ studs away.
  - **hold:** stays where it is, facing the body. Weighted by calm and low mobility.
  - **circle:** the old behaviour. Weighted by mobility.
  - **switch:** turns on another known enemy that's still up within `Fight_DownedSwitchRange` (30 studs), then chases it. Weighted by aggression.
- **`RecoveryState`:** once up, in standoff range, the Quin steps straight back into the fight with a chance of 0.15 + aggression × 0.45 instead of always circling.
- **Readout:** the attribute `DownedReaction` and a RuntimeTracer checkpoint.
- **Switches:** `Fight_DownedChoice = false` and `Recovery_ReengageChoice = false`.

**Measured (80 s 16v16):** 131 knockdown choices:

| press | hold | circle | switch |
|---|---|---|---|
| 43 | 29 | 33 | 26 |

Circling went from 100% of knockdowns to 25%.

**Still in the code (not changed):** `ChaseState` hands over to Circling at random when it arrives in range: 30% of the time, or 20% when it is "mirroring" a circling target. That is a smaller source of the same pattern. Tell me if it still reads as one.

## 2. A Quin idle in Chase ("Stepping stone: 40 up, 38 across", speed 0)

**Cause.** In `ChaseState/Climb`, once a stone was found, the Quin braked to a stop for the whole `Nav_StoneHopCooldown` (2.5 s) between hops.

**Fix.** Between hops it now walks to the stone and lines up with it. Once it is within `Nav_StoneWaitGap` (8 studs), it waits there facing it.

## 3. The jump loop under a tree

**Cause.** `NavigationModule.nextStone` accepted, as stepping stones:
- the trunk mesh's bounding-box top, which is not a real surface;
- the collidable blocks hidden inside the non-collidable canopy. Its "room to stand" ray ignored the leaves.

Quins chasing a target on higher ground hopped for those blocks, hit their heads, and tried again.

**Fix (`NavigationModule.nextStone`):**
- A ray down at the landing point must land on that part, which rules out mesh tops.
- The 8 studs over the landing point must hold no visible anchored geometry, non-collidable leaves included.
- With a ceiling within 10 studs over its own head, the Quin only takes stones at least `Nav_StoneCeilingHop` (10) studs out.
- A stone it hopped for but didn't end up on is skipped for `Nav_StoneFailMemory` (20 s).
- `Climb` records each try. Probe counters: `StoneHops` and `StoneFails`.

**Measured:** 7 spot hops in 80 s, 2 of which missed their stone. These counts cover only the Quins still alive at the end. The head bumps themselves weren't counted: judge them by eye under the trees.

## 4. KO'd Quins in the prep room still chasing

**Cause.** A race. `ArenaPrepRoom.bringHome` spawned the copy with the fighter tags and a running `Main`, and only marked it inert after `QuinSpawner.spawn` returned. That function yields on FX, so `Main` could start a Chase first and then freeze in it.

**Fix.** `QuinSpawner.spawn` with team `"Defeated"`:
- sets `IsInert`, `ForceState Idle`, `CurrentState Idle` and `Defeated` before `Main` runs;
- never adds the `Quin` / `AI_Fighter` tags.

The idle pose still plays, because `Main` enters Idle on start.

**Checked:** one KO'd copy in the test came home inert, in Idle, with no tag, task or target. That's one sample; the race itself is gone by construction.

## 5. Punching a Quin at its feet

**Cause.** `Strike.chooseStrike` picked punch or kick, then any clip of that kind, without looking at height.

**Fix.** Each clip is weighed by where it would land: the attacker's root height + the clip's `height`, compared with the target's body. The body runs from 3 studs below the target's root to 2.5 above (`Answers_BodyBelow` / `Answers_BodyAbove`). A clip that would pass over the head or under the feet falls to as little as `Answers_OffBodyWeight` (0.08) of its normal weight. Nothing says "feet = kick": a low kick from a ledge simply lands on the body, so it wins.
- New reason `height` in `StrikeAnswer`, and a probe attribute `StrikeKind`.
- Switch: `Answers_HeightAware = false`.

**Measured (80 s 16v16), strikes by the attacker's height over the target:**

| | Punch | Kick | Kick share |
|---|---|---|---|
| Level | 442 | 600 | 58% |
| 4+ studs above | 6 | 22 | **79%** |

- **From 4+ studs up, most strikes still miss:** kicks hit 4 of 22, with 18 whiffs. These strikes are thrown from too far, across a ledge; the choice of clip isn't the problem. That's the mind's "strike from where?" call (Fight Programme step 6).
- **Not tuned:** the clip heights are still estimates (step 3).

## Overall

- No script errors in the 80 s 16v16.
- Frame time was not measured this run.
- `CombatConfig` has no new lines: every new tunable is read with its default in code (`or …`).
