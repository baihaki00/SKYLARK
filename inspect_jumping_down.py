import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_hips = arm.pose.bones['mixamorig:Hips']
pbone_lfoot = arm.pose.bones.get('mixamorig:LeftFoot')
pbone_rfoot = arm.pose.bones.get('mixamorig:RightFoot')

print("Frame | Hips Loc X, Y, Z | Hips World X, Y, Z | LFoot World Z | RFoot World Z")
for f in range(1, 77, 3):
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation
    lfw = (arm.matrix_world @ pbone_lfoot.matrix).translation if pbone_lfoot else None
    rfw = (arm.matrix_world @ pbone_rfoot.matrix).translation if pbone_rfoot else None
    hl = pbone_hips.location
    print(f"{f:2d} | Loc: ({hl.x:7.2f}, {hl.y:7.2f}, {hl.z:7.2f}) | World: ({hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}) | LFootZ: {lfw.z:6.2f} | RFootZ: {rfw.z:6.2f}")

scene.frame_set(76)
hw = (arm.matrix_world @ pbone_hips.matrix).translation
lfw = (arm.matrix_world @ pbone_lfoot.matrix).translation
rfw = (arm.matrix_world @ pbone_rfoot.matrix).translation
hl = pbone_hips.location
print(f"76 | Loc: ({hl.x:7.2f}, {hl.y:7.2f}, {hl.z:7.2f}) | World: ({hw.x:6.2f}, {hw.y:6.2f}, {hw.z:6.2f}) | LFootZ: {lfw.z:6.2f} | RFootZ: {rfw.z:6.2f}")
