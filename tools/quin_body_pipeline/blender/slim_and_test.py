"""Shell under Roblox's limit (decimate before the armature, weights kept), then the run animation on
the rig, rendered from the side at a few frames.
blender -b --python slim_and_test.py -- <rigged.blend> <run.fbx> <render_prefix>"""
import bpy, sys, math
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
sc = bpy.context.scene; V = bpy.context.view_layer
arm = next(o for o in sc.objects if o.type == 'ARMATURE')
shell = sc.objects["Quin_Shell"]
tris = sum(len(p.vertices) - 2 for p in shell.data.polygons)
target = 20000
if tris > target:
    bpy.ops.object.select_all(action='DESELECT'); shell.select_set(True); V.objects.active = shell
    dec = shell.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = target / tris; dec.use_symmetry = True; dec.symmetry_axis = 'X'
    bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
    bpy.ops.object.modifier_apply(modifier="Decimate")
print("SHELL tris %d -> %d" % (tris, sum(len(p.vertices) - 2 for p in shell.data.polygons)))
bare = sum(1 for v in shell.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
print("SHELL unweighted after decimate", bare)
bpy.ops.wm.save_mainfile()
print("SAVED", a[0])

# --- test: the Quins' run clip on this rig (not saved into the file)
before = set(sc.objects)
bpy.ops.import_scene.fbx(filepath=a[1])
new = [o for o in sc.objects if o not in before]
src = next(o for o in new if o.type == 'ARMATURE')
act = src.animation_data.action
for o in new: bpy.data.objects.remove(o, do_unlink=True)
arm.animation_data_create(); arm.animation_data.action = act
if hasattr(arm.animation_data, "action_slot") and act.slots:
    arm.animation_data.action_slot = act.slots[0]
arm.data.pose_position = 'POSE'
f0, f1 = (int(x) for x in act.frame_range)
for o in sc.objects:
    if o.type == 'EMPTY': o.hide_render = True
red = (0.9, 0.85, 0.75)
sh = sc.display.shading
sc.render.engine = 'BLENDER_WORKBENCH'; sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'
sh.show_cavity = True; sh.background_type = 'VIEWPORT'; sh.background_color = (0.25, 0.25, 0.27)
sc.render.resolution_x, sc.render.resolution_y = 700, 900
cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 2.4
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
for i, f in enumerate([f0, f0 + (f1 - f0) // 3, f0 + 2 * (f1 - f0) // 3]):
    sc.frame_set(f)
    hips = arm.matrix_world @ arm.pose.bones["mixamorig:Hips"].head
    for label, off, rot in (("side", (6, 0, 0), (math.radians(90), 0, math.radians(90))), ("front", (0, -6, 0), (math.radians(90), 0, 0))):
        cam.location = (hips.x + off[0], hips.y + off[1], 0.95); cam.rotation_euler = rot
        sc.render.filepath = "%s_f%02d_%s.png" % (a[2], f, label)
        bpy.ops.render.render(write_still=True)
        print("RENDERED", sc.render.filepath)
