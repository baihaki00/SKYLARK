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
| **Pose Viewer** | is a bad pose the clip or a game layer? | `startPoseViewer(gender, player)` |

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

## Adding a test mode

1. **Scene:** a `GameModeManager.startX(...)` function, or a module like `PoseViewer` with `start` / `stop`. It sets `CurrentMode` and ends itself when another mode takes over.
2. **Server route:** a branch in the `SetTestMode` handler of `AnimationLabServer` that calls it. Optionally add a `GameCommand` command and a Studio `DevCommand` in `GameModeManager`.
3. **Menu card:** `createModeCard(tmGrid, x, title, badge, description, accentColor, onClick)` in `AnimationLabController` section 8. Cards are 240 px apart; widen `tmGrid.CanvasSize` when you add one.
4. **Docs:** a row in the table above and a section here.

Planned next (owner, 2026-10-03): a jumping test in the same style.
