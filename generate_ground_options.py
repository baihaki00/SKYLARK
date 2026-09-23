import struct

src_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx'
with open(src_path, 'rb') as f:
    orig_bytes = bytearray(f.read())

x_start_offset = 74388
y_start_offset = 75748
z_start_offset = 77108

x_vals = list(struct.unpack('<76f', orig_bytes[x_start_offset:x_start_offset + 304]))
y_vals = list(struct.unpack('<76f', orig_bytes[y_start_offset:y_start_offset + 304]))
z_vals = list(struct.unpack('<76f', orig_bytes[z_start_offset:z_start_offset + 304]))

# -------------------------------------------------------------
# OPTION 1: Zero Location / Fixed Rest Pose (What YouTube tutorials do)
# X = 0, Z = 0, Y = 99.7919 (the exact rest pose Lcl Translation)
# This removes all translation delta so the hips NEVER leave the root.
# -------------------------------------------------------------
bytes_no_loc = bytearray(orig_bytes)
new_x_zero = [0.0] * 76
new_z_zero = [0.0] * 76
new_y_rest = [99.7919] * 76

bytes_no_loc[x_start_offset:x_start_offset + 304] = struct.pack('<76f', *new_x_zero)
bytes_no_loc[y_start_offset:y_start_offset + 304] = struct.pack('<76f', *new_y_rest)
bytes_no_loc[z_start_offset:z_start_offset + 304] = struct.pack('<76f', *new_z_zero)

out_no_loc = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_NoHipsLocation.fbx'
with open(out_no_loc, 'wb') as f:
    f.write(bytes_no_loc)
print(f"Created: {out_no_loc}")

# -------------------------------------------------------------
# OPTION 2: Ground-Anchored In-Place (Matching Jump.fbx baseline: 89.20)
# Start & Landing baseline = 89.20 (standard Mixamo standing height)
# Apex = Jump arc tuck relative to ground
# -------------------------------------------------------------
bytes_ground = bytearray(orig_bytes)
# X = 0, Z = 0
bytes_ground[x_start_offset:x_start_offset + 304] = struct.pack('<76f', *new_x_zero)
bytes_ground[z_start_offset:z_start_offset + 304] = struct.pack('<76f', *new_z_zero)

# In original Jumping Down:
# Ground landing baseline (frames 60-76) is 44.8098.
# In Jump.fbx, standing baseline is 89.20.
# The difference to align ground landing with standard standing height is:
# offset = 89.20 - 44.8098 = +44.3902
# And in the airborne phase, we compensate the ledge drop (-86.0110)
# so the character starts at 89.20 (standing on ground),
# leaps up into the air, and lands back at 89.20 (ground)!
new_y_ground = []
for i in range(76):
    f_num = i + 1
    # Original value
    val = y_vals[i]
    # In original: f1=130.82, f76=44.81 (delta = -86.01)
    # If normalized so f1 and f76 both align with landing baseline 44.81:
    if f_num <= 28:
        # Pre-jump: bring ledge down to ground baseline (subtract 86.01)
        val_norm = val - 86.0110
    elif f_num >= 46:
        # Ground landing: already at ground baseline
        val_norm = val
    else:
        # Airborne blend
        t = (f_num - 28.0) / (46.0 - 28.0)
        s = t * t * (3.0 - 2.0 * t)
        val_norm = val - 86.0110 * (1.0 - s)
        
    # Now val_norm has start=44.81 and end=44.81.
    # Now shift the entire curve up by +44.3902 so ground baseline is exactly 89.20 (matching Jump.fbx!):
    val_ground = val_norm + (89.20 - 44.8098)
    new_y_ground.append(val_ground)

print(f"Ground-Anchored Y: Start={new_y_ground[0]:.2f}, Apex={max(new_y_ground):.2f}, Landing={min(new_y_ground):.2f}, End={new_y_ground[-1]:.2f}")
bytes_ground[y_start_offset:y_start_offset + 304] = struct.pack('<76f', *new_y_ground)

out_ground = r'D:\SKYLARK\SKYLARKTEST\Jumping Down_GroundAnchored.fbx'
with open(out_ground, 'wb') as f:
    f.write(bytes_ground)
print(f"Created: {out_ground}")
