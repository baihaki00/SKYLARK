import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\SKYLARKTEST\Jump.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]

# Rest pose (no action)
arm.animation_data_clear()
bpy.context.view_layer.update()

w_hips = (arm.matrix_world @ arm.pose.bones['mixamorig:Hips'].matrix).translation
w_lfoot = (arm.matrix_world @ arm.pose.bones['mixamorig:LeftFoot'].matrix).translation
w_rfoot = (arm.matrix_world @ arm.pose.bones['mixamorig:RightFoot'].matrix).translation
w_ltoe = (arm.matrix_world @ arm.pose.bones['mixamorig:LeftToeBase'].matrix).translation
w_rtoe = (arm.matrix_world @ arm.pose.bones['mixamorig:RightToeBase'].matrix).translation

print("=== Rest Pose World Z Heights ===")
print(f"Hips Z: {w_hips.z:.4f}m")
print(f"LeftFoot Z: {w_lfoot.z:.4f}m")
print(f"RightFoot Z: {w_rfoot.z:.4f}m")
print(f"LeftToe Z: {w_ltoe.z:.4f}m")
print(f"RightToe Z: {w_rtoe.z:.4f}m")
print(f"Ground Floor level in rest pose: {min(w_ltoe.z, w_rtoe.z):.4f}m")
