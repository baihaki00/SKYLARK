"""
Tools/Utilities/capture_16v16_feet.py
Automated Multi-Quin Locomotion & Turning Inspection Pipeline for 16v16 Battles.
Locks the camera onto the feet and legs of Quins actively running, turning, and chasing across the arena,
capturing burst frames to verify anatomical stride compliance, knee pole alignment, and zero joint twisting.
Outputs a detailed multi-frame filmstrip and animated GIF to the artifacts directory.
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


class MultiQuinFeetInspector:
    def __init__(self):
        self.client = RobloxStudioClient()

    def set_camera(self, cam_pos, look_pos):
        code = f"""
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
        return "Camera set"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def release_camera(self):
        code = """
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CameraOverrideActive", false)
        return "Camera released"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def toggle_huds(self, enabled=False):
        code = f"""
        local lp = game:GetService("Players").LocalPlayer
        if lp and lp:FindFirstChild("PlayerGui") then
            for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and (gui.Name:find("HUD") or gui.Name:find("Spectator") or gui.Name:find("Quin") or gui.Name:find("AnimationLab")) then
                    gui.Enabled = {str(enabled).lower()}
                end
            end
        end
        return "HUDs toggled"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def capture_frame(self, frame_idx=0):
        res = self.client.screen_capture(capture_id=f"FeetCap_{frame_idx}_{int(time.time()*1000)}")
        content = res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                data = item.get("data", "")
                img_bytes = base64.b64decode(data)
                return Image.open(io.BytesIO(img_bytes)).convert("RGB")
        return None

    def find_active_quin(self):
        """Finds a Quin in QuinGhost that is currently moving or turning."""
        code = """
        local Workspace = game:GetService("Workspace")
        local HttpService = game:GetService("HttpService")
        local qg = Workspace:FindFirstChild("QuinGhost")
        if not qg then return "{}" end

        local best = nil
        local maxScore = -1

        for _, ghost in ipairs(qg:GetChildren()) do
            local hrp = ghost:FindFirstChild("HumanoidRootPart")
            local lf = ghost:FindFirstChild("mixamorig:LeftFoot", true)
            local rf = ghost:FindFirstChild("mixamorig:RightFoot", true)
            local lk = ghost:FindFirstChild("mixamorig:LeftLeg", true)
            local rk = ghost:FindFirstChild("mixamorig:RightLeg", true)

            if hrp and lf and rf and lk and rk then
                local baseName = ghost.Name:gsub("_Visual", "")
                local aiModel = Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(baseName) or Workspace:FindFirstChild(baseName)
                local simHrp = aiModel and aiModel:FindFirstChild("HumanoidRootPart") or hrp
                local vel = simHrp.AssemblyLinearVelocity
                local angVel = simHrp.AssemblyAngularVelocity
                local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
                local turnRate = math.abs(angVel.Y)
                local state = aiModel and aiModel:GetAttribute("CurrentState") or "Unknown"
                local elem = aiModel and aiModel:GetAttribute("Element") or "Unknown"

                -- Strictly select ground locomotion runners and turners (Chase or Circling)
                local isGroundLoco = (state == "Chase" or state == "Circling")
                if isGroundLoco and hrp.Position.Y < 12.0 and speed > 8.0 then
                    -- Score running and turning heavily
                    local score = speed + (turnRate * 20.0)
                    if state == "Chase" then score = score + 15 end

                    if score > maxScore then
                        maxScore = score
                        local lookVec = hrp.CFrame.LookVector
                        local rightVec = hrp.CFrame.RightVector
                        best = {
                            name = baseName,
                            ghostName = ghost.Name,
                            state = state,
                            elem = elem,
                            speed = speed,
                            turnRate = angVel.Y,
                            score = score,
                            pos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
                            look = { lookVec.X, lookVec.Y, lookVec.Z },
                            right = { rightVec.X, rightVec.Y, rightVec.Z },
                            lfPos = { lf.TransformedWorldCFrame.Position.X, lf.TransformedWorldCFrame.Position.Y, lf.TransformedWorldCFrame.Position.Z },
                            rfPos = { rf.TransformedWorldCFrame.Position.X, rf.TransformedWorldCFrame.Position.Y, rf.TransformedWorldCFrame.Position.Z },
                            lkPos = { lk.TransformedWorldCFrame.Position.X, lk.TransformedWorldCFrame.Position.Y, lk.TransformedWorldCFrame.Position.Z },
                            rkPos = { rk.TransformedWorldCFrame.Position.X, rk.TransformedWorldCFrame.Position.Y, rk.TransformedWorldCFrame.Position.Z },
                        }
                    end
                end
            end
        end

        return HttpService:JSONEncode(best or {})
        """
        res = self.client.execute_luau(code, datamodel_type="Client")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            return json.loads(txt)
        except Exception:
            return {}

    def get_quin_telemetry(self, ghost_name):
        code = f"""
        local Workspace = game:GetService("Workspace")
        local HttpService = game:GetService("HttpService")
        local qg = Workspace:FindFirstChild("QuinGhost")
        local ghost = qg and qg:FindFirstChild("{ghost_name}")
        if not ghost then return "{{}}" end

        local hrp = ghost:FindFirstChild("HumanoidRootPart")
        local lf = ghost:FindFirstChild("mixamorig:LeftFoot", true)
        local rf = ghost:FindFirstChild("mixamorig:RightFoot", true)
        local lk = ghost:FindFirstChild("mixamorig:LeftLeg", true)
        local rk = ghost:FindFirstChild("mixamorig:RightLeg", true)

        if not (hrp and lf and rf and lk and rk) then return "{{}}" end

        local baseName = ghost.Name:gsub("_Visual", "")
        local aiModel = Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(baseName) or Workspace:FindFirstChild(baseName)
        local simHrp = aiModel and aiModel:FindFirstChild("HumanoidRootPart") or hrp
        local vel = simHrp.AssemblyLinearVelocity
        local angVel = simHrp.AssemblyAngularVelocity
        local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        local lookVec = hrp.CFrame.LookVector
        local rightVec = hrp.CFrame.RightVector

        local reactionCtrl = _G.GhostReactionControllers and _G.GhostReactionControllers[ghost]
        local telem = reactionCtrl and reactionCtrl:getTelemetry() or {{}}

        local data = {{
            name = baseName,
            ghostName = ghost.Name,
            state = aiModel and aiModel:GetAttribute("CurrentState") or "Unknown",
            elem = aiModel and aiModel:GetAttribute("Element") or "Unknown",
            speed = speed,
            turnRate = angVel.Y,
            pos = {{ hrp.Position.X, hrp.Position.Y, hrp.Position.Z }},
            look = {{ lookVec.X, lookVec.Y, lookVec.Z }},
            right = {{ rightVec.X, rightVec.Y, rightVec.Z }},
            lfPos = {{ lf.TransformedWorldCFrame.Position.X, lf.TransformedWorldCFrame.Position.Y, lf.TransformedWorldCFrame.Position.Z }},
            rfPos = {{ rf.TransformedWorldCFrame.Position.X, rf.TransformedWorldCFrame.Position.Y, rf.TransformedWorldCFrame.Position.Z }},
            lkPos = {{ lk.TransformedWorldCFrame.Position.X, lk.TransformedWorldCFrame.Position.Y, lk.TransformedWorldCFrame.Position.Z }},
            rkPos = {{ rk.TransformedWorldCFrame.Position.X, rk.TransformedWorldCFrame.Position.Y, rk.TransformedWorldCFrame.Position.Z }},
            telem = telem
        }}
        return HttpService:JSONEncode(data)
        """
        res = self.client.execute_luau(code, datamodel_type="Client")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            return json.loads(txt)
        except Exception:
            return {}

    def run_tracking_capture(self, num_frames=8, fps=4):
        print("=== Multi-Quin 16v16 Feet & Locomotion Inspection ===")
        self.toggle_huds(False)

        # 1. Find a prime candidate Quin currently moving / chasing
        quin = self.find_active_quin()
        if not quin or not quin.get("ghostName"):
            print("No active Quin found, retrying...")
            time.sleep(1.0)
            quin = self.find_active_quin()

        if not quin:
            print("ERROR: Still no Quin found in QuinGhost.")
            return

        ghost_name = quin["ghostName"]
        print(f"Tracking Quin: {quin['name']} ({quin['elem']}) in State: {quin['state']}, Speed: {quin['speed']:.1f} studs/s, Turn: {quin['turnRate']:.2f} rad/s")

        frames = []
        telemetries = []
        interval = 1.0 / fps

        for i in range(num_frames):
            t_start = time.time()
            data = self.get_quin_telemetry(ghost_name)
            current_state = data.get("state")
            current_spd = data.get("speed", 0.0)

            # If current tracked Quin stopped running or transitioned to Fight, dynamically re-acquire an active runner/turner
            if not data or not data.get("pos") or current_state not in ("Chase", "Circling") or current_spd < 8.0:
                new_q = self.find_active_quin()
                if new_q and new_q.get("ghostName"):
                    ghost_name = new_q["ghostName"]
                    data = self.get_quin_telemetry(ghost_name)

            if data and data.get("pos"):
                pos = data["pos"]
                look = data.get("look", [0, 0, 1])
                right = data.get("right", [1, 0, 0])

                # Close-up athletic 3/4 low camera focused directly on feet and toes
                look_pos = [pos[0], pos[1] - 4.3, pos[2]]
                cam_pos = [
                    pos[0] + (right[0] * 3.6) - (look[0] * 2.4),
                    pos[1] - 3.3,
                    pos[2] + (right[2] * 3.6) - (look[2] * 2.4)
                ]

                self.set_camera(cam_pos, look_pos)
                time.sleep(0.08) # small settle time for camera update

                img = self.capture_frame(i)
                if img:
                    frames.append(img)
                    telemetries.append(data)

            elapsed = time.time() - t_start
            sleep_time = max(0, interval - elapsed)
            if sleep_time > 0:
                time.sleep(sleep_time)

        self.release_camera()
        self.toggle_huds(True)

        if not frames:
            print("ERROR: No frames captured.")
            return

        print(f"Captured {len(frames)} frames. Generating contact sheet & filmstrip...")

        # Annotate frames with live biomechanical telemetry
        annotated_frames = []
        for idx, (img, t) in enumerate(zip(frames, telemetries)):
            annotated = self.annotate_frame(img, t, idx + 1)
            annotated_frames.append(annotated)

        # Output paths
        gif_path = os.path.join(ARTIFACT_DIR, "16v16_running_feet.gif")
        filmstrip_path = os.path.join(ARTIFACT_DIR, "16v16_running_feet_filmstrip.png")

        # Save animated GIF
        annotated_frames[0].save(
            gif_path,
            save_all=True,
            append_images=annotated_frames[1:],
            duration=int(interval * 1000),
            loop=0
        )
        print(f"Saved GIF: {gif_path}")

        # Build horizontal filmstrip
        self.build_filmstrip(annotated_frames, telemetries, filmstrip_path)
        print(f"Saved filmstrip: {filmstrip_path}")

    def annotate_frame(self, img, t, frame_num):
        annotated = img.copy()
        draw = ImageDraw.Draw(annotated)

        try:
            font_title = ImageFont.truetype("arialbd.ttf", 15)
            font_small = ImageFont.truetype("arial.ttf", 11)
        except Exception:
            font_title = ImageFont.load_default()
            font_small = ImageFont.load_default()

        # Header Badge
        header_text = f"Snapshot #{frame_num} | {t.get('name', 'Quin')} ({t.get('elem', '?')}) | State: {t.get('state', '?')}"
        draw.rectangle([8, 8, 480, 28], fill=(15, 20, 30, 220))
        draw.text((12, 10), header_text, font=font_title, fill=(0, 220, 255))

        # Biomechanical Telemetry Overlay
        speed = t.get("speed", 0.0)
        turn = t.get("turnRate", 0.0)
        lf = t.get("lfPos", [0, 0, 0])
        rf = t.get("rfPos", [0, 0, 0])
        telem = t.get("telem", {})
        if not isinstance(telem, dict):
            telem = {}
        foot_telem = telem.get("footIK", {})
        if not isinstance(foot_telem, dict):
            foot_telem = {}
        l_w = foot_telem.get("leftWeight", 0.0)
        r_w = foot_telem.get("rightWeight", 0.0)
        hips_dip = foot_telem.get("hipsDip", 0.0)
        l_toe_flex = foot_telem.get("leftToeFlexDeg", 0.0)
        r_toe_flex = foot_telem.get("rightToeFlexDeg", 0.0)

        lines = [
            f"Speed: {speed:.1f} studs/s | AngVel Y: {turn:.2f} rad/s",
            f"Left Foot Y: {lf[1]:.2f} (IK: {l_w:.2f}, ToeFlex: {l_toe_flex:.1f}°) | Right: {rf[1]:.2f} (IK: {r_w:.2f}, ToeFlex: {r_toe_flex:.1f}°)",
            f"Pelvis Dip: {hips_dip:.2f} studs | Toe Anti-Penetration Active"
        ]

        draw.rectangle([8, img.height - 58, 520, img.height - 8], fill=(15, 20, 30, 220))
        y_off = img.height - 54
        for line in lines:
            draw.text((12, y_off), line, font=font_small, fill=(200, 240, 255))
            y_off += 15

        return annotated

    def build_filmstrip(self, frames, telemetries, output_path):
        if not frames:
            return

        w, h = frames[0].size
        n = len(frames)
        header_h = 36
        thumb_w = 480
        thumb_h = int(h * (thumb_w / w))

        total_w = thumb_w * n
        total_h = thumb_h + header_h

        strip = Image.new("RGB", (total_w, total_h), (12, 16, 24))
        draw = ImageDraw.Draw(strip)

        try:
            font = ImageFont.truetype("arialbd.ttf", 13)
        except Exception:
            font = ImageFont.load_default()

        for idx, frame in enumerate(frames):
            resized = frame.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            x_pos = idx * thumb_w
            strip.paste(resized, (x_pos, header_h))

            # Header label
            t = telemetries[idx] if idx < len(telemetries) else {}
            lbl = f"Frame {idx + 1} ({t.get('state', '?')})"
            draw.text((x_pos + 8, 10), lbl, font=font, fill=(0, 220, 255))
            draw.line([(x_pos, 0), (x_pos, total_h)], fill=(40, 50, 70), width=1)

        strip.save(output_path, "PNG")


if __name__ == "__main__":
    inspector = MultiQuinFeetInspector()
    inspector.run_tracking_capture(num_frames=6, fps=3)
