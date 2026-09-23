"""
Tools/Utilities/inspect_locomotion_cycle.py
Automated Multi-Frame Inspection & Diagnostic Pipeline for Quin Locomotion, Procedural Foot IK, and Active Ragdolls.
Captures burst frames directly from Roblox Studio, annotates stride scaling, angular velocity, and IK telemetry,
and outputs high-resolution filmstrip PNGs and animated GIFs to the artifacts directory.
"""

import os
import sys
import time
import json
import base64
import io
import argparse
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"


class LocomotionInspector:
    def __init__(self):
        self.client = RobloxStudioClient()
        self.studio_id = self.client.studio_id

    def set_camera(self, cam_pos, look_pos):
        code = f"""
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CamPosX", {cam_pos[0]})
        ws:SetAttribute("CamPosY", {cam_pos[1]})
        ws:SetAttribute("CamPosZ", {cam_pos[2]})
        ws:SetAttribute("CamLookX", {look_pos[0]})
        ws:SetAttribute("CamLookY", {look_pos[1]})
        ws:SetAttribute("CamLookZ", {look_pos[2]})
        ws:SetAttribute("CameraOverrideActive", true)
        shared.CameraOverrideCFrame = CFrame.lookAt(
            Vector3.new({cam_pos[0]}, {cam_pos[1]}, {cam_pos[2]}),
            Vector3.new({look_pos[0]}, {look_pos[1]}, {look_pos[2]})
        )
        return "Camera set"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def release_camera(self):
        code = """
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CameraOverrideActive", false)
        shared.CameraOverrideCFrame = nil
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

    def ensure_tester_rig(self):
        code = """
        local Workspace = game:GetService("Workspace")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local qs = Workspace:FindFirstChild("QuinServer") or Workspace
        local tester = qs:FindFirstChild("QuinA_Tester")

        if not tester then
            local GMM = _G.GameModeManager or shared.GameModeManager
            if GMM and GMM.startTestAnimationMode then
                GMM.startTestAnimationMode()
            end
        end
        return "Checked"
        """
        self.client.execute_luau(code, datamodel_type="Server")
        time.sleep(1.0)

    def trigger_maneuver(self, maneuver_name):
        action_map = {
            "sprint_180": ("RunLocomotionTest", "{ testType = 'Sprint180' }"),
            "plant_turn_90": ("RunLocomotionTest", "{ testType = 'PlantTurn90' }"),
            "arc_run": ("RunLocomotionTest", "{ testType = 'ArcRun' }"),
            "hard_brake": ("RunLocomotionTest", "{ testType = 'SprintBrake' }"),
            "ledge_step": ("RunLocomotionTest", "{ testType = 'LedgeStepTest' }"),
            "knockback_high": ("TestKnockbackLaunch", "{ style = 'high_arc' }"),
            "knockback_low": ("TestKnockbackLaunch", "{ style = 'low_smash' }"),
        }
        if maneuver_name not in action_map:
            return {"error": f"Unknown maneuver {maneuver_name}"}

        action, data_tbl = action_map[maneuver_name]
        code = f"""
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Events = ReplicatedStorage.QuinCore.Events
        local labEvent = Events:FindFirstChild("AnimationLabEvent")
        if labEvent then
            labEvent:FireServer("{action}", {data_tbl})
            return "Dispatched {action} via Client FireServer"
        end
        return "No labEvent found"
        """
        res = self.client.execute_luau(code, datamodel_type="Client")
        return res

    def get_tester_telemetry(self):
        code = """
        local HttpService = game:GetService("HttpService")
        local Workspace = game:GetService("Workspace")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local CombatConfig = require(ReplicatedStorage.QuinCore.CombatConfig)
        local AnimationModule = require(ReplicatedStorage.QuinCore.Modules.AnimationModule)

        local qs = Workspace:FindFirstChild("QuinServer") or Workspace
        local tester = qs:FindFirstChild("QuinA_Tester") or qs:FindFirstChildWhichIsA("Model")
        if not tester then
            return HttpService:JSONEncode({ error = "No tester found" })
        end

        local hrp = tester:FindFirstChild("HumanoidRootPart")
        local hum = tester:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then
            return HttpService:JSONEncode({ error = "Missing HRP or Humanoid" })
        end

        local linVel = hrp.AssemblyLinearVelocity
        local angVel = hrp.AssemblyAngularVelocity
        local horizSpeed = Vector3.new(linVel.X, 0, linVel.Z).Magnitude
        local strideScale = horizSpeed > 0.5 and (horizSpeed / (CombatConfig.RunStrideBase or 38.0)) or 1.0

        local lIK = hum:FindFirstChild("LeftFootIK")
        local rIK = hum:FindFirstChild("RightFootIK")
        local lAtt = hrp:FindFirstChild("LeftFootTargetAtt")
        local rAtt = hrp:FindFirstChild("RightFootTargetAtt")

        local gaitPhase = (AnimationModule and AnimationModule.getGaitPhase and hum) and AnimationModule.getGaitPhase(hum) or 0

        local rootJoint = hrp:FindFirstChild("RootJoint") or (tester:FindFirstChild("LowerTorso") and tester.LowerTorso:FindFirstChild("RootJoint"))
        local rjRoll = 0
        if rootJoint then
            local _, _, rz = rootJoint.C0:ToOrientation()
            rjRoll = math.deg(rz)
        end

        local lAttPos = lAtt and { lAtt.Position.X, lAtt.Position.Y, lAtt.Position.Z } or nil
        local rAttPos = rAtt and { rAtt.Position.X, rAtt.Position.Y, rAtt.Position.Z } or nil
        local hipsDip = tester:GetAttribute("HipsDipOffset") or 0

        local data = {
            name = tester.Name,
            pos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
            vel = { linVel.X, linVel.Y, linVel.Z },
            angVel = { angVel.X, angVel.Y, angVel.Z },
            speed = horizSpeed,
            strideScale = strideScale,
            rollDeg = math.abs(rjRoll) > 0.1 and rjRoll or hrp.Orientation.Z,
            gaitPhase = gaitPhase,
            isPlatformStand = hum.PlatformStand,
            footIK = {
                enabled = CombatConfig.FootIK_Enabled == true,
                leftWeight = lIK and lIK.Weight or 0,
                rightWeight = rIK and rIK.Weight or 0,
                leftPos = lAttPos,
                rightPos = rAttPos,
                hipsDip = hipsDip
            }
        }
        return HttpService:JSONEncode(data)
        """
        res = self.client.execute_luau(code, datamodel_type="Server")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            return json.loads(txt)
        except Exception:
            return {}

    def capture_frame(self, frame_idx=0):
        res = self.client.screen_capture(capture_id=f"LocoCap_{frame_idx}_{int(time.time()*1000)}")
        content = res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                data = item.get("data", "")
                img_bytes = base64.b64decode(data)
                return Image.open(io.BytesIO(img_bytes)).convert("RGB")
        return None

    def run_diagnostic(self, maneuver="sprint_180", duration=2.5, fps=8, out_name=None):
        out_name = out_name or f"diagnostic_{maneuver}"
        print(f"=== Starting Locomotion Inspection for '{maneuver}' ===")
        print(f"Duration: {duration}s @ {fps} fps ({int(duration * fps)} frames expected)")

        self.ensure_tester_rig()
        telem = self.get_tester_telemetry()
        pos = telem.get("pos", [0, 7.5, 0])
        print(f"QuinA_Tester position: {pos}")

        # Tailored camera positions per maneuver for optimal cinematic framing
        if maneuver == "sprint_180":
            cam_pos = [-24, 12, 0]
            look_pos = [0, 7.5, 0]
        elif maneuver == "plant_turn_90":
            cam_pos = [-24, 12, 10]
            look_pos = [0, 7.5, 5]
        elif maneuver == "arc_run":
            cam_pos = [-34, 22, 22]
            look_pos = [0, 7.5, 0]
        elif maneuver == "hard_brake":
            cam_pos = [-20, 11, 10]
            look_pos = [0, 7.5, 10]
        elif maneuver == "ledge_step":
            cam_pos = [-14, 10, 16]
            look_pos = [0.6, 5.0, 7.5]
        elif maneuver.startswith("knockback"):
            cam_pos = [-22, 13, 8]
            look_pos = [0, 8.0, 10]
        else:
            cam_pos = [pos[0] - 18, pos[1] + 8, pos[2] + 12]
            look_pos = [pos[0], pos[1] + 3, pos[2]]

        self.set_camera(cam_pos, look_pos)
        self.toggle_huds(False)
        time.sleep(0.3)

        # Trigger maneuver
        self.trigger_maneuver(maneuver)

        frames = []
        telemetries = []
        interval = 1.0 / fps
        start_time = time.time()

        while time.time() - start_time < duration:
            t0 = time.time()
            img = self.capture_frame()
            t_data = self.get_tester_telemetry()
            if img:
                frames.append(img)
                telemetries.append(t_data)
            dt = time.time() - t0
            sleep_time = max(0, interval - dt)
            if sleep_time > 0:
                time.sleep(sleep_time)

        # Restore camera & HUDs
        self.release_camera()
        self.toggle_huds(True)

        print(f"Captured {len(frames)} frames successfully.")
        if not frames:
            print("ERROR: No frames captured!")
            return

        # Build Annotated Filmstrip & GIF
        annotated_frames = []
        for i, (frame, t_data) in enumerate(zip(frames, telemetries)):
            draw = ImageDraw.Draw(frame)
            w, h = frame.size

            # Bottom overlay bar
            bar_height = 48
            overlay = Image.new("RGBA", (w, bar_height), (15, 20, 30, 210))
            frame.paste(overlay, (0, h - bar_height), overlay)

            speed = t_data.get("speed", 0.0)
            stride = t_data.get("strideScale", 1.0)
            roll = t_data.get("rollDeg", 0.0)
            gait = t_data.get("gaitPhase", 0.0)
            ik = t_data.get("footIK", {})
            ik_en = "ON" if ik.get("enabled") else "OFF"
            l_w = ik.get("leftWeight", 0.0)
            r_w = ik.get("rightWeight", 0.0)
            hips_dip = ik.get("hipsDip", 0.0)
            is_ps = t_data.get("isPlatformStand", False)

            line1 = f"FRAME #{i+1:02d} | Maneuver: {maneuver.upper()} | Speed: {speed:.1f} studs/s | StrideScale: {stride:.2f}x | TorsoBank: {roll:.1f}° | GaitPhase: {gait:.2f}"
            line2 = f"FootIK: {ik_en} (L_wt: {l_w:.2f}, R_wt: {r_w:.2f}) | HipsDip: {hips_dip:.2f} studs | PlatformStand: {is_ps} | HRP: ({t_data.get('pos', [0,0,0])[0]:.1f}, {t_data.get('pos', [0,0,0])[1]:.1f}, {t_data.get('pos', [0,0,0])[2]:.1f})"

            draw.text((10, h - bar_height + 6), line1, fill=(0, 220, 255))
            draw.text((10, h - bar_height + 26), line2, fill=(200, 230, 255))
            annotated_frames.append(frame)

        # 1. Save Animated GIF
        gif_path = os.path.join(ARTIFACT_DIR, f"{out_name}.gif")
        annotated_frames[0].save(
            gif_path,
            save_all=True,
            append_images=annotated_frames[1:],
            duration=int(interval * 1000),
            loop=0
        )
        print(f"Saved animated GIF: {gif_path}")

        # 2. Save Horizontal Filmstrip (select up to 7 evenly spaced frames)
        num_strip_frames = min(7, len(annotated_frames))
        indices = [int(i * (len(annotated_frames) - 1) / (num_strip_frames - 1)) for i in range(num_strip_frames)]
        strip_imgs = [annotated_frames[idx] for idx in indices]

        thumb_w, thumb_h = 320, 180
        filmstrip_w = thumb_w * num_strip_frames
        filmstrip_h = thumb_h + 30
        filmstrip = Image.new("RGB", (filmstrip_w, filmstrip_h), (12, 16, 24))
        draw_strip = ImageDraw.Draw(filmstrip)

        for j, img in enumerate(strip_imgs):
            resized = img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            filmstrip.paste(resized, (j * thumb_w, 30))
            frame_num = indices[j] + 1
            draw_strip.text((j * thumb_w + 10, 8), f"Snapshot #{j+1} (Frame {frame_num})", fill=(0, 220, 255))

        strip_path = os.path.join(ARTIFACT_DIR, f"{out_name}_filmstrip.png")
        filmstrip.save(strip_path, "PNG")
        print(f"Saved horizontal filmstrip: {strip_path}")

        print("=== Diagnostic Pipeline Finished Successfully ===")


def main():
    parser = argparse.ArgumentParser(description="Inspect Quin Locomotion, IK & Ragdoll")
    parser.add_argument("--maneuver", choices=["sprint_180", "plant_turn_90", "arc_run", "hard_brake", "ledge_step", "knockback_high", "knockback_low"], default="sprint_180")
    parser.add_argument("--duration", type=float, default=2.5)
    parser.add_argument("--fps", type=int, default=8)
    parser.add_argument("--name", type=str, default=None)
    args = parser.parse_args()

    inspector = LocomotionInspector()
    inspector.run_diagnostic(
        maneuver=args.maneuver,
        duration=args.duration,
        fps=args.fps,
        out_name=args.name
    )


if __name__ == "__main__":
    main()
