
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
cam_data = bpy.data.cameras.new('Cam')
cam = bpy.data.objects.new('Cam', cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam
cam.location = (5, -5, 3)
cam.rotation_euler = (1.1, 0, 0.785)
bpy.context.scene.render.filepath = r'C:\Users\User\.gemini\antigravity\scratch\test_render.png'
bpy.ops.render.render(write_still=True)
print('Render done')
