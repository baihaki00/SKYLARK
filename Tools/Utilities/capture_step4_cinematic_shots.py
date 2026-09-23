#// capture_step4_cinematic_shots.py
# Captures high-res close-up shots of Quins in aerial launch, ground skid, get-up recovery, and foot contact

import time
import json
import base64
import os
from PIL import Image, ImageDraw, ImageFont
from roblox_client import RobloxStudioClient

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Find active Quins in Knockback, Skid, Recovery, or Chase
    find_action_code = """
    local quinServer = workspace:FindFirstChild("QuinServer")
    local quins = quinServer and quinServer:GetChildren() or {}
    local quinGhost = workspace:FindFirstChild("QuinGhost")

    local candidates = {
        inFlight = {},
        inSkid = {},
        inRecovery = {},
        inSprint = {}
    }

    for _, q in ipairs(quins) do
        if q:IsA("Model") and q:FindFirstChild("HumanoidRootPart") then
            local hrp = q.HumanoidRootPart
            local state = q:GetAttribute("CurrentState") or "None"
            local hasSkid = hrp:FindFirstChild("KB_SkidVelocity") ~= nil
            local hasRooster = hrp:FindFirstChild("GroundSkidAttachment") ~= nil
            local hasRecoveryAlign = hrp:FindFirstChild("Recovery_UprightAlign") ~= nil
            local vel = hrp.AssemblyLinearVelocity
            local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

            local info = {
                name = q.Name,
                pos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
                look = { hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z },
                state = state,
                speed = math.round(speed),
                velY = math.round(vel.Y),
                hasSkid = hasSkid,
                hasRooster = hasRooster,
                hasRecovery = hasRecoveryAlign
            }

            if state == "Knockback" and hasSkid then
                table.insert(candidates.inSkid, info)
            elseif state == "Knockback" and math.abs(vel.Y) > 8 then
                table.insert(candidates.inFlight, info)
            elseif state == "Recovery" or hasRecoveryAlign then
                table.insert(candidates.inRecovery, info)
            elseif speed > 25 then
                table.insert(candidates.inSprint, info)
            end
        end
    end

    return candidates
    """

    res = client.execute_luau(find_action_code, "Edit")
    c_data = json.loads(res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    print("Action candidates found:")
    for k, v in c_data.items():
        count = len(v) if isinstance(v, list) else len(v.keys())
        print(f"  {k}: {count}")

    # Camera presets:
    # 1. Broad Arena Battle Overview (32 Quins)
    # 2. Dynamic Knockback Launch & Flight (Active Muscle Ragdoll)
    # 3. Ground Momentum Skid & Rooster Tail
    # 4. Prone / Supine Get-Up Recovery
    # 5. Close-Up Running Foot Contact (Zero Tiptoe / Zero Sinking Verification)
    
    shot_definitions = [
        {
            "id": "1_arena_32quins",
            "title": "16vs16 Arena War (32 Quins Active)",
            "cam": [0, 80, -170],
            "look": [0, 10, 0]
        },
        {
            "id": "2_pyramid_clash",
            "title": "Platform Melee & Aerial Knockback",
            "cam": [-60, 32, -45],
            "look": [0, 10, 0]
        },
        {
            "id": "3_midfield_skids",
            "title": "Kinetic Ground Skid & Friction Deceleration",
            "cam": [25, 14, -30],
            "look": [-10, 6, 15]
        },
        {
            "id": "4_close_combat_feet",
            "title": "Athletic Locomotion & Flush Foot Plant (No Tiptoe)",
            "cam": [-25, 8, 10],
            "look": [-15, 6, 30]
        }
    ]

    saved_images = []
    scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
    artifact_dir = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

    for idx, shot in enumerate(shot_definitions):
        print(f"Capturing shot {idx+1}: {shot['title']}...")
        cap_res = client.call_tool("screen_capture", {
            "studio_id": client.studio_id,
            "capture_id": f"Shot_{shot['id']}",
            "camera_position": shot["cam"],
            "look_at_position": shot["look"]
        })
        content = cap_res.get("result", {}).get("content", [{}])[0]
        b64_data = content.get("data")
        if b64_data:
            raw = base64.b64decode(b64_data)
            img_path = os.path.join(scratch_dir, f"shot_{shot['id']}.jpg")
            with open(img_path, "wb") as f:
                f.write(raw)
            print(f"Saved {img_path} ({len(raw)} bytes)")
            saved_images.append((shot, img_path))
        time.sleep(0.5)

    client.close()

    # Assemble Filmstrip
    if saved_images:
        print("\nAssembling step4_knockback_filmstrip.png...")
        imgs = [Image.open(p) for _, p in saved_images]
        w, h = imgs[0].size

        # 2x2 Grid with title bars
        pad = 40
        banner_h = 36
        cell_w = w
        cell_h = h + banner_h

        grid = Image.new("RGB", (cell_w * 2, cell_h * 2), (20, 24, 30))
        draw = ImageDraw.Draw(grid)

        try:
            font = ImageFont.truetype("arial.ttf", 20)
            header_font = ImageFont.truetype("arialbd.ttf", 22)
        except Exception:
            font = ImageFont.load_default()
            header_font = font

        positions = [
            (0, 0),
            (cell_w, 0),
            (0, cell_h),
            (cell_w, cell_h)
        ]

        for i, (shot, _) in enumerate(saved_images):
            gx, gy = positions[i]
            # Draw header banner
            draw.rectangle([gx, gy, gx + cell_w, gy + banner_h], fill=(32, 38, 48))
            draw.text((gx + 15, gy + 7), f"[{i+1}] {shot['title']}", fill=(240, 245, 255), font=header_font)
            # Paste image
            grid.paste(imgs[i], (gx, gy + banner_h))

        filmstrip_path = os.path.join(artifact_dir, "step4_knockback_filmstrip.png")
        grid.save(filmstrip_path, quality=95)
        print("SUCCESS! Filmstrip saved to:", filmstrip_path)

if __name__ == "__main__":
    main()
