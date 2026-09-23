import bpy
import os
import math

files = ['Jump.fbx', 'Jumping Down.fbx']

for fname in files:
    fpath = os.path.join(r'D:\SKYLARK\SKYLARKTEST', fname)
    print('\n' + '='*75)
    print(f'RIG & ROTATION DEEP-DIVE: {fname}')
    print('='*75)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fpath)
    
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    strip = act.layers[0].strips[0]
    cb = strip.channelbags[0]
    
    # Check bone scale
    scale_anomalies = []
    for b in arm.pose.bones:
        if any(abs(s - 1.0) > 0.01 for s in b.scale):
            scale_anomalies.append((b.name, list(b.scale)))
    print(f'Bone Scale Anomalies (non-1.0): {len(scale_anomalies)}')
    if scale_anomalies:
        for bname, sc in scale_anomalies[:5]:
            print(f'  {bname}: {sc}')
            
    # Check rotation discontinuities (quaternion flip check between consecutive keyframes)
    rot_flips = []
    fcurves_dict = {}
    for fc in cb.fcurves:
        fcurves_dict.setdefault(fc.data_path, {})[fc.array_index] = fc
        
    for dp, idx_map in fcurves_dict.items():
        if 'rotation_quaternion' in dp and len(idx_map) == 4:
            # Check for sudden sign flips where q ~ -q or large jumps
            kps_w = idx_map[0].keyframe_points
            kps_x = idx_map[1].keyframe_points
            kps_y = idx_map[2].keyframe_points
            kps_z = idx_map[3].keyframe_points
            num_keys = len(kps_w)
            for i in range(num_keys - 1):
                qw1, qx1, qy1, qz1 = kps_w[i].co[1], kps_x[i].co[1], kps_y[i].co[1], kps_z[i].co[1]
                qw2, qx2, qy2, qz2 = kps_w[i+1].co[1], kps_x[i+1].co[1], kps_y[i+1].co[1], kps_z[i+1].co[1]
                dot = qw1*qw2 + qx1*qx2 + qy1*qy2 + qz1*qz2
                if dot < 0: # Antipodal flip
                    bone = dp.split('"')[1] if '"' in dp else dp
                    rot_flips.append((bone, kps_w[i].co[0], dot))
                    
    print(f'Quaternion Antipodal Flips (sign inversion causing potential interpolation twitch): {len(rot_flips)}')
    if rot_flips:
        for bname, f, dot in rot_flips[:10]:
            print(f'  {bname} at frame {f:.0f}: dot={dot:.4f}')
