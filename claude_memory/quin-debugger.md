---
name: quin-debugger
description: "Debugger revamp 2026-10-28 - live label switches, QuinRecorder, QuinReplay F6 (live slow-mo/scrub); test handles and traps; steps 4-5 open"
metadata:
  node_type: memory
  type: project
  originSessionId: b059c2f4-3bd5-4c8f-aaf9-9534ac2c09b1
  modified: 2026-10-28T12:09:21.451Z
---

Owner's request 2026-10-28: slow-mo / pause / scrub "without interfering the actual game" to judge state transitions and animations, more hands-on debugging. Plan of 5 steps approved ("yup"):

1. DONE 074a616: Modules/DebugSwitches = PointDebug, InterestDebug, Tactical/Look/Gait/Foot prints as Admin-only "Show:" toggles in the Spectator HUD (server-owned attributes via QuinCore.DebugSwitchEvent). Same commit: map + teleport HUD start minimised, Studio joins as Admin (Workspace JoinAsPlayer opts out).
2. DONE 143aff5/85f2b2b: StarterPlayerScripts/QuinRecorder - every Quin, 15 s, part+bone world CFrames, clips by AnimationConfig registry path, attribute changes (NOISY list skipped). 16v16 ~0.6 ms/frame.
3. DONE d3ad86f: QuinReplay F6. Owner correction: the game must keep going; replay opens LIVE and 0.5x falls behind while the fight goes on, "Live" catches up (NOT a frozen snapshot). Real Quins hidden locally, ghosts posed from the recording; recorder holds 120 s while open. 16v16 ~57 fps replaying.
4+5. DONE ca2f82c (owner: "refactor all these into one menu ... its a haywire"): Spectator HUD = one menu with tabs Quins / Inspect / Switches (folding groups). Inspect tab = shared.DebugDock.setInspect(data) fed by the freeze and the replay; state pinned on top, change rows scroll, click a row = before/after card + Copy report (StarterPlayerScripts/QuinTimeline). One top bar (GodPauseClient): Freeze/Resume F4 + steps + Replay F6; replay controls sit under it. Pilot button removed from the HUD header (owner asked; P key still pilots).
ef5c187 SUPERSEDES the bar design below: owner "buttons: PAUSE/PLAY ... we already have the scrubber ... the game stops where I last pause it". Pause IS the replay: one PAUSE/PLAY [F4] button (GodPauseClient); PAUSE freezes the real game and opens the scrubber (QuinReplay, no own buttons, opens at the pause); PLAY closes it and the game continues from the pause. No Open replay / Back to live / Play replay / speeds / game steps. Don't re-add them. 8fe00fb: Inspect list follows the scrubber (gold row = scrubber moment, later rows dimmed); menu cards move the paused camera; right-drag orbits (read per frame via GetMouseLocation - with a free cursor InputChanged carries no Delta). Trap: Studio MCP synthetic mouse drags/scrolls are flaky (first drag often missed, scroll never arrives) - check per-frame state, not one try.
0ec5293 (owner: "every label and prints 3d overlays correct, for the selected quin, toggle this quin / all quin"): Switches tab top = scope bar ScopeThis / ScopeAll (default This). Workspace DebugScopeQuin (DebugSwitches.requestScope, Admin) gates PointTag/InterestTag/Tactical/Look/Gait/Foot via an inline check in each consumer; RuntimeVisualizer watchAll follows it; overlays never fall back to quins[1]. Look/Gait/Foot values = DebugValuesTag labels (QuinDebugHUD). Labels + overlays hidden while scrubbed back (QuinReplay.atPause). Selection is one thing: shared/_G/Workspace SpectatedQuin. Verified both modes in 16v16. InterestTag draws only when a Quin's interest changes (pre-existing). Trap: Studio MCP coordinate clicks on the HUD don't register, instance_path clicks do - give buttons unique Names.
(older) f448642 (owner: two bars "ambiguous / mixed", "no extra buttons that do the same thing"): ONE bar at a time at the top - GAME bar (chip GAME RUNNING/FROZEN, Freeze/Resume game F4, steps only while frozen, Open replay F6) hides while the replay is open; the REPLAY bar takes its place (chip shows the game's state, Close replay F6). Keep it that way: never two buttons for one action, label which clock a control drives. shared.PointerOverMenu() (QuinDebugHUD) = cameras ignore the wheel over the menu/bars (SmoothCamera, replay). SST clock badge renamed "SST CLOCK • PAUSED". Trap: Studio MCP user_mouse_input scroll does not reach the game - wheel fixes cannot be tested that way.

Traps:
- execute_luau has its own `shared`; test through BindableFunctions: QuinRecorder.Query:Invoke("stats"|"snapshot"), QuinReplay.Control:Invoke("open"|"close"|"follow",name|"seek",0..1|"play",speed|"live").
- A skinned mesh only uses bones in its own assembly: a cloned rig with its welds stripped draws in bind pose (T-pose). Keep welds, anchor only the root, drive Motor6D.Transform.
- Drone cameras clear shared.CameraOverrideCFrame every frame; replay uses its own shared.ReplayCameraCFrame (SmoothCamera).
- StudioAutoDebugCombat was saved true (auto 16v16 on Play); owner asked no autostart - set false 2026-10-28.

God pause (owner 2026-10-28: "literally pausing the time and play god"; the replay was a second timeline, sounds kept going). Owner chose plan B:
1. DONE d7fe590: Modules/GameClock (now/tick/serverNow/wait/delay, frozen by Workspace GameFrozen / GameFrozenAt / GameFrozenTotal); 72 QuinCore files switched mechanically. SkylarkTime, NpcDialog, QuinDataStoreService kept on the real clock. SocialLeaders has its own local tick(). Revert point: d3ad86f.
2. DONE e85fba1: F4 / top pill (GodPauseClient) -> QuinCore.GameFreezeEvent -> Modules/GameFreeze (started by DebugManager): anchors roots keeping velocity, holds clips, clients pause sounds/particles, AIGhostHandler edits pose with dt 0, 16 Heartbeat loops gated, orchestrator + LanternSiege on GameClock. 16v16: 0.000 studs / 0 strikes frozen. Not frozen: crowd NPCs, GameModeManager, loose physics parts, SST world clock (on purpose).
3. DONE 5c15e1c: frozen inspector in GodPauseClient (click a Quin / centre dot; state line, held clips with pre-freeze speed from the recorder, last changes); '.' steps 1 frame, buttons 0.1 s / 1 s. Test handle GodPauseClient.Inspect:Invoke(name). Trap: a body moved by physics then anchored never replicates that move - freeze nudges each root 0.001 studs. Real slow-mo impossible (Roblox physics one speed); slow-mo stays in the replay (mute live sounds there: not done).

Owner's message was cut off: "hm the confusing part is the..." - ask what it was.

Related: [[visual-bug-testing]], [[movement-commitment-poi]]
