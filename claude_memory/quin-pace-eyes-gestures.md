---
name: quin-pace-eyes-gestures
description: 2026-10-27 general Quin pass (steps 1-5): Pace gears, reaction, posts/scan/greet, eye prototype, event gestures; switches, numbers, open items
metadata:
  type: project
---

Built for every mode, following [[quins-improve-in-general]]. Commits 018453d (steps 1-3) and the next one (eyes and gestures).

- **Pace** (Modules/Pace): Walk/Jog/Run from urgency. Habits tilt the urgency. It shifts up at once and shifts down only after the urgency stays low. It eases into a spot. Live A/B: Workspace `PaceOff`.
  - Chase uses chaseUrgency, so long calm approaches are a jog. Task urgency is in TaskChoice.
  - Lantern Siege, 40 s: still 74%→45%, jog 6%→35%, back-and-forth 43→26.
  - 16v16 unchanged (≈ all Run, because the Quins are always closing in).
- **16v16 back-and-forth is mostly Chase mechanics**: skid reversals, ledge approach, detour on/off. It is NOT fixed yet; it's the next candidate.
- **IdleState jobs**: on a new spot, look first (reaction comes from Awareness). Then settle, face ObjectiveFace, and keep pace with a moving spot.
- **Gaze**: greet an arriving ally with a nod; scan believed enemy spots and the watch arc. It uses the LookPoint/LookUntil attributes, which LookController reads.
  - Gestures (attribute Gesture): Alert, Ready, Acknowledge. They are head, eyes, nod and stance only, never leg clips.
- **Eyes**: QuinEyes.client.lua is cosmetic and client-only. It puts one plate per eye on the head bone at (±0.125, 0.3, -0.392), turned 37° outward.
  - Switch: Workspace `QuinEyes` = Mix | Off | Slit | Calm | Visor | Round | Dot | Anime; the per-Quin `EyeStyle` attribute wins.
  - The owner said the first single plate "floats"; it was replaced with the per-eye version, which the owner has not seen yet.
- **Trap**: the MCP screen_capture showed the spectate camera even after I took over the camera; I could not verify the eyes visually myself.
- **Trap**: calling open_application on Roblox Studio spawned a second Studio, and a "Multiple Sessions" prompt closed the session. Never do that; ask the owner to press F5.
