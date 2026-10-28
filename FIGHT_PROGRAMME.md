# Fight Programme

The plan for making Quins fight like martial artists who dance: approved by the owner 2026-10-29.
It builds on `QUIN_CREATURE_DESIGN.md` (a Quin is a living creature made for combat) and stays
inside the current QuinCore architecture: no refactor passes (see "Refactor verdict").

## Rules for every step

- **One creature.** The AI and a piloted Quin share one body and one rulebook; only the decider
  differs. Body, hits, moves and rules improve both. Only the mind (part E) is AI-only; a player's
  Quin acts only on input.
- **Two gates, plus fps.** A step ships only if the 16v16 still looks like what the owner loves
  (watching), it feels right piloted ("butter smooth, with weight, fast"), and 60 fps holds.
- **Judged in a 1v1 first** by the owner's eye, then checked in the 16v16.
- **A switch for every piece** (CombatConfig / `Ablate_` / `Layers`), so it can be A/B'd live.
- **Protect the tempo contrast.** The current 16v16 has fast bursts and slow, deliberate stalking.
  A step that flattens that contrast is reverted, whatever else improves.
- **Clutter test.** Every step must read clearly with VFX off. Hype comes from timing and impact;
  big effects only in the top force tier, and rarely.
- **Weapon-ready.** A move atom names its channel and what it holds, so weapons and guns later are
  new atoms, not a rebuild.

## The five parts

**A. Body.** Three channels: legs (stance, steps, kicks), arms (strikes, guards, grabs), core
(flips, evades, aerial). A move claims only its channels. Spacing by real strike reach, a soft
personal-space gap, hits that push. Balance (the existing Posture) worn by hits, whiffs, bad footing.

**B. Hits.** The reaction comes from where (head / body / legs, side, front or back), how hard, and
what the defender was doing. A few base clips (flinch, stagger, buckle, knockdown, launch) bent by
the procedural layer. Force tiers from flinch up to a crater; the top tier is rare.

**C. Moves.** Atoms with tags: channel, limb, range, height, line, side, energy, reach, and the
opening the move creates. The owner authors only the core of each move; windup and recovery are
time-warped and blended from it (held, sped up), mirroring is automatic, combos are never authored.
Grabs, clinch and throws are paired moves where one Quin drives both bodies (the ClashOrbit pattern).

**D. Rules.** Guards cover a height; evades have a direction; parry opens a counter; two strikes
meeting clash; simultaneous hits trade. Openings are facts the rules produce.

**E. Mind.** Reads the tell, openings and balance; answers rather than spams; learns within a fight;
takes angles, uses terrain, breaks off and re-engages; fights in phrases (flurry, separation,
reposition, re-entry). Five range bands, measured as time (Reach), awareness by sight:

| Band | What happens there |
|---|---|
| Very close | Sifu-style hand fighting, short kicks, parries, clinch and grabs |
| Close | Dash kicks, slip just enough, take the rear, back to very close |
| Mid | Footwork, stepping in and out, feints, leg checks |
| Far | Dash-ins, flying knees, projectile jumps, stalking |
| Very far | Sees the target across the arena, decides to commit, takes a route |

## Steps and where they land

| Step | Files | Risk |
|---|---|---|
| 0 Baseline | `scripts/fight_probe.lua`, report in `audits/`; QuinCore untouched | none |
| 1 Spacing (**built 2026-10-29**, [report](audits/2026-10-29_fight_step1_spacing.md); waits for the owner's eye) | new `Modules/Spacing` (loop from `Server`), `ImpulseModule.cancelToward`, `reach` per clip in `AnimationConfig`, `Strike.lua` stepIn stops at the clip's gap, the riposte lunge in `FightState` gets a room limit, `CombatConfig.Spacing_*`. No collision switch: bodies already collide (CollisionBody) | low-medium (hit rate): hit rate held |
| 2 Channels (**built 2026-10-29**, [report](audits/2026-10-29_fight_step2_channels.md); test with `Test_ArmsOnlyPunches`, waits for the owner's eye) | `AnimationConfig` `channel` field (default Body = today), `AnimationModule.play` stop rule (Action vs Action only if channels overlap), `FightState` plant-while-striking skipped for arms-only strikes, Cascadeur converter "arms only" option | low |
| 3 Hits (**round 1 built 2026-10-29**, [report](audits/2026-10-29_fight_step3_hits.md): contact by reach, hit clip only for real blows) | `DamageModule.apply` (zone + side attributes, reaction chosen by zone and force), `ProceduralCombatReactionController.triggerImpact` (head / body / legs), balance = existing Posture, top tier beside `resolveOutcome` | low (drawing, switch) |
| 4 Move vocabulary | Tags on `AnimationConfig.Attacks`; `Strike.chooseStrike` reads tags; `ComboModule` keeps its API, scales damage by step | medium (every strike; A/B) |
| 5 Rules, openings | `DamageModule` guard check gains height; `Instinct.answer` picks it (can be wrong); `Strike.conclude` publishes openings; clash beside the trade window | medium |
| 6 Mind | `FightState/Decide.lua` from dice to answers; `Reach` bands (very close split); `Rhythm` phrases; lock = `Attention` / `TargetingModule` / pilot T-G tuning | highest for the 16v16 feel |
| 7 Timing | `HitStop.lua`, `Strike` windup hold between the Windup and HitStart markers | low |
| 8 Grabs | new `States/GrabState` on the ClashOrbit pattern | isolated, biggest new piece |
| 9 Aerial | `MidAirClashState` / `ClashOrbit`, `AirInterceptModule`, `ComboModule.Aerial` | low-medium |

**Clips the owner makes:** base hit reactions by step 3, the range-plan moves by step 4 (arms-only
where they are hand moves), paired grab poses by step 8. No windups, recoveries or combos.

## Refactor verdict

None needed. Three cleanups go inside the steps that need them:
1. The move vocabulary lives in three places that disagree (`ComboModule` step names, damage and
   hitbox; the clip picked separately by name in `Strike`). Fixed in step 4.
2. Two hit-stops stack (`DamageModule` 0.05-0.08 s and `HitStop` 0.15-0.6 s). Merged in step 7.
3. `AnimationModule.stopCategory` is defined twice (the second wins). Only touched if step 2 needs it.

`FightState.update` is long but stays as it is: new behaviour goes into `Decide`, `Strike` and new
modules.
