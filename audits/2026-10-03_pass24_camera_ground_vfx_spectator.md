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

## 24b. Fly Spectator by default, mouse-look, first person (`SmoothCamera`)

### Fly Spectator is the default
- The game opens in `FREEFLY`, not on the Roblox avatar.
- While not walking, the avatar is **parked**: hidden for this player (`LocalTransparencyModifier`, re-applied every frame, because a respawned body loads its parts after `CharacterAdded`) and its default controls disabled, so WASD flies only the camera.
- **B** toggles walking as the avatar. **R** always returns to flying.
- When a spectated Quin dies or a possessed one is released, the camera returns to flying, not to the avatar.
- While a Quin is possessed, PlayerQuinController owns the controls and the costume; the parking code leaves them alone.
- **Two fly cameras, one key:** the Quin Manager (`AnimationLabController`) had its own fly camera bound to B as well, which fought SmoothCamera every frame (the camera stayed scripted after B). B now belongs to SmoothCamera; the panel's Cam button still toggles the panel camera, and its "[B]" labels are gone.

### Mouse-look without holding a button
- In flying and spectating modes the view follows the mouse (`LockCenter`, re-asserted every frame, since Roblox scripts reset `MouseBehavior`).
- **Middle mouse** (or **L**) frees and re-locks the cursor for clicking buttons.
- The cursor is also free while the Quin Manager or Arena System window is open, or a text box has focus.
- Entering any flying or spectating mode starts with mouse-look on.
- Hold-to-look and the old L lock are gone.
- The camera publishes `Camera` attributes `SpectatorMode` and `FirstPerson` for tests and other scripts.

### First person (Play As Quin)
- Scrolling in past the closest orbit zoom (4 studs) puts the camera at the costume's head bone, 0.3 studs forward, eye height smoothed.
- The view turns with the mouse, not with the head animation.
- The costume's parts get `LocalTransparencyModifier = 1` (this player only).
- Scrolling out, releasing or the Quin leaving restores the body and the orbit.
- Your own shadow stays visible, as in most first-person games.

### Streaming follows the camera
StreamingEnabled streams around the character, which the fly camera leaves behind, and after a release there is no character at all.
- The client sends the camera position about twice a second (`ReplicatedStorage.CameraFocus`).
- The new block at the end of `ServerScriptService.Server` moves an invisible anchored part (`workspace.StreamFocus`) there and sets it as `player.ReplicationFocus`, except while wearing a costume (possession sets the focus to the costume).
- My Studio tools cannot add scripts to ServerScriptService, hence the existing script.

### Verified (Play)
- **Start:** `FREEFLY`, `LockCenter`, avatar hidden 18/18. W flies the camera 239 studs and the avatar moves 0.
- **L / menu:** L frees and re-locks; the Quin Manager open frees the cursor, and closing it re-locks.
- **B / R:** B gives the normal camera, avatar visible, W walks 12.8 studs. R flies again, avatar hidden.
- **First person:** P possesses; scrolling in gives first person (camera 0.34 studs from the head, costume 4/4 hidden, screenshot clean). Scrolling out restores 4/4 and the orbit.
- **Release:** P releases back to `FREEFLY` with mouse-look on. The respawned avatar is hidden 18/18 and doesn't move with W.
- **Streaming:** the focus is on `StreamFocus` at the camera.
- **Arena System:** reaches IN_GAME with 0 errors.
