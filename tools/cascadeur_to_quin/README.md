# Cascadeur → Quin converter (backup copy)

The live copy is at `D:\SKYLARK\ANIMATIONCASCADEUR\`, with the scripts in `_converter\`. To use it:

1. Drop Cascadeur FBX exports into the folder.
2. Double-click `run_cascadeur_to_quin.bat`.

Each `<Name>.fbx` gets a `<Name>_Quin\` folder containing:

| File | What it is |
|---|---|
| `<Name>_Mixamo.fbx` | The clip retargeted onto the Quin's Mixamo skeleton |
| `<Name>_InPlace[x0.044].fbx` | No horizontal travel; height kept |
| `<Name>_NoHipsLocation[x0.044].fbx` | Hips pinned |

Import the InPlace or NoHipsLocation file into Roblox, as with the Mixamo files.

## Why a retarget, not a rename

All published clips use Mixamo bone names, so the Quins keep them. The Cascadeur skeleton differs from the Mixamo one in four ways:
- bone names;
- bone axes (Cascadeur's right side points backwards);
- rest pose (A-pose vs T-pose);
- the spine (2 bones vs 3) and the fingers (4 joints vs 3).

So `cascadeur_to_quin_blender.py` (headless Blender) retargets in world space:
- Each Quin bone takes its Cascadeur twin's rotation away from rest.
- The limbs and fingers are first swung joint to joint from the Mixamo rest onto the Cascadeur rest.
- Spine1 takes half way between Spine and Spine2.
- The hips follow the pelvis, scaled by hip height.

Verified on SIDESTEP: every limb segment matches the source to 0° on every frame, and the fingers are within 14°.

## Files

- **`quin_rig_template.fbx`** (only in the live folder) is `NEW ANIMATION\Standard Run.fbx`, a Mixamo download of the Quin's rig. Its clip is discarded.
- **`autofixer.py`** is a copy of `NEW ANIMATION\autofixer.py` with one fix: FBX object ids are always 8 bytes. The original read 4 bytes in pre-7500 files, and Blender writes 7400.
- **The Blender export details:**
  - Arrays are written uncompressed, so the autofixer can patch them.
  - A rest key at frame -1 makes the static bone transforms the rest pose, as in a Mixamo file.
  - The clip is keyed from frame 0, which is FBX time 0.
