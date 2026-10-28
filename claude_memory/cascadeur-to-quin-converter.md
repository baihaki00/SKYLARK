---
name: cascadeur-to-quin-converter
description: Cascadeur clips reach the Quins through a one-click retarget (D:\SKYLARK\ANIMATIONCASCADEUR\run_cascadeur_to_quin.bat); the Quins keep Mixamo bone names — never rename rig bones
metadata:
  node_type: memory
  type: project
  originSessionId: eb5b13b5-9a2c-4d0f-9f26-36cb6c216d99
  modified: 2026-10-09T05:54:41.108Z
---

On 2026-10-09 the owner asked to rename every Quin's bones to Cascadeur names (pelvis, thigh_l, …), as in `SIDESTEP.fbx`. I advised against it, and the owner chose a converter instead.

**Why the rename was a bad idea:** every published clip finds its bones by Mixamo name, so a rename would freeze all of them. The skeletons also differ in more than names:
- bone axes (Cascadeur's right side points backwards);
- rest pose (A-pose vs T-pose);
- the spine (2 bones vs 3) and the fingers (4 joints vs 3).

**The converter:** `D:\SKYLARK\ANIMATIONCASCADEUR\` (backup in `QUINCORE_BACKUP/tools/cascadeur_to_quin/`, commits 38024f1 … 8ef528d and the InPlace commit).
- To use it, drop the FBX files in the folder and run the .bat.
- Output, in `<Name>_CascadeurQuin\`: `<Name>_Quin[x0.044].fbx` (motion as authored), `<Name>_Quin_InPlace[x0.044].fbx` (no hips travel across the ground; height and rotations kept), and the same two mirrored left<->right (`_Quin_Mirror`, `_Quin_Mirror_InPlace`: twin bone turns reflected across world X, hips travel x flipped; verified exact). Owner asked for these 2026-10-09.
- How it works: headless Blender does a world-space retarget onto `_converter\quin_rig_template.fbx` (a copy of `NEW ANIMATION\Standard Run.fbx`) and outputs each bone's local transform per frame. Then `quin_fbx.py` + `fbx_tree.py` write that into the template FBX itself, in the exact Mixamo layout (rest in PreRotation, motion in the rotation curves, a position curve on the hips only, x0.044).
- Roblox import: Rig Type Custom, Rest Pose Source **Imported Rig** (CONFIRMED working by the owner, 8ef528d), Scale Unit Stud, Scale Factor 1. Zeroed Rotations comes out crippled: it zeroes the rest angles, and the Quin's bones rest rotated (LeftUpLeg 180° about Z in Studio).
- What the three Rest Pose modes mean, as observed:
  - **Zeroed Rotations:** every rest rotation zeroed; it suits rigs whose bones rest unrotated, which the Quin's don't.
  - **Imported Rig:** reads the file's static pose.
  - **Animation Editor Rig:** measures against the Studio rig's bones (the hips' parent is the Alpha_Surface mesh centre, hips rest at y 0.42), so a file whose hips sit 4.39 above the ground floats.
- TRAPS with a Blender FBX export:
  - it mixes rest and motion into one rotation (crippled in both Imported modes, floating in Editor Rig);
  - it writes a position curve on every bone (the giant rig when only the hips' was scaled).
- Traps that are already handled:
  - Blender compresses FBX arrays; the export writes them plain so they can be patched;
  - Blender writes the static bone transforms from the current frame, fixed with a rest key at frame -1;
  - the clip must start at FBX time 0.
- Verified: limbs match the source to 0°, fingers within 14°.
- TRAP: 01de00d "wouldn't load" in Roblox. Its likely cause was a Blender-style footer on a 7700 file. The FBX SDK footer uses the file's own id plus `4 + (16 - pos % 16)` zero bytes. `fbx_tree` now round-trips Mixamo files byte for byte.
- Leftover template curves (153 unconnected, plus 1 orphan R node) are stretched to the clip's length.
- 8ef528d loads in Roblox (the footer fix worked).

**Why:** the owner animates in Cascadeur (and in place; the game drives the motion).
**How to apply:**
- Never rename the rig bones.
- Clips made on the old Mixamo model inside Cascadeur keep `mixamorig:` names; since 2026-10-26 the script falls back to `mixamorig:<Quin bone>` when the Cascadeur name is missing (Spine1 then maps directly, no blend). First used for QuickBodyEvade_Backward/Left/Right.
- For new Cascadeur rigs or bones, extend MAP / SWING in `cascadeur_to_quin_blender.py`, and edit both copies (the live folder and the repo backup).

Related: [[combat-animation-guide]], [[quin-animation-authoring-plan]]
