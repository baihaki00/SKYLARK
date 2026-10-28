---
name: quin-test-modes
description: "One-click diagnostic test modes in the Quin Manager (TEST MODES tab), incl. the owner-loved Pose Viewer; where they live and how to add more (jump test planned)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 067aa4a4-9c77-4da6-812b-ce8bdf098393
  modified: 2026-10-26T19:48:05.656Z
---

The owner loved the Pose Viewer (pass 23b) and asked (2026-10-03) for it to be permanent, one click, labelled as a test and known to every later session/agent. Done in pass 23c (`a535f48`).

- **Where:** in-game Quin Manager = `StarterGui.AnimationLabUI` (pill "Quin Manager [M]"), tab **TEST MODES** (`AnimationLabController` section 8, `createModeCard`). NOT `StarterGui.QuinMenuUI`: that ScreenGui is disabled in StarterGui (old "QUIN MANAGER & ARENA TRACKER").
- **Route:** card -> `labEvent:FireServer("SetTestMode", {mode=...})` -> `AnimationLabServer` handler -> `GameModeManager.startX`.
- **Pose Viewer:** `ServerScriptService.PoseViewer` / `GameModeManager.startPoseViewer(gender, player)`. Raw male + female rigs play the walk clip with no game layers, beside a live Quin with all layers, all frame-labelled. Workspace attrs `PoseViewerSpeed` / `PoseViewerPaused` / `PoseViewerFrame`. From MCP: `workspace:SetAttribute("DevCommand","pose_viewer:Male")`.
- **IK Lab (2026-10-03, `68be0be`):** first card on TEST MODES. `GameModeManager.startIKLab()` only sets `CurrentMode = "IKLab"`; the scene is client-side in `Workspace.IKLab.IKLabDemo` (Script, RunContext Client - re-set RunContext if the script is ever recreated, it silently falls back to server). Four lanes (animation only / basic IK / foot placement / engine parts), bottom bar: clip browser over `AnimationConfig.getAllPaths()`, Tour, per-Quin orbit camera, slow motion. Buttons only write attributes on `Workspace.IKLab` (`Clip`, `Focus`, `TimeScale`, `Paused`), so MCP can drive it the same way. From MCP: `workspace:SetAttribute("DevCommand","ik_lab")`. See [[iklab-ikcontrol-experiment]].
- **Full guide:** repo `QUINCORE_BACKUP/TEST_MODES.md` (README §10 points to it). `Docs/` is gitignored, so docs go at the repo root.
- **Next (owner, not yet):** a jumping test in the same style. Follow "Adding a test mode" in TEST_MODES.md.
- **Clicking the menu from MCP:** `user_mouse_input` x/y = the GUI's AbsolutePosition (no topbar inset). The TEST MODES grid scrolls horizontally: set `CanvasPosition` first.

Related: [[quin-movement-audit-workflow]], [[studio-git-export]]

- **Performance Benchmark (2026-10-26):** the last card. ServerScriptService.PerfBenchmark + StarterPlayerScripts.PerfBenchmarkClient. A 16v16 nobody dies in (Workspace.BenchImmortal), crowd on, fixed cam, START and STEADY windows, results panel with variant buttons. DevCommand `bench:full`. See [[skylark-performance-plan]].

**Arena System [O] switches + DEBUG COMBAT (2026-10-26):**
- New toggles (ArenaConfig.DefaultToggles): CrowdAvatars (the 1000 stand avatars, via Workspace CrowdNpcs), Clothes (fighters' clothes, via Workspace WardrobeOff; live flips dress/undress fighters at once), RandomMusic (random track per playlist). Orchestrator `applyWorldToggles()` + `track(kind, selected)`.
- DEBUG COMBAT button (bottom dock, left of START): stops a running match, starts an instant 16v16 with no clothes, crowd, crowd FX, music, announcer, fireworks or drones (owner: to judge combat).
- **Auto on Play (2026-10-27):** Workspace attribute `StudioAutoDebugCombat` = true (set, saved with the place once owner saves) -> ServerScriptService.StudioAutoDebugCombat makes the first player Admin and starts the DEBUG COMBAT 16v16 on every Play. Untick to play normally. Remember: my own MCP tests then start inside that match.
- P now works as a Player too (becomes Admin, waits for the role, then pilots); O ignores the key while the Arena screen is hidden (Player role).
