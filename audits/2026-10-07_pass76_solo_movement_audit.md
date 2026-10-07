# Pass 76: Solo movement audit (the owner's list after the first Solo test)

The owner drove their Quin alone in Solo and listed what felt wrong. Each item was measured in Studio (Solo match, driven through the `PilotTestInput` hook, server and client sampled), fixed, and measured again.

Probes: [scripts/solo_turn_probe.lua](../scripts/solo_turn_probe.lua), [scripts/solo_jump_probe.lua](../scripts/solo_jump_probe.lua). The other checks were run inline from MCP and are described below.

## What was found and fixed

| Owner's note | Found | Fix | After |
|---|---|---|---|
| Spawned off the dais | With Instant Match the Quin was stood on the dais while it was still rising: inside it, pushed out onto the floor (found at x 72, z −495; the dais is centred at 0, −438). | The player modes wait for the dais to finish rising (`SocialRespect.daisRiseTime`). | Spawns on top, at the centre. |
| **Walking up the stairs is not smooth** | Eight tiers, each 0.375 studs high and 0.75 deep: the body popped up eight times. | An invisible ramp over the steps: 72 wedges, floor to top (`CeremonyRamp`, on by default). The steps are still what you see. | Jogging up: sum of vertical-speed changes 52 → 2. Running: 67 → 46 (what is left is the two corners of the slope). |
| **Normal jump feels boxy, hangs at the apex** | The jump clip (Jump Launch, also used by the vault) lifts the hips **4.3 studs** above the body's real arc, peaking at 0.28 s. The mesh shot up to +16, sat flat at the top for about 0.05 s, then dropped. | Clip correction `noLift` (`CombatConfig.ClipCorrections`): the clip's hip rise above the rest pose is removed, so the body's arc is the jump. | Hips stay within 0.4 studs of the body all jump (on the client). |
| **Can't move during a jump; locked, rough** | 1. A standing jump capped the in-air speed at the takeoff speed: **2 studs/s**. 2. The jump's facing hold kept the takeoff direction all flight. 3. Air acceleration 30. 4. The jump debounce counted 1.0 s from takeoff: after landing, about 0.3 s with no jump. 5. A jump pressed just before landing was dropped. | 1. A body may drift up to `Locomotion_AirDriftSpeed` (14) in the air (planned AI flights keep their exact speed). 2. The facing turns with the drift (`Locomotion_AirFacing`). 3. `Locomotion_AirAcceleration` 60. 4. Once down, only `Locomotion_JumpReplant` (0.05 s). 5. A jump buffer (`PlayerQuin.JumpBuffer` 0.15 s); a short tap still cuts it to a hop. | Standing jump plus sideways: 12 studs/s and 9.6 studs across before landing, the body turned toward the drift. Pressed 0.02 s before landing: off again 0.11 s after touching down. |
| **Running on air for a while after landing** | Not on the server: there the feet reach the ground 0.07 s after the landing. On **the client**, the body's position arrives ~0.2 s after its animations (positions are interpolated, clips are not). The run clip played while the body shown was still up to 7 studs in the air. | `Presentation_AirHold` (body layer `AirHold`, switchable): while the body shown is still over 1.2 studs above its ground, coming down, and the server has it on its feet, a local Fall pose covers it until it is down. | The run clip takes over when the body shown reaches the ground. |
| **Footsteps don't match the run** | The run clip's markers are right (about 20 ms early on the left foot), but at a sprint every other step comes 0.15 s after the one before: exactly the old anti-double debounce, so steps were dropped at random and the rhythm limped. | Debounce 0.15 → 0.08 s. (Steps doubled by blended clips are already silenced by clip weight.) | Every step sounds. |
| **Idle to walk: the knee breaks into a horse leg** | Sampled after the client's poser: setting off the other way, the body spins round at up to ~12 rad/s while a foot planted at idle (`PlantWhenStill`) stays pinned. The leg solve then bent the knee **backward** for ~0.1 s, about 20 frames per start (worst bend −1.0). Any one layer off still showed it; foot planting off removed it. | A knee only bends forward: the solver keeps it on the body's front side of the hip-ankle line. Also: the knee's bend is smoothed in the body's frame (it was in the world, so it lagged a fast spin), and the turn guard that loosens planted feet counts the body's own spin (it was only measured once moving). | 0 backward-knee frames in 12 starts (jog and run), all layers on. |
| **PJ only works aimed down, and then lands on the spot** | The aim's point was used as is. Aimed at the sky or a far wall, the point was high in the air, and the 120-stud look down from it found nothing ("nowhere to land"). Aimed at your own feet, it launched and came straight back down. | No nearer than `ProjectileJumpMinRange` (25) and no further than the reach (90). The ground is looked for from above the aim, so a high aim finds the top or the floor under it. Aimed at a wall's face, it lands in front of it. | Own feet: 30 studs. Floor 60 ahead: 62. Sky: 90 (style 1, apex +44), 90 (style 2, the high launch). |
| **PJ sometimes doesn't work (mana?)** | It needs 40 mana (`ProjectileJumpMinEnergy`); a jump to a spot costs 8, at a Quin 40. A V press in the air or mid-strike was dropped silently. The server's refusal note (`PilotNote`) was never shown. | The HUD shows mana with a mark at 40, the PJ gauge says READY or NEEDS MANA, and the note shows refusals ("Projectile jumps start from the ground", "Nowhere to land there", "Not enough mana"). | — |
| **Turning while running is stiff ("only one angle, 30°?")** | No 30° limit anywhere. Three delays add up: (1) the move direction came from the eased camera, ~0.1 s behind the mouse; (2) the body's turn at a sprint, a 180°/s mouse sweep trailed by 22°; (3) the client shows a server-run body ~0.2 s late. Also, the player's state turned AutoRotate back on every tick while the steer had it off for its own facing: the two fought. | (1) Steered by the mouse's target yaw (`shared.CameraTargetYaw` from SmoothCamera). (2) Agile grip 200 → 260, sprint turn cap 6 → 7.5 rad/s (every Quin: one body). (3) Not fixed here (below). AutoRotate flip removed. | At a sprint: a 30° turn 0.20 → 0.11 s, 90° 0.33 → 0.27 s, 360°/s sweep lag 114° → 44°, speed held at 40 through turns. |

## HUD (new)

At the bottom middle:
- health;
- mana, with a mark at the 40 a projectile jump needs;
- the jump gauge: Space held fills from HOP to FULL in 0.3 s, the cut window;
- the projectile-jump gauge: V held fills from ARC to ARC + DIVE in 0.3 s; "V: DIVE NOW" in a high launch; READY or NEEDS MANA otherwise;
- the server's note when something is refused.

A small dot at the middle of the view while in the air or aiming a projectile jump: what the aim is on.

## Also

- `ChaseState`: `if not X == false` (which happens to read as intended) written as `if X ~= false`.
- `PlayerQuin.JumpHeight` was in the table twice (8 and 11): the 8 is gone, 11 was the one in effect.
- Test hook: while it drives, the live client's input waits 1.5 s. The client sends a still "move" every 0.25 s and was overwriting the hook's moves, which is why some earlier hook tests didn't move.

## Not fixed: the ~0.2 s screen delay

A server-owned body is shown ~0.2 s behind the server (measured in Studio; more with real ping). Every turn and stop you make appears that late, on top of the turn itself.

The fix is to move the player's Quin's movement to the player's machine (network ownership plus a client-side driver for the same locomotion), with the server still running everything else. It is a larger change, and it touches the "server owns the body" choice from Pass 73, so it is the owner's call.

## 16v16 check (the grip and the air changes are every Quin's)

Flow probe, 240 s, generated arena (seed B9E405), against the phase 2–6 final:

| Measure | Phases 2–6 | Pass 76 |
|---|---|---|
| Strikes per Quin-minute | 15.4 | 15.1 |
| Hit / whiff / blocked / interrupted % | 66.6 / 6.8 / 3.8 / 22.6 | 69 / 6.2 / 3 / 21.6 |
| Engaged % / standing to decide % | 47.7 / 11.6 | 45.4 / 11.7 |
| Speed kept, Chase → Fight | 0.51 | 0.51 |
| Strike start speed, median | 15 | 15 |
| Answers % | 41.9 | 40.6 |
| In the air % | 12.2 | 12.2 |
| Swings per minute / CV | 12.2 / 0.27 | 11.1 / 0.25 |
| Knockdowns per Quin-minute | 3.40 | 3.17 |

The 16v16 is unchanged.

**Frame time:** the probe read 12.1 ms (median) against 4.9 ms before. The probe's measure is the Heartbeat step, which is the whole Studio process, client rendering included.
- Same session, same 16v16:
  - the previous build (HEAD, swapped back in for the test) read 11.0 ms;
  - this build read 8–10 ms;
  - an empty arena read 4.0 ms.
- So the difference is Studio's state today, not this pass. The body layers off change it by about 1 ms.

## Pass 76b (the owner's second test): the floating and the camera

**Running on air after a jump, 1–2 s (it was still there).**
- Reproduced with the client sending input the way PilotClient does. After a running jump on the dais, the body landed **1.75 studs above the dais top** and ran on air until it left the dais (about 2 s at a run).
- Narrowed down:
  - not the ramp, not the steps, not the cylinder shape, and nothing invisible under the feet;
  - it does happen on a copy of the dais part placed on the open floor;
  - it happens on any block **turned 90° on Z** (its local up pointing sideways);
  - the same block upright, or turned about Y, is fine;
  - standing jumps are fine.
- So it is a Roblox Humanoid quirk: landing at a run on a part laid on its side. The round dais tiers are cylinders, which are always laid on their side (their axis is X).
- **Fix:** the tiers are only seen now (no collision). The top is walked on as invisible upright strips (2 studs wide, `CeremonyFloorStrip`), with the ramp over the steps.
- **After:** running jumps at the centre, off-centre and sideways all land at standing height (+0.00, was +1.75), and the run up onto the top is smooth.
- **Elsewhere in the arena:** one obstacle (ArenaOne/OB, a 59-stud-tall block on its side) could do the same if a Quin lands on its top. MOVINGPLATFORM is laid on its side too, but it sits 645 studs up and unanchored, outside play.

**The camera (owner: "locked to the body during turning").**
- SmoothCamera pinned its focus dead-centre on the root every frame ("zero lag centering", added in an earlier pass for spectating). Running sideways or cutting across, the body never moved on the screen; the world slid past it. A jump left the body fixed on screen while the floor dropped away.
- **Fix:** on the Quin the player pilots, the focus follows with a capped lag:
  - 4/s sideways and in depth, 6/s up and down;
  - at most 5 studs to the side, 3 in depth, 4 up or down.
- Spectating an AI Quin keeps the dead-centre framing.
- **Measured on the client:**
  - running sideways, the body moves to about 10% of the screen width off-centre, and the view catches up when it stops;
  - a jump now shows on the screen: the body rises about 14% of the screen height, then drops below centre on landing until the view catches up.

## Pass 77: the player's machine moves its Quin, as in Play As Quin

Owner: "make it like play as quin".
- Play As Quin feels immediate because the player's machine moves that Quin.
- Player Quin mode moved the body on the server, and the screen showed every key and mouse turn ~0.2 s late. During a mouse turn the body looked "locked" to the camera.

**Now (`PlayerQuin.ClientMovement`, on):**
- **Handover:** while the Quin is in Piloted, the server hands its body to the player (`PilotInput.giveBody`: network ownership, attribute `PilotClientMoves`).
- **The player's machine:** PilotClient moves it every frame with the same LocomotionModule steer driver and GaitModule as every Quin. That covers turning, air control, reversals, jump with buffer and cut, dash, slide and the ground contract.
- **The server keeps:** strikes, guard, the lock, the squared-up facing (the fight gyro, a constraint the owner's physics carries out) and projectile jumps. While its Quin strikes or guards, the body brakes on the player's machine.
- **The server takes the body back:**
  - on any hit that throws it: `KnockbackModule` (knockback, launch, skid, slam) calls `reclaimBody` first, because velocity the server writes on a body it does not own is ignored;
  - on leaving Piloted (`PilotedState.exit`: Knockback, Recovery, ProjectileJump...);
  - it hands the body back on re-entering Piloted, or 0.6 s after a hit that did not end Piloted (`ReclaimHold`).
- **No doubled clips:** the server's ground contract is off while the player's machine moves the body.
- **Test hooks (Studio):** Workspace `PilotTestMove = "x,z,pace"` and `PilotTestJump = seconds held`, read by PilotClient.

**Measured (client):**
- moving 0.05 s after the key;
- a 90° turn faced in 0.27 s;
- the run, stop and idle clips play;
- a full jump +12.5, a tapped hop +5.3;
- running jumps on the dais land at standing height;
- the server sees the body (velocity 40), and took it back for a projectile jump while the owner was testing.

**Known:**
- The leg clips played on the player's machine are not seen by the server or other players. Strikes and reactions, played by the server, are. That's fine player-vs-AI; PvP will need it.
- Not exercised here: a hit from an AI Quin while running (the owner was in the game).
