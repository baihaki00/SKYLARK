"""Re-weight from the body and join everything into one mesh `Quin_Body`.
blender -b --python join_body.py -- <in.blend> <out.blend>"""
import bpy, bmesh, re, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
V = bpy.context.view_layer
def activate(ob, *others):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    for o in (*others, ob):
        o.hide_set(False); o.select_set(True)
    V.objects.active = ob
# leftover imported skeleton(s): any armature nothing is skinned to
used = {m.object for o in bpy.data.objects if o.type == 'MESH' for m in o.modifiers if m.type == 'ARMATURE'}
for o in [o for o in bpy.data.objects if o.type == 'ARMATURE' and o not in used]:
    print("REMOVED leftover", o.name)
    bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.data.pose_position = 'REST'
joints, shell = bpy.data.objects["Quin_Joints"], bpy.data.objects["Quin_Shell"]
# 1. the body: automatic weights afresh
for g in list(joints.vertex_groups): joints.vertex_groups.remove(g)
activate(arm, joints); bpy.ops.object.parent_set(type='ARMATURE_AUTO')
# 2. the plates: weights from the body underneath (nearest surface)
for g in list(shell.vertex_groups): shell.vertex_groups.remove(g)
for g in joints.vertex_groups: shell.vertex_groups.new(name=g.name)
activate(shell)
dt = shell.modifiers.new("WeightsFromBody", 'DATA_TRANSFER')
dt.object = joints; dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}
dt.vert_mapping = 'POLYINTERP_NEAREST'; dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
bpy.ops.object.modifier_apply(modifier=dt.name)
# each plate keeps only bones with >= 12% of it; the head plate is rigid on Head
bm = bmesh.new(); bm.from_mesh(shell.data); bm.verts.ensure_lookup_table()
seen, parts = set(), []
for v in bm.verts:
    if v.index in seen: continue
    st = [v]; seen.add(v.index); part = []
    while st:
        c = st.pop(); part.append(c.index)
        for e in c.link_edges:
            o = e.other_vert(c)
            if o.index not in seen: seen.add(o.index); st.append(o)
    parts.append(part)
bm.free()
vs, G = shell.data.vertices, shell.vertex_groups
head = G.get("mixamorig:Head")
for part in parts:
    tot = {}
    for i in part:
        for g in vs[i].groups: tot[g.group] = tot.get(g.group, 0) + g.weight
    whole = sum(tot.values()) or 1
    if head and tot.get(head.index, 0) / whole > 0.3:
        for g in G: g.remove(part)
        head.add(part, 1.0, 'REPLACE'); continue
    keep = {gi for gi, w in tot.items() if w / whole >= 0.12} or {max(tot, key=tot.get)}
    top = max(keep, key=lambda gi: tot[gi])
    for i in part:
        for g in list(vs[i].groups):
            if g.group not in keep: G[g.group].remove([i])
        if sum(g.weight for g in vs[i].groups) < 1e-4: G[top].add([i], 1.0, 'REPLACE')
# 3. join into one mesh; tip bones emptied, smoothed, normalised, max 4
activate(joints, shell); bpy.ops.object.join()
body = V.objects.active
body.name = body.data.name = "Quin_Body"
TIP = re.compile(r"(_End$|Thumb4$|Index4$|Middle4$|Ring4$|Pinky4$)")
allv = list(range(len(body.data.vertices)))
for g in body.vertex_groups:
    if TIP.search(g.name): g.remove(allv)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
body.data.use_paint_mask = False; body.data.use_paint_mask_vertex = False
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=4, expand=0.0)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
mods = [m for m in body.modifiers if m.type == 'ARMATURE']
for m in mods[1:]: body.modifiers.remove(m)
mods[0].object = arm
bare = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
print("BODY verts %d tris %d materials %s unweighted %d" % (len(body.data.vertices), sum(len(p.vertices)-2 for p in body.data.polygons), [m.name for m in body.data.materials], bare))
arm.data.pose_position = 'POSE'
activate(arm)
bpy.ops.wm.save_as_mainfile(filepath=a[1])
print("SAVED", a[1])
