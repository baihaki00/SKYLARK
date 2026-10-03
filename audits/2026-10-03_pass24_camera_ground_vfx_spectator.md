# Pass 24: camera feel, ground VFX, spectator defaults, first person

The owner's list after pass 23c.
1. Motion blur.
2. Landing impact VFX (no parts).
3. Footprints that look like real feet.
4. Camera shake.
5. First person when zoomed in during Play As Quin.
6. Fly Spectator as the default.
7. Mouse-look without holding a button.
8. Animation hit events. The owner is authoring these, using the naming convention in [COMBAT_ANIMATION_GUIDE.md](../COMBAT_ANIMATION_GUIDE.md).

## 24a. Motion blur, camera shake, footprints, landing impact

### Motion blur: off
Roblox only has a full-screen Gaussian `BlurEffect`, so the "motion blur" blurred the whole frame evenly on every turn, which read as haze. `MotionBlur_Enabled = false`; the Workspace attribute `MotionBlur = true` still tries it.

### Camera shake: rebuilt (`ClientVfxHandler`)
**Before**
- random angle spikes every frame, decayed ×0.2 per frame: jitter, and its length depended on the frame rate (the owner runs ~235 fps);
- the server's shakes have radii of 200-600 studs, so in a 16v16 landings anywhere kept the view rumbling.

**Now**
- each shake adds trauma: intensity × multiplier × **squared** distance falloff × `CameraShake_TraumaPerDegree` (0.22);
- the view turns by trauma² along smooth Perlin noise (`CameraShake_Frequency` 18), capped at `CameraShake_MaxPitch` / `MaxYaw` 2°, `MaxRoll` 1.2°;
- trauma decays at 1.6 per second, so it is frame-rate independent;
- the master `CameraShake_Multiplier` and the `CameraShakeMultiplier` attribute are kept.

**Measured** (FFA 8, pinned camera, real impacts 78-147 studs away): at most 0.2°. A slam beside the viewer is ~0.5°, a clash ~1°.

### Ground decals (`VfxModule`)
Footprints, slide streaks and landing cracks are now **drawn on the floor**: a SurfaceGui on an invisible, non-colliding flat carrier (`workspace.GroundDecals`), fading through a CanvasGroup. They are no longer grey Part rectangles. The 60-mark cap is kept.

Traps found:
- a SurfaceGui on a Top face runs its width along the part's **Z** and its height along **X**. The carrier's X axis lies along the mark.
- the drawing's top edge points to −X, so the carrier faces `-forward`.

**Footprints**
- A boot sole drawn toe-up: forefoot, outer arch, heel, tread grooves; the big-toe side is mirrored per foot.
- Placed under the foot that stepped: the `Footstep` marker's new parameter `Left` / `Right`, else the lower ankle. Centred 0.42 studs from the ankle toward the toe, along ankle→ball-of-foot, on the floor found by a ray. Size 1.2 × 0.48 (the rig's ankle-to-ball distance is 0.69).
- Replaceable: `Vfx_FootprintImage` (right foot, toe up) and the optional `Vfx_FootprintImageLeft`.
- Verified by screenshot: toe toward the direction of travel; left and right prints nearly in line, as in real running.

**Landing impact** (`createLandingImpact(source, strength, element)`)
- Ground dust (the existing particles).
- A crack and scorch decal for strength ≥ 0.45: jagged 3-segment cracks with branches, sized 3 + 5 × strength studs. Replaceable via `Vfx_LandingCrackImage`.
- Earth clods as particles thrown up and falling back.
- Replaces `createDust` (loose Part chunks) and `createShockwave` (a neon cylinder Part) at:
  - the ProjectileJump Impact (strength from arrival speed; precise hops 0.3, dust only);
  - the Knockback ground slam.
- Switch: `Vfx_LandingImpact`.

**Slide streaks** (`createGroundMark`): a rounded streak with soft, faded ends.

**Verified**
- FFA 8: cracks render (screenshot), 0 loose small parts in the workspace.
- 16v16 for 50 s: 0 errors, 32 alive, 35 marks on the floor (under the cap).
