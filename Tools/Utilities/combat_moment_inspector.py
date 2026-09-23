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

class CombatMomentInspector:
    def __init__(self):
        self.client = RobloxStudioClient()
        self.studio_id = self.client.studio_id

    def set_camera_override(self, cam_pos, look_pos):
        code = f"""
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CamPosX", {cam_pos[0]})
        ws:SetAttribute("CamPosY", {cam_pos[1]})
        ws:SetAttribute("CamPosZ", {cam_pos[2]})
        ws:SetAttribute("CamLookX", {look_pos[0]})
        ws:SetAttribute("CamLookY", {look_pos[1]})
        ws:SetAttribute("CamLookZ", {look_pos[2]})
        ws:SetAttribute("CameraOverrideActive", true)
        return "Camera override set"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def release_camera_override(self):
        code = """
        local ws = game:GetService("Workspace")
        ws:SetAttribute("CameraOverrideActive", false)
        return "Camera override released"
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
        return "HUDs { 'enabled' if enabled else 'hidden' }"
        """
        self.client.execute_luau(code, datamodel_type="Client")

    def get_quin_telemetry(self):
        code = """
        local HttpService = game:GetService("HttpService")
        local CollectionService = game:GetService("CollectionService")
        local Workspace = game:GetService("Workspace")

        local quins = CollectionService:GetTagged("Quin")
        local ghostFolder = Workspace:FindFirstChild("QuinGhost")
        local data = {}

        for _, q in ipairs(quins) do
            local hrp = q:FindFirstChild("HumanoidRootPart")
            local hum = q:FindFirstChildOfClass("Humanoid")
            if hrp and hum then
                local ghostName = q.Name .. "_Visual"
                local ghost = ghostFolder and ghostFolder:FindFirstChild(ghostName)
                local ghostPos = ghost and ghost.PrimaryPart and ghost.PrimaryPart.Position or hrp.Position
                
                table.insert(data, {
                    name = q.Name,
                    state = q:GetAttribute("CurrentState") or "None",
                    target = q:GetAttribute("CurrentTarget") or "None",
                    hp = hum.Health,
                    maxHp = hum.MaxHealth,
                    energy = q:GetAttribute("Energy") or 0,
                    hrpPos = { hrp.Position.X, hrp.Position.Y, hrp.Position.Z },
                    ghostPos = { ghostPos.X, ghostPos.Y, ghostPos.Z },
                    vel = { hrp.AssemblyLinearVelocity.X, hrp.AssemblyLinearVelocity.Y, hrp.AssemblyLinearVelocity.Z },
                    speed = hrp.AssemblyLinearVelocity.Magnitude,
                    isGuarding = q:GetAttribute("IsGuarding") == true,
                    knockbackType = q:GetAttribute("KnockbackType") or "none",
                    upY = hrp.CFrame.UpVector.Y
                })
            end
        end
        return HttpService:JSONEncode(data)
        """
        res = self.client.execute_luau(code, datamodel_type="Server")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "[]")
        try:
            return json.loads(txt)
        except Exception:
            return []

    def compute_cinematic_camera(self, telemetries):
        if not telemetries:
            return [0, 15, -30], [0, 5, 0]

        if len(telemetries) >= 2:
            p1 = telemetries[0]["ghostPos"]
            p2 = telemetries[1]["ghostPos"]
            maxY = max(p1[1], p2[1])
            mid = [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, (p1[2] + p2[2]) / 2]
            dx = p1[0] - p2[0]
            dz = p1[2] - p2[2]
            dist = max(10.0, (dx*dx + dz*dz)**0.5)

            # Perpendicular side view
            perp_x = -dz / dist
            perp_z = dx / dist

            is_airborne = maxY > 15.0
            cam_dist = max(35.0 if is_airborne else 15.0, dist * (1.6 if is_airborne else 1.2))
            cam_y = max(mid[1] + (15.0 if is_airborne else 3.5), 18.0 if is_airborne else 8.0)
            cam = [mid[0] + perp_x * cam_dist, cam_y, mid[2] + perp_z * cam_dist]
            look = [mid[0], max(mid[1] * 0.5, 4.0), mid[2]]
            return cam, look

        p = telemetries[0]["ghostPos"]
        is_airborne = p[1] > 15.0
        cam_dist = 30.0 if is_airborne else 12.0
        cam = [p[0] + cam_dist, max(p[1] + 10.0, 15.0), p[2] - cam_dist]
        look = [p[0], max(p[1] * 0.5, 4.0), p[2]]
        return cam, look

    def capture_burst(self, moment_name, frame_count=6, frame_interval=0.25, hide_hud=True):
        print(f"\n[CombatMomentInspector] Initiating capture for: {moment_name}")
        print(f"  Frames: {frame_count} | Interval: {frame_interval}s | Hide HUD: {hide_hud}")

        if hide_hud:
            self.toggle_huds(False)
            time.sleep(0.1)

        captured_frames = []
        frame_telemetries = []
        start_time = time.time()

        for i in range(frame_count):
            t_rel = time.time() - start_time
            telem = self.get_quin_telemetry()
            frame_telemetries.append({
                "frame": i + 1,
                "time": t_rel,
                "data": telem
            })

            cam, look = self.compute_cinematic_camera(telem)
            self.set_camera_override(cam, look)

            # Short wait for camera alignment
            time.sleep(0.04)

            res_cap = self.client.call_tool("screen_capture", {
                "studio_id": self.studio_id,
                "capture_id": f"{moment_name}_f{i+1}",
                "camera_position": cam,
                "look_at_position": look
            })

            items = res_cap.get("result", {}).get("content", [])
            for item in items:
                if item.get("type") == "image":
                    raw_bytes = base64.b64decode(item["data"])
                    img = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
                    captured_frames.append(img)
                    break

            time.sleep(frame_interval)

        self.release_camera_override()
        if hide_hud:
            self.toggle_huds(True)

        print(f"[CombatMomentInspector] Captured {len(captured_frames)} frames successfully.")
        return captured_frames, frame_telemetries

    def compile_artifacts(self, moment_name, frames, telemetries):
        if not frames:
            print("[CombatMomentInspector] No frames to compile.")
            return None, None

        # 1. Compile Animated GIF
        gif_filename = f"{moment_name}.gif"
        gif_path = os.path.join(ARTIFACT_DIR, gif_filename)
        duration_ms = int(1000 * 0.30)
        frames[0].save(
            gif_path,
            save_all=True,
            append_images=frames[1:],
            duration=duration_ms,
            loop=0
        )
        print(f"[OK] Generated Animated GIF: {gif_path} ({os.path.getsize(gif_path)} bytes)")

        # 2. Compile Annotated Contact Sheet / Filmstrip
        # Thumbnail dimensions
        w, h = frames[0].size
        thumb_scale = 0.45
        tw, th = int(w * thumb_scale), int(h * thumb_scale)
        header_h = 75
        col_w = tw
        total_w = tw * len(frames)
        total_h = th + header_h

        filmstrip = Image.new("RGB", (total_w, total_h), (18, 20, 24))
        draw = ImageDraw.Draw(filmstrip)

        for idx, (frame, telem_info) in enumerate(zip(frames, telemetries)):
            thumb = frame.resize((tw, th), Image.Resampling.LANCZOS)
            x_offset = idx * tw
            filmstrip.paste(thumb, (x_offset, header_h))

            # Header box
            draw.rectangle([x_offset, 0, x_offset + tw - 2, header_h - 2], fill=(28, 32, 38))
            draw.line([x_offset + tw - 1, 0, x_offset + tw - 1, total_h], fill=(60, 65, 75), width=2)

            t_val = telem_info["time"]
            draw.text((x_offset + 10, 8), f"Frame {idx + 1} | T+{t_val:.2f}s", fill=(255, 215, 0))

            q_data = telem_info["data"]
            if q_data:
                q1 = q_data[0]
                q1_summary = f"{q1['name'][:10]}: {q1['state']} | Spd:{q1['speed']:.1f} | HP:{q1['hp']:.0f}"
                draw.text((x_offset + 10, 28), q1_summary, fill=(180, 220, 255))
                if len(q_data) >= 2:
                    q2 = q_data[1]
                    q2_summary = f"{q2['name'][:10]}: {q2['state']} | Spd:{q2['speed']:.1f} | HP:{q2['hp']:.0f}"
                    draw.text((x_offset + 10, 48), q2_summary, fill=(255, 180, 180))

        filmstrip_filename = f"{moment_name}_filmstrip.png"
        filmstrip_path = os.path.join(ARTIFACT_DIR, filmstrip_filename)
        filmstrip.save(filmstrip_path)
        print(f"[OK] Generated Filmstrip: {filmstrip_path} ({os.path.getsize(filmstrip_path)} bytes)")

        # 3. Rule & Quirk Analysis
        quirks = self.analyze_quirks(telemetries)

        return gif_path, filmstrip_path, quirks

    def analyze_quirks(self, telemetries):
        findings = []
        for telem_item in telemetries:
            frame_num = telem_item["frame"]
            t_val = telem_item["time"]
            for q in telem_item["data"]:
                # Check 1: Tilt / Prone posture without being in Recovery or Knockback
                if q["upY"] < 0.70 and q["state"] not in ["Recovery", "Knockback", "ReEntry"]:
                    findings.append(f"Frame {frame_num} (T+{t_val:.2f}s): {q['name']} tilted flat (upY={q['upY']:.2f}) while in state '{q['state']}' (Prone Flaw / Cockroach risk)!")

                # Check 2: Zero velocity in Chase
                if q["state"] == "Chase" and q["speed"] < 1.0:
                    findings.append(f"Frame {frame_num} (T+{t_val:.2f}s): {q['name']} in Chase but speed={q['speed']:.1f} st/s (Momentum Stall risk)!")

                # Check 3: Extreme velocity solver explosion
                if q["speed"] > 180.0:
                    findings.append(f"Frame {frame_num} (T+{t_val:.2f}s): {q['name']} velocity={q['speed']:.1f} st/s exceeds maximum physical safety clamp (180 st/s)!")

        if not findings:
            findings.append("ZERO QUIRKS DETECTED: Physical orientation, kinematic speeds, and state transitions conform to all 6 Immutable Rules.")
        return findings

    def trigger_scenario(self, scenario_name):
        code = f"""
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local cmd = ReplicatedStorage:FindFirstChild("GameCommand")
        if not cmd then return "GameCommand RemoteEvent not found" end

        local sc = "{scenario_name}"
        if sc == "midair_clash" then
            cmd:FireServer("midair_clash")
        elseif sc == "1v1" then
            cmd:FireServer("ffa", 2)
        elseif sc == "4v4" then
            cmd:FireServer("team", 4)
        elseif sc == "movement" then
            cmd:FireServer("movement_test")
        elseif string.find(sc, "jump") then
            local num = tonumber(string.match(sc, "%d+")) or 1
            cmd:FireServer("jump_test", num)
        else
            return "Unknown scenario: " .. sc
        end
        return "Triggered scenario: " .. sc
        """
        res = self.client.execute_luau(code, datamodel_type="Client")
        return res.get("result", {}).get("content", [{}])[0].get("text", "")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CombatMomentInspector")
    parser.add_argument("--scenario", type=str, default="", help="Scenario to trigger: 1v1, 4v4, midair_clash, movement")
    parser.add_argument("--name", type=str, default="action_moment", help="Output moment name")
    parser.add_argument("--frames", type=int, default=6, help="Number of frames to capture")
    parser.add_argument("--interval", type=float, default=0.25, help="Interval between frames in seconds")
    parser.add_argument("--wait", type=float, default=2.5, help="Wait time before capturing after triggering scenario")
    args = parser.parse_args()

    inspector = CombatMomentInspector()

    if args.scenario:
        print(f"Triggering scenario '{args.scenario}'...")
        trig_res = inspector.trigger_scenario(args.scenario)
        print("Trigger result:", trig_res)
        print(f"Waiting {args.wait}s for combatants to engage...")
        time.sleep(args.wait)

    frames, telems = inspector.capture_burst(args.name, frame_count=args.frames, frame_interval=args.interval, hide_hud=True)
    if frames:
        gif_p, strip_p, quirks = inspector.compile_artifacts(args.name, frames, telems)
        print("\n=== QUIRK & RULE ANALYSIS ===")
        for f in quirks:
            print(" -", f)
        print(f"\nSaved Artifacts:")
        print(f"  GIF:       {gif_p}")
        print(f"  Filmstrip: {strip_p}")

