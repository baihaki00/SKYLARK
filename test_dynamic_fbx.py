import struct
import zlib
import os
import sys

def parse_node_header(data, pos, is_64):
    if is_64:
        if pos + 25 > len(data): return None
        end_offset, num_props, prop_len, name_len = struct.unpack('<QQQ B', data[pos:pos+25])
        header_len = 25
    else:
        if pos + 13 > len(data): return None
        end_offset, num_props, prop_len, name_len = struct.unpack('<III B', data[pos:pos+13])
        header_len = 13
    if end_offset == 0:
        return None
    name = data[pos+header_len:pos+header_len+name_len].decode('ascii', errors='replace')
    return {
        'pos': pos,
        'end_offset': end_offset,
        'num_props': num_props,
        'prop_len': prop_len,
        'name_len': name_len,
        'header_len': header_len,
        'name': name,
        'prop_start': pos + header_len + name_len
    }

def read_property_raw(data, pos):
    ptype = chr(data[pos])
    pos += 1
    if ptype in ('Y', 'C'):
        return ptype, None, None, pos + (2 if ptype == 'Y' else 1)
    elif ptype in ('I', 'F'):
        return ptype, None, None, pos + 4
    elif ptype in ('D', 'L'):
        return ptype, None, None, pos + 8
    elif ptype in ('f', 'd', 'l', 'i', 'b', 'c'):
        arr_len, enc, comp_len = struct.unpack('<III', data[pos:pos+12])
        data_start = pos + 12
        return ptype, arr_len, (enc, data_start, comp_len), pos + 12 + comp_len
    elif ptype in ('S', 'R'):
        slen = struct.unpack('<I', data[pos:pos+4])[0]
        val = data[pos+4:pos+4+slen]
        return ptype, val, None, pos + 4 + slen
    else:
        raise ValueError(f"Unknown prop type {ptype} at {pos}")

def find_fbx_animation_curves(data):
    ver = struct.unpack('<I', data[23:27])[0]
    is_64 = (ver >= 7500)
    
    # 1. Scan root nodes to find Objects and Connections
    pos = 27
    objects_node = None
    connections_node = None
    
    while pos < len(data):
        nh = parse_node_header(data, pos, is_64)
        if not nh: break
        if nh['name'] == 'Objects':
            objects_node = nh
        elif nh['name'] == 'Connections':
            connections_node = nh
        pos = nh['end_offset']
        
    if not objects_node or not connections_node:
        raise ValueError("Could not locate Objects or Connections nodes in FBX")
        
    # 2. Parse Connections to locate mixamorig:Hips -> T AnimCurveNode -> d|X, d|Y, d|Z
    # We first scan Objects to find Model mixamorig:Hips ID
    pos = objects_node['prop_start']
    hips_id = None
    anim_curve_nodes = {}
    
    while pos < objects_node['end_offset']:
        nh = parse_node_header(data, pos, is_64)
        if not nh:
            pos += (8 if is_64 else 4)
            continue
            
        if nh['name'] == 'Model':
            # read props to get ID and Name
            ppos = nh['prop_start']
            _, model_id, _, ppos = read_property_raw(data, ppos) # Prop 0 is ID (L)
            # unpack id
            model_id = struct.unpack('<q' if is_64 else '<i', data[nh['prop_start']+1:nh['prop_start']+1+(8 if is_64 else 4)])[0]
            # check name
            sub = data[ppos:ppos+50]
            if b'Hips' in sub:
                hips_id = model_id
                
        elif nh['name'] == 'AnimationCurveNode':
            acn_id = struct.unpack('<q' if is_64 else '<i', data[nh['prop_start']+1:nh['prop_start']+1+(8 if is_64 else 4)])[0]
            # read name
            _, name_val, _, _ = read_property_raw(data, nh['prop_start']+1+(8 if is_64 else 4))
            anim_curve_nodes[acn_id] = name_val
            
        pos = nh['end_offset']
        
    if not hips_id:
        raise ValueError("Could not find mixamorig:Hips model in FBX")
        
    # 3. Parse Connections
    pos = connections_node['prop_start']
    hips_t_node_id = None
    curve_ids = {} # 'd|X': id, 'd|Y': id, 'd|Z': id
    
    while pos < connections_node['end_offset']:
        nh = parse_node_header(data, pos, is_64)
        if not nh:
            pos += (8 if is_64 else 4)
            continue
            
        if nh['name'] == 'C':
            ppos = nh['prop_start']
            _, ctype, _, ppos = read_property_raw(data, ppos)
            child_id = struct.unpack('<q' if is_64 else '<i', data[ppos+1:ppos+1+(8 if is_64 else 4)])[0]
            ppos += 1 + (8 if is_64 else 4)
            parent_id = struct.unpack('<q' if is_64 else '<i', data[ppos+1:ppos+1+(8 if is_64 else 4)])[0]
            ppos += 1 + (8 if is_64 else 4)
            prop_name = None
            if ppos < nh['end_offset']:
                _, prop_name, _, _ = read_property_raw(data, ppos)
                if isinstance(prop_name, bytes):
                    prop_name = prop_name.decode('ascii', errors='replace')
                    
            if parent_id == hips_id and prop_name == 'Lcl Translation':
                hips_t_node_id = child_id
            elif hips_t_node_id and parent_id == hips_t_node_id:
                if prop_name in ('d|X', 'd|Y', 'd|Z'):
                    curve_ids[prop_name] = child_id
                    
        pos = nh['end_offset']
        
    # 4. Find the AnimationCurve objects for these curve IDs and get KeyValueFloat info
    curves_info = {}
    pos = objects_node['prop_start']
    while pos < objects_node['end_offset']:
        nh = parse_node_header(data, pos, is_64)
        if not nh:
            pos += (8 if is_64 else 4)
            continue
            
        if nh['name'] == 'AnimationCurve':
            cid = struct.unpack('<q' if is_64 else '<i', data[nh['prop_start']+1:nh['prop_start']+1+(8 if is_64 else 4)])[0]
            for axis, target_id in curve_ids.items():
                if cid == target_id:
                    # search KeyValueFloat inside this node
                    cpos = nh['pos']
                    kvf_pos = data.find(b'KeyValueFloat', cpos, nh['end_offset'])
                    if kvf_pos != -1:
                        # inspect KeyValueFloat prop
                        knh = parse_node_header(data, kvf_pos - (25 if is_64 else 13), is_64)
                        ptype, arr_len, (enc, dstart, clen), _ = read_property_raw(data, knh['prop_start'])
                        curves_info[axis] = {
                            'cid': cid,
                            'arr_len': arr_len,
                            'enc': enc,
                            'data_start': dstart,
                            'data_len': clen
                        }
        pos = nh['end_offset']
        
    return is_64, hips_id, curves_info

# Quick test
with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx', 'rb') as f:
    data = f.read()
is_64, hips_id, cinfo = find_fbx_animation_curves(data)
print("Dynamic Detection Test:")
print(f"  is_64: {is_64}, hips_id: {hips_id}")
for axis, info in cinfo.items():
    print(f"  Axis {axis}: data_start={info['data_start']}, arr_len={info['arr_len']}, enc={info['enc']}")
