import bpy
import os

files = {
    'Original': r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx',
    'Pure_Full': r'D:\SKYLARK\SKYLARKTEST\Jumping Down_Pure_InPlace_Full.fbx',
    'Pure_Horiz': r'D:\SKYLARK\SKYLARKTEST\Jumping Down_Pure_InPlace_Horizontal.fbx'
}

data_store = {}

for label, fpath in files.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fpath)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    scene = bpy.context.scene
    
    # Sample rotations of key bones across frames
    key_bones = ['mixamorig:Spine', 'mixamorig:LeftArm', 'mixamorig:RightUpLeg', 'mixamorig:LeftFoot', 'mixamorig:Head']
    frames = [1, 15, 30, 45, 60, 75]
    
    rot_samples = {}
    hips_pos_samples = {}
    for f in frames:
        scene.frame_set(f)
        rot_samples[f] = {b: list(arm.pose.bones[b].rotation_quaternion) for b in key_bones}
        w_hips = (arm.matrix_world @ arm.pose.bones['mixamorig:Hips'].matrix).translation
        hips_pos_samples[f] = list(w_hips)
        
    data_store[label] = {
        'rots': rot_samples,
        'hips_pos': hips_pos_samples
    }

print("\n=== VERIFICATION: Bone Rotation Fidelity against Original ===")
for target in ['Pure_Full', 'Pure_Horiz']:
    max_rot_diff = 0.0
    for f in [1, 15, 30, 45, 60, 75]:
        for b in ['mixamorig:Spine', 'mixamorig:LeftArm', 'mixamorig:RightUpLeg', 'mixamorig:LeftFoot', 'mixamorig:Head']:
            q_orig = data_store['Original']['rots'][f][b]
            q_targ = data_store[target]['rots'][f][b]
            diff = sum((a - b)**2 for a, b in zip(q_orig, q_targ))**0.5
            if diff > max_rot_diff:
                max_rot_diff = diff
    print(f"[{target}] Maximum bone rotation difference across all keyframes: {max_rot_diff:.10f}")

print("\n=== Hips World Position Comparison ===")
for f in [1, 15, 30, 45, 60, 75]:
    p_orig = data_store['Original']['hips_pos'][f]
    p_full = data_store['Pure_Full']['hips_pos'][f]
    p_horiz = data_store['Pure_Horiz']['hips_pos'][f]
    print(f"Frame {f:2d}:")
    print(f"  Orig:  X={p_orig[0]:6.2f}, Y={p_orig[1]:6.2f}, Z={p_orig[2]:6.2f}")
    print(f"  Full:  X={p_full[0]:6.2f}, Y={p_full[1]:6.2f}, Z={p_full[2]:6.2f}")
    print(f"  Horiz: X={p_horiz[0]:6.2f}, Y={p_horiz[1]:6.2f}, Z={p_horiz[2]:6.2f}")
