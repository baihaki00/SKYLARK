# Quin body pipeline: Blender → Roblox game template

How the owner's own Quin bodies get into the game. The live Blender files and scripts are in `D:\SKYLARK\QUINBASEMESH\` (scripts in `scripts\`). This folder is the backup copy.

- **Male:** live as `QuinMale_v4` (v3 on 2026-10-21; v4, the neck fix, on 2026-10-22).
- **Female:** `QuinFemale_v1` (2026-10-22) is the male v4 rig reshaped by the owner. It uses the same ybot skeleton, so every animation plays on it.

## Versions
- **Exports are numbered per gender:** `QUIN_DESIGN\export\Male\QuinMale_vN.fbx` and `QUIN_DESIGN\export\Female\QuinFemale_vN.fbx`. Each folder has a `versions.txt` saying which .blend each version came from.
- **Exporting:** drag the rigged .blend onto `export_quin.bat`, which calls `export_versioned.py`. A name containing "Female" exports as female; anything else as male. N is one past the highest existing version.
- **Importing:** import keeping the version name (Workspace `QuinFemale_v1`, …).
- **Going live:** `build_quin_template.lua` with `IMPORT` = that name and `TEMPLATE` = `QuinFemale` / `QuinMale`. The template's `BodyVersion` attribute records which version is live.
- **Rollback:** every previous template is in `ServerStorage.QuinBodyBackups`.

## The path

| Step | Who | What |
|---|---|---|
| 1. Model | owner | Model in Blender: wood plates (material **WARM IVORY LACQUER**) and bronze (material **BRONZE**), T-pose. |
| 2. Fit the skeleton | owner | Import `Male\ybot.fbx`, keep the Armature, slide the joints into the model. For mirror editing, `bones_to_LR.py`, then `bones_back_to_mixamo.py` before skinning. **Never** rename, rotate or delete bones. |
| 3. Rig | Claude (`build_rig.py`, or `join_body.py` for one mesh) | The body gets Automatic Weights; the plates copy weights from the body; each plate keeps only its own bones; tip bones emptied; limit 4 bones per vertex. |
| 4. Check | Claude (`find_stretch.py`, `find_spike.py`, `view34.py`, `closeups_pose.py`) | Play Standard Run on the rig, rank the pieces that stretch, find bad weights, render. |
| 5. Fix | Claude (`fix_weights.py`, `fix_shoulders_fingers.py` + `thumb_tips.py`) | Stray weights; collarbones back to the ybot's rest angle; tip bones weighted, so Roblox keeps all 52. |
| 6. Export | owner, one click | Drag the rigged .blend onto **`export_quin.bat`**. It writes the next version, `QUIN_DESIGN\export\<Gender>\Quin<Gender>_vN.fbx`: rest pose; every mesh split and joined by material; regions split if any mesh passes 20k triangles. |
| 7. Import | owner | Studio → 3D Importer → the FBX. Settings: Rig Type **Custom**, Rest Pose **Imported Rig**. It comes in at about 8 studs. Wait until it has a `RootPart` holding the bones. |
| 8. Template | Claude (`scripts/build_quin_template.lua`, Studio Edit) | Run with `IMPORT` (the Workspace model) and `TEMPLATE` (`QuinMale` / `QuinFemale`). It backs up the old template to `ServerStorage.QuinBodyBackups`, keeps the rig shell (HRP, Humanoid, Sounds, RootJoint), drops the import's Hips exactly on the old Hips, moves the skeleton into the shell (renamed `Alpha_Surface`), welds the other zones, and applies the zone colours and `KeepBodyColors`. |
| 9. Verify | Claude | Bone and clip comparison against the backup, a live spawn, and the 16v16 flow probe. |

## Zones and colours
- Each material becomes its own MeshPart (Roblox: one colour and material per part): `Alpha_Surface` (Shell) and `Quin_Joints` (Joints).
- Colours are template attributes: `ShellColor` / `ShellMaterial`, `JointsColor` / `JointsMaterial`.
- Defaults: ivory lacquer `E8D3B5` SmoothPlastic, bronze `8A5A2E` Metal.
- `KeepBodyColors` stops FXService's team body paint. Team identity is to come from wristbands.

## Rules learned
- **Roblox limits:**
  - 20k triangles per mesh;
  - 4 bones per vertex;
  - Roblox drops bones that hold no weight (give tip bones some, or animations lose them).
- **Blender traps:**
  - decimating thin Solidify plates tears them;
  - Automatic Weights on double-walled plates splits the walls (copy weights from the body instead);
  - renaming bones from a script only works in Edit Mode;
  - `vertex_group_smooth` needs Weight Paint mode.
- **The skeleton:** moving joints along a limb is safe. A fitted collarbone start turned its rest angle by 32°, and kicks then differed by up to 16°, so restore it (step 5).
- **Templates must be scale-1 models with LevelOfDetail Disabled.** The build keeps the old template's settings.
- **"Shell missing in game":** a freshly uploaded mesh can show in Edit (Studio's local cache) but fail to load in Play (`ContentProvider:GetAssetFetchStatus` = Failure on the client) while it is being processed or moderated. Check Creator Hub → Development Items → Meshes. To test, clone the MeshPart into Workspace on a Play client and read the fetch status (PreloadAsync on raw mesh ids always says Failure).

## Rollback
The previous body is in `ServerStorage.QuinBodyBackups.<TEMPLATE>_<date>`. Move it back into `ReplicatedStorage.QuinType` under the template's name.

## Measured on going live (2026-10-21, QuinMale_v3)
- Bones: 52, all matching. The hips land exactly on the old body's; the soles are 5.238 studs below the root, unchanged.
- Clips against the old rig: the run is within 1.1°; the punch 6°; the high kick 12°; the wheel drive 10°.
- 16v16 flow probe (150 s): 16.7 strikes per Quin-minute, 69 % hit, 6.2 % whiff, no deaths. Pass 79 baseline: 16.1 / 67 % / 6.6 %.
