import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_hips = arm.pose.bones['mixamorig:Hips']
pbone_head = arm.pose.bones['mixamorig:Head']
pbone_foot = arm.pose.bones['mixamorig:LeftFoot']

for f in [1, 25, 45, 52, 60, 70, 76]:
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation.z
    headw = (arm.matrix_world @ pbone_head.matrix).translation.z
    footw = (arm.matrix_world @ pbone_foot.matrix).translation.z
    print(f"Frame {f:2d}: Hips={hw:.3f}m, Head={headw:.3f}m, Foot={footw:.3f}m (Height={headw - footw:.3f}m)")
