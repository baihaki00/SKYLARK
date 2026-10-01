# Pass 6 (2026-10-01): quick fixes and combat

Phases 0 and 1 of the plan agreed after pass 5. Studio backup:
`ServerStorage.backup_pre_16v16audit6_20261001`.

## Phase 0 — quick fixes

| Report | Cause | Fix |
|---|---|---|
| Pale T-posed torso flickering at both spawns | `Alpha_Surface` used `RenderFidelity = Automatic`; at 285-470 studs from the camera the simplified, unskinned mesh was drawn for a frame. Likely cause — no stray instance was found by a spawn/lifetime probe | `Precise` on all Quin templates (place file, not in this repo) |
| F no longer flies | Three scripts reacted to F: `TheArchitectCode` (body fly, bound to the first avatar only, so dead after Play As Quin / respawn), `SmoothCamera` and `AnimationLabController` (both detach a free camera), plus `PlayerQuinController` (punch) | F = fly the current body (avatar or worn Quin), rebinding on character change; free camera moved to B; punch stays on left click. Verified with simulated key presses on both bodies |
| Overhead "Quin | CHASE" label always visible | `RuntimeVisualizer.update` ran every frame on the first Quin regardless of the HUD | Drawn only while the Spectator HUD is open, cleared when it closes |

## Phase 1 — combat

### What was wrong (68 s of 16v16, before)

- 217 air knockbacks, 1 ground. About 76% of landed hits launched the victim.
- 437 guards raised, 2 held.
- Up to three separate `LinearVelocity` movers on a body at once (902 frames in Fight).

Causes:

1. **Cornered detection measured the arena from the world origin.**
   `SpatialModule.getSafeRetreatDirection` looked for `argoniaonion.ArenaGround` as a direct
   child; it is at `argoniaonion.ArenaOne.ArenaGround`. Centre fell back to (0,0,0) (real centre
   (0,0,-438)), every direction scored as leaving the arena, and Quins read as cornered ~39% of
   the time.
2. **Last stand re-armed the desperate counter on every decision tick.** Cornered ⇒ last stand ⇒
   `DesperateCounter = true` each evaluation ⇒ nearly every attack was the counter-strike, which
   always launched. This, not the combo finishers, produced the constant one-punch launches.
3. Combo steps advanced on every swing, hit or miss; steps 4-5 always launched.
4. Guard success read `BlockChance` (0.08, the chance to *raise* a guard).
5. A hit pushed the victim twice (DamageModule and FightState), while the attacker lunged
   through its target and the spacing slide pushed it back out.

### Changes

- `Modules/ImpulseModule` (new): one horizontal force channel per Quin. Tagged requests add up,
  a same-tag request replaces the old one from the body's current speed, and opposing requests
  never run together (higher priority wins: knockback > hit reaction > own motion).
  `KnockbackModule.applyLunge / applyMicroKnockback / applySlide / applyGroundKnockback` now go
  through it; public signatures kept (`applyMicroKnockback`'s `studs` is now the real distance).
- Hit outcomes resolved in one place (`DamageModule.resolveOutcome`): flinch + slide by default,
  finishers knock back along the ground, any hit can launch by chance (finisher 40%, other hits
  5%, scaled by crit, back attack, victim posture, launch power / weight). All in
  `CombatConfig.Combat_*`.
- A swing that connects with nothing resets the combo. A Quin caught in a combo, or between its
  own attacks, can get its guard up once per incoming strike; `Combat_GuardStrength` (0.70)
  decides whether it holds.
- Desperate counter: armed once on entering last stand, 6 s cooldown, resolves like a finisher.
- Attack lunge is capped by the gap to the target (`Combat_LungeStopDistance`); the spacing
  slide does not fire mid-swing.
- Arena bounds for retreat scoring come from `SpatialModule.getArenaBounds()`.

### After (57-68 s of 16v16)

| Measure | Before | After |
|---|---|---|
| Landed hits ending in a flinch / slide | ~24% | ~87% |
| Ground knockbacks | 1 | 16-31 |
| Air knockbacks | 217 | 66-74 (~10% of hits) |
| Guards held | 2 | 27-28 |
| Time in Fight (Quin-seconds) | 414 | 640-840 |
| Time read as cornered | ~39% | ~1% |
| Retreats started | 4 | 5-25 |
| Frames with more than one mover (Fight) | 902 | 0 |
| Fight velocity reversals not caused by being hit | not split | ~0.14 per Quin-second (walk 67, own lunge 17, own slide 8 in 640 s) |

No script errors in any run.

### Left open

- `SpatialModule.getArenaCenterPull` has the same direct-child lookup and therefore returns zero:
  the arena-centre pull in Chase / Circling has never been active. Not changed here — switching
  it on alters movement and belongs with the cognition phase.
- `LocomotionModule.slide` still owns its own mover (`LocoSlideLV`).
- `FightState` immediate counter still snaps facing with a CFrame write.
- `Server.server.lua:169` calls `KnockbackModule.apply`, which does not exist.
- Blocks are ~4-5% of strikes; raise `BlockChance` / `Combat_ComboBreakChance` if more is wanted.
