"""
Minimal binary FBX reader/writer: parse into a node tree, change it, write it back. Property
payloads are kept as raw bytes unless replaced, so an untouched file writes back identically
(checked on the Mixamo template).
"""
import struct
import zlib

HEAD = b"Kaydara FBX Binary  \x00\x1a\x00"
FOOT_ID = b'\xfa\xbc\xab\x09\xd0\xc8\xd4\x66\xb1\x76\xfb\x83\x1c\xf7\x26\x7e'
FOOT_MAGIC = b'\xf8\x5a\x8c\x6a\xde\xf5\xd9\x7e\xec\xe9\x0c\xe3\x75\x8f\x29\x0b'

_SCALAR = {'Y': ('<h', 2), 'C': ('<B', 1), 'I': ('<i', 4), 'F': ('<f', 4), 'D': ('<d', 8), 'L': ('<q', 8)}
_ARRAY = {'f': ('f', 4), 'd': ('d', 8), 'l': ('q', 8), 'i': ('i', 4), 'b': ('B', 1)}


class Node:
    __slots__ = ("name", "props", "children", "nested")

    def __init__(self, name, props=None, children=None, nested=None):
        self.name = name
        self.props = props or []        # [(type, raw payload bytes)]
        self.children = children or []
        self.nested = bool(children) if nested is None else nested  # ends with a null record

    # --- property values ---
    def value(self, i):
        t, raw = self.props[i]
        if t in _SCALAR:
            return struct.unpack(_SCALAR[t][0], raw)[0]
        if t == 'S':
            return raw[4:].decode('utf-8', 'replace')
        if t == 'R':
            return raw[4:]
        if t in _ARRAY:
            n, enc, clen = struct.unpack('<III', raw[:12])
            data = raw[12:]
            if enc == 1:
                data = zlib.decompress(data)
            return list(struct.unpack('<%d%s' % (n, _ARRAY[t][0]), data))
        raise ValueError(t)

    def values(self):
        return [self.value(i) for i in range(len(self.props))]

    def set_scalar(self, i, v):
        t = self.props[i][0]
        self.props[i] = (t, struct.pack(_SCALAR[t][0], v))

    def set_array(self, i, values, t=None):
        t = t or self.props[i][0]
        code, size = _ARRAY[t]
        data = struct.pack('<%d%s' % (len(values), code), *values)
        self.props[i] = (t, struct.pack('<III', len(values), 0, len(data)) + data)

    def find(self, name):
        return next((c for c in self.children if c.name == name), None)

    def find_all(self, name):
        return [c for c in self.children if c.name == name]


def _parse(d, pos, end, v64):
    nodes = []
    while pos < end:
        if v64:
            e, n, plen, nlen = struct.unpack('<QQQB', d[pos:pos + 25]); h = 25
        else:
            e, n, plen, nlen = struct.unpack('<IIIB', d[pos:pos + 13]); h = 13
        if e == 0:
            return nodes, pos + h
        name = d[pos + h:pos + h + nlen].decode('ascii')
        p = pos + h + nlen
        props = []
        for _ in range(n):
            t = chr(d[p]); p += 1
            if t in _SCALAR:
                size = _SCALAR[t][1]
            elif t in 'SR':
                size = 4 + struct.unpack('<I', d[p:p + 4])[0]
            elif t in _ARRAY:
                size = 12 + struct.unpack('<III', d[p:p + 12])[2]
            else:
                raise ValueError("unknown property type %r" % t)
            props.append((t, bytes(d[p:p + size]))); p += size
        child_start = pos + h + nlen + plen
        nested = e > child_start
        children = _parse(d, child_start, e, v64)[0] if nested else []
        nodes.append(Node(name, props, children, nested))
        pos = e
    return nodes, pos


def read(path):
    d = open(path, 'rb').read()
    assert d[:23] == HEAD, "not a binary FBX"
    version = struct.unpack('<I', d[23:27])[0]
    nodes, _ = _parse(d, 27, len(d), version >= 7500)
    return version, nodes


def _size(node, v64):
    h = 25 if v64 else 13
    s = h + len(node.name) + sum(1 + len(raw) for _, raw in node.props)
    if node.nested:
        s += sum(_size(c, v64) for c in node.children) + h
    return s


def _write(out, node, v64, offset):
    h = 25 if v64 else 13
    end = offset + _size(node, v64)
    plen = sum(1 + len(raw) for _, raw in node.props)
    fmt = '<QQQB' if v64 else '<IIIB'
    out += struct.pack(fmt, end, len(node.props), plen, len(node.name)) + node.name.encode('ascii')
    for t, raw in node.props:
        out += t.encode('ascii') + raw
    if node.nested:
        pos = offset + h + len(node.name) + plen
        for c in node.children:
            _write(out, c, v64, pos)
            pos += _size(c, v64)
        out += b'\0' * h
    return end


def write(path, version, nodes):
    """(The footer follows Blender's writer, whose files Roblox imports; readers ignore it.)"""
    v64 = version >= 7500
    h = 25 if v64 else 13
    out = bytearray(HEAD + struct.pack('<I', version))
    for n in nodes:
        _write(out, n, v64, len(out))
    out += b'\0' * h
    out += FOOT_ID + b'\0' * 4
    pad = ((len(out) + 15) & ~15) - len(out)
    out += b'\0' * (pad or 16)
    out += struct.pack('<I', version) + b'\0' * 120 + FOOT_MAGIC
    open(path, 'wb').write(out)
