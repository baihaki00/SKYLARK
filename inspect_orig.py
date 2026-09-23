
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene
hips = arm.pose.bones['mixamorig:Hips']
lf = arm.pose.bones['mixamorig:LeftFoot']
rf = arm.pose.bones['mixamorig:RightFoot']

print('--- ORIG FRAMES ---')
for f in range(1, 99, 4):
    scene.frame_set(f)
    bpy.context.view_layer.update()
    hw = arm.matrix_world @ hips.head
    lw = arm.matrix_world @ lf.head
    rw = arm.matrix_world @ rf.head
    print(f'F{f:2d} | Hips: ({hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}) | LF: ({lw.x:6.2f}, {lw.y:6.2f}, {lw.z:6.2f}) | RF: ({rw.x:6.2f}, {rw.y:6.2f}, {rw.z:6.2f})')
