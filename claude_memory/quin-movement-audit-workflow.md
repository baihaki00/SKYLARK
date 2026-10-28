---
name: quin-movement-audit-workflow
description: "How to run, measure and visually inspect the 16v16 Quin battle in QUIN_COMBAT.rbxl, plus non-obvious traps found during the 2026-10-01 movement audits"
metadata:
  node_type: memory
  type: project
  originSessionId: aab93d9f-4a24-4c2a-9a6e-34e1919e40d6
  modified: 2026-10-01T06:50:53.665Z
---

QUIN_COMBAT.rbxl (Roblox Studio MCP) is where the Quin combat AI lives; the local repo folder only holds a backup. Since 2026-10-03 the owner publishes it to Roblox as **QUIN_COMBAT_V2 (placeId 135832583650579)**; the MCP studio_id changes per Studio session, so call list_roblox_studios first. Two movement audit passes of the 16v16 team battle were done on 2026-10-01 (backups `ServerStorage.backup_pre_16v16audit3/4_20261001`).

**Run the 16v16 from MCP:** start play, then from the *Client* datamodel run `game.ReplicatedStorage.GameCommand:FireServer("team", 16)`. `_G`/`shared` from execute_luau are a separate context from game scripts (and `require` gives a separate module instance, so CombatConfig cannot be changed live), but `_G` persists between execute_luau calls, enough to keep a Heartbeat sampler alive and read it back.

**Measure, don't eyeball:** server Heartbeat sampler over `CollectionService:GetTagged("Quin")` counting per-frame velocity jumps (>18 studs/s), yaw jumps (>20 deg), teleports, animation plays per state; compare at the same match time (57s). Client RenderStepped sampler for IKControl Enabled toggles and bone heights (`TransformedWorldCFrame`).

**Look at poses:**
- Edit mode pose lab: clone a rig into Workspace, `Animator:LoadAnimation`, `Animator:StepAnimations(dt)` to a time, then `screen_capture` with camera args. Deterministic. `KeyframeSequenceProvider:GetKeyframeSequenceAsync` gives hip translation/rotation per keyframe.
- In play: the game's camera script overrides the capture camera. Bind a client `BindToRenderStep` at `Last+50` that sets `CurrentCamera.CFrame` from a `_G` value, then call `screen_capture` with no camera args. Freeze a Quin for a shot by anchoring its root and writing `AssemblyLinearVelocity` on the anchored part each tick (velocity-driven poses keep working); slow a move with `workspace:SetAttribute("GameSpeedMultiplier", 0.05)`.
- Force a projectile jump style: set `ForceJumpStyle` then `ForceAction = "projectile_jump"` on a Quin in Fight.

**Traps:**
- Arena centre is (0, 0, -438), not the world origin; walls are inside the out-of-bounds margin. Use `SpatialModule.getArenaBounds()`. The ground part is `Workspace.argoniaonion.ArenaOne.ArenaGround`; code that looks it up as a direct child of `argoniaonion` silently falls back to the origin (this made Quins "cornered" 39% of the time until pass 6; `getArenaCenterPull` still has it and returns zero).
- A behaviour that looks like a combat rule may come from the decision layer: the constant one-punch launches were `DecisionSystem` re-arming `DesperateCounter` every tick during a false last stand. Trace who triggers an action before tuning it.
- The MCP `screen_capture` does not show BillboardGuis at all, and HandleAdornments only render with the default `ZIndex` and an adornee near the camera. Do not conclude "text is broken" from a capture.
- `user_mouse_input` with `instance_path` clicks HUD buttons; `user_keyboard_input` presses keys. Use them to drive client UI state that `require` from the command bar cannot reach (separate module instance).
- Several client scripts bind the same key (F was fly, two free cameras and punch). Grep all of `StarterPlayerScripts` and `StarterGui` for a key before rebinding.
- Timestamps are mixed: some attributes written with `os.clock()`, read with `tick()`. Check both sides of any cooldown.
- Several scripts have CRLF line endings; multi-line `multi_edit` fails on them. Normalise, or edit via execute_luau with plain `string.find` spans and a `loadstring` compile check (works in Edit mode).
- The Animator scales clip bone translation by `Model:GetScale()`. QuinFemale was at 0.044 (fixed by moving its children into a fresh Model); any re-imported rig must be checked.
- The Humanoid floats the root 5.11 above the floor (HipHeight 3.8 + half root), not the 5.36/5.4 quoted in older comments.
- `RunTurn90Left/Right`, `RunTurn180`, `Turn180Pivot` are one clip (177 deg hip pivot); `ArcRun30RearLeft/Right` are one clip; `GetUpBackSlow` has no hip translation (floats). Flags in CombatConfig keep the turn/arc overlays off.
- IKControl writes its solve into `Bone.Transform`/`TransformedWorldCFrame`: once on, the clip pose is unrecoverable that frame. Do foot logic that needs the clip pose with a script-side leg solve (pass 13). Probe final poses in `RunService.PreAnimation`, not RenderStepped (order vs the presentation handler is unknown).
- Client scripts write telemetry attributes onto the server Quin models; check a name is not also a server-written input before using it (`GazePitch` collision, pass 13).
- Shuffle metric: a foot counts as planted below max(1.5, 15% of body speed); a fixed 1.5 counts good sprint plants as skating. The winning clip is the highest-PRIORITY track with weight > 0.3, not the highest weight.
- AnimationModule caches one track per asset id: two config entries with the same id (Survey = FightIdle) share a track and overwrite each other's Looped/Priority.
- Pose lab for clip facing: compare hips TransformedWorldCFrame.LookVector with the root's (idle = +0.99); also check hip translation size for export-scale errors.
- Spike A/B: compare the MEDIAN Quin's rate, not bucket totals (a few Quins dominate; totals swung 4->42 for the same setting).
- MovementTestArena: `GameCommand:FireServer("movement_test")` = runner chases an anchored target down the hurdle line (2..83 studs); arena bounds switch with CurrentMode.
- Glitch metric: "angle change > 25 deg/frame" also counts normal fast motion (run arm swing is 10-20 deg/frame at ~46 fps). Use spikes (a >10 deg reversal on two consecutive frames) and alternate off/on in 10 s blocks in one match; later match windows have more fighting, so unpaired windows mislead.
- Client-side A/B: a workspace attribute set from the Client datamodel is read by client presentation code in the same match (`FootPlant`, `ProceduralStyle`).
- The Studio console output tool returns only BattleEvent spam; hook `LogService.MessageOut` for errors instead.

- Ground states (Chase, Fight) update at 10 Hz: at 40 studs/s a Quin moves 4 studs per tick, so distance-triggered actions (takeoffs) need a `task.delay` to the exact moment.
- MovementTestArena: the runner can beat the anchored target (then it idles); re-send `movement_test`. Check obstacle sizes before teleporting a Quin (the hurdle blocks are up to 46 deep).
- `StrikeResult`/`StrikeSeq` attributes (pass 17) give per-strike outcomes for fight audits.

- Studio MCP after a Studio restart (2026-10-03) runs SANDBOXED: no `_G`/`shared` persistence between calls, cannot `require` game modules, cannot fire GameCommand from the Client, cannot parent new Scripts to ServerScriptService; editing existing script Source still works. Start modes from the Server with `workspace:SetAttribute("DevCommand","movement_test" | "team:16")` (Studio-only hook in GameModeManager) and inline test harnesses in each call. Export slices must rebuild the JSON per call.
- Owner's MovementTestArena courses (pass 18): JUMPLANE z383, SKIDLANE z425, VAULTUNDERLANE z340, JUMPONOBSTACLES z304 (150x8 lanes, x -261..-111, top y21, floor is lava) and a circle slab at (-329, top 5, 387). Lap a Quin on real locomotion with attributes DevLapRadius/DevLapCenter (Studio only). Debug attributes: SkidPlan, JumpSkip, ObstaclePace, EdgeHeld.
- Humanoid.FloorMaterial / state lag a landing by tenths of a second: use LocomotionModule.isOnGround (ray). The Humanoid adds JumpPower on the step after entering Jumping (jumps below 50 studs/s flew at 50 until pass 18).

**Why:** the user's complaint is jerky / stiff / awkward Quin motion; they want every cause found and measured, minimal correct fixes, no invented features, and they like the projectile jump as designed.
**How to apply:** back up first (existing convention), measure, fix the cause, re-measure, verify poses with a screenshot. Open after pass 2: wall-runs are rare (chase steering avoids walls before a run can start), obstacle-blind strafing in Circling, AirborneState never reached from ground combat, no landing animation on hard landings (deliberate in code).
- `DevGoal` / `DevGoalSpeed` attributes (Studio only, pass 20) make a Quin run at a point on real locomotion at 10 Hz; clear floor for turn tests: MovementTestArena x -660..-460, z 440..560. Planted-toe metric on the server: ToeBase bone y < 2.35 (straight run slips ~3.5 studs/s). Client bone probes of AI Quins are unreliable (straight run reads 45).
- Sandbox: server `task.spawn` threads survive the call (schedule a server action, then sample on the client in a parallel call); client threads die with the call. New scripts CAN be created in ReplicatedFirst and StarterPlayerScripts via multi_edit (className). A ReplicatedFirst LocalScript writing a Workspace attribute is how to log the first frames after join.
- Arena System (pass 21): Studio-only Workspace attribute `ArenaDevCommand` = `start <json cfg>` / `skip` / `stop` drives the orchestrator. Arena scripts drifted from git once (someone edited them in Studio): before any arena work, hash-compare Studio vs `studio_snapshot` and commit the found state first. execute_luau calls time out at ~60 s (client calls sooner, ~10 s): run long tests as a server `task.spawn` that writes a log into a Workspace attribute, then read it back. A client call that holds the camera (BindToRenderStep) in parallel with `screen_capture` gets an in-play screenshot.
- Roblox UI traps: UIListLayout with all LayoutOrder 0 sorts by Name; TextLabel.TextSize caps at 100; Gotham/GothamBlack lack ✕ and ✦ (render as boxes).
- Workspace StreamingEnabled is ON in QUIN_COMBAT: client-side probes only see what is streamed to the player (check counts first); Quin models are Persistent since pass 21d.
- Owner recordings come as GIFs: split them into a frame sheet with PIL (ImageSequence) and look at consecutive frames; single-frame artifacts only show up that way.
- Model.LevelOfDetail cannot be written by game scripts (needs Plugin capability) - set it only in Edit mode. Writing it in QuinSpawner broke every spawn (pass 21e -> fixed 21f). After any risky edit, run an Arena System match through to IN_GAME and Play As Quin (P) before reporting.
- The owner also uses Gemini on this place: it can add scripts (e.g. GhostHunter_AutoSpawn). Before each session, hash-compare Studio vs git and look for NEW scripts.
- If MCP start_stop_play is stuck on "Start play hasn't finished yet" (after a timed-out start), start Play from the Edit datamodel with `task.spawn(function() game:GetService("StudioTestService"):ExecutePlayModeAsync({}) end)`; after that start/stop works again. Play As Quin check: press P on the Client, then `workspace.CurrentCamera.CameraSubject` is `PlayerCostumes.Costume_<name>.Humanoid`.
- Studio throttles Play to ~15 fps when its window is in the background (server and client; `Stats.HeartbeatTimeMs` stays low, physics stays ~53 Hz). Check Heartbeat fps before trusting any per-frame metric; ask the owner to keep Studio focused for those runs. In the sandbox, RBXScriptConnections made inside a `task.spawn` do not survive the call: use a `while ... RS.Heartbeat:Wait()` loop in the spawned thread and write results to a Workspace attribute.
- Never count "more than N degrees in one frame": it depends on frame length (the owner switches windows mid-run and Studio fps drops). Use AssemblyAngularVelocity and seconds. Best A/B for a server-side constraint property: in one match, overwrite the property live on half the Quins from the probe and compare the halves. The sandbox cannot parent anything into ServerStorage (no Studio backups from MCP any more): the git snapshot is the backup - hash-compare first.
- The owner's client runs ~235 fps in the movement test; about 1 rendered frame in 13 has no animation step. Anything that edits Bone.Transform in RenderStepped must run once per PreAnimation. To read the pose that is DRAWN on the client: inside a RenderStepped handler use `task.defer` and read `Bone.Transform` there (Heartbeat/PreAnimation reads see the Animator's raw output on step frames and mislead). Walk demo: movement_test, runner at (-340,7.5,520) with Energy held at 10 walks at 7.5 studs/s (PaceReason Fatigue, same clip as the stalk); the runner needs the target within ~900 studs or it idles.
- Pose viewer (pass 23b, owner liked it): server-side clones of ReplicatedStorage.QuinType.QuinMale/QuinFemale, anchored, playing a clip in place with BillboardGui labels (clip name, id, time, frame at 30 fps) plus the same label on the live runner; Workspace attrs PoseViewerSpeed / PoseViewerPaused / PoseViewerFrame. The owner screenshots the bad frame -> compare raw vs live. movement_test runner gender is random: re-send until Gender=Male. Stance-slide metrics with fixed foot heights mislead across rigs; use planted-foot slip speed or drawn-vs-clip joint angles.

**2026-10-04:** pose-level edits (Bone.Transform written in RenderStepped) must be measured in the render step after the edits, not at PreAnimation: with Studio in the background the engine runs about 4 animation steps per drawn frame and the in-between steps show the unedited pose. See [[iklab-ikcontrol-experiment]].
