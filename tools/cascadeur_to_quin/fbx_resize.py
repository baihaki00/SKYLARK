"""
Resize a binary FBX's skeleton and its animation in place: every Model's Lcl Translation, every
translation AnimationCurveNode's defaults, and every translation AnimationCurve's key values are
multiplied by `scale`. (The autofixer only scaled the hips' curves; Blender writes a translation
curve for every bone, which left the rest of the skeleton full size: the giant rig in Roblox.)
Needs uncompressed arrays (the Blender step writes them so). Sizes never change, so the file is
patched byte for byte.
"""
import struct


def _node(d, pos, v64):
    if v64:
        end, n, plen, nlen = struct.unpack('<QQQB', d[pos:pos + 25]); h = 25
    else:
        end, n, plen, nlen = struct.unpack('<IIIB', d[pos:pos + 13]); h = 13
    if end == 0:
        return None
    ps = pos + h + nlen
    return {"end": end, "n": n, "name": d[pos + h:ps].decode('ascii', 'replace'), "ps": ps, "ch": ps + plen}


def _props(d, p, n):
    """[(type, value, offset_of_value)]"""
    out = []
    for _ in range(n):
        t = chr(d[p]); p += 1
        if t in 'SR':
            l = struct.unpack('<I', d[p:p + 4])[0]
            v = d[p + 4:p + 4 + l]
            out.append((t, v.decode('utf-8', 'replace') if t == 'S' else v, p + 4)); p += 4 + l
        elif t in 'DL':
            out.append((t, struct.unpack('<d' if t == 'D' else '<q', d[p:p + 8])[0], p)); p += 8
        elif t in 'IF':
            out.append((t, struct.unpack('<i' if t == 'I' else '<f', d[p:p + 4])[0], p)); p += 4
        elif t == 'Y':
            out.append((t, None, p)); p += 2
        elif t == 'C':
            out.append((t, None, p)); p += 1
        else:  # array
            l, enc, cl = struct.unpack('<III', d[p:p + 12])
            out.append((t, (l, enc), p + 12)); p += 12 + cl
    return out


def _children(d, nd, v64):
    pos = nd["ch"]
    while pos < nd["end"]:
        c = _node(d, pos, v64)
        if not c:
            break
        yield c
        pos = c["end"]


def resize(path, scale):
    d = bytearray(open(path, 'rb').read())
    v64 = struct.unpack('<I', d[23:27])[0] >= 7500
    top = {}
    pos = 27
    while pos < len(d):
        nd = _node(d, pos, v64)
        if not nd:
            break
        top[nd["name"]] = nd
        pos = nd["end"]

    # which curve nodes drive a translation, and which curves feed them
    tnodes, curve_of = set(), {}
    for c in _children(d, top["Connections"], v64):
        if c["name"] != "C":
            continue
        pr = _props(d, c["ps"], c["n"])
        if len(pr) >= 4 and pr[0][1] == "OP":
            child, parent, prop = pr[1][1], pr[2][1], pr[3][1]
            if prop == "Lcl Translation":
                tnodes.add(child)
            elif prop in ("d|X", "d|Y", "d|Z"):
                curve_of[child] = parent

    def scale_doubles_in_P70(obj, wanted):
        n = 0
        for c in _children(d, obj, v64):
            if c["name"] != "Properties70":
                continue
            for p in _children(d, c, v64):
                pr = _props(d, p["ps"], p["n"])
                if pr and pr[0][1] in wanted:
                    for t, v, off in pr[4:]:
                        if t == 'D':
                            d[off:off + 8] = struct.pack('<d', v * scale); n += 1
        return n

    counts = {"models": 0, "curve_nodes": 0, "curves": 0}
    for obj in _children(d, top["Objects"], v64):
        pr = _props(d, obj["ps"], obj["n"])
        oid = pr[0][1] if pr and pr[0][0] == 'L' else None
        if obj["name"] == "Model":
            if scale_doubles_in_P70(obj, ("Lcl Translation",)):
                counts["models"] += 1
        elif obj["name"] == "AnimationCurveNode" and oid in tnodes:
            scale_doubles_in_P70(obj, ("d|X", "d|Y", "d|Z"))
            counts["curve_nodes"] += 1
        elif obj["name"] == "AnimationCurve" and curve_of.get(oid) in tnodes:
            for c in _children(d, obj, v64):
                if c["name"] in ("KeyValueFloat", "Default"):
                    for t, v, off in _props(d, c["ps"], c["n"]):
                        if t == 'f':
                            l, enc = v
                            if enc != 0:
                                raise ValueError("compressed curve; the Blender step must write plain arrays")
                            vals = struct.unpack('<%df' % l, d[off:off + 4 * l])
                            d[off:off + 4 * l] = struct.pack('<%df' % l, *[x * scale for x in vals])
                        elif t == 'D':
                            d[off:off + 8] = struct.pack('<d', v * scale)
            counts["curves"] += 1
    open(path, 'wb').write(d)
    return counts
