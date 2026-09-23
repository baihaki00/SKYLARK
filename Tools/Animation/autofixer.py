"""
Mixamo FBX Batch Auto-Fixer for Roblox (Generic)
================================================
Universal tool to auto-fix and scale ANY imported Mixamo animation for Roblox custom rigs.
Supports: Locomotion, Combat, Attacks, Blocks, Dodges, Landings, Falls, Jumps, Idles, Taunts.

For every FBX file in the folder, it creates a `<Name>_Fixed/` directory with 2 generic variants:
  1. `<Name>_InPlace[x0.044].fbx`:
     - Horizontal translation (X, Z) locked in-place (no forward/lateral sliding).
     - Vertical translation (Y) preserved (natural jump arcs, ducks, landing compression).
     - All bone rest positions and curves scaled by 0.044 to match Roblox stud proportions.
     
  2. `<Name>_NoHipsLocation[x0.044].fbx`:
     - Hips translation completely neutralized to rest pose (pure rotation only).
     - Ideal for Run, Walk, Sprint, Idle, and static Combat cycles where hips must remain pinned to root.
     - All bone rest positions scaled by 0.044.

Zero bone crippling: All bone rotations are bit-identical to the original Mixamo file (0.0000000000 delta).
"""

import os
import sys
import glob
import struct
import argparse

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
        if ptype == 'S':
            val = val.decode('utf-8', errors='replace')
        return ptype, val, None, pos + 4 + slen
    else:
        raise ValueError(f"Unknown prop type {ptype} at {pos}")

def find_fbx_animation_curves(data):
    ver = struct.unpack('<I', data[23:27])[0]
    is_64 = (ver >= 7500)
    
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
        
    pos = objects_node['prop_start']
    hips_id = None
    
    while pos < objects_node['end_offset']:
        nh = parse_node_header(data, pos, is_64)
        if not nh:
            pos += (8 if is_64 else 4)
            continue
            
        if nh['name'] == 'Model':
            ppos = nh['prop_start']
            model_id = struct.unpack('<q' if is_64 else '<i', data[ppos+1:ppos+1+(8 if is_64 else 4)])[0]
            _, model_name, _, _ = read_property_raw(data, ppos+1+(8 if is_64 else 4))
            if 'Hips' in str(model_name):
                hips_id = model_id
                
        pos = nh['end_offset']
        
    if not hips_id:
        raise ValueError("Could not find mixamorig:Hips model in FBX")
        
    pos = connections_node['prop_start']
    conn_map = {}
    
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
            conn_map.setdefault(parent_id, []).append((child_id, prop_name))
                    
        pos = nh['end_offset']
        
    hips_t_node_id = None
    if hips_id in conn_map:
        for child_id, prop_name in conn_map[hips_id]:
            if prop_name == 'Lcl Translation':
                hips_t_node_id = child_id
                break
                
    if not hips_t_node_id:
        raise ValueError("Could not find Lcl Translation AnimCurveNode on Hips")
        
    curve_ids = {}
    if hips_t_node_id in conn_map:
        for child_id, prop_name in conn_map[hips_t_node_id]:
            if prop_name in ('d|X', 'd|Y', 'd|Z'):
                curve_ids[prop_name] = child_id
                
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
                    cpos = nh['pos']
                    kvf_pos = data.find(b'KeyValueFloat', cpos, nh['end_offset'])
                    if kvf_pos != -1:
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
        
    return is_64, curves_info

def scale_lcl_translations(data, scale):
    pos = 0
    scaled_count = 0
    hips_rest_y_scaled = 0.0
    
    while True:
        pos = data.find(b'Lcl Translation', pos)
        if pos == -1: break
        if pos >= 5 and data[pos-5] == ord('S'):
            str_len = struct.unpack('<I', data[pos-4:pos])[0]
            if str_len == 15:
                cur = pos + 15
                valid = True
                for _ in range(3):
                    if cur >= len(data) or data[cur] != ord('S'):
                        valid = False
                        break
                    slen = struct.unpack('<I', data[cur+1:cur+5])[0]
                    cur += 5 + slen
                if valid and cur + 27 <= len(data):
                    if data[cur] == ord('D') and data[cur+9] == ord('D') and data[cur+18] == ord('D'):
                        v1 = struct.unpack('<d', data[cur+1:cur+9])[0]
                        v2 = struct.unpack('<d', data[cur+10:cur+18])[0]
                        v3 = struct.unpack('<d', data[cur+19:cur+27])[0]
                        
                        sv1 = v1 * scale
                        sv2 = v2 * scale
                        sv3 = v3 * scale
                        
                        if abs(v2 - 99.79) < 10.0:
                            hips_rest_y_scaled = sv2
                            
                        data[cur+1:cur+9] = struct.pack('<d', sv1)
                        data[cur+10:cur+18] = struct.pack('<d', sv2)
                        data[cur+19:cur+27] = struct.pack('<d', sv3)
                        scaled_count += 1
                        pos = cur + 27
                        continue
        pos += 15
        
    return scaled_count, hips_rest_y_scaled

def process_fbx_file(input_fbx, scale=0.044, force=False):
    dir_name = os.path.dirname(os.path.abspath(input_fbx))
    file_name = os.path.basename(input_fbx)
    base_name, _ = os.path.splitext(file_name)
    
    target_folder = os.path.join(dir_name, f"{base_name}_Fixed")
    out_inplace = os.path.join(target_folder, f"{base_name}_InPlace[x{scale}].fbx")
    out_noloc = os.path.join(target_folder, f"{base_name}_NoHipsLocation[x{scale}].fbx")
    
    # Check if already processed
    if not force and os.path.exists(out_inplace) and os.path.exists(out_noloc):
        src_mtime = os.path.getmtime(input_fbx)
        out_inplace_mtime = os.path.getmtime(out_inplace)
        out_noloc_mtime = os.path.getmtime(out_noloc)
        
        if out_inplace_mtime >= src_mtime and out_noloc_mtime >= src_mtime:
            print(f"  [SKIPPED] {file_name} -> Already up-to-date in {os.path.basename(target_folder)}/")
            return False
            
    os.makedirs(target_folder, exist_ok=True)
    print(f"\n=======================================================")
    print(f"Processing: {file_name}")
    print(f"Target Folder: {os.path.basename(target_folder)}/")
    print(f"=======================================================")
    
    with open(input_fbx, 'rb') as f:
        orig_bytes = bytearray(f.read())
        
    is_64, curves_info = find_fbx_animation_curves(orig_bytes)
    if 'd|X' not in curves_info or 'd|Y' not in curves_info or 'd|Z' not in curves_info:
        raise ValueError("Could not find all 3 Hips translation curves in this FBX")
        
    for k in ('d|X', 'd|Y', 'd|Z'):
        if curves_info[k]['enc'] != 0:
            raise ValueError(f"Curve {k} is zlib-compressed (enc=1). Binary byte patcher requires uncompressed FBX curves.")
            
    count = curves_info['d|X']['arr_len']
    x_start = curves_info['d|X']['data_start']
    y_start = curves_info['d|Y']['data_start']
    z_start = curves_info['d|Z']['data_start']
    
    x_vals = list(struct.unpack(f'<{count}f', orig_bytes[x_start:x_start + count*4]))
    y_vals = list(struct.unpack(f'<{count}f', orig_bytes[y_start:y_start + count*4]))
    z_vals = list(struct.unpack(f'<{count}f', orig_bytes[z_start:z_start + count*4]))
    
    # -------------------------------------------------------------
    # 1. GENERATE: <Name>_InPlace[x0.044].fbx
    # (X, Z locked to 0.0 at root origin; Y height dynamics preserved; scaled to 0.044)
    # -------------------------------------------------------------
    data_inplace = bytearray(orig_bytes)
    scaled_bones, _ = scale_lcl_translations(data_inplace, scale)
    
    # Strictly center horizontal root translation to (0.0, 0.0).
    # Clamping to vals[0] risks freezing animations clipped mid-stride/leap at arbitrary offsets.
    new_x = [0.0] * count
    new_y = [v * scale for v in y_vals]
    new_z = [0.0] * count
    
    data_inplace[x_start:x_start + count*4] = struct.pack(f'<{count}f', *new_x)
    data_inplace[y_start:y_start + count*4] = struct.pack(f'<{count}f', *new_y)
    data_inplace[z_start:z_start + count*4] = struct.pack(f'<{count}f', *new_z)
    
    with open(out_inplace, 'wb') as f:
        f.write(data_inplace)
    print(f"  [1/2] Created In-Place (Vertical Preserved): {os.path.basename(out_inplace)}")
    
    # -------------------------------------------------------------
    # 2. GENERATE: <Name>_NoHipsLocation[x0.044].fbx
    # (X, Y, Z locked to rest pose; scaled to 0.044)
    # -------------------------------------------------------------
    data_noloc = bytearray(orig_bytes)
    _, hips_rest_y = scale_lcl_translations(data_noloc, scale)
    
    zero_x = [0.0] * count
    zero_y = [hips_rest_y] * count
    zero_z = [0.0] * count
    
    data_noloc[x_start:x_start + count*4] = struct.pack(f'<{count}f', *zero_x)
    data_noloc[y_start:y_start + count*4] = struct.pack(f'<{count}f', *zero_y)
    data_noloc[z_start:z_start + count*4] = struct.pack(f'<{count}f', *zero_z)
    
    with open(out_noloc, 'wb') as f:
        f.write(data_noloc)
    print(f"  [2/2] Created No Hips Location (Root Locked): {os.path.basename(out_noloc)}")
    return True

def main():
    parser = argparse.ArgumentParser(description="Universal Mixamo FBX Auto-Fixer for Roblox.")
    parser.add_argument('inputs', nargs='*', help="Optional specific FBX files to process")
    parser.add_argument('--scale', type=float, default=0.044, help="Rig scale factor (default: 0.044)")
    parser.add_argument('--force', action='store_true', help="Force re-processing even if already up to date")
    args = parser.parse_args()
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    if args.inputs:
        target_files = args.inputs
    else:
        all_fbx = glob.glob(os.path.join(script_dir, "*.fbx"))
        target_files = [
            f for f in all_fbx 
            if not f.endswith("_InPlace[x0.044].fbx")
            and not f.endswith("_NoHipsLocation[x0.044].fbx")
            and not f.endswith("_HeroLanding_Planted[x0.044].fbx")
            and not f.endswith("_Fixed.fbx")
            and not f.endswith("[x0.044].fbx")
            and not f.endswith("_Planted.fbx")
            and not f.endswith("test.fbx")
        ]
        
    if not target_files:
        print("No raw FBX files found in this directory to process.")
        return
        
    print(f"Found {len(target_files)} FBX file(s) to check.")
    processed_count = 0
    skipped_count = 0
    
    for fbx_path in target_files:
        try:
            was_processed = process_fbx_file(fbx_path, scale=args.scale, force=args.force)
            if was_processed:
                processed_count += 1
            else:
                skipped_count += 1
        except Exception as e:
            print(f"  ERROR processing {os.path.basename(fbx_path)}: {e}")
            
    print("\n=======================================================")
    if processed_count > 0:
        print(f"Finished! Newly fixed: {processed_count}, Already up-to-date: {skipped_count}.")
    else:
        print(f"All {skipped_count} animation(s) are already up-to-date. Zero duplicate work!")
    print("=======================================================")

if __name__ == '__main__':
    main()
