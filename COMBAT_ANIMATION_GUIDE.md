# Combat Animation Guide

The reference for authoring Quin combat clips:
- **Part 1:** the animation-event (marker) naming convention the code reads.
- **Part 2:** what exists today, with asset IDs.
- **Part 3:** the full clip list the combat needs.
- **Part 4:** how to work through it.

Written 2026-10-03 (pass 23c) from the owner's request. The combat reorganisation that uses it comes later.

---

## Part 1. Marker naming convention

**Rules**
1. **The name says what happens; the parameter says the detail.** Roblox events have one name and one parameter text, and the code listens by name.
2. **PascalCase, exact spelling, no spaces.** `HitStart`, never `hit start` or `Hit_Start`. Names are case-sensitive.
3. **Windows come in pairs:** `...Start` / `...End`. A single moment is a single marker.
4. **Parameters come from the fixed lists below.** Leave the parameter empty where it says *none*.
5. **Markers live inside the animation asset.** A clip shared by several moves shares its markers, so give every move its own clip (Part 2 lists the shared ones). Re-publish by **overwriting** the existing animation so its ID stays the same.

**Shared parameter values**
- **Limbs:** `RightHand`, `LeftHand`, `RightFoot`, `LeftFoot`, `RightElbow`, `LeftElbow`, `RightKnee`, `LeftKnee`, `Head`, `Body` (shoulder or hip check).
- **Sides:** `Front`, `Left`, `Right`, `Low`, `Back`.
- **Weight:** `Light`, `Heavy`.

### 1.1 Strikes (punches, kicks, elbows, knees, headbutts, ripostes, specials)

| Marker | Place it on | Parameter |
|---|---|---|
| `Windup` | first frame the attack is recognisable to a defender | none |
| `Plant` | the support foot plants for the step-in | `LeftFoot` / `RightFoot` |
| `Whoosh` | the swing sound | `Light` / `Heavy` |
| `HitStart` | the limb becomes dangerous | limb |
| `HitEnd` | the limb stops being dangerous | same limb |
| `Hit` | *instead of the pair*, for a single-frame contact | limb |
| `Cancel` | earliest frame a combo follow-up may start | none |
| `Recover` | the attacker is free to act again (end of recovery frames) | none |

- **Minimum per strike:** `HitStart` + `HitEnd` (or `Hit`) + `Recover`.
- **Multi-hit clips:** one `HitStart`/`HitEnd` pair per hit.

### 1.2 Blocks and parries

| Marker | Place it on | Parameter |
|---|---|---|
| `GuardUp` | the guard starts stopping hits | side |
| `ParryStart` | the perfect-parry window opens | side |
| `ParryEnd` | the perfect-parry window closes | side |
| `GuardDown` | the guard stops stopping hits | none |

### 1.3 Dodges (slips, ducks, sidesteps, backsteps, rolls)

| Marker | Place it on | Parameter |
|---|---|---|
| `EvadeStart` | the body leaves the line of attack | `Duck` / `SlipLeft` / `SlipRight` / `Back` / `SideLeft` / `SideRight` / `Roll` |
| `EvadeEnd` | the body is back in the line | none |
| `Recover` | free to act (e.g. counter) | none |

### 1.4 Hit reactions, knockdowns, get-ups, deaths

| Marker | Place it on | Parameter |
|---|---|---|
| `Impact` | the body (or back, or knees) hits the ground or a wall | `Light` / `Heavy` |
| `Recover` | the victim can act again (block, move, attack); replaces the fixed stun | none |

### 1.5 Grabs and throws

| Marker | Place it on | Parameter |
|---|---|---|
| `GrabStart` / `GrabEnd` | the hands can catch | limb |
| `Release` | the victim is let go / thrown | none |
| `Impact` | the thrown body lands (on the victim's clip) | `Heavy` |
| `Recover` | as above | none |

### 1.6 Movement (already used by the code)

| Marker | Place it on | Parameter |
|---|---|---|
| `Footstep` | each foot plant | `Left` / `Right` (new; old clips without it still work) |
| `Footstep180` | turn-step plant | `Left` / `Right` |
| `Jump` | takeoff | none |
| `ProjectileJump` | projectile-jump takeoff | none |
| `Landing` | touchdown | `Soft` / `Hard` |

### 1.7 Specials

| Marker | Place it on | Parameter |
|---|---|---|
| `ChargeStart` | power starts gathering | none |
| `Release` | the beam or blast leaves | limb |
| `HitStart` / `HitEnd` / `Recover` | melee specials, as strikes | as strikes |

### 1.8 Free hooks (any clip)

| Marker | Effect | Parameter |
|---|---|---|
| `Sound` | plays a named sound | sound name, e.g. `Grunt` |
| `Vfx` | spawns a named effect | effect name, e.g. `Sparks` |

### 1.9 Example timelines

**Jab (0.6 s)**
```
Windup 0.05 · Whoosh(Light) 0.14 · HitStart(LeftHand) 0.18 · HitEnd(LeftHand) 0.24 · Recover 0.40
```

**Roundhouse**
```
Windup · Plant(LeftFoot) · Whoosh(Heavy) · HitStart(RightFoot) · HitEnd(RightFoot) · Recover
```

**Block**
```
GuardUp(Front) · ParryStart(Front) · ParryEnd(Front) · GuardDown
```

**Duck**
```
EvadeStart(Duck) · EvadeEnd · Recover
```

**Knockdown**
```
Impact(Heavy) · Recover
```

**What `Recover` means:** a strike has windup → contact → follow-through. The tail of the follow-through is settling; a real fighter is already starting the next action. `Recover` marks the frame where the move is visibly done (fist back to guard, weight centred). Until then the Quin is committed (its recovery frames). After it, it may decide its next action, and the next clip blends over the settling tail.
- **Too early:** moves cut in mid-swing.
- **Too late:** the Quin freezes in a finished pose and gets punished.

Without the marker the code uses the clip's `cancelRatio` (about 70%).

---

## Part 2. What exists today (AnimationConfig, 2026-10-03)

Grouped by **unique asset**: markers are edited once per asset ID. ⚠️ marks an asset shared by moves that need different timing or meaning.

### 2.1 Strikes

| Asset ID | Used as | Notes |
|---|---|---|
| `113219639247452` | Lead Jab, Uppercut (punch), Ground Slam, Slam Impact, Special Move 1, Uppercut (special) | ⚠️ 6 moves, 1 clip |
| `79937990476934` | Cross Left | |
| `99362983788110` | Cross Right, Desperate Counter | counter can share |
| `84162023451491` | High Kick | |
| `71573540671127` | Low Kick | |
| `87872094663324` | Power Kick, Special1, Rival Decisive Finisher | ⚠️ 3 moves |
| `89487629068473` | Wheeldrive, Slam (special) | ⚠️ 2 moves |
| `71743026406362` | AOE Arc Jump Smack Down | |

### 2.2 Blocks

| Asset ID | Used as |
|---|---|
| `81580688159305` | Block, Block Front |
| `71555510097974` | Block Left |
| `81446994688965` | Block Right |

### 2.3 Dodges

| Asset ID | Used as | Notes |
|---|---|---|
| `131563762426355` | Procedural Evade 01 | |
| `135253684509200` | Procedural Evade Enemy 02 | |
| `90546747503310` | Procedural Jump / Evade 01 | |
| `71421932655009` | Tactical Backstep Hop | ⚠️ same clip as Strafe Left Walk |

### 2.4 Hit reactions, knockdowns, get-ups, deaths

| Asset ID | Used as | Notes |
|---|---|---|
| `83869147275692` | Light Hit Flinch, Knockback | ⚠️ also Kinetic Braking Skid (movement) |
| `82096408080514` | Heavy Hit Recoil | |
| `88475997278069` | Airborne Tumble, Slam Shockwave Blast, Fall Air Knockback | |
| `131344167080457` | Knockdown from Behind 01 | |
| `95406088712190` | Get Up Back (Ninja Fast) | |
| `128158227118276` | Get Up Back (Slow Recovery) | |
| `108624065264351` | Get Up From Crouch | |
| `79207866638803` | Recover to Feet, Ground Slam Recovery Rise | |
| `80496269227852` | Standard Defeat Collapse, Defeat Collapse | |
| `122802842451487` | Decisive Finisher Knockout | |

### 2.5 Stance

| Asset ID | Used as | Notes |
|---|---|---|
| `109837817595150` | Fight Idle / Combat Idle | no markers needed; also used by Survey Idle, Assess Target and Beam Struggle |

### 2.6 How hit reactions work today (to be replaced)
- **Selection:** `DamageModule.apply` plays a **random** pick of the two reaction clips (Light Hit Flinch or Heavy Hit Recoil) on every landed hit. Strength, location and side are ignored, and the "light flinch" is the braking-skid clip.
- **Direction:** a procedural lean (client, `ImpactDir` / `ImpactMag`) is the only direction-aware part.
- **Stun:** fixed at 0.35 s light and 0.5 s heavy.

---

## Part 3. The full clip list the combat needs

**Status:** ✅ exists (own clip) · 🔁 exists but shared (needs its own clip) · ➕ new.

**Mirrors:** Roblox cannot mirror an animation at runtime, so every Left/Right pair is two clips (a quick mirror in Blender). The names are the proposed AnimationConfig keys.

### 3.1 Stances and combat footwork

| Name | What | Status |
|---|---|---|
| `FightIdle` | guard stance loop | ✅ `109837817595150` |
| `GuardIdle` | holding a raised guard (loop) | ➕ |
| `StepForward` / `StepBack` | short footwork steps in stance | ➕ |
| `StepLeft` / `StepRight` | lateral footwork in stance | ➕ (the strafe walks are run cycles) |
| `Taunt` | between exchanges, personality | ➕ optional |

### 3.2 Strikes: punches

| Name | Limb | Status |
|---|---|---|
| `Jab` | LeftHand | 🔁 `113219639247452` |
| `Cross` | RightHand | ✅ `99362983788110` (Cross Right) |
| `CrossLeft` | LeftHand | ✅ `79937990476934` |
| `HookLeft` / `HookRight` | hand | ➕ |
| `Uppercut` (L/R) | hand | 🔁 `113219639247452` |
| `BodyJab` / `BodyHook` (L/R) | hand, to the body | ➕ |
| `Overhand` | RightHand, heavy | ➕ |

### 3.3 Strikes: kicks, knees, elbows, other

| Name | Limb | Status |
|---|---|---|
| `HighKick` | foot | ✅ `84162023451491` |
| `LowKick` | foot | ✅ `71573540671127` |
| `PowerKick` | foot | 🔁 `87872094663324` |
| `FrontKick` (push kick) | foot | ➕ |
| `SpinKick` / `Wheeldrive` | foot | 🔁 `89487629068473` |
| `Knee` (L/R) | knee | ➕ |
| `Elbow` (L/R) | elbow | ➕ |
| `Headbutt` | head | ➕ optional |
| `ShoulderCharge` | body | ➕ optional |

### 3.4 Strikes: specials, finishers, counters

| Name | Status |
|---|---|
| `GroundSlam` / `SlamImpact` / `SlamRecovery` | 🔁 slam clips shared |
| `SmackDown` (arc jump) | ✅ `71743026406362` |
| `Special1` | 🔁 `87872094663324` |
| `RivalFinisher` | 🔁 `87872094663324` |
| `Riposte` (after a perfect parry, fast) | ➕ (today a jab) |
| `DesperateCounter` | ✅ shares Cross Right (acceptable) |
| `ChargeLoop` / `ChargeRelease` | ➕ optional, for charged specials |

### 3.5 Blocks and parries

| Name | Status |
|---|---|
| `BlockFront` / `BlockLeft` / `BlockRight` | ✅ |
| `BlockLow` (vs low kicks) | ➕ |
| `BlockHit` (L/R/Front): guard absorbs a hit, slides back | ➕ |
| `Parry` (L/R): deflects the strike aside | ➕ |
| `GuardBreak`: guard smashed open, stunned | ➕ |
| `Parried`: the **attacker's** recoil when parried | ➕ |

### 3.6 Dodges

| Name | Status |
|---|---|
| `SlipLeft` / `SlipRight` (head slips) | ➕ |
| `Duck` | ➕ |
| `Backstep` | 🔁 `71421932655009` (strafe clip) |
| `SidestepLeft` / `SidestepRight` | ➕ |
| `Evade01` / `Evade02` | ✅ procedural evades |
| `Roll` (L/R) | ➕ optional |
| `EvadeJump` | ✅ `90546747503310` |

### 3.7 Hit reactions (on their feet)

| Name | Plays when | Status |
|---|---|---|
| `FlinchLight` | any light hit (generic fallback) | ➕ (today the braking skid) |
| `HitHeadFront` | jab or straight to the face: head snaps back | ➕ |
| `HitHeadLeft` / `HitHeadRight` | hooks: head twists aside | ➕ |
| `HitHeadUp` | uppercut: chin up, onto the toes | ➕ |
| `HitBodyFront` | body straight or front kick: folds forward | ➕ |
| `HitBodyLeft` / `HitBodyRight` | to the ribs: crunches sideways | ➕ |
| `HitLegBuckle` (L/R) | low kick: the knee buckles | ➕ |
| `HitHeavyStagger` | power hit: 2–3 steps back, arms out | 🔁 Heavy Hit Recoil `82096408080514` can serve |
| `HitBack` | from behind: jolts forward, half turn | ➕ |
| `HitSpinOut` | heavy side hit turns the body | ➕ optional |

### 3.8 Knockdowns, air and wall

| Name | Status |
|---|---|
| `KnockdownBack` (falls on the back) | ➕ |
| `KnockdownFront` (falls on the face) | ➕ |
| `KnockdownBehind` | ✅ `131344167080457` |
| `AirTumble` / `AirHit` (hit while airborne, juggle) | 🔁 `88475997278069` shared with fall/slam |
| `LaunchUp` (uppercut launch) | ➕ optional |
| `WallSplat` (hits a wall, slides down) | ➕ |
| `GroundHit` (hit while down) | ➕ optional |

### 3.9 Get-ups and deaths

| Name | Status |
|---|---|
| `GetUpBackFastNinja` (instant recovery) / `GetUpBackFast` / `GetUpBackSlow` / `GetUpFrontFast` / `GetUpFrontSlow` / `GetUpFromCrouch` | ✅ |
| `GetUpFront` (from face down) | ➕ |
| `GetUpRoll` (roll away, then up) | ➕ optional |
| `RecoverToFeet` | 🔁 `79207866638803` shared with slam recovery |
| `DeathCollapse` / `DeathFinisher` | ✅ |

### 3.10 Grabs and throws (new category; only if wanted)

| Name | Status |
|---|---|
| `GrabAttempt` (attacker) | ➕ |
| `GrabWhiff` | ➕ |
| `ThrowForward` / `ThrowBehind` (attacker) | ➕ |
| `Thrown` (victim, lands with `Impact`) | ➕ |
| `GrabBreak` (both) | ➕ |

### 3.11 Clashes (two strikes meet)

| Name | Status |
|---|---|
| `ClashRecoil` (both bounce off a fist or shin clash) | ➕ |
| Mid-air clash and beam struggle | ✅ existing systems (procedural) |

### Rough count

| | Exists | Shared | New |
|---|---|---|---|
| Strikes | 6 | 5 | 14+ |
| Blocks | 3 | — | 5 |
| Dodges | 3 | 1 | 6+ |
| Reactions, knockdowns, get-ups | ~9 | 3 | 15+ |

Grabs and footwork are optional extras.

---

## Part 4. Working through it

1. **Untangle the shared clips first** (Part 2 ⚠️), so each move can carry its own markers.
2. **Add markers to the strikes** (`HitStart`/`HitEnd`/`Recover`), then blocks and dodges, then reactions (`Recover`, `Impact`). Overwrite on publish to keep IDs.
3. **New clips in priority order:**
   1. `FlinchLight` (stop hits playing the skid);
   2. the 4 head reactions;
   3. Hook L/R;
   4. body and leg reactions;
   5. `BlockHit` / `Parry` / `Parried`;
   6. slips and duck;
   7. knockdowns and get-ups;
   8. the rest.
4. **Send new IDs with their Part 3 names;** they go into AnimationConfig under those keys.
5. **Planned code side** (combat reorganisation):
   - read the markers ahead of play (`KeyframeSequenceProvider`, and the in-place `RBX_ANIMSAVES` copies so marker tweaks test without publishing);
   - per-move frame data;
   - limb-following hitboxes;
   - reaction choice by hit location, side and weight;
   - a marker checker and a Combat Lab test mode (see TEST_MODES.md).
