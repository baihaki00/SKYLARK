---
name: server-cframe-teleport-snap
description: Server root CFrame writes/anchoring snap on clients (buffer dropped); teleport smoother + RootPriority fix (2026-10-27); how to measure the drawn body
metadata:
  node_type: memory
  type: project
  originSessionId: 0ff340fb-2a3d-4252-85c7-bcb1f4382fce
  modified: 2026-10-28T23:34:24.690Z
---

Measured 2026-10-27 with a falling test part:
- A server CFrame write on a moving body reaches the client as a teleport: the client drops its ~0.25 s interpolation buffer and jumps 80+ studs in one frame.
- Anchoring a moving body on the server freezes it at a stale spot on the client.
- A physics stop (a velocity mover) replicates smoothly.

In the 16v16 this was:
- ProjectileJump set-down (80-230 studs);
- knockback/Recovery falls (~40 studs);
- Fight/Airborne/Knockback rotation writes (a hop forward of a few studs).

**Fix (commit 6b5ea97)**
- Main sets `HumanoidRootPart.RootPriority = 127`. The skinned mesh (Alpha_Surface, 8-stud T-pose box) had been the assembly root, so a client offset moved the HRP instead of the mesh.
- AIGhostHandler (Direct mode) `smoothTeleport` draws the mesh where it was via `RootJoint.C0` and drains the gap at the body's speed. `RootJoint.Transform` does NOT move a body the client doesn't own.
- The smoother is off in MidAirClash, ReEntry and Death. Workspace `TeleportSmoothOff = true` turns it off for comparison.

**Results:** sudden drawn jumps per 20 s went from 34-48 (off) to 11-12 (on). The rest are ClashOrbit's own client-drawn path, plus a few PJ jumps while an offset drains mid-flight.

**Why:** owner saw "snapping" onto platforms, in clash falls, and on landings. Server-side probes show nothing; only the client sees it.

**How to apply:**
- Prefer physical stops (velocity or movers) over CFrame writes/anchoring for moving Quins.
- Measure snaps on the CLIENT: sample `Alpha_Surface.Position` in BindToRenderStep at `Camera.Value + 1`.
- Use the metric "step > 3 × previous step + 4". Plain second-difference counts every landing.
- Never sample with RenderStepped + task.defer: that created fake one-frame spikes.
- execute_luau runs in its own VM: `shared` is not the game's.

**Launch lead (2026-10-29).** A server velocity launch is drawn ~0.18 s late on the client (interpolation buffer), while clips and attributes arrive at once. `KnockbackModule` publishes `LaunchVel`. `AIGhostHandler.applyLaunchLead`, run after smoothTeleport, draws the mesh on the predicted arc via `RootJoint.C0` until the root moves, then drains over 0.5 s. The visible delay went from 0.148 s to 0.043 s. Switch: Workspace `LaunchLeadOff`. Trap: track "already seen" with a separate init flag; a nil-start check skipped every Quin's first launch.

**Owner rule (2026-10-27):**
- Leave ProjectileJump dives as they are. Only platform/stair-hop landings were meant to change.
- The smoother is off in ProjectileJump and for 0.4 s after it (47a633a).
- The hop-landing knee dip (ebfb5f0, Landing_Hop* config) also skips ProjectileJump.

Related: [[quin-movement-audit-workflow]], [[visual-bug-testing]]
