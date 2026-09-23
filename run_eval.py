import subprocess

blender = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
script = r"""
import bpy, os

def eval_anim(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    scene = bpy.context.scene
    hips = arm.pose.bones.get('mixamorig:Hips') or arm.pose.bones.get('Hips')
    lf = arm.pose.bones.get('mixamorig:LeftFoot') or arm.pose.bones.get('LeftFoot')
    rf = arm.pose.bones.get('mixamorig:RightFoot') or arm.pose.bones.get('RightFoot')
    
    print(f"\n=== {os.path.basename(path)} ===")
    for f in [1, 6, 30, 60, 98]:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        hw = arm.matrix_world @ hips.head
        lfw = arm.matrix_world @ lf.head
        rfw = arm.matrix_world @ rf.head
        fc_z = (lfw.z + rfw.z) / 2
        fc_x = (lfw.x + rfw.x) / 2
        print(f"  F{f:2d}: Hips=({hw.x:5.2f}, {hw.y:5.2f}, {hw.z:5.2f}) | FeetCenter=({fc_x:5.2f}, {fc_z:5.2f})")

eval_anim(r'D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace[x0.044].fbx')
eval_anim(r'D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Locked[x0.044].fbx')
eval_anim(r'D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Planted[x0.044].fbx')
"""
py_tmp = r"C:\Users\User\.gemini\antigravity\scratch\eval_variants.py"
with open(py_tmp, "w", encoding="utf-8") as f:
    f.write(script)

res = subprocess.run([blender, "--background", "--python", py_tmp], capture_output=True, text=True, errors="replace")
print(res.stdout[res.stdout.find("=== Landing_Hard_InPlace"):])
