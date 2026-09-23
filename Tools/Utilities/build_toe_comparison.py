"""
Create a side-by-side comparison of the user's reported toe sinking vs the verified non-sinking toe.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"
user_img_path = os.path.join(ARTIFACT_DIR, ".user_uploaded", "media_1790121146101.png")
macro_strip_path = os.path.join(ARTIFACT_DIR, "toe_ground_contact_filmstrip.png")
out_path = os.path.join(ARTIFACT_DIR, "toe_fix_comparison.png")

user_img = Image.open(user_img_path).convert("RGB")
macro_strip = Image.open(macro_strip_path).convert("RGB")

# Crop Frame #4 from macro strip (thumb_w = 540)
# Frame #4 is from x = 1620 to 2160
w, h = macro_strip.size
frame4 = macro_strip.crop((1620, 36, 2160, h))

# Crop directly on the feet in frame 4
f_w, f_h = frame4.size
feet_crop = frame4.crop((int(f_w * 0.35), int(f_h * 0.10), int(f_w * 0.70), int(f_h * 0.85)))

# Target height 360
target_h = 360

# Resize user img to target_h preserving aspect ratio
u_w, u_h = user_img.size
user_resized = user_img.resize((int(u_w * (target_h / u_h)), target_h), Image.Resampling.LANCZOS)

# Resize feet crop to target_h
c_w, c_h = feet_crop.size
feet_resized = feet_crop.resize((int(c_w * (target_h / c_h)), target_h), Image.Resampling.LANCZOS)

total_w = user_resized.width + feet_resized.width + 16
total_h = target_h + 50

comp = Image.new("RGB", (total_w, total_h), (14, 18, 26))
draw = ImageDraw.Draw(comp)

try:
    font = ImageFont.truetype("arialbd.ttf", 15)
except Exception:
    font = ImageFont.load_default()

# Paste user img
comp.paste(user_resized, (0, 50))
draw.text((12, 16), "BEFORE: Toe Clipping & Sinking", font=font, fill=(255, 90, 90))

# Paste verified img
x_offset = user_resized.width + 16
comp.paste(feet_resized, (x_offset, 50))
draw.text((x_offset + 12, 16), "AFTER: Toe Flexion & Flush Contact", font=font, fill=(0, 230, 180))

comp.save(out_path, "PNG")
print(f"Comparison saved: {out_path}")
