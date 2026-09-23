import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
act = bpy.data.actions[0]
strip = act.layers[0].strips[0]
cb = strip.channelbags[0]

fcs = {fc.data_path + f'[{fc.array_index}]': fc for fc in cb.fcurves}

# Check Hips location curves
loc_x = fcs['pose.bones["mixamorig:Hips"].location[0]']
loc_y = fcs['pose.bones["mixamorig:Hips"].location[1]']
loc_z = fcs['pose.bones["mixamorig:Hips"].location[2]']

print("Original Hips Location:")
print(f"X: Start={loc_x.keyframe_points[0].co[1]:.2f}, End={loc_x.keyframe_points[-1].co[1]:.2f}")
print(f"Y: Start={loc_y.keyframe_points[0].co[1]:.2f}, End={loc_y.keyframe_points[-1].co[1]:.2f}")
print(f"Z: Start={loc_z.keyframe_points[0].co[1]:.2f}, End={loc_z.keyframe_points[-1].co[1]:.2f}")

# Let's see what happens if we create an In-Place version:
# In-place means:
# 1. Z (forward in bone local space) is locked to its starting value or 0
# 2. X (lateral) is locked to its starting value or 0
# 3. Y (vertical): If the animation starts on a ledge (+31.03) and lands on the ground (-54.98):
# Notice: In a game engine, when you play a 'Jump Down' animation, the character is jumping off an edge.
# If physics drives the character falling:
# Option A: Horizontal In-Place only (Z=start, X=start, Y untouched)
# Option B: Full In-Place (Horizontal locked, Y normalized so landing matches standing height)
