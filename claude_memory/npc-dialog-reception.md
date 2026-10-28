---
name: npc-dialog-reception
description: "NpcDialog (side-view NPC conversation, reusable), Arena Receptionist, queue platforms, the arena's grounds rule — built 2026-10-25 (commit cc2382d)"
metadata:
  node_type: memory
  type: project
  originSessionId: 25c85d49-de6e-4f92-9c82-8f5fba9ab143
  modified: 2026-10-24T21:28:02.096Z
---

Owner asked (2026-10-25) for one reusable NPC conversation view: NPC + big speech bubble on the
LEFT, menu/options on the RIGHT (owner's sketch). Camera tries (side view, front view, long lens,
fake-orthographic FOV 4) were all rejected; "don't touch the camera" was tried too, then the owner
said (later on 2026-10-25) that moving while talking is crazy. **Current rule:** while open, controls are
off and you face the NPC; the camera is held face to face: DISTANCE 6.5 studs straight in front of
the NPC (their head's LookVector), level with their neck, neck dead centre, eased in over 0.5 s; both
are released on close. Owner's mockup = NPC filling the middle, your avatar NOT in shot (an
over-the-shoulder try was rejected: "not centered"). MCP screen_capture in Play renders from Studio's
own view without the GUI: check the camera by numbers (WorldToViewportPoint), not by that capture. No body turn or
skew on the NPC (she stays straight). Menus sit against the right edge (MENU_EDGE 24 px in: owner wants them almost at the edge). Built as
ReplicatedStorage/QuinCore/NpcDialog.lua (open/say/choose/place/close). Use it for the Trainer,
Quin Specialist and every future NPC; first user is the Arena Receptionist (ArenaEntry.client).

Owner-placed parts: QueuePlatformTrigger (front spot) + QueuePlatform x7 per terminal, and the
"Arena Receptionist" model behind each ArenaTerminal (prebook terminals have none, self-service).

Decisions (owner said "go with your recommendations"):
- walk-in side fixed at registration (lighter side); "Take me to my prep room" = side's prep hallway
- registered owners must be inside the arena's grounds (ArenaGround + 250 studs = r 550) at each
  round start; 10 s grace while live; missed = entry gone, prebook deposit lost (walk-ins pay per round)
- leaving mid-event: Quins finish the current round, owner out of the rest
- "new here" = none of your Quins has fought yet (no extra DataStore)

**Traps:** SmoothCamera.client keeps CameraType Scriptable always, so NpcDialog holds the camera
with BindToRenderStep at RenderPriority.Last. ProximityPrompts only show when on screen: in tests
stand behind the terminal (e.g. x+3, z -768) facing -Z, then InputHoldBegin/End. MCP mouse clicks on
IgnoreGuiInset GUIs (NpcDialogUI) land 58 px low: click at y - 58. Anchoring the HRP on the client
stops position replication (boundary tests: don't anchor).

Related: [[npc-owner-queue-plan]], [[skylark-many-arenas]], [[placeholder-world-intentional]].
