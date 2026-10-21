"""
One-click rig: a Quin modelling file -> a rigged, Roblox-ready Quin, on the fitted ybot skeleton.

  blender -b --python build_rig.py -- <model.blend> <fitted.blend> <out.blend> [keep|subsurf_level]

  model.blend   your modelling file, modifiers live (e.g. BASE2.blend); its bronze body is `basemesh`
  fitted.blend  the file whose Armature you fitted to the model (e.g. BASE2_rigfit_LR.blend);
                its `basemesh` tells where the model sits on the skeleton
  out.blend     written new; nothing else is changed

What it does:
  1. Every modifier applied as the model has it (default "keep"; no reduction of any kind). An
     optional subsurf_level (e.g. 0) overrides Subdivision, to get under Roblox's 20k triangles
     without decimating (decimating thin Solidify shells tears them).
  2. The model moved and scaled onto the skeleton, the same way as in fitted.blend.
  3. The fitted Armature brought in; bone names back to Mixamo if they were .L/.R.
  4. Zones: every wood piece joined into `Quin_Shell`, the bronze body named `Quin_Joints`;
     smooth shading (creases over 35 degrees kept).
  5. Skinning: `Quin_Joints` by Automatic Weights. `Quin_Shell` copies its weights from the bronze
     body underneath (nearest surface), so a plate's inner and outer walls move together (Automatic
     Weights on thin double-walled plates gave the walls different weights: they tore apart).
     Each separate plate then keeps only the bones owning at least 12% of it (stray pulls from a
     neighbouring limb tore the torso plate's sides).
  6. At most 4 bones per vertex, normalised (Roblox). A report of triangles and unweighted vertices.
"""
import re
import sys
import bpy
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index("--") + 1:]
MODEL, FITTED, OUT = a[0], a[1], a[2]
SUBSURF = a[3] if len(a) > 3 else "keep"  # "keep": the model's own modifier settings, untouched
BODY = "basemesh"
TRI_LIMIT = 20000


def world_bbox(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    pts = [ob.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def activate(ob, *others):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for o in (*others, ob):
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = ob


# where the body sits on the skeleton (from the fitted file)
bpy.ops.wm.open_mainfile(filepath=FITTED)
fit_lo, fit_hi = world_bbox(bpy.data.objects[BODY])

# 1. the model, modifiers applied
bpy.ops.wm.open_mainfile(filepath=MODEL)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
if SUBSURF != "keep":
    for o in meshes:
        for m in o.modifiers:
            if m.type == 'SUBSURF':
                m.levels = m.render_levels = int(SUBSURF)
for o in meshes:
    if o.modifiers:
        activate(o)
        bpy.ops.object.convert(target='MESH')

# 2. onto the skeleton: the body's box matched to the fitted one (uniform scale, then offset)
lo, hi = world_bbox(bpy.data.objects[BODY])
s = (fit_hi.z - fit_lo.z) / (hi.z - lo.z)
offset = (fit_lo + fit_hi) / 2 - (lo + hi) / 2 * s
T = Matrix.Translation(offset) @ Matrix.Scale(s, 4)
for o in meshes:
    o.matrix_world = T @ o.matrix_world
for o in meshes:
    activate(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 3. the fitted armature
with bpy.data.libraries.load(FITTED, link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n == "Armature"]
arm = dst.objects[0]
bpy.context.scene.collection.objects.link(arm)
activate(arm)
bpy.ops.object.mode_set(mode='EDIT')
for b in arm.data.edit_bones:
    new = re.sub(r"^mixamorig:(.+)\.L$", r"mixamorig:Left\1", b.name)
    new = re.sub(r"^mixamorig:(.+)\.R$", r"mixamorig:Right\1", new)
    b.name = new
arm.data.use_mirror_x = False
bpy.ops.object.mode_set(mode='OBJECT')
arm.data.pose_position = 'REST'
if arm.animation_data:
    arm.animation_data.action = None

# 4. zones
joints = bpy.data.objects[BODY]
wood = [o for o in meshes if o is not joints]
activate(wood[0], *wood[1:])
bpy.ops.object.join()
shell = bpy.context.view_layer.objects.active
shell.name = shell.data.name = "Quin_Shell"
joints.name = joints.data.name = "Quin_Joints"

# smooth shading (creases kept), only when Subdivision was taken off (the plates looked faceted)
if SUBSURF != "keep":
    for o in (shell, joints):
        activate(o)
        bpy.ops.object.shade_smooth_by_angle(angle=0.61)  # 35 degrees

# 5. skinning
activate(arm, joints)
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
activate(arm, shell)
bpy.ops.object.parent_set(type='ARMATURE_NAME')  # (armature modifier and empty groups)
activate(shell)
dt = shell.modifiers.new("WeightsFromBody", 'DATA_TRANSFER')
dt.object = joints
dt.use_vert_data = True
dt.data_types_verts = {'VGROUP_WEIGHTS'}
dt.vert_mapping = 'POLYINTERP_NEAREST'
dt.layers_vgroup_select_src = 'ALL'
dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
bpy.ops.object.datalayout_transfer(modifier=dt.name)
bpy.ops.object.modifier_apply(modifier=dt.name)

# Each separate plate keeps only the bones that own it: a bone with under PART_SHARE of the plate's
# total weight is dropped (the torso plate's sides took weight from the upper arm, the nearest body
# surface there, and tore off with it), then the plate's weights are renormalised.
PART_SHARE = 0.12
import bmesh
bm = bmesh.new(); bm.from_mesh(shell.data); bm.verts.ensure_lookup_table()
seen, parts = set(), []
for v in bm.verts:
    if v.index in seen: continue
    stack, part = [v], []
    seen.add(v.index)
    while stack:
        c = stack.pop(); part.append(c.index)
        for e in c.link_edges:
            o = e.other_vert(c)
            if o.index not in seen:
                seen.add(o.index); stack.append(o)
    parts.append(part)
bm.free()
verts = shell.data.vertices
groups = shell.vertex_groups
dropped = 0
for part in parts:
    totals = {}
    for i in part:
        for g in verts[i].groups:
            totals[g.group] = totals.get(g.group, 0) + g.weight
    whole = sum(totals.values()) or 1
    keep = {gi for gi, w in totals.items() if w / whole >= PART_SHARE} or {max(totals, key=totals.get)}
    top = max(keep, key=lambda gi: totals[gi])
    for i in part:
        for g in list(verts[i].groups):
            if g.group not in keep:
                groups[g.group].remove([i]); dropped += 1
        if sum(g.weight for g in verts[i].groups) < 1e-4:
            groups[top].add([i], 1.0, 'REPLACE')
print("PLATES %d, stray bone weights dropped %d" % (len(parts), dropped))

# 6. Roblox limits and a report
report = []
for o in (shell, joints):
    activate(o)
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    bare = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    report.append("%s %d tris%s, unweighted %d" % (o.name, tris, " (OVER %d!)" % TRI_LIMIT if tris > TRI_LIMIT else "", bare))
arm.data.pose_position = 'POSE'
activate(arm)
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("RIG_OK", OUT, "|", " | ".join(report))
