
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

# Let's inspect what happens if Hips X and Z are set to 0.0 in the action
act = arm.animation_data.action

hips_pb = arm.pose.bones['mixamorig:Hips']
lf_pb = arm.pose.bones['mixamorig:LeftFoot']
rf_pb = arm.pose.bones['mixamorig:RightFoot']

# Option 1: Hips X=0, Z=0 (raw local location = 0)
# Option 2: Hips X and Z adjusted so feet are centered at (0,0)

print('--- SIMULATION OF DIFFERENT CENTERING OPTIONS ---')
# Let's check how the bones evaluate at rest pose vs frame 1 vs frame 50 vs frame 98
scene.frame_set(1)
bpy.context.view_layer.update()
print('Frame 1 with original Hips:', hips_pb.location)

# If we set hips_pb.location.x = 0 and hips_pb.location.z = 0:
# Note: in Blender, hips_pb.location is local to rest pose!
print('Local location values on frame 1:')
print(f'  loc.x = {hips_pb.location.x:.3f}, loc.y = {hips_pb.location.y:.3f}, loc.z = {hips_pb.location.z:.3f}')
