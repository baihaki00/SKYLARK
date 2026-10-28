---
name: skylark-time-schedule
description: "Skylark clock + arena schedule system (2026-10-22): modules, debug time controls, Auto Events link to the orchestrator, test hooks, traps"
metadata:
  node_type: memory
  type: project
  originSessionId: d7bf1767-1302-4352-a4c1-665593d03486
  modified: 2026-10-22T11:02:45.214Z
---

Built on 2026-10-22 as MVP week 1 (see [[skylark-mvp-target]]).

**Files**
- `QuinCore.SkylarkTime`: the clock.
  - EPOCH Mon 2026-10-19 00:00 UTC = Spring day 1, Year 1.
  - 8 h Skylark day; season = 21 Skylark days = 1 real week; year = 4 weeks.
- `QuinCore.ArenaSchedule`: the DAILY slots plus the weekday EVENTS, each with a `Match` config for the orchestrator. Brackets rotate Sizes 1/2/4/8.
- `SkylarkScheduleService` (server):
  - publishes the Workspace attributes ArenaSlot, ArenaSlotKind, ArenaSlotEndsAt;
  - announces each new slot on the arena screen;
  - Auto Events: starts a round through shared.ArenaOrchestrator when the arena is IDLE, 15 s between rounds, only if a round (~918 s) fits in the window;
  - Auto Events is off by default in Studio, on in live servers.
- `SkylarkClock.client`:
  - the lighting cycle, from keys by hour (NIGHT, DAWN, DAY = the authored lighting, DUSK);
  - a season ColorCorrection named "SkylarkSeason";
  - the widget at top right; click it for the board; (SUPERSEDED 2026-10-24, 768752d: see the HUD note at the end)
  - the owner TIME panel (the TIME button or F7).

**Debug time**
- The single Workspace attribute `SkylarkTimeOverride` = "base|anchor|rate". It is atomic; clearing it returns the clock to real time.
- Command bar: `workspace:SetAttribute("SkylarkTimeCommand", "hour 18.5" | "shift 1200" | "rate 0" | "real" | "autoevents on" | "daycycle off")`.
- The remote is `ArenaNetwork.SkylarkTimeDebug`, allowed in Studio or for the place creator.

**Trap:** shared.SkylarkSchedule / shared.ArenaOrchestrator are not visible from MCP execute_luau (a different VM). Require the modules directly there.

**Verified in Play:** the scrub, pause, dusk and night lighting, the board, and an auto round (Team Battles started a 16v16).

**Arena entry, fair queue (built 2026-10-22, commit 87b8739)**
- `ServerScriptService.ArenaRegistration` (a module, required by the orchestrator):
  - entry opens 1 SST hour before a window and lasts all window; the entries are cleared when the window ends;
  - 1 roster Quin per player per round;
  - pickRound orders entrants by satOut (most first), then by who registered first;
  - seats: TeamBattle 2×TeamSize, FFA TeamSize, 1vs1 2.
- **Orchestrator:** picks the entrants at PREPARATION_ROOM (only while the entries' window is live). `spawnSeat` swaps a player's QuinInstance in for an arena Quin and tags the model OwnerUserId / OwnerName; `roundOver` runs at stopMatch.
- **Client:** `ArenaEntry.client` puts an entry bar under the clock (y=122) and an entry panel to its left. The TIME panel moved down to y=162.
- **Verified:** register → a 4v4 seated my Quin on Alpha with 7 arena Quins; the window ending cleared the entry.
- **Not yet:** a second Quin in spare seats, multi-player rotation (only tested solo), rewards/outcomes (recordMatchOutcome exists in QuinRosterService), the prep room / bench / cameras (week 3-4).

**Terminal flow (2026-10-23, commit c44e291), owner's spec**
- The game starts as a walking Roblox player (SmoothCamera starts in "DEFAULT"; B flies).
- Players register at the Workspace parts "ArenaTerminal" (a ProximityPrompt; the server anchors them) through a centred popup. The server checks the player is within 16 studs of a terminal.
- PerPlayer 2 in 16v16 (ArenaSchedule TEAM / TEAM_TERRAIN): both Quins go on the same side. Seating gives everyone's first Quin a seat before anyone's second.
- Entry closes 5 real min before the window ends.
- **Owner:** no elements (Fire/Water/Ice) in any UI. The data still carries Element; it is only hidden.
- `ArenaPrepRoom`: the 32 Workspace "PreparationRoom" pads; the side nearer the Alpha QuinSpawn is Alpha's.
  - Each player gets a pad with their Quins (inert) and is teleported there.
  - spawnSeat moves those same models into the arena (moveToArena: raycast plus standOffset).
  - The player stays on the pad; at stopMatch they go back to the SpawnLocation.
  - Scheduled rounds use PreparationRoom = 60 s.
- **Studio:** the default roster has 4 Quins. The Edit attribute Workspace.SkylarkTestHour (now 12.5) starts every Play paused at that hour.
- **MCP traps:** screen_capture does not draw the ProximityPrompt overlay, and the keyboard E did not trigger it. Use prompt:InputHoldBegin()/End() on the client.

**Prep rooms, NPC owners, barrier (2026-10-23, commit 9ce667f)**
- **Rooms:** the owner's template Workspace models "PrepRoom" (4 PrepRoomCopies groups × 8 = 32; 2 floors per side). Each has PrepRoomQuinSpawn, 4 PrepRoomTerminal, 3 chairs with Seats, PreparationRoomGlass, Door, PreparationRoomHallWay. `ArenaPrepRoom` uses these; the old "PreparationRoom" pads are no longer used.
- **Door rule:** the owner, friends of the owner (IsFriendsWith), or people let in after a knock (the DoorPrompt; an NPC owner says yes 60% of the time).
  - The server keeps doors CanCollide=false (for NPCs). PrepRoomClient makes them solid locally for anyone not allowed.
  - The server teleports intruders out to the hallway.
  - The room attributes PrepOwner / PrepOwnerUserId / PrepTeam / PrepAllowed (",id,") are what the clients read.
- **All of an owner's Quins down:** after 6 s, players go back to the SpawnLocation; NPC owners walk out.
  - My reading of the owner's "spawn back in the game". UNCONFIRMED: asked the owner.
- **PrepRoomTerminal (TerminalPrompt):** binoculars from the glass (hold RMB to look, wheel to zoom), the POV of your own Quins only (OwnerUserId), and stats from StateReplication.
  - Camera via `shared.TerminalCameraCFrame`, which SmoothCamera honours first. ArenaDroneClientController clears shared.CameraOverrideCFrame every frame, so don't use that key.
- **`ArenaNpcOwners`:**
  - fillRound gives ~60% of the empty seats to NPC owners with 1-2 Quins each, limited by free rooms.
  - Avatars: R15 from a HumanoidDescription (random colours), collision group ArenaSpectators.
  - Behaviour loop: wander / sit / window (faces its own Quin during the fight) / terminal / visit other NPC rooms on the same side and floor via the hallway.
  - Off with Workspace attribute ArenaNpcOwners=false.
- **ArenaBarrier.server:** an invisible box over ArenaGround (on the arena side of the room glass), 600 tall plus a roof; only collision group ArenaSpectators (players' avatars, NPC owners) collides with it. Verified: a walk stops at the south face.
- **Buttons:** "Play As Admin [P]" (was Play As Quin) and "Play As Roblox Player" (shared.SetSpectatorMode("DEFAULT") in SmoothCamera).

**Terminal rework (2026-10-23, commit 1430769), owner's spec**
- **Binoculars:** a hand-held restricted free-fly camera (WASD, Space/C, Shift; a box 70 forward × ±60 side × -25/+45 from the glass), a slight noise shake that grows with zoom, smooth FOV zoom.
- **Own Quins:** 3rd person (the PrepRoomClient orbit, like the Spectator HUD view) or POV (the Quin's body hidden locally); the owner likes POV, keep it.
- **`shared.SpectateFilter`** (set while at a terminal) limits QuinDebugHUD's getAllAliveQuins / setSpectatedQuin and SmoothCamera's getActiveSpectatedQuin to the player's own Quins. Exiting the terminal resets to walking (shared.SetSpectatorMode).
- **Verified:** Q/E cycles only my own Quin; binocular fly + zoom; POV. NOT yet seen: the 3rd-person view, the named buttons, the POV body-hide (MCP Play got stuck: "Start play hasn't finished yet").
- **MCP traps:** clicks by x/y from user_mouse_input were unreliable on the terminal bar, so the buttons are now named for instance_path. MCP execute_luau resets CameraType to Custom after it runs.

**Crowd NPCs + animations (2026-10-23), verified in Play after the owner restarted Studio**
- **StarterCharacterScripts.Animate had an admin whitelist** (returned for anyone but Bai/baiyyaki00) and custom walk/run ids (103396337997545 / 108246513830939). Now: no whitelist, default walk 507777826 / run 507767714.
- **`NpcAnimator`** (ServerScriptService module): server-side default R15 anims (idle variants, walk/run/jump/fall/sit from the Humanoid state for `moving` NPCs) plus emotes (cheer, wave, point, laugh, dance1-3). An NPC's Animate LocalScript never runs, which is why they were frozen.
- **ArenaNpcOwners:** NPC_SHARE 1 (Workspace ArenaNpcShare overrides). One owner per free room first, extras become second Quins, so all 32 rooms fill when no players are in (a player's 2-Quin room leaves 1 room empty on that side). 54 names. Owners cheer/point at the glass during the fight.
- **ArenaCrowdManager:** `Crowd.Reacted` (team, category, major) fires in react(); `Crowd.getSections()` gives centre + team.
- **`ArenaCrowdNpcs.server`:** avatars on the 4 ArenaOne "CrowdArea" parts (flat stands: two 50×597 sides at y~107/111, two 196×30 ends at y144), 3.4-stud grid.
  - Built as 16 looks, then cloned; root anchored, EvaluateStateMachine=false, nothing collides.
  - React by nearest section's team: Celebration = 3-6 hops + dance; cheer/roar = cheer emote + hops; groan/disappointment = point (boo); gasp = still.
  - Ambient emotes scale with excitement.
  - Workspace CrowdNpcCount (default 200) / CrowdNpcs=false rebuild the crowd; CrowdNpcActive is the live count.

- **Measured in Studio** (server and client on one machine, so pessimistic):
  - 200 avatars built in 0.7 s; 1000 in 4.6 s.
  - 16v16 with no registration: 32/32 rooms owned, all owners animating.
  - Fight + 200 crowd: server 76 fps, 80/200 reacting.
  - Winner: 70 cheering or dancing, 61 in the air.
  - 1000 + fight: server 25-31 fps (worst 69-88 ms), client 33 fps. 1000 idle: 138 fps. So the cost is the reactions (tweens, emote track loads) at scale plus the fight, not standing avatars.
- **If reactions at 1000 need to be cheaper:** cap reacting avatars per event, or move the hops and emotes to clients.

**Crowd on the clients (2026-10-23), owner wants 1000+ crowd at 120+ fps in fights**
- **Server `ArenaCrowdNpcs`:**
  - builds 16 looks (Humanoid removed, AnimationController, colours baked) into ReplicatedStorage.CrowdNpcTemplates;
  - lays out the stands; RemoteFunction ArenaNetwork.CrowdNpcLayout returns {x, y, z, look, section};
  - RemoteEvent CrowdNpcs sends "layout" / "react" (team, category, major, sectionTeams) / "mood" (excitement, teams) once a second in IN_GAME;
  - default count 1000.
- **Client `ArenaCrowdClient`:** builds the crowd locally, with animation LOD (nearest ANIMATE_MAX), batched hops via BulkMoveTo, capped reactions per frame. Live knobs: Workspace CrowdAnimateMax / CrowdHopMax / CrowdReactScale.
- **Measured (first client version: 250 animated, uncapped reactions), Studio with server and client on one machine:**
  - no fight: 1000 crowd 129 fps vs 240 without the crowd;
  - 16v16 with crowd hidden: client 83 / server 88;
  - 16v16 with crowd reacting: client 12 / server 19.
  - So the reactions (animations, LoadAnimation churn, hops) were the cost. Then cut: 120 animated within 240 studs, 12 animation switches a frame, tracks kept, 60 responders a frame, 200 hops within 450 studs. NOT measured yet.
- **Note:** in Studio the 16v16 alone gives ~83 client fps (server on the same CPU), so a "120+ in fights" check needs a live server or the owner's own fps cap removed.
- **MCP trap:** Stop then Start Play in quick succession leaves start_stop_play stuck at "Start play hasn't finished yet". The owner had to restart Studio. Avoid Stop/Start churn: push while in Edit and start once.

**Crowd perf findings (2026-10-23, commit 174c815)**
- **TRAP:** Roblox avatars (CreateHumanoidModelFromDescription) now join limbs with AnimationConstraints, which are PHYSICS constraints.
  - Any body motion (moving the root, raising a joint attachment, writing Transform) wakes the solver for every limb.
  - Measured: a 1000-crowd celebration took the fight to 12 fps.
  - Fix: rebuild the looks with Motor6Ds (C0/C1 = the attachments' CFrames) and delete the other constraints and WrapTargets. Then hops via Root Motor6D.Transform cost ~nothing: celebration during the fight 67 fps.
- A Motor6D's C0 cannot be written from MCP execute_luau (read-only in that context).
- **Studio fight numbers (median fps, client and server on one CPU):** crowd hidden 80-94; 1000 crowd standing ~73; +40-120 animated ~60-67. The standing crowd costs ~1 ms idle, ~3 ms during the fight; each animated rig ~0.03-0.04 ms.
- **Default now:** nearest 60 animated within 200 studs, 200 hops within 450 studs, 60 responders a frame.
- **For 120+ in production:** measure in a live server (Studio shares the CPU with the 16v16 server). Further levers if needed: hide avatars beyond ~500 studs, fewer parts for far avatars, lower CrowdAnimateMax.

**Crowd v3 + avatar camera (2026-10-23, commit e2cf249)**
- **Player animation fix:** StarterCharacterScripts.Animate had Enabled=false in the place, and its child Animations held custom ids (walk 103396337997545, run 108246513830939, idle 105826473356353, jump 85622241844167, fall 79340771026707). Now Enabled, with Roblox's defaults. The mood anims 14366558676 / 10921269718 still play from the "mood" children.
- **SmoothCamera "AVATAR" mode** (the default; SetSpectatorMode("DEFAULT"/"AVATAR") and B toggle to it): the Play As Admin orbit on the player's own body, starting in first person; the wheel goes between them.
  - In first person the HRP faces smoothYaw (AutoRotate off).
  - First person is re-entered when the body changes: the first character gets replaced at Play start.
  - menuOpen frees the cursor for TerminalPopup / ScheduleBoard / TimeDebug / PrepTerminalUI.
- **Server crowd looks:** random users via GetHumanoidDescriptionFromUserId, needing a Shirt/ShirtGraphic + Pants after layered clothing is removed; 40 looks.
  - AnimationConstraint→Motor6D, RigidConstraint→Weld; FaceControls removed.
  - Layout entries carry the bench row: axis/from/to.
- **Client crowd v3:**
  - appears when StateReplication Phase leaves IDLE (8 s glitch-in, cyan Highlight on ≤20) and leaves at IDLE; Workspace CrowdAlwaysOn=true keeps it.
  - Near 60: emotes only (NO idle anim: Roblox's default idle crouches these rigs ~30° at the knees; some emotes may too).
  - Faces (≤40 within 70 studs): SurfaceGui eyes/brows/mouth; mesh heads get TextureID="" while it is shown.
  - Middle distance up to 380: Transform poses (cheer/clap/point/head/slump/talk/walk); walkers 6% along their rows (BulkMoveTo); talkers 5% face their neighbour, TextChatService:DisplayBubble.
- **Measured (fresh Play, fight, camera on the stand):** crowd 65 fps vs hidden 88 (Studio).

**Dorm life + crowd looks (2026-10-23, commit d99d044)**
- **NPC owners:**
  - ~70% at the glass;
  - visits: friends walk in; others knock and get in 65% of the time; then host and guest stand side by side at the glass with "manager" lines (server BillboardGui bubbles via say());
  - PathfindingService walkTo with stall detection; after a wander they face the glass or the room.
  - NpcAnimator "sit" is keyed to hum.SeatPart (the sitting bug).
  - leave() sets npc.leaving and walks out with exiting=true.
- **Owner friends** (NpcOwners.addFriends from ArenaPrepRoom.open; removeFriends in releaseRoom):
  - 0-5 per room (Workspace ArenaNpcFriendsMax), in the room or arriving in the hallway and knocking;
  - PrepRoom friendKnock: NPC owner yes (strangers 60%); a player owner gets the Let in/No with a negative id;
  - friends roam: glass 28%, sit, hallway groups 40% (rings of ≤6, HALL_LINES), knocking on other rooms 12%, stepping out.
  - Measured: 104 NPCs, 60 in the hallways, server 228 fps (prep room).
- **Crowd looks:** desc.Shirt/Pants ≠ 0 and the templates non-empty (Roblox creates empty Shirt/Pants objects); hook accessories weight 0.12; random Height/Width/Depth/Head scale (12% short); 90 looks. Owner rule: women fully clothed, men pants. With no gender signal, everyone needs a shirt for now.

**Crowd + dorm fixes (2026-10-24, commit 3daa68b)**
- **TRAP: NPC network ownership.** Sitting welds an NPC to the anchored Seat; standing up returns automatic ownership and Roblox hands the body to the nearest player.
  - That client then walks it into the doors it keeps closed locally (the "stuck at door"), and its state is unreliable (the sit pose mid-fall).
  - ArenaNpcOwners re-claims SetNetworkOwner(nil) every 0.5 s.
- **TRAP:** Roblox's current default R15 hand is a C-claw mesh (8650168401), the owner's "pirate hook". AvatarTidy.blockHands swaps it for a block Part. BaseWrap/SurfaceAppearance must be destroyed, not moved: moving one crashed the match ("BaseWrap must be parented to a MeshPart").
- **Walking:** passBy waypoints (advance within 3 studs, poll 0.05 s); NpcAnimator goes to idle only after 0.35 s still. Visits and knocks reach both floors (the owner's ArenaStairCopiesCopies stairs at the north end, z≈-245..-253); 2 floor changes seen in 20 s.
- **Owner's layout now:** lower floor rooms/hallways at y 171, upper at 206.
- **Crowd looks:**
  - a pool of 150 dressed users (Shirt and Pants ≠ 0, hair-only accounts kept 20%), USER_ID_RANGE 1e5..1.5e9;
  - each look is mixed from different users (shirt / pants / hair / hat / face / neck / back) on a random skin; rare-first picks with a used-penalty;
  - paintClothes colours the body (so a failed clothing texture is not bare); Model:ScaleTo 0.7-1.3 (desc scales barely showed); reject Height > 9 × scale.
- **Client crowd:**
  - anthem: STADIUM_ANTHEM → everyone's "anthem" pose on server time (sway, arms up), 360 updates a frame, no talk or walk; client 61 fps;
  - Mexican wave: server "wave" every 35-60 s in the fight, WAVE_WIDTH 9°;
  - chant: mood carries the chant team → 35% of its sections do "pump".
  - Poses use a posingCount turn gate (fair round robin).
- **Music:** the pre-game music is no longer stopped at TELEPORTING; it fades when the anthem starts, or at IN_GAME if the anthem was skipped.

**Anthem rave (2026-10-24):** owner: the anthem is loud and pumping, the crowd must go wild.
- Client updateBeat finds the playing *DRUM* Sound under ArenaOne (ActiveAnthem_ANTHEM1_DrumFX on CrowdFX.CrowdStem) and reads hits from its PlaybackLoudness (> avg×1.3+8, ≥0.24 s apart) to learn the interval.
- No drum, or no signal for 2 s, means a steady 128 bpm pulse. Studio Play reports PlaybackLoudness 0, so the tests ran on the pulse.
- The "anthem" pose has 4 kinds by phase: jumpers (Root lift 2.6), fist pumpers with headbang, arm wavers swinging every 2 beats, headbangers. Faces "cheer". The nearest are posed every frame.
- Measured: ~500 avatars airborne at the peaks, 0 on the beat; client 58 fps.
- The anthem starts ~14 s into its 60 s window (back-timed); the pre-game music plays until then.

**Bass visualiser + organic anthem (2026-10-24)**
- **ArenaBassPulse.client:** mirrors the playing music (the anthem *DRUM* stem, else ArenaGlobe "ArenaMusic_*") into SoundService AudioPlayer → Wire → AudioAnalyzer (SpectrumEnabled) with no output, synced to the Sound's TimePosition.
  - Spectrum: 512 bins × 46.9 Hz, so 40-80 Hz is bins 1-2. Auto-levelled; kick = level > avg×1.35 and > 0.3.
  - shared.ArenaBass {level, beatAt, interval, live}. The globe Size × (1 + 0.035·level), measured ~1% pulses.
  - The AudioAnalyzer works in Studio even where Sound.PlaybackLoudness reads 0.
- **Owner's feedback on the first rave:** "forced, stuck midair, not everyone". Now:
  - hops are 0.32 s parabolas (4x(1-x)·hopH 0.9-1.9);
  - roles hop/pump/clap/nod/sway/calm, weighted by 2 random "ultras" sectors (55°) and a 20 s energy build;
  - per fan: lag -0.03..0.1 s, every-other-beat 35%, amp; roles re-rolled every 4-12 beats;
  - calm fans keep chatting and walking (the life loop runs in the anthem for role calm).
  - Measured: ≤ ~80 airborne at once, 64 fps.

**Crowd energy + social (2026-10-24):** owner disliked the "organic" anthem: it lost energy, most were idle, and the on-beat stuff was 80% too strong. Wants randomness.
- Anthem now:
  - roles hop / pump / wave / clap / scream / calm (5%), each on the fan's own random rate (a.rate 1.2-2.8 Hz);
  - hops are arcs on the fan's own cycle (HOP_SHARE 0.55);
  - the kick is only BEAT_ACCENT 0.2 (a small Root bounce and nod);
  - ultras areas only raise the hop weight; roles re-rolled every 4-12 beats.
  - Measured: 943/1000 moving, ~80-110 airborne at any time, 61 fps.
- **Fight:** LIVELY_SHARE 3% of the crowd start a random express every 0.5 s.
- **Turning:** a.yaw is jittered ±25° at build; LOOK_SHARE 5% turn every 0.5 s (±55° from the arena, or to the neighbour 20%), smoothed over TURN_TIME 0.6. Measured: 671/1000 off-centre by 15°+.
- **Walkers:** keep PERSONAL_SPACE 2.2 using the shared grid (4-stud cells kept current); if blocked they wait 0.8-1.6 s, then stop.
- **Talk:** CrowdChatter (ReplicatedStorage.QuinCore) has pre/live/post lines (512) with {team}/{other}/{quin}/{n}/{name} slots.
  - conversation() = opener → reply → maybe a follow-up → maybe a reply. The speaker's face is "talk", the listener's happy; bubbles within 90 studs, 1.8-3.2 s between turns.
  - Chat phase comes from the StateReplication Phase (lastPhaseForChat).

**Next on the MVP:** spectating (bench, arena cams, freecam) and results/rewards (weeks 3-4), then Quin damage + Workshop.

**Roles, owner chat, attendance (2026-10-23, commit b1e083a, verified in Play)**
- Player attribute SkylarkRole "Player" (default) / "Admin" (SkylarkRoles.server, remote ReplicatedStorage.SkylarkRole; SkylarkCanAdmin = Studio, creator, group rank 254+, Workspace SkylarkAdmins "id,id"). Play As Admin -> Admin, Play As Roblox Player -> Player.
- Player: SkylarkRoleClient disables admin ScreenGuis (QuinMenuUI, ArenaDroneUI, MasterDebugUI, TuningPanel, AnimationLabUI, JumpDebugUI, ArenaOrchestratorUI); QuinDebugGui only while shared.SpectateFilter is set (prep terminal). Key handlers check shared.IsAdmin(). Admin: barrier group Default, all doors open (client) and never ejected (server).
- OwnerChatter (540 lines, topic threads 4-7 turns, pre/live/post x glass/hall); ArenaNpcOwners say() -> ReplicatedStorage.NpcSay -> NpcChatBubbles (DisplayBubble within 90 studs, same as stands).
- Crowd attendance (ArenaCrowdClient ATTENDANCE): open 15%, gen 30, prep 50, teleport 70, anthem 90, pre 95, fight 100; after 300 s in game -3%/min (max 25%); closure -1.2%/s; IDLE fast. Leavers: walk off + flicker, flicker in place, or pairs with CrowdChatter.leaving (ATC food invites). Measured: prep ~480, anthem 900, fight 982, closure 954->669 in 25 s.

**HUD since 2026-10-24 (768752d):** SkylarkClockUI.TopBar is one row level with the Roblox buttons (GuiService.TopbarInset, ScreenInsets None): [TIME admin] [MENU] [SC] [clock]. The clock shows only time and period; clicking it calls shared.OpenPlayerMenu("SCHEDULE"). The ScheduleBoard and the entry bar are gone. Arena status lives in the menu's SCHEDULE, one section per arena (ReplicatedStorage.QuinCore.SkylarkArenas); ArenaEntry shares shared.ArenaEntryStatus. MCP trap: the look camera locks the cursor to the centre, so synthetic HUD clicks miss until a menu is open (press G first).

**Block timing + ARENA MENU [DEBUG] (2026-10-25, 7264c62):**
- All block timing is in ReplicatedStorage.QuinCore.ArenaTiming: walk-in opens 20 min before; close rule BeforeEnd (5 min before the block ends) or LastRound; prebook 30% off; round gap 15 s; the round's phases; FastRounds.
- Session overrides live in Workspace ArenaTiming_<Key>.
- Auto rounds stop at ArenaTiming.lastRoundAt, which is EndsAt minus roundLength times the rate (a paused clock counts as 1x).
- The terminal's debug button opens ArenaBlockMenu.client. It has a timeline, jump buttons, clock and round controls, quick match, and the timings. Server side is ArenaBlockDebug.server, a RemoteFunction ArenaNetwork.ArenaBlockDebug.
- The owner has not yet picked the walk-in close rule. LastRound is my recommendation; the default is still BeforeEnd.
- MCP trap: start_stop_play can hang on "Start play hasn't finished yet". The owner presses Play by hand.
