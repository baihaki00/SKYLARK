import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_ltoe = arm.pose.bones['mixamorig:LeftToeBase']
pbone_rtoe = arm.pose.bones['mixamorig:RightToeBase']
pbone_lfoot = arm.pose.bones['mixamorig:LeftFoot']
pbone_rfoot = arm.pose.bones['mixamorig:RightFoot']
pbone_rhand = arm.pose.bones['mixamorig:RightHand']
pbone_hips = arm.pose.bones['mixamorig:Hips']

print("Frame | Hips Z | Lowest Point Z (Floor Contact)")
for f in range(45, 77, 3):
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation.z
    lt = (arm.matrix_world @ pbone_ltoe.matrix).translation.z
    rt = (arm.matrix_world @ pbone_rtoe.matrix).translation.z
    lf = (arm.matrix_world @ pbone_lfoot.matrix).translation.z
    rf = (arm.matrix_world @ pbone_rfoot.matrix).translation.z
    rh = (arm.matrix_world @ pbone_rhand.matrix).translation.z
    lowest = min(lt, rt, lf, rf, rh)
    print(f"Frame {f:2d} | Hips={hw:.4f}m | Lowest={lowest:.4f}m | LToe={lt:.4f}m | RToe={rt:.4f}m | RHand={rh:.4f}m")
