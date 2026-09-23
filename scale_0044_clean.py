import sys
sys.path.append(r'C:\Users\User\.gemini\antigravity\scratch')
import struct
from parse_fbx import read_node

# Let's inspect the exact byte offsets of all Lcl Translation properties
with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down_HeroLanding_Planted.fbx', 'rb') as f:
    orig_data = bytearray(f.read())

scale = 0.044
patched = bytearray(orig_data)

# 1. Scale KeyValueFloat arrays for Hips Translation (d|X, d|Y, d|Z)
for offset in [74388, 75748, 77108]:
    floats = list(struct.unpack('<76f', orig_data[offset:offset + 304]))
    scaled_floats = [v * scale for v in floats]
    patched[offset:offset + 304] = struct.pack('<76f', *scaled_floats)
    print(f"Scaled KVF at {offset}: {floats[0]:.4f} -> {scaled_floats[0]:.4f}")

# 2. Scale Lcl Translation in Properties70
# In FBX binary Properties70, each property is stored as a 'P' node:
# Node name: 'P'
# Props:
#   0: 'Lcl Translation' (String)
#   1: 'Compound' or other type string
#   2: ''
#   3: 'A'
#   4: double X
#   5: double Y
#   6: double Z
# Let's find each 'Lcl Translation' string exactly and verify its following props
pos = 0
count = 0
while True:
    pos = orig_data.find(b'Lcl Translation', pos)
    if pos == -1:
        break
    
    # Check if this is preceded by property string header: length 15 (0x0F, 0x00, 0x00, 0x00) and type 'S'
    if pos >= 5 and orig_data[pos-5] == ord('S'):
        str_len = struct.unpack('<I', orig_data[pos-4:pos])[0]
        if str_len == 15:
            # Found a Property named 'Lcl Translation'!
            # Now let's inspect the next properties following this string
            cur = pos + 15
            # Read next 3 string properties (props 1, 2, 3)
            valid = True
            for _ in range(3):
                if cur >= len(orig_data) or orig_data[cur] != ord('S'):
                    valid = False
                    break
                slen = struct.unpack('<I', orig_data[cur+1:cur+5])[0]
                cur += 5 + slen
                
            if valid and cur + 27 <= len(orig_data):
                # Now should be 3 doubles: 'D', 8 bytes, 'D', 8 bytes, 'D', 8 bytes
                if orig_data[cur] == ord('D') and orig_data[cur+9] == ord('D') and orig_data[cur+18] == ord('D'):
                    v1 = struct.unpack('<d', orig_data[cur+1:cur+9])[0]
                    v2 = struct.unpack('<d', orig_data[cur+10:cur+18])[0]
                    v3 = struct.unpack('<d', orig_data[cur+19:cur+27])[0]
                    
                    sv1, sv2, sv3 = v1 * scale, v2 * scale, v3 * scale
                    patched[cur+1:cur+9] = struct.pack('<d', sv1)
                    patched[cur+10:cur+18] = struct.pack('<d', sv2)
                    patched[cur+19:cur+27] = struct.pack('<d', sv3)
                    count += 1
                    if count <= 5 or any(abs(v) > 1.0 for v in (v1, v2, v3)):
                        print(f"  [{count:2d}] Lcl Translation at {cur}: ({v1:.2f}, {v2:.2f}, {v3:.2f}) -> ({sv1:.4f}, {sv2:.4f}, {sv3:.4f})")
                    pos = cur + 27
                    continue

    pos += 15

print(f"\nSuccessfully scaled {count} bone Lcl Translations by {scale}!")

out_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_HeroLanding_Planted[x0.044].fbx'
with open(out_path, 'wb') as f:
    f.write(patched)
print(f"Saved: {out_path} ({len(patched)} bytes)")
