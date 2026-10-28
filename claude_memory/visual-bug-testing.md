---
name: visual-bug-testing
description: "how to hunt visual bugs (blinking etc.) with the owner: instant 16v16 with crowd via ArenaDevCommand, owner's eyes judge, code measures; no screenshot hunting"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c8c40631-9d8d-4e53-974d-4b0baa4a6ca0
  modified: 2026-10-26T09:10:43.096Z
---

For flicker/blink style bugs, the owner judges by eye in a live match, and code measures the triggers. Don't hunt with screen captures (one frame, misses a 0.5 s blink); the owner said so (2026-10-26).

**Why:** screenshots wasted time, a scripted camera fought the owner's camera, the old IKLab Quin was the wrong model, and the quick `GameCommand "team" 16` mode has no crowd. The owner got frustrated by all of it.

**How to apply:**
- Start a real fight with crowd fast: Server `workspace:SetAttribute("ArenaDevCommand", 'start {"TeamSize":16,"Toggles":{"InstantMatch":true}}')` ("stop" first to restart). Not Auto Events (a slow ~1 min lead-in): the owner said "just instant match".
- One variable per run, A/B the owner can see, ask "blinks or no blinks" and step through levels (worked for the mesh-count threshold, see [[skylark-performance-plan]]).
- Never take over the camera while the owner is in Play.
