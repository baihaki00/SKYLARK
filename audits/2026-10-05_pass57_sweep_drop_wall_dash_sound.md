# Pass 57: The swept Quin drops cleanly; the wall dash sounds like a dash

The owner, after the Pass 56 demo:
- "not the dash during projectile jump bro, the normal dash sound during dash wall";
- "the flip for the other guy looks buggy and glitchy";
- wanted a plain demo with two Quins: run and slide with a hurdle, run and slide with a sweep, a wall run, and a wall run with a dash off the wall.

## Wall dash sound

**Cause:** the borrowed `ProjectileJump.NinjaJump` clip carries a `ProjectileJump` marker. AnimationModule wires that marker to `AudioModule.playJumpUp`, the projectile launch sound, so every dash off a wall made it.

**Fix:**
- The marker's sound only plays while the Quin's state is ProjectileJump.
- The air dash's effects are now exactly the ground dash's: `playDash` and a 0.4 s vapour cone.
- The shockwave puff is removed (along with `AirDash_PuffSize`).

## The glitchy fall

Recorded on the server, frame by frame:

1. **Pass 56's first sweep:** the fall clip (`Movement.FallFront`) was not loaded yet. For 0.15–0.43 s no Action4 clip was playing, and the body tilted to 47° and turned 80°. The fall pose only arrived on the way down, and the get-up began while the body was still tilted 35°.
2. **Once loaded:** the root stayed upright and the fall pose blended in by 0.21 s. But the sweep's 0.33 s of air was too short. The fall clips (1.5–1.6 s, looped) are poses for flying through the air, not falls to the ground. The get-up (`GetUpFrontFast` / `GetUpBackFast`, 3.2 s) starts lying flat, so the body went from half-fallen to flat in one cut.

No trip or fall-to-ground clip exists in the library.

## Change: the sweep is a drop into the get-up's first frame

**`SlideTackle.sweep`, on the frame the legs go:**
- the victim gets a small hop (`SlideTackle_Launch` 30 → 12);
- the get-up clip for its side plays held on its first, lying frame (speed 0), blended in over `SlideTackle_DropBlend` 0.35 s;
- `GetUpClipOverride` is set.

**`KnockbackState`:**
- No longer starts the fall clip for a swept Quin; it only primes the get-up if the sweep could not.
- Holds the Quin down for `SlideTackle_DownTime` 0.8 s. On the ground the humanoid holds its height again (`PlatformStand` off), so the lying pose stays on the floor.
- Then hands over to Recovery.

**`RecoveryState.getUpClip`:** takes `GetUpClipOverride`, so the same clip carries on from its first frame. There is one continuous motion, with no second get-up.

**Preload:** SlideTackle preloads the two get-up clips at start. The first sweep on each side otherwise stood for about 0.4 s while the asset loaded.

## Measured

Head-on sweeps, server timeline:
- Root upright (0° tilt) throughout. Height 7.4 throughout: it does not sink or float.
- One get-up clip, continuous: it starts at time 0 while the Quin lies down, and Recovery plays it on from there.
- **Before the same-frame start and the preload** (4 sweeps): the lying pose began 0.10 s after the sweep and was full at 0.40 s. The first sweep on each side began at 0.44 s, because its clip was still loading.
- **After those two changes:** not measured. Studio's Play hung before the run.

## Demo switch

Studio only: Workspace `TackleOutcome` = "hurdle" | "sweep" forces the target's reflex.

## Not checked

- **By eye (owner):** the drop and the sound.
- **The final timing:** the same-frame drop start and the preload.
- **The planned scripted demo sequence:** not run yet.
