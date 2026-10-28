---
name: player-quin-mode
description: "Player Quin match mode (Pass 73, 2026-10-07) — the owner pilots a Quin vs AI Quins on the dais; how it is wired (shared AI paths, only inputs differ) and the owner's constraints"
metadata:
  node_type: memory
  type: project
  originSessionId: ea7205bd-c408-40a5-bbb1-9f9da28928a4
  modified: 2026-10-06T16:22:15.769Z
---

On 2026-10-07 the owner asked for an Arena System match mode, "Player Quin". They pilot a Quin against 1–16 AI Quins on the round dais, with obstacles optional. Their constraints:
- test how combat feels and watch the AI;
- player vs AI only, NOT PvP yet (but it should be a bridge to PvP later);
- focus on chase, retreat and combat;
- every addition shared between player and AI Quins: "only inputs would change".

**Wiring (Pass 73, `139a985`)**
- **Input chain:** `StarterPlayerScripts.PilotClient` (keys) → RemoteEvent `ReplicatedStorage.PilotInput` → `Modules/PilotInput` (started in Server.server.lua) → `States/PilotedState`.
- **Main:** a Quin with attribute `PilotedBy` (a UserId) skips AI targeting and decisions. Voluntary states map to Piloted; Knockback, Recovery, Death and ReEntry stay shared (`PILOT_STATES`).
- **Server owns the body.** The old Play As Quin "costume" (P key) is a separate client-owned path; it is kept for free roam but outside the fight.
- **Strikes:** `FightState.throwStrike` / `FightState.faceTarget` are public, and the AI's own light and heavy strikes use them too.
- **Arena:** the dais is `SocialRespect.buildDais/sinkDais`. Obstacles off = `ArenaGenerator.clearArena()`. The panel's Procedural Arena Generation toggle is the obstacles switch.
- **Tunables:** `CombatConfig.PlayerQuin`. AI projectile jumps are off in this mode (`AIProjectileJumps`).
- **MCP test:**
  - start a match: `ArenaDevCommand = start {"Mode":"PlayerQuin","TeamSize":2,"Toggles":{"InstantMatch":true,"ProceduralTerrain":false}}`;
  - drive it with `user_keyboard_input` / `user_mouse_input` on the Client;
  - freeze AIs with `IsInert`.

**Solo (Pass 75, `c61f517`):** mode `"PlayerSolo"` (panel button "Solo"). The player's Quin alone in the middle of the dais, for movement work. No time limit since 2026-10-08 (owner): it ends only on the Quin's death or a stop/skip; the clock display holds. The owner asked for it after finding the movement still needs work (2026-10-07).

**Pass 76 (Solo movement audit, 2026-10-07)**
- Fixed: the spawn waits for the dais to rise; an invisible ramp over the dais steps; the jump clip's 4.3-stud hip lift removed (`ClipCorrections` `noLift`); air drift (14), air facing and air acceleration 60; jump replant and a buffer; `Presentation_AirHold` against "running on air"; footstep debounce 0.08; knees only bend forward (the PlantWhenStill pin made a horse leg on starts); the PJ aim finds ground from above the aim (min range 25); the HUD and aim dot in PilotClient; steering from the mouse's target yaw (`shared.CameraTargetYaw`); grip 260.
- **The client shows a server-owned body ~0.2 s late** (positions are interpolated, clips are not). This is the main cause left behind the stiff feel. The fix is client-side movement for the player's Quin (network ownership); offered to the owner, not done.
- **Test traps:**
  - sample the client pose at `RunService.PreAnimation`; earlier render-step reads saw the raw clip;
  - the live client's still "move" overwrote hook input, so the hook now holds it off for 1.5 s;
  - tasks spawned by a Server `execute_luau` call can die with the call; keep driver loops blocking;
  - a Client background `task.spawn` recorder survives.

**Pass 77 (2026-10-07, owner: "make it like play as quin"):** the player's machine moves its Quin while it is in Piloted.
- **Handover:** `PlayerQuin.ClientMovement`; `PilotInput.giveBody` / `reclaimBody`; attribute `PilotClientMoves`.
- **The player's machine:** PilotClient drives LocomotionModule and GaitModule.
- **The server keeps:** strikes, guard, lock, the fight-gyro facing and projectile jumps. KnockbackModule takes the body back before throwing it. The server's ground contract is off while the client moves the body.
- **Test hooks:** Workspace `PilotTestMove = "x,z,pace"`, `PilotTestJump = seconds` (PilotClient; the server hook no longer moves the body).
- **Leg clips played on the client are not seen by the server or others:** a PvP to-do.
- **Trap:** the poser now runs at BindToRenderStep Camera-1. To see the drawn pose, sample at RenderPriority.Last+n; PreAnimation can catch unedited animation steps.
- **Studio trap:** if the owner is in Play, their keys drive the Quin during my tests.

**Pass 78 / 78b (2026-10-07/08): sharp turns.**
- **Reversals** plant and pivot from any pace above 3 studs/s.
- **The pivot keeps running:** 10 studs/s at 22 rad/s. The owner rejected a near-stop pivot ("idle animation / full stopping"): below `Gait_IdleBlendSpeed` 3 the gait fades into the idle.
- **Studio live tuning:** Workspace `Tune_<CombatConfig key>` overrides LocomotionModule.tune.
- **Pass 79:** the owner wants turnarounds straight back along the line (drew it), with no hook, and cornering kept as is. So: `Locomotion_ReversalStraight` brakes, flips and drives out while the body turns on the spot; `Gait_ReversalSpeedFloor` keeps the legs striding through it.
- **Pass 80:** turnarounds play Movement.RunTurn180 (turns right) with ClipCorrections `stripYaw`. The left clip is the owner's published mirror, 74343002398863 (Pass 80b). Each side plays its own clip. Air control 300, drift 40 (owner).
- **Tuning panel (Pass 78c):** Studio-only `TuningPanel.client.lua`, F3: 14 movement settings via Workspace `Tune_<key>` on the client (the player's Quin only), Print/Reset.
- **16v16 runs vary:** a single run read 9.9 % whiffs, then 5.7 %. Re-run before blaming a change.

**Open:** owner's by-feel review; no heavy-strike input; no AI allies; the social layer still runs.

Related: [[combat-markers-future]], [[arena-generation]], [[social-layer]]

**73b (`7dfcce2`):** owner's first try was "kinda shit": walking backwards, and the camera stuck on fast turns.
- TRAP: never set `humanoid.AutoRotate = false` in a state that steers. `LocomotionModule.steer` reads AutoRotate off + no own facing as strafing and keeps the body's facing (moonwalk).
- SmoothCamera yaw easing is now continuous, not the shortest way round (flicks over 180° stalled it).
- Client-side `AssemblyLinearVelocity` of server-owned Quins reads ~0; measure motion on the Server.

**Keys as of 2026-10-07:**
- WASD (camera-relative), hold Shift to run, Z walk;
- Space: tap for a short hop, hold for a full jump;
- left click strike, hold right click guard;
- C slide, Q/E dash;
- V projectile jump (tap = arc, hold = high launch, V again in the air = dive at the crosshair);
- T lock / unlock, G next lock.

Engaged footwork within 16 studs (unless running). Jump just before hitting a wall = wall tech. Test without a keyboard: Workspace `PilotTestInput` JSON.

**2026-10-12, run leap (`2185306`).** The owner wants a running long jump: run → one super-long airborne stride with a little running in the air → run, with no stop.
- `scripts/make_run_leap.lua` (Edit DataModel, loadstring via HTTP 58918) builds it from Movement.Run (109090784752055: 0.467 s cycle; Footstep at 0.167 = left contact, 0.433 = right contact).
- How it is built: it walks the run's phase, legs and arms exaggerated around the cycle's mean pose (x1.7 at the hang), lingers at the split, does one quick air cycle, and ends on the exact contact pose.
- It saves RunLeapRight / RunLeapLeft (28 keyframes, 0.9 s, markers Jump and Footstep) in `RBX_ANIMSAVES.QUINTESTMALE`. The owner publishes them.
- Preview strip: `audits/2026-10-12_run_leap_strip.jpg`.
- Wired in (`527f178`), then **REVERTED** (`dbb95b5`, 2026-10-12): the owner tried it and didn't like it. Jumps play the jump clip again. The published clips (Right 77977577669807, Left 134666516301359) and the generator remain. Don't re-wire unasked. A useful trick from it: choose a clip off the run's phase before `GaitModule.notifyLaunch` (which stops the run).
