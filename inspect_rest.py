
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]

hips = arm.data.bones['mixamorig:Hips']
lf = arm.data.bones['mixamorig:LeftFoot']
rf = arm.data.bones['mixamorig:RightFoot']

print('--- REST POSE (Armature Space) ---')
print('Hips head:', hips.head_local)
print('LF head:  ', lf.head_local)
print('RF head:  ', rf.head_local)
feet_center = (lf.head_local + rf.head_local) / 2.0
print('Feet center in rest pose:', feet_center)
