# Fight Programme step 2: body channels

Step 2 of [FIGHT_PROGRAMME.md](../FIGHT_PROGRAMME.md), built 2026-10-29 in Studio (QUIN_COMBATV4). It separates what the arms do from what the legs do, so a punch can be thrown while the legs keep their footwork. **Still waiting on:** the owner's eye.

## The idea

Today every strike clip keys the whole body. When a punch plays, it owns the legs too. FightState then plants the body for the length of the strike: punches thrown on the move used to slide on 56–59% of frames, and this plant was the fix.

A clip now says which part of the body it drives, with a `channel` field in AnimationConfig:
- `"Body"`: all of it. This is the default, and every clip in the game today is Body.
- `"Arms"`: the upper body only.
- `"Legs"`: the legs only. Any Movement-tier clip with no channel counts as Legs (the gait, strafes, steps).

An arms clip and a legs clip play together and never cut each other. Everything else stops and starts exactly as before.

## What changed

| Where | Change |
|---|---|
| `Modules/AnimationModule` | `channelOf(trackId, priority)` reads `channel` from AnimationConfig (cached for 1 s). In `play()`'s stop rule, two tracks on different channels (Arms and Legs) both play on; only a finished one-shot lingering at its end pose is cleared. |
| `AnimationConfig` | A note on the `channel` field. No clip has one yet. |
| `States/FightState/Strike` | Publishes `StrikeChannel` on the Quin at strike start. |
| `States/FightState` | The plant-while-striking brake is skipped for an Arms strike. During an Arms strike the gait is updated from the body's real velocity, so the legs step with the step-in instead of gliding in the fight idle. |
| `Modules/ProceduralCombatReactionController` (client) | `StrikeFeetFree` lets go of the feet only for strikes that own the legs. During an arms strike, the foot planting stays on. |
| `Modules/StrikeMarkers` | `alias(sourceId, newId)`: a copy of a clip keeps its markers. |
| `Modules/ChannelLab` (new, Studio test bench) | `armsOnly(id)` makes an arms-only copy of any strike clip: the Hips key is emptied (weight 0, so the spine above still plays), the legs' keys are removed, and the markers are kept. `setArmsOnlyPunches(on)` swaps both punches for those copies live. `saveArmsOnlyPunches()` (Edit mode) puts the copies in `ServerStorage.ArmsOnlyClips` for publishing. |
| `ServerScriptService.Server` | Studio only: the Workspace attribute `Test_ArmsOnlyPunches` calls `ChannelLab.setArmsOnlyPunches`. |

**Switches:**
- With no clip carrying a channel, the game behaves exactly as before.
- `Test_ArmsOnlyPunches = true` (Studio play) turns arms-only punches on; false puts the real punches back.
- The copies use temporary ids that only work in Studio. Nothing ships until the owner publishes a clip.

## Measured (1v1, 50 s each, client)

| During a strike | Body strikes (kicks, today's punches) | Arms-only punches, before the gait fix | Arms-only punches, with it |
|---|---|---|---|
| A legs clip playing (Movement tier, weight > 0.3) | 23–25% | 25% | **49%** |
| Body moving faster than 3 studs/s | 37–46% | 52% | 50% |

- **Before the fix:** arms-only strikes moved the body half the time with no stepping clip on the legs, so the legs stood in the fight idle and glided.
- **With the fix:** the legs clip is on about as often as the body moves.
- **Feet:** a crude "lowest foot moving faster than 4 studs/s" count read 61% for both kinds of strike, so it doesn't separate them. Judge the feet by eye.
- **16v16, switch off:** no errors in the console. The server frame read 24 ms median over the first 40 s of the match, measured as raw Heartbeat time. That isn't the same method as step 1's 21.9 ms (flow probe, 240 s), so it can't be read as a change. Recheck it in the next step's full probe run.

## For the owner to judge

1. Play, start a 1v1, set the Workspace attribute `Test_ArmsOnlyPunches` to true. The punches become arms-only; kicks stay whole-body.
2. Watch punches thrown while stepping in or circling. The legs should keep walking under the punch, instead of the whole body freezing into the punch pose.
3. Set it back to false to compare.

**Things to look for:**
- The arms-only punch loses the hip turn and weight shift the full clip had, because the Hips key is gone and only the spine twists. It may look like "arm punching". If so, the real answer is a punch authored for the Arms channel (hips left to the legs, more spine and shoulder), not this stripped copy.
- Where the gait is standing still, the legs hold the fight idle under the punch.

**If it looks right:**
- In Edit mode, run `require(game.ReplicatedStorage.QuinCore.Modules.ChannelLab).saveArmsOnlyPunches()` from the command bar.
- Publish the two KeyframeSequences in `ServerStorage.ArmsOnlyClips` (right-click > Save to Roblox).
- Then either swap them in, or add them next to the full-body punches with `channel = "Arms"`. Keeping both gives two kinds of punch: a planted power punch and a moving jab.

## Round 2 (after the owner's first look, 2026-10-29)

The owner reported five things.

**1. "I don't see the punch while stepping."**
- `Test_ArmsOnlyPunches` was never set in that playtest, so every punch was the full-body clip. Setting it in Edit mode before Play wouldn't have worked either: the hook only listened for changes.
- **Fixed in two ways:**
  - The hook also applies at start (`Server.server.lua`).
  - There is now an Arena System [O] toggle, "TEST: Arms-only punches" (`ArenaConfig.DefaultToggles.ArmsOnlyPunches`, applied by `ArenaSystemOrchestrator.applyWorldToggles`). It applies at match start and live. The match's toggle wins over the attribute.
- **Measured with it on (1v1):** 14 of 31 strikes were arms-only. Server tracks sampled while an arms punch plays and the body moves show the gait clips under it at a combined weight of about 1.0.
- The client count of "legs clip on during an arms strike" stayed low (14%). That is because `Attacking` stays true until the strike's finish time even after a hit has cut it short, and then a full-body hit reaction owns the body.
- **What to expect:** in this 1v1 the body moved during 32% of arms-strike frames. The rest of the time the Quins punch standing in the sweet spot, so the legs hold the fight idle. Footwork during punches (shuffling, circling while jabbing) is a decision the mind makes, which is step 6. Step 2 only makes it possible.

**2. Pause bug: one Quin's arms stuck straight out in the scrubber.**
- The recorder (`QuinRecorder`) listed a Quin's bones once, the moment the Quin appeared on the client. A Quin seen half-streamed was recorded without its arm bones, so its ghost held the bind pose.
- Before the fix: 85 poses a frame for 2 Quins. After: 124, for 122 live parts and bones.
- **Fixed:** parts and bones that stream in later are added. Only the pause view was affected.

**3. "Punching the air while both are on the ground: do they target the head, the arms, the legs?"**
- **They don't aim at a body part.** Each clip has its own height:
  - punches about 1.1 studs above the root (chest / head);
  - low kicks about −2.8 (legs);
  - high kicks and wheel kicks about +1.3.

  The hit check is a box in front of the attacker that counts the whole body as one target.
- **A strike visibly meets air when:**
  - it was thrown from too far: a whiff started at 7.5–10 studs, and the clip reaches about 5;
  - the target leaned out of it, which counts as Dodged by design;
  - it was cut by a hit (Interrupted, about a quarter of strikes): the arm still goes out.
- In two 45 s runs there were 4 whiffs: 2 thrown from out of reach, 1 across a height difference, 1 other.
- Aiming at head / body / legs is steps 3 and 5 (hit zones, guard height, openings).

**4. Bodies still clip while closing in.**
- **Added:** `Spacing` now judges a closing body's gap 0.1 s ahead (`Spacing_LookAhead`). The server's hold reaches the client that moves the body a frame or two late, and two bodies closing at once ate the gap in that time.
- **Measured (1v1, 42 s):** roots under 3 studs on 0.1–0.3% of frames. That compares with 2.0% in step 1's 150 s run (% of engaged time), and 8.9% at baseline.

**5. The quick evade slides.**
- The quick-evade clips are in-place leans. Two paths played them on top of a 35 studs/s push for 0.25 s, about 8 studs, which is the 27.8 studs/s in the owner's pasted card:
  - the FightState "dodge" action;
  - the Instinct slip fallback, used when Evasion can't play.
- **Fixed in FightState:** a dodge with a strike coming is now the in-place evade (`Evasion.evade`: the clip's own ~1.4-stud sway; the strike misses while the lean is in). A dodge with nothing coming is a short step (`Flow_DodgeSlideSpeed` 12, about 3 studs).
- **Measured:** the fastest evade went from 27.8 to 10 studs/s.
- The Instinct fallback (out of Fight / Circling, on the run) still slides, as it was written to do.

## Round 3: the arms-only punch went up into the air

**What the owner saw:** the arms-only copy wasn't aimed at the enemy; the arm went up. Emptying the Hips key also took the punch's hip turn and tilt away from everything built on the hips (spine, chest, shoulders, arm). The arm then pointed wherever the stance's hips faced.

**Fixed in `ChannelLab.armsOnly`:** the hips' rotation is moved into the Spine key (rest⁻¹ · hipsRotation · rest · spine), so the chest keeps the full clip's angle in the root's space. Only the hips' drop and forward shift are left to the legs.

**Measured** on a still dummy at the HitStart frame, in studs from the root (x right, y up, z forward):

| | Punching hand | Chest (Spine2) |
|---|---|---|
| full LeftPunch | (−0.24, 1.59, 3.73) | (0.07, 0.22, 0.84) |
| arms-only LeftPunch | (−0.07, 1.88, 3.30) | (0.24, 0.51, 0.40) |

The punch now goes the same way, 0.3 higher and 0.4 shorter: the hips' drop and lean that the full clip has and the copy leaves to the legs. RightPunch mirrors it.

**Still true:** no punch aims at a body part. A clip lands where it was animated, and the fist meets the target at head height because that's where the clip puts it. Aiming at head / body / legs is step 3 onward.

## Not done in this step

- **The Cascadeur converter's "arms only" option** (in the plan). It waits until the owner wants to author arms clips in Cascadeur; ChannelLab covers testing until then.
- **`AnimationModule.stopCategory` is defined twice** (the second definition wins). Step 2 didn't need it, so it was left alone, as the plan said.
