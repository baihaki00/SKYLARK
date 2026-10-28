---
name: skylark-economy-design
description: "Owner's economy/stats/scoring asks (2026-10-23) and my proposal in SKYLARK_ECONOMY_DESIGN.md: SC, seats, performance score, stat budget, no P2W; awaiting owner picks"
metadata:
  node_type: memory
  type: project
  originSessionId: 763b81d0-f578-4604-9efb-fa8705d651aa
  modified: 2026-10-23T15:05:14.472Z
---

On 2026-10-23 the owner asked for:
- the ArenaTerminal with Spectate and Register Quin;
- Spectate: Alpha/Beta side, Normal Seat or VIP Seat (VIP box already built; drone and free-fly cameras only inside the VIP box, through its terminal);
- SC (Skylark Coin): 100 for a normal seat, 300 for a VIP seat;
- a performance score, with the final score at winner decided paying SC;
- defeated Quins sent back to their room, not the gate;
- a toggleable stats HUD on the prep room glass;
- Workshop/Training Ground dialogs (NPCs already exist, basic) running on Skylark time.

Core rule from the owner:
- unpredictability over grinding (stats 15–100), but stats must be trackable;
- players feel an edge before the event through knowing their Quin and strategy;
- absolutely no pay to win, no exploits;
- money drains and gains, balanced.

My proposal is in `D:\SKYLARK\SKYLARK LOCAL REPO\SKYLARK_ECONOMY_DESIGN.md`:
- start balance 2,500 (owner floated 10,000);
- capped stat budget, with gains shrinking toward 100;
- condition and sharpness;
- personality fixed and revealed by watching;
- pre-event stance and target plans;
- scouting;
- prepared Quins win ~60–65%;
- server-authoritative wallet in DataStore.

**Why:** it scopes the MVP loop ([[skylark-mvp-target]]).
**How to apply:**
- Nothing is canon until the owner picks.
- Build order: 1 terminal+wallet+seats+room return, 2 score+payouts+glass HUD, 3 stats+care, 4 plans+scouting, 5 balance.

**Owner decisions, round 2 (2026-10-23):**
- Personality is chosen only in the Hero Intro, for the first Quin (named personalities: Friendly, Jester, Egoist, ...).
- Quins are scarce: a new Quin costs a lump sum; they trade owner to owner, via auction and via resellers.
- Personality is discovered by appraisal or over N games; the owner likes both.
- Prebooking: a live Alpha/Beta board anyone can inspect before the event.
- The owner struggles with permanent progression versus fairness.

**My answer (in the doc):**
- Bond (affects how well the Quin follows the plan, never damage; resets on sale);
- veteran traits that are trade-offs;
- signature techniques with limited slots;
- history that raises resale value;
- prebook: the plan stays hidden, an early-booking discount, a lock at T−5, a cancel fee.

**Round 3 (2026-10-23):**
- Bond confirmed: it drives how much the Quin trusts and carries out the owner's plan.
- Signature techniques parked: no animation work for now; focus on logic.
- Side picking: I proposed choosing a side with a Strength Index guard (+15%), with NPQ fill as a hidden balancer. Awaiting the owner's OK.

**Round 4 (2026-10-23):**
- The owner says the Quirky labels (Charger, Observer, Showoff...) are long outdated, though they're still in the code (PersonalitySystem.assignInitialQuirky, RetreatTacticsModule).
- The 10 personality dimensions must change over time: Quins are creatures, and the owner sculpts them.
- My proposal: temperament (born named personality, sets home ranges, near-fixed) plus habits (the 10 dimensions drift ~0.01–0.03 per fight from the plans used, fight events and training focus; Bond scales the owner's influence; arrows in the stats panel; habits carry over in a sale; appraisals go stale).
- The owner approved temperament + habits ("first time i feel like i tied the knot"). Side picking with the SI guard was confirmed ("yup").

**Step 1 shipped (commit 99dda64, 2026-10-24):**
- SkylarkWallet: server-only SC, attribute "SC", start 2,500. **The start balance is still unconfirmed** (the owner floated 10,000).
- SkylarkSpectate + SpectateClient: Normal/VIP seats, VIP doors and eject, and the VIP terminal (`vip` remote → shared.VipAccess).
- ArenaEntry: the chooser and spectate panel. Buttons are named (SpectateChoice, RegisterChoice, AlphaBtn, BetaBtn, NormalBtn, VipBtn, BuyBtn) so MCP can click them by path.
- Defeated Quins return to the owner's prep room (ArenaPrepRoom.bringHome).
- Trap: ProximityPrompts never render while Studio is driven over MCP (PlayerGui.ProximityPrompts stays empty, and E / InputHoldBegin don't trigger). The VIP-terminal → V/B step is therefore verified only on the server side; the owner must press it by hand.
- Next: step 2, the performance score and payouts at WINNER_DETERMINATION, plus the glass HUD toggle.

**Step 2 shipped (commit 4816800, 2026-10-24):**
- Start balance 2,500 is CONFIRMED by the owner.
- Entry 100/Quin, charged at seating (pickRound), refunded if the round stops before the winner.
- Score: SkylarkPayouts, live as the MatchScore attribute. Pay = 30 + score × 0.2 + 150 win + 50 still standing.
- The owner's target: an early double loss is about −100 (now ~−105). Audience 16–30 ("not dumb kids who cant count", rich kids who aurafarm), so losses are OK if they're explained.
- UI: MatchResultsUI card (ResultsClose button) and the PrepStatsBoard SurfaceGui on the owner's PreparationRoomGlass (HideStats / ShowStats).
- An average loss is about +46 for 2 Quins before step 3's drains. Re-balance at step 5.
- Test recipe: Play (SkylarkTestHour 12.5 is inside Tuesday Team Battles); on the client, teleport to an ArenaTerminal and call ArenaEntry:InvokeServer("register", {1,2}); on the server, ArenaDevCommand `start {"Mode":"TeamBattle","TeamSize":4,"Toggles":{"InstantMatch":true}}`. A 4v4 takes about 3 min.
- MCP can't turn the first-person camera to photograph the glass board. Its text was verified by reading the labels.

**Step 3 shipped (commit 10fbb7d, 2026-10-24):**
- Owner: "yes condition handicap, stats later, timer first, go". Numbers are in SKYLARK_ECONOMY_DESIGN.md under "Step 3 built".
- Code: ServerScriptService/QuinCare (condition, rest, busy, Bond, appraisal, remote ArenaNetwork.QuinCare) and StarterPlayerScripts/QuinCareClient (the QuinCareUI dialog). Stations: the QuinWorkshop floor (its prompt sits on an attachment over the operating tables; anywhere on the floor counts as near), "Quin Trainer" and QuinSpecialist.
- TRAP: MCP execute_luau runs in its own VM. Requiring a module there builds a second copy. Requiring QuinCare took over the remote's OnServerInvoke, so tests went to the wrong roster. Drive tests through the workspace attribute QuinCareDev (`cond <slot> <v>` | `finish <slot>` | `dump`; the reply is in QuinCareDevResult) or through the client.
- Verified in Play: the dialogs, repair, training, appraisal, post-match condition loss, a worn Quin at 900/900 HP with energy held at 90, and the busy seat skip (no entry charged).
- Still deferred: six combat stats ("stats later"), visible sparring at the TrainingGround ("timer first").
- MCP trap: stopping Play and then starting it again often times out, after which every start says "Start play hasn't finished yet" while Studio sits in Edit. Only the owner pressing F5 clears it. Batch script pushes so Play restarts are rare, and ask for F5 early.

## Step 4 owner rules (2026-10-24)
- Plans are set ONLY in the prep room ("that's what prep room is for") — never at the prebook terminal or boards.
- A player either spectates an event or takes part in it, never both: entrants/prebooked can't buy seats (SkylarkSpectate), seat holders can't register (ArenaRegistration). Built c589ba7.
- Prebook happens only at ArenaPrebookTerminal parts (owner-placed); ArenaBoards are display only. Arena Terminals = staffed walk-in desk, full price.
- Step 4C plans BUILT cc6604f: ServerScriptService/QuinPlans (follow 0.4+0.6·Bond, clash ×0.7 + 0.8 s hesitation via PlanHesitation in the orchestrator release), TargetingModule score 14 "Owner's plan", PLAN panel on the prep terminal. Test trap: keyboard E doesn't fire ProximityPrompts via MCP; use prompt:InputHoldBegin()/InputHoldEnd() from the Client VM. Registered Quins are only seated while the event is Live (set hour 12.1 for Team Battles).
- MCP trap: screen_capture does NOT show BillboardGuis (owner sees them fine). Don't debug "invisible" billboards from screenshots; ask the owner or check properties. Prep terminal test hook: player attribute PrepTerminalOpen opens the Plan/Binoculars menu (45b05e4).
- Owner: Play As Admin / Play As Roblox Player / Spectator HUD buttons are DEBUG buttons — hidden by default, F8 shows them (player attr ShowDebugButtons, SkylarkRoleClient). Keep them that way (66e99e7).
- Step 4D scouting BUILT a2d1052: Workspace ScoutRoster (ArenaPrepRoom, bands only) + ArenaScout (ArenaGenerator) read by ReplicatedStorage/QuinCore/ScoutView; both sides (own side added on request). Arena cover barely varies (2.6-5.4%), so its OPEN/SOME/HEAVY bands are relative thirds. Re-measure: ArenaGenDevCommand "scout 200" -> ArenaGenCheck.
- QUICK MATCH (839d763): debug button on the Arena Terminal chooser (F8, any role; server allows Studio or SkylarkCanAdmin). It jumps the clock into the next 16v16 Team Battles window, enters your Quins and starts a round.
- Plan test 2026-10-24 (PlanDevCommand hook, 369c9d6): at Bond 0 (follow ~0.4) Aggressive vs Defensive came out 1-1, Alpha won both, behaviour barely moved. NPQs all score 60 strength (fresh, Bond 0), so NPQ fill has no lever yet. Both went to the owner for decisions.
- TRAPS: live HP is Humanoid.Health (the Health attribute is max 1000). KO'd models get Team="Defeated". loadstring is unavailable in the Server MCP VM, so paste collectors inline. A 16v16 takes ~6-8 min; poll a collector attribute with ~58 s execute_luau waits.
- Owner decision 2026-10-24: keep plans light, let Bond carry them. The Bond 100 test showed a clear style trade-off, not a winning stance. Built 7058962: veteran NPQ tiers (50/35/15), fill dealt by projected side strength, NPC owners plan via QuinPlans.npcPick. Step 4 left: the hesitation animation.
- Save safety BUILT 246cfc4 (2026-10-24): ServerScriptService/SkylarkSession is the per-player DataStore lock. Wallet and roster wait for it (Session.waitFor), save only while it is held (maySave), and save via Session.addSaver before release. A failed roster load is now unsaveable; it used to save starter Quins over the real roster. Studio has NO DataStore API access, so the lock goes straight to "unsaved" (memory only). Test the lock logic with a mocked store in the Edit VM (loadstring of the source with ENV gsubs).
- New-player check 2026-10-24: the spawn (argoniaonion.ArenaOne.SpawnLocation, faces -Z) faces AWAY from the terminals and the arena (both +Z). The terminals are plain unlabelled grey 6x7x9 parts. "go to an Arena Terminal" has no pointer. Proposals went to the owner.
- Player menu BUILT 0f29af7: StarterPlayerScripts/PlayerMenuClient opens with G or the MENU button left of the SC pill. Tabs: MY QUINS (QuinCare "list") / SCHEDULE / WALLET (session log, ArenaNetwork.WalletLog) / LAST MATCH (shared.LastMatch from MatchResultsClient). It only shows things; actions stay at stations. Test hook: player attribute PlayerMenuOpen = tab name. The MCP Client VM has its own `shared`, so it can't inject LastMatch. MY QUINS = left-to-right cards (baac82d) with a live 3D Quin per card via ReplicatedStorage.QuinCore.QuinPreview (gender template in a ViewportFrame, idle, drag to turn; add accessories in QuinPreview.build). Window 1080x680 with a UIScale fit. The attribute hook opens the menu but lands on SCHEDULE: click TabMYQUINS via user_mouse_input instance_path.
- Sprint: Roblox has no default sprint. The old ToggleWalkRun (Z) script is fully commented out. StarterCharacterScripts/Animate is a copy of Roblox's default Animate.
