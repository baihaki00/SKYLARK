import struct
import zlib

with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx', 'rb') as f:
    data = f.read()

def inspect_curve_node(offset, label):
    print(f"\n=== Inspecting {label} around offset {offset} ===")
    # The ID was found at `offset`. In FBX 7700:
    # A node starts 25 bytes before its properties:
    # end_offset (uint64), num_props (uint64), prop_len (uint64), name_len (uint8), name...
    # Let's search backward for 'AnimationCurve'
    name_pos = data.rfind(b'AnimationCurve', 0, offset)
    node_start = name_pos - 25 # 8 + 8 + 8 + 1 = 25
    end_offset, num_props, prop_len, name_len = struct.unpack('<QQQ B', data[node_start:node_start+25])
    print(f"Node start: {node_start}, End offset: {end_offset}, num_props: {num_props}, prop_len: {prop_len}")
    
    # Let's find KeyValueFloat child node inside this range [node_start, end_offset]
    kvf_pos = data.find(b'KeyValueFloat', node_start, end_offset)
    print(f"KeyValueFloat found at: {kvf_pos}")
    kvf_start = kvf_pos - 25
    k_end, k_np, k_plen, k_nlen = struct.unpack('<QQQ B', data[kvf_start:kvf_start+25])
    print(f"KeyValueFloat node: start={kvf_start}, end={k_end}, num_props={k_np}, prop_len={k_plen}")
    
    # Property starts at kvf_pos + 13 ('KeyValueFloat' is 13 chars)
    prop_start = kvf_pos + 13
    prop_type = chr(data[prop_start])
    arr_len, enc, comp_len = struct.unpack('<III', data[prop_start+1:prop_start+13])
    print(f"Prop type: {prop_type}, Array len: {arr_len}, Encoding: {enc}, Comp len: {comp_len}")
    
    raw = data[prop_start+13:prop_start+13+comp_len]
    if enc == 1:
        raw = zlib.decompress(raw)
    floats = struct.unpack(f'<{arr_len}f', raw)
    print(f"Values ({len(floats)}): Start={floats[0]:.4f}, End={floats[-1]:.4f}, Min={min(floats):.4f}, Max={max(floats):.4f}")
    return {
        'kvf_start': kvf_start,
        'prop_start': prop_start,
        'data_start': prop_start + 13,
        'comp_len': comp_len,
        'enc': enc,
        'arr_len': arr_len,
        'values': list(floats)
    }

c_x = inspect_curve_node(73578, 'd|X')
c_y = inspect_curve_node(74938, 'd|Y')
c_z = inspect_curve_node(76298, 'd|Z')
