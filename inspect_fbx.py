import bpy
import os
import math

files = ['Jump.fbx', 'Jumping Down.fbx']

for fname in files:
    fpath = os.path.join(r'D:\SKYLARK\SKYLARKTEST', fname)
    print('\n' + '='*75)
    print(f'ANALYSIS OF: {fname}')
    print('='*75)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fpath)
    
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    
    # Get all fcurves in channelbag
    strip = act.layers[0].strips[0]
    channelbag = strip.channelbags[0]
    
    # Organize fcurves
    fcurves_dict = {}
    for fc in channelbag.fcurves:
        fcurves_dict.setdefault(fc.data_path, {})[fc.array_index] = fc
        
    print(f'Armature: {arm.name}, Bone Count: {len(arm.data.bones)}')
    print(f'Action: {act.name}')
    
    # Determine actual frame range from keyframes
    all_frames = []
    for fc in channelbag.fcurves:
        for kp in fc.keyframe_points:
            all_frames.append(kp.co[0])
            
    min_frame = min(all_frames) if all_frames else 0
    max_frame = max(all_frames) if all_frames else 0
    print(f'Keyframe Range: Frame {min_frame:.0f} to {max_frame:.0f} (Total: {max_frame - min_frame + 1:.0f} frames)')
    
    # Check which bones have NON-CONSTANT location curves
    non_constant_loc_bones = []
    constant_loc_bones = []
    
    for dp, idx_map in fcurves_dict.items():
        if 'location' in dp:
            is_moving = False
            for idx, fc in idx_map.items():
                vals = [kp.co[1] for kp in fc.keyframe_points]
                if len(vals) > 1 and (max(vals) - min(vals)) > 1e-4:
                    is_moving = True
                    break
            bone_name = dp.split('"')[1] if '"' in dp else dp
            if is_moving:
                non_constant_loc_bones.append(bone_name)
            else:
                constant_loc_bones.append(bone_name)
                
    print(f'\nBones with MOVING translation: {non_constant_loc_bones}')
    print(f'Bones with STATIC (constant) translation: {len(constant_loc_bones)} bones')
    
    # Detailed analysis of Hips bone translation
    hips_path = 'pose.bones["mixamorig:Hips"].location'
    if hips_path in fcurves_dict:
        print('\n--- Hips Bone Translation Analysis (Bone Local Space) ---')
        for idx, axis in [(0, 'X (Lateral / Side)'), (1, 'Y (Vertical / Up)'), (2, 'Z (Forward / Depth)')]:
            fc = fcurves_dict[hips_path].get(idx)
            if fc:
                kps = [(kp.co[0], kp.co[1]) for kp in fc.keyframe_points]
                frames = [k[0] for k in kps]
                vals = [k[1] for k in kps]
                start_val = vals[0]
                end_val = vals[-1]
                net_disp = end_val - start_val
                min_v = min(vals)
                max_v = max(vals)
                span = max_v - min_v
                
                # Check for snaps (step delta > threshold)
                step_deltas = [abs(vals[i+1] - vals[i]) for i in range(len(vals)-1)]
                max_step = max(step_deltas) if step_deltas else 0
                max_step_frame = frames[step_deltas.index(max_step)] if step_deltas else 0
                
                print(f'  Axis {idx} [{axis}]:')
                print(f'    Start Val (f{frames[0]:.0f}): {start_val:10.4f} | End Val (f{frames[-1]:.0f}): {end_val:10.4f}')
                print(f'    Net Displacement (End - Start): {net_disp:10.4f}')
                print(f'    Min Val: {min_v:10.4f} | Max Val: {max_v:10.4f} | Total Span: {span:10.4f}')
                print(f'    Max Delta between adjacent frames: {max_step:10.4f} at frame {max_step_frame:.0f}')

    # Sample evaluated world transforms across frames
    print('\n--- Evaluated World-Space Hips Position across Animation ---')
    scene = bpy.context.scene
    hips_pbone = arm.pose.bones['mixamorig:Hips']
    sample_frames = list(range(int(min_frame), int(max_frame) + 1, max(1, int((max_frame - min_frame) / 8))))
    if int(max_frame) not in sample_frames:
        sample_frames.append(int(max_frame))
        
    for f in sample_frames:
        scene.frame_set(f)
        # World translation of the Hips bone head
        w_mat = arm.matrix_world @ hips_pbone.matrix
        w_trans = w_mat.translation
        print(f'  Frame {f:3d}: World Pos (X={w_trans.x:8.3f}, Y={w_trans.y:8.3f}, Z={w_trans.z:8.3f})')
        
    # Check start vs end world displacement
    scene.frame_set(int(min_frame))
    w_start = (arm.matrix_world @ hips_pbone.matrix).translation.copy()
    scene.frame_set(int(max_frame))
    w_end = (arm.matrix_world @ hips_pbone.matrix).translation.copy()
    w_delta = w_end - w_start
    print(f'Net World Displacement from start to end: (X={w_delta.x:.4f}, Y={w_delta.y:.4f}, Z={w_delta.z:.4f}) | Distance: {w_delta.length:.4f}')

    # Check loop discontinuity (Frame End -> Frame Start jump)
    loop_jump = w_start - w_end
    print(f'Loop Discontinuity (Frame End -> Frame Start wrap): (X={loop_jump.x:.4f}, Y={loop_jump.y:.4f}, Z={loop_jump.z:.4f}) | Distance: {loop_jump.length:.4f}')
