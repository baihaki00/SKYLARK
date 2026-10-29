---
name: quin-debugger
description: "Debugger revamp 2026-10-28 - live label switches, QuinRecorder, QuinReplay F6 (live slow-mo/scrub); test handles and traps; steps 4-5 open"
metadata:
  node_type: memory
  type: project
  originSessionId: b059c2f4-3bd5-4c8f-aaf9-9534ac2c09b1
  modified: 2026-10-28T22:57:03.649Z
---

Owner's request 2026-10-28: slow-mo / pause / scrub "without interfering the actual game" to judge state transitions and animations, more hands-on debugging. Plan of 5 steps approved ("yup"):

1. DONE 074a616: Modules/DebugSwitches = PointDebug, InterestDebug, Tactical/Look/Gait/Foot prints as Admin-only "Show:" toggles in the Spectator HUD (server-owned attributes via QuinCore.DebugSwitchEvent). Same commit: map + teleport HUD start minimised, Studio joins as Admin (Workspace JoinAsPlayer opts out).
2. DONE 143aff5/85f2b2b: StarterPlayerScripts/QuinRecorder - every Quin, 15 s, part+bone world CFrames, clips by AnimationConfig registry path, attribute changes (NOISY list skipped). 16v16 ~0.6 ms/frame.
3. DONE d3ad86f: QuinReplay F6. Owner correction: the game must keep going; replay opens LIVE and 0.5x falls behind while the fight goes on, "Live" catches up (NOT a frozen snapshot). Real Quins hidden locally, ghosts posed from the recording; recorder holds 120 s while open. 16v16 ~57 fps replaying.
4+5. DONE ca2f82c (owner: "refactor all these into one menu ... its a haywire"): Spectator HUD = one menu with tabs Quins / Inspect / Switches (folding groups). Inspect tab = shared.DebugDock.setInspect(data) fed by the freeze and the replay; state pinned on top, change rows scroll, click a row = before/after card + Copy report (StarterPlayerScripts/QuinTimeline). One top bar (GodPauseClient): Freeze/Resume F4 + steps + Replay F6; replay controls sit under it. Pilot button removed from the HUD header (owner asked; P key still pilots).
ef5c187 SUPERSEDES the bar design below: owner "buttons: PAUSE/PLAY ... we already have the scrubber ... the game stops where I last pause it". Pause IS the replay: one PAUSE/PLAY [F4] button (GodPauseClient); PAUSE freezes the real game and opens the scrubber (QuinReplay, no own buttons, opens at the pause); PLAY closes it and the game continues from the pause. No Open replay / Back to live / Play replay / speeds / game steps. Don't re-add them. 8fe00fb: Inspect list follows the scrubber (gold row = scrubber moment, later rows dimmed); menu cards move the paused camera; right-drag orbits (read per frame via GetMouseLocation - with a free cursor InputChanged carries no Delta). Trap: Studio MCP synthetic mouse drags/scrolls are flaky (first drag often missed, scroll never arrives) - check per-frame state, not one try.
0ec5293 (owner: "every label and prints 3d overlays correct, for the selected quin, toggle this quin / all quin"): Switches tab top = scope bar ScopeThis / ScopeAll (default This). Workspace DebugScopeQuin (DebugSwitches.requestScope, Admin) gates PointTag/InterestTag/Tactical/Look/Gait/Foot via an inline check in each consumer; RuntimeVisualizer watchAll follows it; overlays never fall back to quins[1]. Look/Gait/Foot values = DebugValuesTag labels (QuinDebugHUD). Labels + overlays hidden while scrubbed back (QuinReplay.atPause). Selection is one thing: shared/_G/Workspace SpectatedQuin. Verified both modes in 16v16. InterestTag draws only when a Quin's interest changes (pre-existing). Trap: Studio MCP coordinate clicks on the HUD don't register, instance_path clicks do - give buttons unique Names.
(older) f448642 (owner: two bars "ambiguous / mixed", "no extra buttons that do the same thing"): ONE bar at a time at the top - GAME bar (chip GAME RUNNING/FROZEN, Freeze/Resume game F4, steps only while frozen, Open replay F6) hides while the replay is open; the REPLAY bar takes its place (chip shows the game's state, Close replay F6). Keep it that way: never two buttons for one action, label which clock a control drives. shared.PointerOverMenu() (QuinDebugHUD) = cameras ignore the wheel over the menu/bars (SmoothCamera, replay). SST clock badge renamed "SST CLOCK • PAUSED". Trap: Studio MCP user_mouse_input scroll does not reach the game - wheel fixes cannot be tested that way.

2026-10-29, not committed (owner: "labels doesnt come out from quin when im on pause it should also be a replay"): before this, `hideReal` switched off every BillboardGui on the real Quins while paused, and ghosts are cloned with BillboardGuis stripped, so no label showed even at the pause.
- **QuinRecorder** now also keeps:
  - every BillboardGui per Quin: `labelBase` / `labelEvents` / `labelTemplates`, with Enabled plus each text object's Text and Visible, matched by order because they share names. These are kept apart from `events`, so the Inspect list isn't flooded;
  - `pose.health` / `energy` / `lastSeen`;
  - `drawings`, the DebugDrawEvent batches with their arrival time.
- **QuinReplay:**
  - `poseLabels(t)` rebuilds the labels on the ghosts from the templates (Adornee re-pointed);
  - `shared.QuinReplay.overlay()` returns `{ view(name), names, spectated, primitives }`;
  - test handle `state` returns `labels` / `overlay` summaries.
- **RuntimeVisualizer:** the client layers take a view (`liveView` or the replay's); `updateReplay(overlay)`.
- **QuinDebugHUD:** draws overlays from `overlay()` while paused, and leaves real labels alone while paused. The scrubbed-back hiding is gone.
- **Tested once (1v1):**
  - the ghost carries its label;
  - recorded energy and state follow the scrubber.
  - The always-present root `BillboardGui` "[ STATE: Idle ]" has its text objects at Visible = false: a dormant tag, invisible live too.
- **Tested 2026-10-29:**
  - A server test label, counting and toggling, replayed exactly (text and on/off by scrubber time); the real label was off while paused.
  - About 190 recorded server drawings come back per moment.
  - `updateReplay` drew every client layer from a view.
  - No errors.
  - Not seen by eye yet.
- **Test trap:** look/gait values weren't written in a 1v1, and point/interest labels are rare. Test with a self-made server BillboardGui instead.
- **MCP trap:** a start-play that times out leaves the MCP stuck at "Start play hasn't finished yet"; the owner pressing Play unblocks it.

**Bug bookmarks (2026-10-29, not committed).** Built after the owner asked what report would help most.
- Key **N** in `QuinRecorder` (B was taken) saves the last `BookmarkSeconds` (6 s) of the spectated Quin, or the one nearest the screen centre. The report holds: floor part, target, the state at the start, a timeline every 0.1 s (state, speed, vy, facing, turn deg/s, humanoid, top 3 clips), and timestamped changes.
- Each bookmark is a StringValue in `PlayerScripts.QuinRecorder.Bookmarks["1".."n"]`. Read it from the Client context while Play still runs; it's gone when Play stops.
- Test trigger: `Query:Invoke("bookmark")`.
- Owner flow: press N and say "bookmark 3".
- **Range comments (same day):** the strip under the pause scrubber (`QuinReplay`). Drag to mark a range of the followed Quin, type a note, then Enter or Save; Esc or Cancel drops it. Each saved range becomes a bookmark via `shared.QuinRecorder.report(name, from, to, note)`, with an `OWNER'S NOTE` line. Saved ranges stay drawn on that Quin's strip while paused.
- Test handle: `Control:Invoke("mark", {from, to, comment})`.
- Not tried by hand yet.
- **Same day, after the owner tried the pipeline ("okay so it works"):**
  - The report's target line now reads the target at the END of the range, plus "(it started on X)" if it changed.
  - CHANGES leaves out MatchScore, InterestPos, EscapeFeasibility, OccupiedQuadrants and numeric attributes ending in At / Until / Since (`REPORT_NOISE` / `reportNoise`). ChaseCommitment and InterceptionLeadTime still tick often; filter them too if they get in the way.
  - Fixed: N during a pause gave an empty report, because the recorder stops while frozen and the range is now cut to the last frame. Fixed: the floor ray hit the replay ghost's own clothes; the filter list is now built first.
- **Space in the pause (QuinReplay):** plays the recording at 1× from the white line, Space again stops it, and it stops by itself at the pause. Measured: about 1.05 s of recording per real second. The time label says "Space plays from the white line / stops". Space also lifts SmoothCamera's free camera; that's the other session's file, so it isn't handled.

**F fly (StarterPlayerScripts.TheArchitectCode), 2026-10-29:** the owner reported it kept rising with no keys pressed and never fully stopped. The cause: the hover ray pointed UP and hit the flyer's own head, so it lifted every frame. `flyHoldStill = true`: the ray looks down past the body, lifts only within `hoverHeight` of the ground, and the body stops dead once the keys are let go (`stopRate` 8, snaps below 2 studs/s). Measured: 0.01 studs of drift in 4 s. Setting `false` gives the old behaviour. The B / R free camera is SmoothCamera, a separate script.

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
