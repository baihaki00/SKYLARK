---
name: humanoid-sideways-part-hover
description: "Roblox Humanoid quirk found in Pass 76b — a Quin landing at a run on a part laid on its side (any cylinder, or a block turned 90 deg on X/Z) hovers 1.75 studs above it and runs on air; build walkable surfaces from upright parts"
metadata:
  node_type: memory
  type: project
  originSessionId: ebbb42a0-75bd-4628-bf70-1172d44f038a
  modified: 2026-10-07T11:51:16.796Z
---

Found 2026-10-07 (Pass 76b), measured in Studio.
- A Quin landing from a running jump on a part whose local up axis is not vertical hovers **1.75 studs** above its top and keeps running on air until it leaves the part.
- Affected parts:
  - any Cylinder part, because a cylinder's axis is X, so a round floor is always laid on its side;
  - any block turned 90 deg on Z.
- Fine: the same block upright or turned only about Y; standing jumps.
- Nothing in our scripts reads part sizes for this; it is the Humanoid.

**Why:** the owner saw "running on air for 1–2 s" after jumps on the Player Quin dais.

**How to apply:**
- Any floor, platform or obstacle top that Quins land on must collide as upright parts. Keep round or rotated parts visual-only (CanCollide off) and put invisible upright collision under them. The dais does this: `DaisFloor` strips plus the `Ramp` wedges in `SocialRespect.buildPlatform`.
- When adding arena pieces (ArenaGenerator), check that walkable tops are upright.
- Still on its side in the arena: ArenaOne/OB, a 59-stud-tall block (only matters if a Quin lands on its top).

Related: [[player-quin-mode]], [[arena-generation]].
