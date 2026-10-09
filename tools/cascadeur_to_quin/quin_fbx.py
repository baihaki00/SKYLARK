"""
Write a retargeted clip into the Quin's Mixamo template FBX, so the result is laid out exactly
like a Mixamo download: each bone's rest angle stays in its PreRotation, the rotation curves
carry the motion, the hips carry the only position curve, all in the template's units, then
everything that is a distance is scaled (x0.044 for Roblox, as the autofixer did).

Import with Rest Pose Source "Imported Rig": the rest is the file's own skeleton, rest angles
included, the same as the Quin rig in Studio. "Zeroed Rotations" zeroes those rest angles too
(it suits rigs whose bones rest unrotated), and the Quin's do not (its leg bones rest turned
180 degrees, for one), so it comes out crippled. A Blender export mixed rest and motion into one
rotation (crippled in both), and "Animation Editor Rig" floated its hips.
"""
import json
import math

import fbx_tree

KTIME_PER_SECOND = 46186158000


def _euler_xyz_matrix(deg):
    """FBX XYZ order: X first, then Y, then Z (R = Rz Ry Rx)."""
    x, y, z = (math.radians(a) for a in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return _mul(rz, _mul(ry, rx))


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _transpose(a):
    return [[a[j][i] for j in range(3)] for i in range(3)]


def _matrix_to_euler_xyz(r):
    y = math.asin(max(-1.0, min(1.0, -r[2][0])))
    if abs(r[2][0]) < 0.9999:
        x = math.atan2(r[2][1], r[2][2])
        z = math.atan2(r[1][0], r[0][0])
    else:  # gimbal: put it all on X
        x = math.atan2(-r[1][2], r[1][1])
        z = 0.0
    return [math.degrees(x), math.degrees(y), math.degrees(z)]


def _unwrap(prev, cur):
    return [c + 360.0 * round((p - c) / 360.0) for p, c in zip(prev, cur)]


def _props70(node):
    p70 = node.find("Properties70")
    return {p.value(0): p for p in p70.children} if p70 else {}


def build(template_path, clip_json, out_path, scale, in_place=False):
    """in_place: the hips keep their rest spot across the ground (no travel); their height,
    and every rotation, stay as animated."""
    version, nodes, foot_id = fbx_tree.read(template_path)
    top = {n.name: n for n in nodes}
    objects = top["Objects"].children
    by_id = {o.value(0): o for o in objects if o.props and o.props[0][0] == "L"}

    with open(clip_json) as f:
        clip = json.load(f)
    fps, frames = clip["fps"], clip["frames"]
    n = len(frames)
    times = [round(i * KTIME_PER_SECOND / fps) for i in range(n)]

    # who drives what
    node_target = {}   # curve node id -> (model, "Lcl Rotation" / "Lcl Translation")
    curve_axis = {}    # curve id -> (curve node id, 0/1/2)
    for c in top["Connections"].children:
        v = c.values()
        if v[0] != "OP":
            continue
        child, parent, prop = v[1], v[2], v[3]
        if prop in ("Lcl Rotation", "Lcl Translation", "Lcl Scaling") and child in by_id:
            node_target[child] = (by_id.get(parent), prop)
        elif prop in ("d|X", "d|Y", "d|Z"):
            curve_axis[child] = (parent, "XYZ".index(prop[-1]))

    # the channel values per curve node, per frame
    channel = {}
    for cn_id, (model, prop) in node_target.items():
        name = model.value(1).split("\x00")[0]
        if name not in frames[0]:
            raise ValueError("the clip has no bone " + name)
        mats = [fr[name] for fr in frames]
        if prop == "Lcl Rotation":
            pre = _props70(model).get("PreRotation")
            pre_m = _euler_xyz_matrix(pre.values()[4:7] if pre else [0, 0, 0])
            pre_inv = _transpose(pre_m)
            vals, prev = [], None
            for m in mats:
                r = [row[:3] for row in m[:3]]
                e = _matrix_to_euler_xyz(_mul(pre_inv, r))
                if prev is not None:
                    e = _unwrap(prev, e)
                vals.append(e)
                prev = e
        elif prop == "Lcl Translation":
            vals = [[m[0][3] * scale, m[1][3] * scale, m[2][3] * scale] for m in mats]
            if in_place:  # (FBX space is Y-up: X and Z are across the ground)
                rest = _props70(model).get("Lcl Translation")
                rx, rz = (rest.value(4), rest.value(6)) if rest else (0.0, 0.0)
                vals = [[rx * scale, v[1], rz * scale] for v in vals]
        else:
            vals = [[1.0, 1.0, 1.0]] * n
        channel[cn_id] = vals

    for o in objects:
        oid = o.value(0) if o.props and o.props[0][0] == "L" else None
        if o.name == "Model":
            t = _props70(o).get("Lcl Translation")
            if t:  # rest positions, scaled
                for i in range(4, 7):
                    t.set_scalar(i, t.value(i) * scale)
        elif o.name == "AnimationCurveNode" and oid in channel:
            first = channel[oid][0]
            for key, p in _props70(o).items():
                if key in ("d|X", "d|Y", "d|Z"):
                    p.set_scalar(4, first["XYZ".index(key[-1])])
        elif o.name == "AnimationCurve":
            if oid in curve_axis and curve_axis[oid][0] in channel:
                cn_id, axis = curve_axis[oid]
                vals = [v[axis] for v in channel[cn_id]]
            else:
                # a leftover curve the template drives nothing with: held still, the clip's length
                # (every curve in the file then has the same keys)
                vals = [o.find("KeyValueFloat").value(0)[0]] * n
            o.find("Default").set_scalar(0, vals[0])
            o.find("KeyTime").set_array(0, times)
            o.find("KeyValueFloat").set_array(0, vals)
            o.find("KeyAttrRefCount").set_array(0, [n])
        elif o.name == "AnimationStack":
            for key, p in _props70(o).items():
                if key in ("LocalStop", "ReferenceStop"):
                    p.set_scalar(4, times[-1])

    for key, p in _props70(top["GlobalSettings"]).items():
        if key == "TimeSpanStop":
            p.set_scalar(4, times[-1])
    for take in top["Takes"].find_all("Take"):
        for k in ("LocalTime", "ReferenceTime"):
            node = take.find(k)
            if node:
                node.set_scalar(1, times[-1])

    fbx_tree.write(out_path, version, nodes, foot_id)
    return n
