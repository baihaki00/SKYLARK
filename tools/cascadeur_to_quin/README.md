# Cascadeur → Quin converter (backup copy)

The live copy is at `D:\SKYLARK\ANIMATIONCASCADEUR\`, with the scripts in `_converter\`.

**To use it:**
1. Drop Cascadeur FBX exports into the folder.
2. Double-click `run_cascadeur_to_quin.bat`.
3. Each `<Name>.fbx` gets a `<Name>_CascadeurQuin` folder with two files:
   - `<Name>_Quin[x0.044].fbx`: the motion as animated, travel included;
   - `<Name>_Quin_InPlace[x0.044].fbx`: the hips stay on their spot (height and every rotation kept).

**Import into Roblox:**
- Rig Type: Custom.
- Rest Pose Source: **Imported Rig**. The rest is the file's own skeleton, rest angles included, which is the same as the Quin rig in Studio.
  - **Zeroed Rotations** comes out crippled: it zeroes those rest angles too, and the Quin's bones don't rest unrotated (its leg bones rest turned 180°, for one).
  - **Animation Editor Rig** measures against the Studio rig.
- Scale Unit: Stud, Scale Factor 1.0.

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
- **`quin_fbx.py` + `fbx_tree.py`:** write the clip into the template FBX itself (a minimal binary FBX reader/writer; an untouched template writes back with an identical node tree). The result is laid out exactly like a Mixamo download:
  - each bone's rest angle stays in its PreRotation;
  - the rotation curves carry only the motion;
  - the hips carry the only position curve;
  - every distance is x0.044.
- **Why not a Blender FBX export (tried first):**
  - Blender mixes rest and motion into one rotation. "Imported Rig" and "Zeroed Rotations" then read a crippled rest, and "Animation Editor Rig" floats the hips (it measured them from the ground, not from the body).
  - Blender writes a position curve for every bone, and only the hips' was scaled, which gave the giant rig.
- The Blender step now only outputs each bone's local transform per frame (JSON). Its clip is keyed from frame 0 (FBX time 0).
