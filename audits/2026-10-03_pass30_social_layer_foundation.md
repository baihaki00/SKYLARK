# Pass 30 (Social layer, phase 1): old showdown removed, SocialSystem foundation, head nod

Plan: "Pack Leaders, Respect Customs & Emergent Arena Events" (the owner's brief), phase 1 of 4. The owner chose to **delete the old scripted Leader Showdown entirely**.

**Place:** from this pass on the work is in **QUIN_COMBAT_V3** (placeId 106089520796817). The owner moved here after an account moderation hold; while the hold was on, every owner asset failed to load in V2. V3 was checked to hold this pass's edits byte for byte before testing continued.

## Removed

- **Deleted:** `Modules/LeaderShowdownSystem` (40 KB of scripted cinematic: staged walks, a dais at a hardcoded wrong centre (0, 2, −38), referees) and `States/LeaderShowdownState`.
- **GameModeManager:** removed the N-v-1 trigger that started the cinematic whenever a team was down to one fighter, and the `LSS.reset()` calls.
- **QuinSpawner:** `cleanAll` now resets `SocialSystem`.
- **Main:**
  - removed the `LeaderShowdown` state, its forced-state routing and its "force spectators into LeaderShowdown" override;
  - the ring constraint is now `SocialSystem.constrainToCeremony` (a no-op until the respect-custom pass).

## Re-pointed (the rules are kept for the Respect Custom)

The old showdown checks in Chase, Circling, Fight, Idle, Retreat, Recovery, Knockback and Overwatch states, plus Cognition, DecisionSystem, TargetingModule, KnockbackModule and DamageModule, now read the new attributes:

| Old | New |
|---|---|
| `LeaderShowdownRole` | `RespectRole` |
| `PerimeterGuard` | `Spectator` |
| `Transition` | `Watching` |
| `LeaderShowdownActive` | `RespectCustomActive` |

**Semantics changed in three places,** because `RespectRole` will also carry values like `Hesitating` and `Honored`:
- **DamageModule:** spectators neither deal nor take damage; a duelist only trades with the other duelist (`DuelUnauthorized`).
- **KnockbackModule:** contained knockback for duelists only.
- **States:** jump suppression for duelists only.

**Spectator branches** that handed over to the deleted state now go to Idle. Idle walks a spectator to its chosen spot (move intent), then it stands.

## Added

**`Modules/SocialSystem`** (new): a whole-field tick at `CombatConfig.Social.TickRate` (4 Hz), started from Main. It provides:
- **Body language:** `lookAt`, `nod`, `acknowledge` (a look, then a nod);
- **Move intents:** `setMoveIntent`, `getMoveIntent`, `followMoveIntent` (steers through `LocomotionModule.steer` and Gait);
- **Animation slots:** `playSlot` (blank slot → nil);
- **Respect-custom role helpers;**
- **Event level:** `raiseEvent` (Workspace `ArenaEventLevel` / `ArenaEvent`, plus the BindableEvent `ReplicatedStorage.ArenaSocialEvent` for the crowd, ARIA and the screen);
- **Tickers:** `addTicker` for later phases;
- **Studio hook:** `SocialDevCommand` (`nod <quin>`, `look <a> <b>`, `ack <a> <b>`).

**Config.**
- `CombatConfig.Social`: look time, nod duration and depth, paces (walk 12, jog 22, run 34), arrive distance, event levels.
- `AnimationConfig.Registry.Social`: blank slots Nod / HoldBack / Beckon / Kneel / Sit / Lean / Crouch / Celebrate / Exhausted / LookUp. They show up as a "Social" tab in the Animation Lab; paste an id to switch one on.

**Client head** (`LookController`).
- A `SOCIAL` look priority (below the glance-back, above scanning) toward `SocialLookAt` until `SocialLookUntil`. It can turn as far as the shoulder glance.
- A procedural nod: two dips of the head after `NodAt` (12°, the second 40% smaller, over 0.6 s), shared 75/25 between head and neck. It works with or without a look target.

## Fixed along the way: head offsets compounding

**Bug.** `LookController` multiplied its offset onto the bone's `Transform` every edit. On frames where the Animator had not rewritten the bone, the offset stacked. A nod measured −6, −41, −18, −60° on alternating frames; the head pitch at rest jumped about 24°.

**Fix.** `applyBoneOffset` remembers what it wrote. If the bone still holds exactly that, it reuses the previous animated base instead of stacking.

**Measured** (Pose Viewer live Quin, sampled at PreAnimation, which is the pose that was rendered):
- **At rest:** −10.0 to −3.2°, with a largest frame-to-frame step of 1.1°.
- **Nod:** −5 → −17 (first dip) → −9 → −15 (second dip) → −3. That's two clean dips.

Sampling note: sample head bones at **PreAnimation**. At Heartbeat the next animation step has already overwritten the edit, and RenderStepped connection order isn't guaranteed.

## Regression (V3)

- **Assets:** 0 failing animations or sounds on server and client.
- **16v16, 45 s:** hit 68%, whiff 6%, interrupted 22%, blocked 5%, 0 errors. The Pass 29 baseline was 66 / 8 / 18 / 8.
- **P possess:** OK.
- **Arena match** with generation: reached IN_GAME, crowd 33 loops, `ArenaEventLevel` Normal, 0 errors.
- **Leftovers:** a whole-place search finds "LeaderShowdown" only in the inert `ServerStorage` backup copies.

Next: phase 2, Pack Leaders (emergent leaders capped per mode, credibility and trust from battlefield results, signals that are followed or ignored, transfer).
