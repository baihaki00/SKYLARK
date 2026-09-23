
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

print('--- DETAILED FOOT & ROOT POSITIONS ---')
for f in range(1, 99):
    scene.frame_set(f)
    bpy.context.view_layer.update()
    
    hw = arm.matrix_world @ hips.head
    lw = arm.matrix_world @ lf.head
    rw = arm.matrix_world @ rf.head
    ltw = arm.matrix_world @ lt.head
    rtw = arm.matrix_world @ rt.head
    
    # Feet contact point: lowest Y/Z
    # In Blender: X is lateral, Y is forward/back, Z is up/down
    # Center of base of support (average of both feet/toes)
    center_x = (lw.x + rw.x + ltw.x + rtw.x) / 4.0
    center_y = (lw.y + rw.y + ltw.y + rtw.y) / 4.0
    
    if f in [1, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 98]:
        print(f'F{f:2d} | Hips: ({hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}) | FeetMid: ({center_x:6.2f}, {center_y:6.2f}) | LF: ({lw.x:6.2f}, {lw.y:6.2f}, {lw.z:6.2f}) | RF: ({rw.x:6.2f}, {rw.y:6.2f}, {rw.z:6.2f})')
