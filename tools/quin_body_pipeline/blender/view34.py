import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
before = set(sc.objects)
bpy.ops.import_scene.fbx(filepath=a[1])
new = [o for o in sc.objects if o not in before]
act = next(o for o in new if o.type == 'ARMATURE').animation_data.action
for o in new: bpy.data.objects.remove(o, do_unlink=True)
arm.animation_data_create(); arm.animation_data.action = act
if hasattr(arm.animation_data, "action_slot") and act.slots: arm.animation_data.action_slot = act.slots[0]
arm.data.pose_position = 'POSE'
for o in sc.objects:
    if o.type == 'EMPTY': o.hide_render = True
sh = sc.display.shading
sc.render.engine = 'BLENDER_WORKBENCH'; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_cavity = True
sh.background_type = 'VIEWPORT'; sh.background_color = (0.25, 0.25, 0.27)
sc.render.resolution_x, sc.render.resolution_y = 700, 700
cd = bpy.data.cameras.new("C"); cd.lens = 50
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
for f in (int(x) for x in a[3].split(",")):
    sc.frame_set(f)
    hips = arm.matrix_world @ arm.pose.bones["mixamorig:Hips"].head
    target = hips + Vector((0, 0, 0.15))
    cam.location = target + Vector((-1.6, 2.6, 0.9))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = "%s_f%02d.png" % (a[2], f)
    bpy.ops.render.render(write_still=True); print("RENDERED", sc.render.filepath)
