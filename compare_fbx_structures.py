import bpy
import os

f_orig = r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx'
f_gen = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_InPlace_Full.fbx'

def inspect_file(filepath):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=filepath)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    
    info = {}
    info['arm_rot'] = list(arm.rotation_euler)
    info['arm_scale'] = list(arm.scale)
    
    # Check rest pose / edit bone orientations
    bones_info = {}
    for b in arm.data.bones:
        bones_info[b.name] = {
            'head': list(b.head),
            'tail': list(b.tail),
            'matrix_local': [list(row) for row in b.matrix_local]
        }
    info['bones'] = bones_info
    
    # Check pose bone rotation at frame 1
    bpy.context.scene.frame_set(1)
    pose_rot = {}
    for pb in arm.pose.bones:
        pose_rot[pb.name] = list(pb.rotation_quaternion)
    info['pose_rot_f1'] = pose_rot
    return info

info_orig = inspect_file(f_orig)
info_gen = inspect_file(f_gen)

print("=== Armature Object Transforms ===")
print("Original Armature Rot:", info_orig['arm_rot'], "Scale:", info_orig['arm_scale'])
print("Generated Armature Rot:", info_gen['arm_rot'], "Scale:", info_gen['arm_scale'])

print("\n=== Bone Rest Orientations Comparison ===")
diff_heads = []
diff_mats = []
for bname in info_orig['bones']:
    h1 = info_orig['bones'][bname]['head']
    h2 = info_gen['bones'][bname]['head']
    d_head = sum((a - b)**2 for a, b in zip(h1, h2))**0.5
    if d_head > 1e-3:
        diff_heads.append((bname, d_head, h1, h2))
        
    m1 = info_orig['bones'][bname]['matrix_local']
    m2 = info_gen['bones'][bname]['matrix_local']
    d_mat = sum(sum((a - b)**2 for a, b in zip(r1, r2)) for r1, r2 in zip(m1, m2))**0.5
    if d_mat > 1e-3:
        diff_mats.append((bname, d_mat))

print(f"Bones with different head positions: {len(diff_heads)}")
for b, d, h1, h2 in diff_heads[:5]:
    print(f"  {b}: dist={d:.4f}, orig={h1}, gen={h2}")
    
print(f"Bones with different matrix_local: {len(diff_mats)}")
for b, d in diff_mats[:5]:
    print(f"  {b}: mat_diff={d:.4f}")
    
print("\n=== Pose Bone Rotations at Frame 1 ===")
diff_pose = []
for bname in info_orig['pose_rot_f1']:
    q1 = info_orig['pose_rot_f1'][bname]
    q2 = info_gen['pose_rot_f1'][bname]
    d_q = sum((a - b)**2 for a, b in zip(q1, q2))**0.5
    if d_q > 1e-3:
        diff_pose.append((bname, d_q, q1, q2))
print(f"Pose bones with different frame 1 rotation: {len(diff_pose)}")
for b, d, q1, q2 in diff_pose[:10]:
    print(f"  {b}: diff={d:.4f}, q1={q1}, q2={q2}")
