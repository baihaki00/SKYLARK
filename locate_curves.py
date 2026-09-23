import sys
import struct
import zlib

def locate_curves(fbx_path):
    with open(fbx_path, 'rb') as f:
        data = f.read()
        
    print(f"File size: {len(data)} bytes")
    
    # Let's search for the IDs in the byte stream
    target_ids = [258573632, 258567376, 258572208]
    names = {258573632: 'd|X', 258567376: 'd|Y', 258572208: 'd|Z'}
    
    for cid in target_ids:
        packed_id = struct.pack('<q', cid)
        pos = data.find(packed_id)
        print(f"ID {cid} ({names[cid]}): found at offset {pos} (0x{pos:X})")

locate_curves(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx')
