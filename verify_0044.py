import bpy

fpath = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_HeroLanding_Planted[x0.044].fbx'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fpath)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

pbone_hips = arm.pose.bones['mixamorig:Hips']
pbone_spine = arm.pose.bones['mixamorig:Spine']
pbone_arm = arm.pose.bones['mixamorig:LeftArm']
pbone_toe = arm.pose.bones['mixamorig:LeftToeBase']

print("=== Rest Pose Bone Positions in Blender ===")
print("Hips Rest:", arm.data.bones['mixamorig:Hips'].head)
print("Spine Rest:", arm.data.bones['mixamorig:Spine'].head)
print("LeftArm Rest:", arm.data.bones['mixamorig:LeftArm'].head)

print("\n=== Sampled World Positions Across Frames ===")
for f in [1, 25, 45, 51, 60, 75]:
    scene.frame_set(f)
    hw = (arm.matrix_world @ pbone_hips.matrix).translation
    tw = (arm.matrix_world @ pbone_toe.matrix).translation
    print(f"Frame {f:2d}: Hips=({hw.x:.4f}, {hw.y:.4f}, {hw.z:.4f}) | Toe Z={tw.z:.4f}m")
