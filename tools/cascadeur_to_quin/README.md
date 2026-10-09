# Cascadeur → Quin converter (backup copy)

The live copy is at `D:\SKYLARK\ANIMATIONCASCADEUR\`, with the scripts in `_converter\`.

**To use it:**
1. Drop Cascadeur FBX exports into the folder.
2. Double-click `run_cascadeur_to_quin.bat`.
3. Each `<Name>.fbx` gets a `<Name>_Quin[x0.044].fbx` beside it.

**Import into Roblox:**
- Rig Type: Custom.
- Rest Pose Source: **Imported Rig**.
- Scale Unit: Stud, Scale Factor 1.0.

The motion is kept as you animated it. Nothing is made in-place.

## Why a retarget, not a rename

All published clips use Mixamo bone names, so the Quins keep them. The Cascadeur skeleton differs in more than names:
- **Bone axes:** Cascadeur's right-side bones point backwards.
- **Rest pose:** A-pose, against Mixamo's T-pose.
- **Bone counts:** 2 spine bones (Mixamo has 3) and 4 finger joints (Mixamo has 3).

So `cascadeur_to_quin_blender.py` retargets in world space, in headless Blender:
- Each Quin bone takes its Cascadeur twin's rotation away from rest.
- Limbs and fingers are first swung, joint to joint, from the Mixamo rest onto the Cascadeur rest.
- Spine1 is set halfway between Spine and Spine2.
- The hips follow the pelvis, scaled by hip height.

**Verified on SIDESTEP:**
- every limb segment matches the source to 0° on every frame;
- fingers are within 14°;
- no bone stretches.

## Files

- **`quin_rig_template.fbx`** (only in the live folder): a copy of `NEW ANIMATION\Standard Run.fbx`, a Mixamo download of the Quin's rig. Its own clip is discarded.
- **`fbx_resize.py`:** multiplies every bone's position (rest and animated) by 0.044, byte for byte.
  - The old autofixer only scaled the hips' curves. Blender writes a position curve for every bone, so the rest of the skeleton stayed full size, which showed up as the giant rig in Roblox.
  - Blender's own `global_scale` only puts the scale on a root node.
- **Blender export details:**
  - Arrays are written uncompressed, so they can be patched in place.
  - A rest key at frame -1 makes the static bone transforms the rest pose.
  - The clip is keyed from frame 0, which is FBX time 0.
