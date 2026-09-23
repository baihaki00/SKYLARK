
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

hips = arm.pose.bones['mixamorig:Hips']
lf = arm.pose.bones['mixamorig:LeftFoot']
rf = arm.pose.bones['mixamorig:RightFoot']
lt = arm.pose.bones['mixamorig:LeftToeBase']
rt = arm.pose.bones['mixamorig:RightToeBase']

print('Frame, Hips_X, Hips_Y, Hips_Z, FeetCenter_X, FeetCenter_Y, FeetCenter_Z')
for f in range(1, 99):
    scene.frame_set(f)
    bpy.context.view_layer.update()
    
    # In Blender: X is lateral, Y is forward/back, Z is up/down
    hw = arm.matrix_world @ hips.head
    lw = arm.matrix_world @ lf.head
    rw = arm.matrix_world @ rf.head
    
    fc_x = (lw.x + rw.x) / 2.0
    fc_y = (lw.y + rw.y) / 2.0
    fc_z = (lw.z + rw.z) / 2.0
    
    if f % 10 == 1 or f == 98 or f == 6:
        print(f'{f:2d}, {hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}, {fc_x:6.2f}, {fc_y:6.2f}, {fc_z:6.2f}')
