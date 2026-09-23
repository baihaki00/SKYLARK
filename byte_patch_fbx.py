import struct

src_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx'
with open(src_path, 'rb') as f:
    orig_bytes = bytearray(f.read())

# Exact byte offsets determined from node inspection:
# KeyValueFloat data starts at prop_start + 13:
# d|X: 74362 + 13 + 13 = 74388
# d|Y: 75722 + 13 + 13 = 75748
# d|Z: 77082 + 13 + 13 = 77108

x_start_offset = 74388
y_start_offset = 75748
z_start_offset = 77108

# Read original values
x_vals = list(struct.unpack('<76f', orig_bytes[x_start_offset:x_start_offset + 304]))
y_vals = list(struct.unpack('<76f', orig_bytes[y_start_offset:y_start_offset + 304]))
z_vals = list(struct.unpack('<76f', orig_bytes[z_start_offset:z_start_offset + 304]))

print("Original Start -> End:")
print(f"  X: {x_vals[0]:.4f} -> {x_vals[-1]:.4f}")
print(f"  Y: {y_vals[0]:.4f} -> {y_vals[-1]:.4f}")
print(f"  Z: {z_vals[0]:.4f} -> {z_vals[-1]:.4f}")

# ---------------------------------------------------------
# 1. PURE IN-PLACE HORIZONTAL (Z and X locked, Y untouched)
# ---------------------------------------------------------
bytes_horiz = bytearray(orig_bytes)

# Lock X to start value
new_x = [x_vals[0]] * 76
bytes_horiz[x_start_offset:x_start_offset + 304] = struct.pack('<76f', *new_x)

# Lock Z to start value
new_z = [z_vals[0]] * 76
bytes_horiz[z_start_offset:z_start_offset + 304] = struct.pack('<76f', *new_z)

out_horiz_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_Pure_InPlace_Horizontal.fbx'
with open(out_horiz_path, 'wb') as f:
    f.write(bytes_horiz)
print(f"Created: {out_horiz_path} ({len(bytes_horiz)} bytes)")

# ---------------------------------------------------------
# 2. PURE IN-PLACE FULL (Z and X locked, Y ledge drop normalized)
# ---------------------------------------------------------
bytes_full = bytearray(orig_bytes)
bytes_full[x_start_offset:x_start_offset + 304] = struct.pack('<76f', *new_x)
bytes_full[z_start_offset:z_start_offset + 304] = struct.pack('<76f', *new_z)

# Normalize Y:
# y_vals[0] is 130.8208 (on ledge)
# y_vals[-1] is 44.8098 (on ground)
delta_y = y_vals[-1] - y_vals[0] # -86.0110
new_y = []
for i in range(76):
    f_num = i + 1 # 1-based frame
    if f_num <= 28:
        offset = 0.0
    elif f_num >= 46:
        offset = -delta_y # +86.0110
    else:
        t = (f_num - 28.0) / (46.0 - 28.0)
        s = t * t * (3.0 - 2.0 * t) # smoothstep
        offset = -delta_y * s
    new_y.append(y_vals[i] + offset)

print(f"Normalized Y: Start={new_y[0]:.4f} -> End={new_y[-1]:.4f} (Net Delta = {new_y[-1] - new_y[0]:.4f})")
bytes_full[y_start_offset:y_start_offset + 304] = struct.pack('<76f', *new_y)

out_full_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_Pure_InPlace_Full.fbx'
with open(out_full_path, 'wb') as f:
    f.write(bytes_full)
print(f"Created: {out_full_path} ({len(bytes_full)} bytes)")
