import struct
import zlib

def read_node(f, is_64):
    if is_64:
        header_fmt = '<QQQ B'
        header_size = 25
    else:
        header_fmt = '<III B'
        header_size = 13
        
    buf = f.read(header_size)
    if len(buf) < header_size:
        return None
    end_offset, num_props, prop_len, name_len = struct.unpack(header_fmt, buf)
    if end_offset == 0:
        return None # Null node marking end of children
        
    name = f.read(name_len).decode('ascii', errors='replace')
    
    props = []
    for _ in range(num_props):
        prop_type = f.read(1).decode('ascii')
        if prop_type == 'Y':
            val = struct.unpack('<h', f.read(2))[0]
        elif prop_type == 'C':
            val = struct.unpack('<?', f.read(1))[0]
        elif prop_type == 'I':
            val = struct.unpack('<i', f.read(4))[0]
        elif prop_type == 'F':
            val = struct.unpack('<f', f.read(4))[0]
        elif prop_type == 'D':
            val = struct.unpack('<d', f.read(8))[0]
        elif prop_type == 'L':
            val = struct.unpack('<q', f.read(8))[0]
        elif prop_type in ('f', 'd', 'l', 'i', 'b', 'c'):
            arr_len, enc, comp_len = struct.unpack('<III', f.read(12))
            raw_data = f.read(comp_len)
            if enc == 1:
                raw_data = zlib.decompress(raw_data)
            val = (prop_type, arr_len, raw_data)
        elif prop_type in ('S', 'R'):
            str_len = struct.unpack('<I', f.read(4))[0]
            val = f.read(str_len)
            if prop_type == 'S':
                val = val.decode('utf-8', errors='replace')
        else:
            raise ValueError(f"Unknown property type {prop_type} at {f.tell()}")
        props.append(val)
        
    children = []
    while f.tell() < end_offset:
        child = read_node(f, is_64)
        if child is None:
            # Null record
            break
        children.append(child)
        
    f.seek(end_offset)
    return {'name': name, 'props': props, 'children': children}

with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx', 'rb') as f:
    f.seek(23)
    ver = struct.unpack('<I', f.read(4))[0]
    is_64 = (ver >= 7500)
    print(f"FBX version: {ver}, is_64: {is_64}")
    
    root_nodes = []
    while True:
        pos = f.tell()
        node = read_node(f, is_64)
        if node is None:
            break
        root_nodes.append(node)
        print(f"Root Node: {node['name']}, children: {len(node['children'])}, props: {len(node['props'])}")
