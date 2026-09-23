#// capture_close_up_spectacle.py
# Spawns a demonstrator Quin directly in front of the camera, executes knockback,
# and captures: 1) Aerial Flight Tilt & Muscle Ragdoll, 2) Ground Skid with Rooster Tail, 3) Smooth Get-Up

import time
import json
import base64
import os
from PIL import Image, ImageDraw, ImageFont
from roblox_client import RobloxStudioClient

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Setup demonstrator Quin at origin
    setup_code = """
    local QuinSpawner = require(game:GetService("ServerScriptService"):WaitForChild("QuinSpawner"))
    local quinServer = workspace:FindFirstChild("QuinServer")
    local quinGhost = workspace:FindFirstChild("QuinGhost")

    -- Clean arena for clear cinematic view
    QuinSpawner.cleanAll()
    if quinGhost then
        for _, g in ipairs(quinGhost:GetChildren()) do g:Destroy() end
    end
    task.wait(0.3)

    -- Ensure AIGhostHandler runner is active
    local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    local ghostScript = sp and sp:FindFirstChild("AIGhostHandler")
    if ghostScript then
        task.spawn(loadstring(ghostScript.Source))
    end

    -- Spawn demonstrator facing +Z at (0, 8.5, 0)
    local demoQuin = QuinSpawner.spawn("TypeA", Vector3.new(0, 8.5, 0), "TeamAlpha", nil, Vector3.new(0, 8.5, 50))
    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.5)

    return {
        name = demoQuin.Name,
        pos = tostring(demoQuin.HumanoidRootPart.Position)
    }
    """

    res = client.execute_luau(setup_code, "Edit")
    info = json.loads(res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    quin_name = info.get("name")
    print(f"Spawned demonstrator: {quin_name} at {info.get('pos')}")

    # Camera settings: side profile to showcase flight tilt, wind spine flex, and ground slide
    # Demo quin will be launched backward from (0, 8.5, 0) along -Z towards (0, 8.5, -60)
    # Camera at (24, 14, -25) looking at (0, 10, -25)
    cam_pos = [26, 14, -25]
    look_pos = [0, 9.5, -25]

    # 2. Trigger spectacle aerial knockback launch!
    launch_code = f"""
    local target = workspace.QuinServer:FindFirstChild("{quin_name}")
    local hrp = target.HumanoidRootPart
    local hum = target.Humanoid

    target:SetAttribute("KnockbackType", "air")
    target:SetAttribute("ForceState", "Knockback")
    target:SetAttribute("LaunchedAt", tick())
    hum.PlatformStand = true

    -- Launch backward along -Z: speed 75 studs/s horizontal, 42 studs/s vertical
    hrp.AssemblyLinearVelocity = Vector3.new(0, 42, -75)
    return "Launched"
    """

    client.execute_luau(launch_code, "Edit")
    print("Launched demonstrator!")

    # 3. Capture Frame 1: Mid-Air Aerodynamic Flight Tilt & Active Muscle Ragdoll
    time.sleep(0.18)
    res_flight = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "Spectacle_1_Flight",
        "camera_position": cam_pos,
        "look_at_position": look_pos
    })

    # 4. Capture Frame 2: Kinetic Ground Skid & Dust Rooster Tail
    time.sleep(0.38)
    res_skid = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "Spectacle_2_Skid",
        "camera_position": cam_pos,
        "look_at_position": look_pos
    })

    # 5. Capture Frame 3: Critically Damped Upright Get-Up Recovery
    time.sleep(0.35)
    res_recovery = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "Spectacle_3_Recovery",
        "camera_position": cam_pos,
        "look_at_position": look_pos
    })

    client.close()

    # Save images and compile triptych
    captures = [
        ("Phase 1: Aerial Trajectory Flight Tilt (55° Backward Pitch)", res_flight),
        ("Phase 2: Kinetic Ground Skid (Exponential Friction & Rooster Tail)", res_skid),
        ("Phase 3: Supine Get-Up (Critically Damped AlignOrientation)", res_recovery)
    ]

    saved_imgs = []
    artifact_dir = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

    for title, c_res in captures:
        content = c_res.get("result", {}).get("content", [{}])[0]
        b64 = content.get("data")
        if b64:
            raw = base64.b64decode(b64)
            img_path = os.path.join(artifact_dir, f"temp_{len(saved_imgs)}.jpg")
            with open(img_path, "wb") as f:
                f.write(raw)
            saved_imgs.append((title, Image.open(img_path)))

    if len(saved_imgs) == 3:
        print("\nAssembling step4_spectacle_sequence.png...")
        w, h = saved_imgs[0][1].size
        banner_h = 42
        card_w = w
        card_h = h + banner_h

        # Horizontal 3-panel strip
        strip = Image.new("RGB", (card_w * 3, card_h), (18, 22, 28))
        draw = ImageDraw.Draw(strip)

        try:
            font = ImageFont.truetype("arialbd.ttf", 22)
        except Exception:
            font = ImageFont.load_default()

        for idx, (title, img) in enumerate(saved_imgs):
            gx = idx * card_w
            # Banner
            draw.rectangle([gx, 0, gx + card_w, banner_h], fill=(28, 34, 44))
            draw.text((gx + 20, 10), title, fill=(240, 245, 255), font=font)
            # Image
            strip.paste(img, (gx, banner_h))

        out_path = os.path.join(artifact_dir, "step4_spectacle_sequence.png")
        strip.save(out_path, quality=95)
        print("SUCCESS! Saved:", out_path)

if __name__ == "__main__":
    main()
