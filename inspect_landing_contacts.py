import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_hips = arm.pose.bones['mixamorig:Hips']
pbone_lfoot = arm.pose.bones.get('mixamorig:LeftFoot')
pbone_rfoot = arm.pose.bones.get('mixamorig:RightFoot')
pbone_lknee = arm.pose.bones.get('mixamorig:LeftLeg')
pbone_rknee = arm.pose.bones.get('mixamorig:RightLeg')
pbone_lhand = arm.pose.bones.get('mixamorig:LeftHand')
pbone_rhand = arm.pose.bones.get('mixamorig:RightHand')

print("Frame | Hips Z | LFoot Z | RFoot Z | LKnee Z | RKnee Z | LHand Z | RHand Z")
for f in range(45, 65):
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation.z
    lfw = (arm.matrix_world @ pbone_lfoot.matrix).translation.z
    rfw = (arm.matrix_world @ pbone_rfoot.matrix).translation.z
    lkw = (arm.matrix_world @ pbone_lknee.matrix).translation.z
    rkw = (arm.matrix_world @ pbone_rknee.matrix).translation.z
    lhw = (arm.matrix_world @ pbone_lhand.matrix).translation.z
    rhw = (arm.matrix_world @ pbone_rhand.matrix).translation.z
    min_contact = min(lfw, rfw, lkw, rkw, lhw, rhw)
    print(f"{f:2d} | Hips={hw:5.2f} | LFoot={lfw:5.2f} | RFoot={rfw:5.2f} | LKnee={lkw:5.2f} | RHand={rhw:5.2f} | MinGround={min_contact:5.2f}")
