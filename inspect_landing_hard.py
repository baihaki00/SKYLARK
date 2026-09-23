import subprocess
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

blender = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
script = r"""
import bpy
import os

fbx_orig = r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx'
fbx_fixed = r'D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace[x0.044].fbx'
fbx_noloc = r'D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_NoHipsLocation[x0.044].fbx'

def inspect_file(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=filepath)
    
    armature = None
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            armature = obj
            break
            
    print(f"\n=======================================================")
    print(f"=== INSPECTING: {os.path.basename(filepath)} ===")
    print(f"=======================================================")
    if not armature:
        print("No armature found!")
        return
        
    scene = bpy.context.scene
    anim_data = armature.animation_data
    action = anim_data.action if anim_data else None
    frame_start = int(scene.frame_start)
    frame_end = int(scene.frame_end)
    if action:
        frame_start = int(action.frame_range[0])
        frame_end = int(action.frame_range[1])
        
    print(f"Frame range: {frame_start} to {frame_end} ({frame_end - frame_start + 1} frames)")
    
    hips_pb = armature.pose.bones.get('mixamorig:Hips') or armature.pose.bones.get('Hips')
    l_foot_pb = armature.pose.bones.get('mixamorig:LeftFoot') or armature.pose.bones.get('LeftFoot')
    r_foot_pb = armature.pose.bones.get('mixamorig:RightFoot') or armature.pose.bones.get('RightFoot')
    l_toe_pb = armature.pose.bones.get('mixamorig:LeftToeBase') or armature.pose.bones.get('LeftToeBase')
    r_toe_pb = armature.pose.bones.get('mixamorig:RightToeBase') or armature.pose.bones.get('RightToeBase')
    
    hips_pb = armature.pose.bones.get('mixamorig:Hips') or armature.pose.bones.get('Hips')
    l_foot_pb = armature.pose.bones.get('mixamorig:LeftFoot') or armature.pose.bones.get('LeftFoot')
    r_foot_pb = armature.pose.bones.get('mixamorig:RightFoot') or armature.pose.bones.get('RightFoot')
    l_toe_pb = armature.pose.bones.get('mixamorig:LeftToeBase') or armature.pose.bones.get('LeftToeBase')
    r_toe_pb = armature.pose.bones.get('mixamorig:RightToeBase') or armature.pose.bones.get('RightToeBase')
    
    print("\nFrame sampling (World Coordinates):")
    # Sample every frame or key frames
    step = max(1, (frame_end - frame_start) // 20)
    for f in range(frame_start, frame_end + 1, step):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        
        hips_w = armature.matrix_world @ hips_pb.head if hips_pb else None
        lf_w = armature.matrix_world @ l_foot_pb.head if l_foot_pb else None
        rf_w = armature.matrix_world @ r_foot_pb.head if r_foot_pb else None
        lt_w = armature.matrix_world @ l_toe_pb.head if l_toe_pb else None
        rt_w = armature.matrix_world @ r_toe_pb.head if r_toe_pb else None
        
        # Also compute feet center
        feet_center_x = (lf_w.x + rf_w.x) / 2 if (lf_w and rf_w) else 0
        feet_center_y = min(lf_w.y, rf_w.y) if (lf_w and rf_w) else 0
        feet_center_z = (lf_w.z + rf_w.z) / 2 if (lf_w and rf_w) else 0
        
        hips_str = f"({hips_w.x:.3f}, {hips_w.y:.3f}, {hips_w.z:.3f})" if hips_w else "N/A"
        lf_str = f"({lf_w.x:.3f}, {lf_w.y:.3f}, {lf_w.z:.3f})" if lf_w else "N/A"
        rf_str = f"({rf_w.x:.3f}, {rf_w.y:.3f}, {rf_w.z:.3f})" if rf_w else "N/A"
        fc_str = f"({feet_center_x:.3f}, {feet_center_y:.3f}, {feet_center_z:.3f})"
        
        print(f"F{f:3d} | Hips: {hips_str} | FeetCenter: {fc_str} | LF: {lf_str} | RF: {rf_str}")

inspect_file(fbx_orig)
inspect_file(fbx_fixed)
inspect_file(fbx_noloc)
"""

py_tmp = r"C:\Users\User\.gemini\antigravity\scratch\run_blender_inspect.py"
with open(py_tmp, "w", encoding="utf-8") as f:
    f.write(script)

cmd = [blender, "--background", "--python", py_tmp]
res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
print(res.stdout.decode('utf-8', errors='replace'))
if res.stderr:
    print("STDERR:", res.stderr.decode('utf-8', errors='replace')[:500])
