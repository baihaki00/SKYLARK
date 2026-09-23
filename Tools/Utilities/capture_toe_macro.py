"""
Tools/Utilities/capture_toe_macro.py
Captures ultra close-up macro frames of Quin feet and toes making contact with the arena floor
to verify zero ground penetration/sinking.
"""

import os
import sys
import time
import json
import base64
import io
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"


def run_toe_macro():
    client = RobloxStudioClient()

    # Query active running or walking Quin
    code = """
    local Workspace = game:GetService("Workspace")
    local HttpService = game:GetService("HttpService")
    local qg = Workspace:FindFirstChild("QuinGhost")
    local qs = Workspace:FindFirstChild("QuinServer")
    if not qg then return "{}" end

    local best = nil
    local maxScore = -1

    for _, ghost in ipairs(qg:GetChildren()) do
        local hrp = ghost:FindFirstChild("HumanoidRootPart")
        local baseName = ghost.Name:gsub("_Visual", "")
        local aiModel = qs and qs:FindFirstChild(baseName) or Workspace:FindFirstChild(baseName)
        local simHrp = aiModel and aiModel:FindFirstChild("HumanoidRootPart") or hrp
        local vel = simHrp.AssemblyLinearVelocity
        local spd = Vector3.new(vel.X, 0, vel.Z).Magnitude
        local state = aiModel and aiModel:GetAttribute("CurrentState") or "Unknown"

        if (state == "Chase" or state == "Circling") and spd > 10.0 and hrp.Position.Y < 12.0 then
            local lf = ghost:FindFirstChild("mixamorig:LeftFoot", true)
            local rf = ghost:FindFirstChild("mixamorig:RightFoot", true)
            local lt = ghost:FindFirstChild("mixamorig:LeftToeBase", true)
            local rt = ghost:FindFirstChild("mixamorig:RightToeBase", true)

            if lf and rf and lt and rt then
                local score = spd
                if score > maxScore then
                    maxScore = score
                    best = {
                        name = baseName,
                        ghostName = ghost.Name,
                        state = state,
                        spd = spd,
                        pos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
                        look = { hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z },
                        right = { hrp.CFrame.RightVector.X, hrp.CFrame.RightVector.Y, hrp.CFrame.RightVector.Z },
                        lfPos = { lf.TransformedWorldCFrame.Position.X, lf.TransformedWorldCFrame.Position.Y, lf.TransformedWorldCFrame.Position.Z },
                        rfPos = { rf.TransformedWorldCFrame.Position.X, rf.TransformedWorldCFrame.Position.Y, rf.TransformedWorldCFrame.Position.Z },
                        ltPos = { lt.TransformedWorldCFrame.Position.X, lt.TransformedWorldCFrame.Position.Y, lt.TransformedWorldCFrame.Position.Z },
                        rtPos = { rt.TransformedWorldCFrame.Position.X, rt.TransformedWorldCFrame.Position.Y, rt.TransformedWorldCFrame.Position.Z },
                    }
                end
            end
        end
    end

    return HttpService:JSONEncode(best or {})
    """

    # Hide UI HUDs
    client.execute_luau("""
        local lp = game:GetService("Players").LocalPlayer
        if lp and lp:FindFirstChild("PlayerGui") then
            for _, g in ipairs(lp.PlayerGui:GetChildren()) do
                if g:IsA("ScreenGui") then g.Enabled = false end
            end
        end
        return "UI hidden"
    """, datamodel_type="Client")

    frames = []
    telemetries = []

    print("=== Capturing Macro Toe-to-Ground Contact Frames ===")
    for i in range(5):
        res = client.execute_luau(code, datamodel_type="Client")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            data = json.loads(txt)
        except Exception:
            data = {}

        if data and data.get("pos"):
            pos = data["pos"]
            look = data.get("look", [0, 0, 1])
            right = data.get("right", [1, 0, 0])
            lf = data.get("lfPos", [pos[0], pos[1] - 4.8, pos[2]])
            rf = data.get("rfPos", [pos[0], pos[1] - 4.8, pos[2]])

            # Choose the lower foot (the one making ground contact)
            ground_foot = lf if lf[1] <= rf[1] else rf

            # Camera 2.2 studs from the foot at ground level (~0.5 studs above floor)
            look_pos = [ground_foot[0], ground_foot[1] - 0.1, ground_foot[2]]
            cam_pos = [
                ground_foot[0] + (right[0] * 2.2) - (look[0] * 1.2),
                ground_foot[1] + 0.4,
                ground_foot[2] + (right[2] * 2.2) - (look[2] * 1.2)
            ]

            cam_code = f"""
            local ws = game:GetService("Workspace")
            ws:SetAttribute("CameraOverrideActive", true)
            ws:SetAttribute("CamPosX", {cam_pos[0]})
            ws:SetAttribute("CamPosY", {cam_pos[1]})
            ws:SetAttribute("CamPosZ", {cam_pos[2]})
            ws:SetAttribute("CamLookX", {look_pos[0]})
            ws:SetAttribute("CamLookY", {look_pos[1]})
            ws:SetAttribute("CamLookZ", {look_pos[2]})
            if ws.CurrentCamera then
                ws.CurrentCamera.CFrame = CFrame.lookAt(
                    Vector3.new({cam_pos[0]}, {cam_pos[1]}, {cam_pos[2]}),
                    Vector3.new({look_pos[0]}, {look_pos[1]}, {look_pos[2]})
                )
            end
            return "Cam set"
            """
            client.execute_luau(cam_code, datamodel_type="Client")
            time.sleep(0.08)

            cap = client.screen_capture(capture_id=f"ToeMacro_{i}_{int(time.time()*1000)}")
            content = cap.get("result", {}).get("content", [])
            for item in content:
                if item.get("type") == "image":
                    img_bytes = base64.b64decode(item.get("data", ""))
                    img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
                    frames.append(img)
                    telemetries.append(data)
                    break
        time.sleep(0.25)

    # Release camera and restore UI
    client.execute_luau("""
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CameraOverrideActive", false)
        local lp = game:GetService("Players").LocalPlayer
        if lp and lp:FindFirstChild("PlayerGui") then
            for _, g in ipairs(lp.PlayerGui:GetChildren()) do
                if g:IsA("ScreenGui") then g.Enabled = true end
            end
        end
        return "Cam released"
    """, datamodel_type="Client")

    if not frames:
        print("ERROR: No macro frames captured.")
        return

    # Build filmstrip
    n = len(frames)
    w, h = frames[0].size
    thumb_w = 540
    thumb_h = int(h * (thumb_w / w))
    strip = Image.new("RGB", (thumb_w * n, thumb_h + 36), (12, 16, 24))
    draw = ImageDraw.Draw(strip)

    try:
        font = ImageFont.truetype("arialbd.ttf", 13)
    except Exception:
        font = ImageFont.load_default()

    for idx, (frame, t) in enumerate(zip(frames, telemetries)):
        resized = frame.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x_pos = idx * thumb_w
        strip.paste(resized, (x_pos, 36))
        lbl = f"Macro #{idx+1} | {t.get('name','')} | {t.get('state','')} ({t.get('spd',0):.1f} s/s)"
        draw.text((x_pos + 8, 10), lbl, font=font, fill=(0, 220, 255))
        draw.line([(x_pos, 0), (x_pos, thumb_h + 36)], fill=(40, 50, 70), width=1)

    out_path = os.path.join(ARTIFACT_DIR, "toe_ground_contact_filmstrip.png")
    strip.save(out_path, "PNG")
    print(f"Saved macro toe filmstrip: {out_path}")


if __name__ == "__main__":
    run_toe_macro()
