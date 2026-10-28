---
name: npc-owner-queue-plan
description: "Approved 3-step plan (2026-10-25) — prep room picker (done), NPC owners registering for real, visible terminal queues with chatter + DEBUG toggles"
metadata:
  node_type: memory
  type: project
  originSessionId: a1acf1c8-196b-4c19-9b49-ff9bb30ffe1f
  modified: 2026-10-24T19:55:46.349Z
---

Owner said "go" on 2026-10-25 to a 3-step plan, one step at a time, owner tests each:

1. **Prep room picker 1-16** at both terminals — DONE (commit 95e5e1d). Rooms numbered per side
   (lower floor 1-8, upper 9-16, along the wall), sign over the door. Prebook = claim on its side;
   walk-in = wish (side set at seating). Nearest free number if taken; players before NPC owners.
   Room choice never decides the side, so team fairness is untouched.
2. **NPC owners register for real** — DONE (commit 8dd703a; npcEntries/npcPending in
   ArenaRegistration, DEBUG toggle "npcowners"). Open gaps: a bumped owner is only a log line
   (bubble + walk to stands needs step 3's bodies); an owner's avatar is re-rolled each round
   (fresh room copy). Trap: at 60x the walk-in desk counts as closed (its 5 real-minute margin
   becomes 5 SST hours), so NPC walk-ins don't get in; test at 1x/10x. A pool per event created when booking opens; ~40%
   prebook (same side guard, shown on boards), the rest walk in; they are real queue entries and
   the same owners who sit in prep rooms round to round (today ArenaNpcOwners.fillRound only makes
   them at seating). A real player registering when seats are full bumps the last NPC owner, who
   says so in a bubble and walks to the stands.
3. **Visible crowd** — DONE (commit 81410ef, ArenaTerminalQueue.lua). NPC owners walk from the
   spawn to the shortest line at walk-in / prebook terminals, chat (OwnerChatter "queue" topics,
   queueLine), get served 4-8 s = registerNpc, hang around, leave. Late arrivals (>90 real s,
   clock jumped) register at once. Workspace ArenaQueueSkip (DEBUG "PLAYERS SKIP NPC QUEUE"):
   true = front NPC waits for the player; false = player joins the line, server refuses register
   until front. Open gaps: avatar re-rolled each round + queue body differs from prep-room body;
   a bumped owner walks to the spawn, not really the stands; maybe duplicate bubbles (seen once).

**Why:** owner wants it "real": the crowd at the terminals are the Quin owners who fight.
**How to apply:** all debug switches go in Menu (G) > DEBUG (PlayerMenuClient drawDebug).
Related: [[skylark-economy-design]], [[skylark-time-schedule]], [[skylark-many-arenas]].
