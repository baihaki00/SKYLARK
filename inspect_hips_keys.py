import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
act = bpy.data.actions[0]
strip = act.layers[0].strips[0]
cb = strip.channelbags[0]

# Let's inspect the exact keyframes of Hips location
fcs = {fc.data_path + f'[{fc.array_index}]': fc for fc in cb.fcurves}
loc_x = fcs['pose.bones["mixamorig:Hips"].location[0]']
loc_y = fcs['pose.bones["mixamorig:Hips"].location[1]']
loc_z = fcs['pose.bones["mixamorig:Hips"].location[2]']

print(f"Total keyframe points: X={len(loc_x.keyframe_points)}, Y={len(loc_y.keyframe_points)}, Z={len(loc_z.keyframe_points)}")
print("\nSample Keyframes (Frame, X, Y, Z):")
for i in range(0, len(loc_x.keyframe_points), 5):
    f = loc_x.keyframe_points[i].co[0]
    x = loc_x.keyframe_points[i].co[1]
    y = loc_y.keyframe_points[i].co[1]
    z = loc_z.keyframe_points[i].co[1]
    print(f"Frame {f:4.0f}: X = {x:8.3f}, Y = {y:8.3f}, Z = {z:8.3f}")

last_idx = len(loc_x.keyframe_points) - 1
f = loc_x.keyframe_points[last_idx].co[0]
x = loc_x.keyframe_points[last_idx].co[1]
y = loc_y.keyframe_points[last_idx].co[1]
z = loc_z.keyframe_points[last_idx].co[1]
print(f"Frame {f:4.0f}: X = {x:8.3f}, Y = {y:8.3f}, Z = {z:8.3f}")
