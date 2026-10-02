# Pass 20: 180° reversals, camera shake volume, join camera bleed, motion blur

Base: pass 19 (`572354c`).

## 1. Sharp reversals ("glitchy legs on rapid 180 turns", #2)

### Test
- Studio-only `DevGoal` / `DevGoalSpeed` attributes on a Quin (Main.server). It runs at that point on its normal locomotion, at the same 10 Hz as Chase.
- Shuttle runs at 40 studs/s on clear floor in MovementTestArena (x -660..-460, z 500). The goal flips behind the Quin when it is 80 studs from it.
- Foot slip is measured on the server, for planted toes only: a `ToeBase` bone below y 2.35. In a straight run a planted toe slips 3.4-3.9 studs/s.

### Before
A reversal was a running U-turn:
- speed dropped only to 17 studs/s;
- the path swung about 24 studs sideways, with 7-9 studs of carry past the turn point;
- the body pointed the new way after about 1.0 s;
- the body yawed at up to 520-670°/s over the run cycle;
- planted toes slipped 4-5 studs/s on average, and about 15% of planted frames slipped more than 8 studs/s.

90° turns were already clean carves (radius about 18, slip close to a straight run) and were left alone.

### Change (LocomotionModule): plant and pivot
A reversal (more than 115° at more than 14 studs/s, steer driver only) now has three phases:
- **brake:** the heading is held on the old line, and the Quin decelerates at `Locomotion_ReversalBrake` 150 studs/s² down to the pivot speed;
- **pivot:** the speed is held at `Locomotion_ReversalPivotSpeed` 6. The heading turns at `Locomotion_ReversalTurnRate` 7 rad/s, and the body's facing target leads the heading by the facing constraint's lag. Without that lead the body trailed by 30-45° and drove out crabwise.
- **drive out:** this starts once the heading is within `Locomotion_ReversalAlignedCos` 0.9 of the goal direction and the body within 0.8.

Safeguards:
- the brake ends early if there is no ground 4 studs ahead (the floor is lava);
- the whole reversal is cancelled when steering stops, the Quin goes airborne, or 1.2 s pass;
- the `SkidTurnTime` hip drop and the foot-smoke VFX are kept;
- `Locomotion_ReversalPivot = false` restores the old U-turn;
- debug attribute: `ReversalPhase`.

### After (5 reversals at 40 studs/s)

| | before | after |
|---|---|---|
| carry past the turn | 7-9 studs | 6-7 studs |
| sideways swing | ~24 studs | ~2 studs |
| pointing the new way | 1.0 s | 0.67 s |
| body vs motion on the drive-out | up to 40° | 3° |
| phases | - | brake 0.22 s, pivot 0.39 s |

- **16v16:** 164 reversals in 40 s (Fight and Chase), averaging 0.43 s each. One reached the 1.2 s cap; there were no errors.
- **Not fixed:** during the 0.39 s pivot the planted feet still turn with the body (8-13 studs/s on the server). There is no working turn-in-place clip (the turn clips are the one broken shared clip). A turn clip from the parked Blender plan would fix this.

## 2. Camera shake: one volume control
- All shakes go through `VfxModule.shakeScreen` and then the client's `ClientVfxHandler`.
- Each action keeps its own intensity; the client now multiplies every shake by `CombatConfig.CameraShake_Multiplier`, set to **0.3 (70% less)**.
- Live override: the Workspace attribute `CameraShakeMultiplier` (0 = no shake).

## 3. Camera "bleed" on join
- **Found:** a first-frame logger in ReplicatedFirst showed that for the first ~0.33 s after joining, before the character exists, the camera has no subject. It sits at Roblox's default spot (0, 9, 4) looking at the world origin, then snaps to the character.
- **Respawns are clean:** the camera goes straight to the new character.
- **Fix:** `ReplicatedFirst.JoinCameraCover` holds a black screen from the first frame until the camera's subject is the local character and is within 60 studs of it, then fades in over 0.25 s. It holds the screen black for at most 15 s.

## 4. Motion blur
- `StarterPlayerScripts.CameraMotionBlur`: a `BlurEffect` on the camera whose size follows the view's turn rate (90 → 540°/s) and travel speed (60 → 200 studs/s), up to size 8. It rises quickly and fades out more slowly.
- It ignores camera cuts (more than 40 studs or 60° in one frame).
- **Measured:** 0 at rest, 0.5 at 120°/s, 3.7 at 300°/s, 8 at 600°/s, and clear 0.5 s after stopping.
- Roblox has no per-pixel or directional motion blur, so this is a full-screen blur that follows motion.
- Switches: `CombatConfig.MotionBlur_*`; live Workspace attributes `MotionBlur` (false = off) and `MotionBlurScale`.

## 5. "T-shirt accessories at the Arena One Quin spawn, appearing and disappearing": not reproduced
- **During a 16v16 spawn:** every part added on the client was a Quin body (`Alpha_Surface`). Nothing was added and then removed.
- **Quin templates:** `ReplicatedStorage.QuinType` holds bodies only, with no clothing or accessories.
- **The world:** the only accessories or clothing anywhere are on the owner's own avatar. They do not flicker, and "Play As Quin" removes the avatar cleanly.
- **Found on the way, not touched:**
  - `Workspace.ybotdark`, a rig standing in T-pose at (-430, 5, 296) in MovementTestArena;
  - `Workspace.Model`, an empty model holding only a Humanoid.
- **Needs from the owner:** a screenshot or position of the ghost.
