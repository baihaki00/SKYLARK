"""Close-ups of a rigged Quin mid-run: back, hand, knee.
blender -b --python closeups_pose.py -- <rigged.blend> <run.fbx> <prefix> <frame>"""
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
for o in sc.objects:
    if o.type == 'EMPTY': o.hide_render = True
sc.frame_set(int(a[3]))
sh = sc.display.shading
sc.render.engine = 'BLENDER_WORKBENCH'; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'
sh.show_cavity = True; sh.show_specular_highlight = True
sh.background_type = 'VIEWPORT'; sh.background_color = (0.25, 0.25, 0.27)
sc.render.resolution_x, sc.render.resolution_y = 800, 800
cd = bpy.data.cameras.new("C"); cd.lens = 60
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
def at(bone):
    return arm.matrix_world @ arm.pose.bones["mixamorig:" + bone].head
for label, target, d, dist in (("back", at("Spine2"), Vector((0.3, 1, 0.2)), 1.1),
                                ("hand", at("LeftHand"), Vector((0.6, -0.6, 0.5)), 0.45),
                                ("knee", at("LeftLeg"), Vector((1, -0.4, 0.1)), 0.8)):
    cam.location = target + d.normalized() * dist
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = "%s_%s.png" % (a[2], label)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)
