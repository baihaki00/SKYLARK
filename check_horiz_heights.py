import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down_Pure_InPlace_Horizontal.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_ltoe = arm.pose.bones['mixamorig:LeftToeBase']
pbone_rhand = arm.pose.bones['mixamorig:RightHand']
pbone_hips = arm.pose.bones['mixamorig:Hips']

print("Frame | Hips Z | Lowest Toe Z | RHand Z | Forward Y")
for f in [1, 20, 35, 45, 51, 60, 75]:
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation
    lt = (arm.matrix_world @ pbone_ltoe.matrix).translation
    rh = (arm.matrix_world @ pbone_rhand.matrix).translation
    print(f"Frame {f:2d} | Hips=({hw.x:.2f}, {hw.y:.2f}, {hw.z:.2f}) | ToeZ={lt.z:.3f}m | HandZ={rh.z:.3f}m")
