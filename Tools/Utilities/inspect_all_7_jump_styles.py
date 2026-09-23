import os
import sys
import time
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient
from combat_moment_inspector import CombatMomentInspector

STYLE_DESCRIPTIONS = {
    1: "High Ballistic Leap (Parabolic Gravity Compensation)",
    2: "Linear Lunge Dive (Direct Ballistic Flight)",
    3: "Multi-Jump / Air Hop (Mid-air double hop into dive)",
    4: "Low-Altitude Skim Arc (Lateral strafe dodge before dive)",
    5: "Cubic Bezier S-Curve (Fluid 3D curve with obstacle clearance)",
    6: "Acrobatic Combo Flip (Multi-phase jump/strafe combo sequence)",
    7: "Float & Hover Slam (High altitude apex delay into 1.5x slam)"
}

def inspect_all_styles():
    inspector = CombatMomentInspector()
    client = inspector.client

    results = {}

    print("=========================================================")
    print("      SKYLARK ISLES — 7 PROJECTILE JUMP STYLES AUDIT     ")
    print("=========================================================\n")

    for style_id in range(1, 8):
        style_name = STYLE_DESCRIPTIONS[style_id]
        print(f"\n---> Auditing Style {style_id}: {style_name}")

        # Trigger jump test mode for this style
        client.execute_luau(f"""
            local rs = game:GetService("ReplicatedStorage")
            local cmd = rs:FindFirstChild("GameCommand")
            if cmd then
                cmd:FireServer("jump_test", {style_id})
            end
        """, datamodel_type="Client")

        # Give 0.4s for spawn and alignment
        time.sleep(0.4)

        # Capture high-frequency trajectory telemetry for 1.8 seconds (20 samples)
        telemetry_samples = []
        start_t = time.time()
        while time.time() - start_t < 1.8:
            telem = inspector.get_quin_telemetry()
            jumper = None
            for q in telem:
                if "TypeA" in q["name"] or "Leader" in q["name"] or q.get("state") == "ProjectileJump":
                    jumper = q
                    break
            if jumper:
                telemetry_samples.append({
                    "time": round(time.time() - start_t, 3),
                    "state": jumper.get("state"),
                    "pos": jumper.get("hrpPos"),
                    "vel": jumper.get("vel"),
                    "speed": round(jumper.get("speed", 0), 1),
                    "knockback": jumper.get("knockbackType")
                })
            time.sleep(0.08)

        # Also capture a cinematic moment visual
        moment_name = f"jump_style_{style_id}"
        frames, telems = inspector.capture_burst(moment_name, frame_count=6, frame_interval=0.15, hide_hud=True)
        if frames:
            gif_p, strip_p, quirks = inspector.compile_artifacts(moment_name, frames, telems)
        else:
            gif_p, strip_p, quirks = None, None, []

        # Analyze trajectory telemetry
        apex_y = max([s["pos"][1] for s in telemetry_samples]) if telemetry_samples else 0
        min_y = min([s["pos"][1] for s in telemetry_samples]) if telemetry_samples else 0
        max_speed = max([s["speed"] for s in telemetry_samples]) if telemetry_samples else 0
        states_seen = list(dict.fromkeys([s["state"] for s in telemetry_samples]))

        results[style_id] = {
            "name": style_name,
            "samples_count": len(telemetry_samples),
            "apex_y": round(apex_y, 2),
            "vertical_climb": round(apex_y - min_y, 2),
            "max_speed": max_speed,
            "states_sequence": states_seen,
            "gif": gif_p,
            "strip": strip_p,
            "quirks": quirks
        }

        print(f"     Apex Height: {round(apex_y, 2)} studs (Climb: +{round(apex_y - min_y, 2)} studs)")
        print(f"     Max Speed: {max_speed} studs/s")
        print(f"     State Flow: {' -> '.join(states_seen)}")

    print("\n=========================================================")
    print("                 AUDIT SUMMARY COMPLETE                  ")
    print("=========================================================")
    print(json.dumps(results, indent=2))
    return results

if __name__ == "__main__":
    inspect_all_styles()
