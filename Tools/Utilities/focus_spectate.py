import sys
import json
import time
import base64
import os

sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local qServer = workspace:FindFirstChild("QuinServer")
local q = qServer and qServer:FindFirstChild("Quin_TypeC_D186")
if not q and qServer then
    q = qServer:GetChildren()[1]
end
if q then
    workspace:SetAttribute("SpectatedQuin", q.Name)
    shared.SpectatedQuin = q
    _G.SpectatedQuin = q
    local hum = q:FindFirstChildOfClass("Humanoid")
    if hum then
        workspace.CurrentCamera.CameraSubject = hum
    end
    return q.Name
end
return "None"
"""
res = client.execute_luau(code, datamodel_type="Client")
print("Set spectated Quin:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

time.sleep(0.5)

# Now capture screenshot from the camera's current position and look direction
cap_code = """
local cam = workspace.CurrentCamera
local cf = cam.CFrame
return game:GetService("HttpService"):JSONEncode({
    pos = {cf.Position.X, cf.Position.Y, cf.Position.Z},
    look = {cf.Position.X + cf.LookVector.X * 20, cf.Position.Y + cf.LookVector.Y * 20, cf.Position.Z + cf.LookVector.Z * 20}
})
"""
res_cam = client.execute_luau(cap_code, datamodel_type="Client")
cam_info = json.loads(res_cam.get("result", {}).get("content", [{}])[0].get("text", "{}"))
print("Camera info:", cam_info)

if "pos" in cam_info:
    cap_res = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_SpectatingQuin",
        "camera_position": cam_info["pos"],
        "look_at_position": cam_info["look"]
    })
    filepath = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_spectating_quin.png"
    if cap_res and not cap_res.get("isError", False):
        content = cap_res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(filepath, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved spectated screenshot to {filepath} ({len(img_data)} bytes)")
                break

client.close()
