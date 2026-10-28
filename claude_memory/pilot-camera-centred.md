---
name: pilot-camera-centred
description: Owner wants the piloted Quin's camera dead-centre like Play As Quin; no follow lag (Pass 76b lag was reverted)
metadata:
  type: feedback
---

The camera on a Quin the player pilots stays dead-centre on the body, exactly like the Play As Quin camera (SmoothCamera's zero-lag centering). Don't add a follow lag or an off-centre drift.

**Why:** in Pass 76b I added a capped follow lag after misreading "the camera is locked to the body during turning". The owner reverted it on 2026-10-07: "i want it centered just like play as quin camera".

**How to apply:**
- Turning or "stiff" complaints about piloting are about the body (facing, latency), not the camera framing. Compare against PlayerQuinController (Play As Quin):
  - it runs on the client;
  - the body turns through Humanoid AutoRotate;
  - it has no server lag.

Related: [[player-quin-mode]].

Update 2026-10-07: the owner then asked to track the torso, not the root, so the body stays centred during the run's body tilt, and for a small gyro. Done in SmoothCamera (`pilotTrackTorso`: the torso's horizontal offset, smoothed; `pilotGyroDeg` 3) on the piloted Quin only.
Then (same day): the owner said no gyro (`pilotGyroDeg` 0) and wants the body dead-centre in corners. The camera had read the torso before the client poser leaned it, so AIGhostHandler's presentation loop is now bound at `RenderPriority.Camera - 1`, ahead of the camera. Measure centring at `RunService.PreAnimation` (the drawn frame).
