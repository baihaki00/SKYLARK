import struct

src_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_HeroLanding_Planted.fbx'
with open(src_path, 'rb') as f:
    data = bytearray(f.read())

scale = 0.044

# 1. Scale KeyValueFloat arrays for Hips Translation (d|X, d|Y, d|Z)
# Offsets:
# d|X: 74388
# d|Y: 75748
# d|Z: 77108

for offset in [74388, 75748, 77108]:
    floats = list(struct.unpack('<76f', data[offset:offset + 304]))
    scaled_floats = [v * scale for v in floats]
    data[offset:offset + 304] = struct.pack('<76f', *scaled_floats)
    print(f"Scaled offset {offset}: {floats[0]:.2f} -> {scaled_floats[0]:.4f}")

# 2. Also search and scale all Lcl Translation properties in Model nodes
# In FBX binary, 'Lcl Translation' property in Properties70 is stored as:
# string 'Lcl Translation' (15 bytes), followed by type strings, then 3 doubles ('D')!
# In FBX 7700 Properties70:
# Property name: 'Lcl Translation'
# type: 'Compound', 'p'
# values: double, double, double
pos = 0
count_lcl = 0
target_prop = b'Lcl Translation'
while True:
    pos = data.find(target_prop, pos)
    if pos == -1:
        break
    # In Properties70 child node 'P':
    # Name: 'Lcl Translation'
    # Following bytes have the property types and 3 doubles (8 bytes each = 24 bytes)
    # Let's inspect the bytes right after 'Lcl Translation'
    sub = data[pos:pos+100]
    # Let's find where the 3 doubles are: search for type marker 'D'
    # In FBX: prop is 'S' (Lcl Translation), 'S' (Compound/type), 'S' (''), 'S' ('A'), 'D' (val1), 'D' (val2), 'D' (val3)
    d_pos = sub.find(b'D')
    if d_pos != -1:
        abs_d_pos = pos + d_pos
        # Check if there are 3 consecutive 'D's or 'D' followed by 8 bytes, 'D', 8 bytes, 'D', 8 bytes
        if abs_d_pos + 27 <= len(data):
            t1 = chr(data[abs_d_pos])
            t2 = chr(data[abs_d_pos + 9])
            t3 = chr(data[abs_d_pos + 18])
            if t1 == 'D' and t2 == 'D' and t3 == 'D':
                v1 = struct.unpack('<d', data[abs_d_pos+1:abs_d_pos+9])[0]
                v2 = struct.unpack('<d', data[abs_d_pos+10:abs_d_pos+18])[0]
                v3 = struct.unpack('<d', data[abs_d_pos+19:abs_d_pos+27])[0]
                
                # Scale the doubles
                sv1, sv2, sv3 = v1 * scale, v2 * scale, v3 * scale
                data[abs_d_pos+1:abs_d_pos+9] = struct.pack('<d', sv1)
                data[abs_d_pos+10:abs_d_pos+18] = struct.pack('<d', sv2)
                data[abs_d_pos+19:abs_d_pos+27] = struct.pack('<d', sv3)
                count_lcl += 1
                if any(abs(v) > 1e-3 for v in (v1, v2, v3)):
                    print(f"  Scaled Lcl Translation at {abs_d_pos}: ({v1:.2f}, {v2:.2f}, {v3:.2f}) -> ({sv1:.4f}, {sv2:.4f}, {sv3:.4f})")
    pos += len(target_prop)

print(f"Total Lcl Translations scaled: {count_lcl}")

out_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_HeroLanding_Planted[x0.044].fbx'
with open(out_path, 'wb') as f:
    f.write(data)
print(f"Saved: {out_path} ({len(data)} bytes)")
