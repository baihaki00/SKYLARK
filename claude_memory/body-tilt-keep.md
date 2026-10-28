---
name: body-tilt-keep
description: Owner loves the whole-body tilt while running (pass 16) - never break it; wants it switchable
metadata:
  node_type: memory
  type: feedback
  originSessionId: 067aa4a4-9c77-4da6-812b-ce8bdf098393
  modified: 2026-10-01T19:21:54.081Z
---

The whole-body tilt (ProceduralCombatReactionController section 4c, `CombatConfig.BodyTilt_*`, workspace attribute `BodyTilt` for live on/off) makes running look "top notch" per the owner (2026-10-02). Never break or tone it down without asking; any later change to the hips/spine/foot layers must be A/B-checked with tilt on. They want an easy way to switch it off (workspace `BodyTilt=false` / config) but default stays on.

**Why:** it is the change the owner liked most in the motion work ("definitely dont ever break it").
**How to apply:** treat tilt as a regression guard in every motion pass; see [[quin-movement-audit-workflow]].

**Exception (owner, 2026-10-05):** no whole-body tilt while strafing ("it looks weird"). Done as the `StrafeUpright` body layer (tilt fades by the share of the body in a strafe clip); the tilt is unchanged everywhere else. See [[procedural-port-body-layers]].
