---
name: quin-retreat-chase-scale-feedback
description: "User feedback (2026-10-01) that Circling and Retreat/Chase play out in a tiny area; they must use the 600x600+ arena, break line of sight, and the pursuer must be relentless"
metadata:
  node_type: memory
  type: feedback
  originSessionId: aab93d9f-4a24-4c2a-9a6e-34e1919e40d6
  modified: 2026-10-01T07:11:13.751Z
---

Circling needs rework, and Retreat <-> Chase needs rework: Quins "run around in a small circle ... like playing in the kindergarten or kids playground". The arena is 600x600 studs and may get bigger, so behaviour must scale with the real arena size, never assume a small space.

What they want from retreat/chase (confirmed: "i want them to run for their life"; the "dont" in the first message was a typo): the fleeing Quin **runs for its life** and looks for a way to **lose sight of its opponent**; the pursuer chases "like the guy owes him debt" (relentless, hunts it down).

**Why:** small-radius circling/retreat loops look childish and waste the arena.
**How to apply:** this is for Phase 4 of [[quincore-phased-plan-20261001]] (after the debug overlays and cognition layers), not Phase 2. Derive distances from `SpatialModule.getArenaBounds()`; the arena-centre pull that is currently dead (`getArenaCenterPull`) and the 30-stud `RetreatSearchRadius` are likely contributors to check first.
