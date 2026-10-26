# Test Modes

One-click diagnostic scenes for Quin movement and animation. They live in the in-game **Quin Manager** (`StarterGui.AnimationLabUI`, opened with the "Quin Manager [M]" pill) on the **TEST MODES** tab. Each card sends `SetTestMode` to `ServerScriptService.AnimationLabServer`, which starts the scene through `GameModeManager`.

| Card | What it is for | Server entry |
|---|---|---|
| Animation Sparring | two locked Quins for scrubbing clips | `GameModeManager.startTestAnimationMode` |
| Block & Counter Lab | directional blocks and ripostes | `startTestAnimationMode` + guard setup |
| Projectile Jump Lab | the 7 jump trajectory styles | `startJumpProjectileTestMode(style)` |
| Infinite Strafe | Circling standoff without snapping to a fight | Workspace `InfiniteStrafeTest` |
| Smooth Landing AI | ground-impact landings | `startCleanSlateJumpState` |
| Tournament Bracket | full 8-Quin bracket | `startTournament` |
| Deterministic Test | scripted face-off with a forced state | `startTestMode` |
| **IK Lab** (first card) | animation only against IK layers, any clip, close-up camera | `startIKLab()` (scene is client-side) |
| **Pose Viewer** | is a bad pose the clip or a game layer? | `startPoseViewer(gender, player)` |
| **Performance Benchmark** (last card) | fps before/after every performance change: same 16v16 + crowd load, measured | `startBenchmark(variant)` (`ServerScriptService.PerfBenchmark`) |

## Pose Viewer

`ServerScriptService.PoseViewer` (added in pass 23b, made a test mode in pass 23c).

**What it shows** (MovementTestArena clear floor, the camera is moved in front of it):
- **Left, blue label:** the male rig (`ReplicatedStorage.QuinType.QuinMale`) playing the walk clip in place with **no game layers**: no foot solver, look-at, tilt or blending. It is the clip exactly as authored.
- **Right, pink label:** the same for the female rig.
- **Live Quin, yellow label:** a male or female Quin walking up and down the floor on its normal locomotion, with **every game layer on**. This is what the game actually draws.

Each label shows the clip path, the asset id, the time and the frame (30 fps). The live one also shows the clip's blend weight and play rate.

**How to use it:**
1. Watch the live Quin and find the frame that looks wrong (screenshot it with the label in view).
2. Hold the raw rigs on that frame (`PoseViewerFrame`).
3. Wrong on the raw rig too: the clip (or how it lands on that rig). Wrong only on the live Quin: a game layer (foot solver, tilt, look-at, blend).

**Controls** (attributes on `Workspace`, Properties panel):

| Attribute | Default | Effect |
|---|---|---|
| `PoseViewerSpeed` | 0.25 | playback speed of the raw rigs |
| `PoseViewerPaused` | false | freeze the raw rigs |
| `PoseViewerFrame` | -1 | hold the raw rigs on this frame; -1 plays |

**Starting it:**
- **Menu:** Quin Manager > TEST MODES > Pose Viewer > "Live MALE" or "Live FEMALE".
- **Script:** `ReplicatedStorage.GameCommand:FireServer("pose_viewer", "Male")`.
- **Studio tools** (e.g. an MCP agent that cannot fire remotes): `workspace:SetAttribute("DevCommand", "pose_viewer:Female")`.

It ends when another mode starts: `CurrentMode` changes, or the new mode clears its live Quin away. The live Quin walks on the `DevGoal` attribute, which `Main` follows in Studio and while `CurrentMode == "PoseViewer"`, so it also works in a published server.

**Options for scripts:** `PoseViewer.start({ gender = "Male", clip = "Movement.WalkConfident", speed = 7.5, player = player })`. Any `AnimationConfig` path works as `clip`, but the live Quin only plays it if its locomotion would (the walk at 7.5 studs/s).

**First find (pass 23b):** the male's left leg looked broken at walk frames 4-9. It was right on the raw rig and wrong only on the live one. The foot solver had pinned the left heel at first touch while the clip still reached forward (fix: `FootIK_PlantWhenStill`).

## IK Lab

`Workspace.IKLab` (course + `IKLabDemo`, a client Script) and `GameModeManager.startIKLab()`. Added 2026-10-03.

**What it shows:** the same male Quin four times, crossing a ramp, stairs, rubble and a side slope in step, with the same clips and speed. Only the layer on top of the animation differs:

| Lane | Layer |
|---|---|
| A | animation only |
| B | basic IK: a foot that would sink is pushed up onto the ground |
| C | foot placement: ground-relative foot height, lock while planted, slope tilt, pelvis drop |
| D | full procedural: C with knee hinges, plus ten full-body layers and engine parts (part on a hand bone, trail, hanging tag) |

Each Quin's label shows the current programme part and its planted-foot numbers (above ground, inside ground, slide).

**Lane D layers** (panel at the bottom left; each button writes `D_<Name>` on `Workspace.IKLab`):

| Layer | Rule |
|---|---|
| Lean | the body tilts toward its acceleration (starts, stops, turns) and forward with speed |
| SlopeLean | and uphill on a slope |
| PelvisSpring | the pelvis follows the feet on a spring and dips on landing |
| HipTwist | the pelvis turns toward the leg that is forward |
| SpineCounter | the lower spine takes back part of the lean and twist, and turns into a turn |
| Look | QuinCore's `LookController` on the blue ball: only when it is in front, capped, spring-smoothed |
| ArmLag | the arms hang the way a loose arm would under the body's acceleration |
| Point | arm IK: the left hand points at the ball when it is in front and within 60 studs |
| Toes | a toe that would dig into the ground bends flat |
| Breath | the chest rises and falls at idle |
| StrideWarp | the step is shortened or stretched when the body's speed is not the clip's |
| ThighTwist | the thigh is rolled back to the clip's roll (the leg IK rolls it freely: knees that look turned in) |
| SquareUp | in a strafe the chest is turned back to the front; the head stays where the clip has it |
| ArmClear | an elbow or wrist that ends up inside the trunk is turned back out |
| Props (off) | the baton, hanging tag and trail |
| Contact | the hand nearest a rail within reach rests on it (rails beside lane D) |
| Inertial (off) | a new clip takes over at once and the last pose is carried into it; the legs pop, so it is off |
| KneeHinge (off) | a hinge between the leg bones; no gain over the knee pole placed from the clip |

Lean, SlopeLean, PelvisSpring and HipTwist move the root before the engine solves the legs, so the feet stay planted. The rest are written into `Bone.Transform` after animation and IK, once per animation step.

**Bar at the bottom of the screen:**
- **Prev / Next, << Category / Category >>:** play any clip of `AnimationConfig` (read with `getAllPaths()`, so new clips appear by themselves). A looping clip that travels (1.5 studs/s or more, measured from the clip) carries the Quins up and down the course; any other clip is played standing on the rubble.
- **Strafe test:** each strafe clip along a line on the open floor, then circling a marker the Quin faces (walk, run, tight).
- **Tour:** the full programme: the walk clip with the body slower and faster than the clip, then walk, run, strafe left, backward, jog, strafe right over the course, then walk and run circles, then run and three jumps.
- **All / Look at A-D:** camera on all lanes, or orbiting one Quin (hold right mouse to look around, wheel to zoom).
- **1x / 0.3x / 0.1x, Pause.**

The buttons only write attributes on `Workspace.IKLab` (`Clip`, `Focus`, `TimeScale`, `Paused`); a script or MCP agent can set the same attributes. `Crowd` (set before the mode starts) adds that many full-procedural Quins for the cost test; `Perf` reports script time and frame rate. Measurements are published as JSON in `Metrics_A` .. `Metrics_D` (feet per programme part and terrain; every tracked bone against lane A).

**Starting it:** Quin Manager > TEST MODES > IK Lab; or `GameCommand:FireServer("ik_lab")`; or (Studio tools) `workspace:SetAttribute("DevCommand", "ik_lab")`. It ends when `CurrentMode` changes; the client removes its rigs, bar and camera.

Results so far: `audits/2026-10-03_iklab_ikcontrol_experiment.md`.

## Performance Benchmark

What it's for: the same load every time, measured, so every performance change can be judged before and after. It is step A of `SKYLARK_PERFORMANCE_PLAN.md` (repo root of SKYLARK LOCAL REPO).

**The scene**
- A 16v16 that nobody dies in, so the load stays a full 32 for the whole run:
  - while `Workspace.BenchImmortal` is set, `DamageModule.apply` tops the target up before each hit;
  - `PerfBenchmark` also tops every Quin up 5 times a second.
- The stands are full (`CrowdAlwaysOn`), unless the variant says otherwise.
- The camera is fixed at (0,140,-178) looking at (0,0,-438), the arena centre.

**The windows**
- START, 0–12 s: spawn, dressing, countdown.
- STEADY, 12–32 s: the fight.

**The variants** (buttons on the results panel)

| Variant | Crowd | Clothes |
|---|---|---|
| `full` | on | on |
| `nocrowd` | off | on |
| `noclothes` | on | wraps off for the run |
| `bare` | off | wraps off |

**Results**
- The panel `PerfBenchmarkUI` (from `StarterPlayerScripts.PerfBenchmarkClient`) shows, per window:
  - client fps, 1% low, p95 and worst frame, render CPU and GPU;
  - server Hz, p95, Lua (Heartbeat) ms and physics ms;
  - the last 4 runs.
- The same numbers go to Output as `[Benchmark] client ...` and `[Benchmark] server ...`, and to the player attribute `BenchResult` (JSON).

**Starting it**
- Menu: Quin Manager > TEST MODES > Performance Benchmark. Admins (`SkylarkCanAdmin`) or Studio only.
- From the Studio tools: `workspace:SetAttribute("DevCommand", "bench:full")` (or `nocrowd` / `noclothes` / `bare`).
- After the run, Quins can die again and the crowd setting is restored.

**Reading the numbers**
- In Studio Play the server steps in the same process as the client. Server Hz simply follows the client fps, and the fps include the server's cost.
  - Judge the server by its Lua ms.
  - Use Team Test for a real player's fps.
- Keep Studio focused. It throttles otherwise, and the panel marks the run UNRELIABLE.
- Triangle counts (`Stats.RenderBreakdown`) and the script profiler (`ScriptProfilerService`) need Plugin capability, so the game can't read them. For the heaviest server scripts, use:
  - F9 > Script Profiler; or
  - the Studio MCP: `ScriptProfilerService:ServerStart(1000)` / `ServerStop` / `ServerRequestData` from the Client VM, with `OnNewData` then `DeserializeJSON`. `TotalDuration` is in seconds.

**Baseline** (2026-10-26, Studio Play, owner's PC, focused, before any optimisation)

| Variant | START fps (1% low) | STEADY fps (1% low) | p95 | render CPU | GPU |
|---|---|---|---|---|---|
| full | 28 (4) | 33 (9) | 51 ms | 19.9 ms | 4.4 ms |
| nocrowd | 43 (9) | 36 (8) | 48 ms | 18.5 ms | 2.9 ms |
| noclothes | 49 (6) | 51 (12) | 28 ms | 10.0 ms | 3.8 ms |
| bare | 82 (10) | 74 (38) | 21 ms | 6.7 ms | 3.1 ms |

- Server Lua was 6.5–7.1 ms a step and physics 2.7–3.2 ms, with 32 alive.
- Heaviest server functions (ms per second, full run):

| ms per second | Function |
|---|---|
| 145 | Main:451 (each Quin's loop) |
| 75 | TacticalPerception.evaluate |
| 75 | Cognition.update |
| 30 | Senses.sense |
| 22 | ArenaTerminalQueue.terminalsOf (during the fight) |
| 21 | Raycast |
| 18 | DebugDraw.raycast |
| 17 | GetAttribute |
| 17 | GaitModule:666 |
| 16 | SpatialModule.checkLineOfSight |
| 15 | EnvironmentAwareness.survey |
| 13 | SetAttribute |
| 10 | GetTagged |

## Adding a test mode

1. **Scene:** a `GameModeManager.startX(...)` function, or a module like `PoseViewer` with `start` / `stop`. It sets `CurrentMode` and ends itself when another mode takes over.
2. **Server route:** a branch in the `SetTestMode` handler of `AnimationLabServer` that calls it. Optionally add a `GameCommand` command and a Studio `DevCommand` in `GameModeManager`.
3. **Menu card:** `createModeCard(tmGrid, x, title, badge, description, accentColor, onClick)` in `AnimationLabController` section 8. Cards are 240 px apart; widen `tmGrid.CanvasSize` when you add one.
4. **Docs:** a row in the table above and a section here.

Planned next (owner, 2026-10-03): a jumping test in the same style.
