---
name: quin-animation-authoring-plan
description: Parked task (2026-10-03) - author base Quin animations in Blender via bpy scripts for the owner to polish; priority clip list; GASP port rejected
metadata:
  node_type: memory
  type: project
  originSessionId: 067aa4a4-9c77-4da6-812b-ce8bdf098393
  modified: 2026-10-07T14:53:39.082Z
---

Owner asked (2026-10-03) whether Claude can make base animations for the Quins in Blender; agreed in principle, then **parked it ("save this task for later")** to keep improving movement first.

Plan agreed in discussion:
- Claude writes Blender Python (bpy) scripts that keyframe base clips on the Quin's Mixamo rig (owner supplies the rig .fbx + bone names, Blender install), renders frames/contact sheets to check, owner polishes; then Claude wires the clips into GaitModule / ChaseState with markers matching the game's measured timings (takeoff distance, apex, flight time).
- Claude is strong on physics/geometry-driven clips (arcs, contacts, speeds, phase-matched loops), weak on acting/style: expect blocking-to-early-polish quality.
- Priority clips (suggested order): true backpedal (currently forward run reversed), diagonal strafes (fwd/back L/R), plant-foot stops L/R, hurdle/step-vault for 5-11 stud obstacles (uses generic jump clip now), mantle/climb-up (stepping stones rocket-hop now). Then: turn-in-place 90/180 and running pivot (turn clips are one broken shared clip, disabled), spot-hop takeoff/landing, edge teeter (edge guard stops at drops), landing variants, directional hit reacts/dodges/stumble, idle variety.
- GASP port from Unreal rejected: Epic content is licensed for Unreal Engine projects only (owner to verify), motion matching does not exist in Roblox, retargeting cost; owner had already asked for GASP removal on 2026-10-01.
- Mixamo: royalty-free use in games OK, no redistribution of raw assets (owner to verify current terms); owner plans own character later.
- Legal alternatives mentioned: Cascadeur, Roblox animation capture / Rokoko Video / Move.ai, CMU mocap, licensed packs.

**Why:** owner's focus right now is movement and game logic; animation authoring comes after.
**How to apply:** when the owner returns to animations, start from this list and ask for the rig .fbx; see [[quin-open-requests-20261002]] and [[quin-movement-audit-workflow]].

**Update 2026-10-07: Blender authoring started** (owner: "lets start with blender").
- **Rig:** `D:\Skylark Isles\XBOT\xbot.blend` (Mixamo X Bot; the owner says it fits Y Bot / the Quin too). Same `mixamorig:` bone names as the Quin. The armature object is scale 0.01; armature space is Y up, +Z forward, character's left = +X.
- **Blender:** 5.1 at `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`; runs headless with `--background --python`.
- **Owner's architecture:** clips are in place, with no root motion. Roblox physics moves the body; a clip only poses the limbs. Jump clips are meant to be played by flight phase, not at a fixed rate.
- **First clip:** QuinLongJumpPhase.
  - 31 frames at 30 fps = phase 0..1: takeoff, rise, apex hang, sail, landing reach.
  - Output in `D:\Skylark Isles\XBOT\QuinLongJumpPhase\` (FBX, a copy .blend, pose renders and a strip).
  - Generator: `QUINCORE_BACKUP/scripts/blender/make_longjump.py` (force-added: the repo ignores *.py and *.png). It aims bones in armature space, parents first.
- **Render trap:** the side camera must sit on the character's right (-X) for right-handed camera axes; otherwise the render is empty.
- **Next:**
  1. The owner imports the FBX in the Roblox Animation Editor and publishes it.
  2. I wire phase-driven playback (clip time = flight phase) into the jump.
- **Cascadeur:** 2025.2 is also installed (Python commands, no headless mode); the owner's template is `D:\SKYLARK\QUIN_TEMPLATE.casc`.
- 2026-10-07: the owner judged the first QuinLongJumpPhase "kinda terrible" and parked the jump ("we do it later"). Turns came first (Pass 78: mechanics only, no turn clip yet).
