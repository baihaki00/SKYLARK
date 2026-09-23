
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

hips_pb = arm.pose.bones['mixamorig:Hips']
lf_pb = arm.pose.bones['mixamorig:LeftFoot']
rf_pb = arm.pose.bones['mixamorig:RightFoot']

# Option B: Relative shift by center_x = 0, center_z = 98.16 cm
# (In Blender local: center_x = 0.0, center_z = 98.16)
print('=== TESTING OPTION B: RELATIVE SHIFT (Z centered around 98.16cm) ===')
for f in [1, 6, 15, 30, 50, 70, 85, 98]:
    scene.frame_set(f)
    bpy.context.view_layer.update()
    
    orig_x = hips_pb.location.x
    orig_z = hips_pb.location.z
    
    # subtract 98.16 from z
    hips_pb.location.x = orig_x - 0.0
    hips_pb.location.z = orig_z - 98.16
    bpy.context.view_layer.update()
    
    hw = arm.matrix_world @ hips_pb.head
    lw = arm.matrix_world @ lf_pb.head
    rw = arm.matrix_world @ rf_pb.head
    
    fc_x = (lw.x + rw.x) / 2.0
    fc_y = (lw.y + rw.y) / 2.0
    fc_z = (lw.z + rw.z) / 2.0
    
    print(f'F{f:2d} | Hips: ({hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}) | FeetMid: ({fc_x:6.2f}, {fc_y:6.2f}, {fc_z:6.2f}) | LF: ({lw.x:6.2f}, {lw.y:6.2f}, {lw.z:6.2f}) | RF: ({rw.x:6.2f}, {rw.y:6.2f}, {rw.z:6.2f})')
