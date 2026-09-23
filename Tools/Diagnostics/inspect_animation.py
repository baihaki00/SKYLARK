import os
import sys
import json

# Ensure Tools/Utilities is on python path
util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def inspect_animations():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    code = """
    local Workspace = game:GetService("Workspace")
    local quinGhost = Workspace:FindFirstChild("QuinGhost")
    local report = {}

    if not quinGhost then
        return { error = "Workspace.QuinGhost not found on Client" }
    end

    for _, ghost in ipairs(quinGhost:GetChildren()) do
        if ghost:IsA("Model") then
            local hum = ghost:FindFirstChildOfClass("Humanoid")
            local anim = hum and hum:FindFirstChildOfClass("Animator")

            -- 1. Playing Tracks
            local tracks = {}
            if anim then
                for _, t in ipairs(anim:GetPlayingAnimationTracks()) do
                    table.insert(tracks, {
                        name = t.Name,
                        id = t.Animation and t.Animation.AnimationId or "N/A",
                        priority = t.Priority.Name,
                        speed = math.round(t.Speed * 100) / 100,
                        weight = math.round(t.WeightCurrent * 100) / 100,
                        timePos = math.round(t.TimePosition * 100) / 100,
                        length = math.round(t.Length * 100) / 100,
                    })
                end
            end

            -- 2. Procedural Bone Angles
            local bones = {}
            local boneNames = { "mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2", "mixamorig:Neck", "mixamorig:Head" }
            for _, bName in ipairs(boneNames) do
                local b = ghost:FindFirstChild(bName, true)
                if b and b:IsA("Bone") then
                    local rx, ry, rz = b.Transform:ToOrientation()
                    local pos = b.Transform.Position
                    bones[bName] = {
                        rotDeg = string.format("(P=%.1f°, Y=%.1f°, R=%.1f°)", math.deg(rx), math.deg(ry), math.deg(rz)),
                        offsetPos = string.format("(%.2f, %.2f, %.2f)", pos.X, pos.Y, pos.Z),
                    }
                end
            end

            table.insert(report, {
                ghostName = ghost.Name,
                reactionType = ghost:GetAttribute("ReactionType") or "NONE",
                reactionPitch = ghost:GetAttribute("ReactionPitch") or 0,
                reactionRoll = ghost:GetAttribute("ReactionRoll") or 0,
                reactionHips = ghost:GetAttribute("ReactionHips") or 0,
                lookMode = ghost:GetAttribute("LookMode") or "NONE",
                gazeYaw = ghost:GetAttribute("GazeYaw") or 0,
                gazePitch = ghost:GetAttribute("GazePitch") or 0,
                tracks = tracks,
                bones = bones,
            })
        end
    end

    return report
    """

    res = client.execute_luau(code, datamodel_type="Client")
    txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("=== CLIENT ANIMATION & SKELETAL DIAGNOSTICS ===")
    try:
        data = json.loads(txt)
        if isinstance(data, dict) and "error" in data:
            print("Error:", data["error"])
        elif isinstance(data, list):
            print(f"Active Client Ghosts Inspected: {len(data)}")
            for g in data:
                print(f"\n[Ghost: {g['ghostName']}]")
                print(f"  Gaze: Mode={g['lookMode']} | Yaw={g['gazeYaw']}° | Pitch={g['gazePitch']}°")
                print(f"  Combat Reaction: Type={g['reactionType']} | Pitch={g['reactionPitch']} | Roll={g['reactionRoll']} | Hips={g['reactionHips']}")
                print(f"  Playing AnimationTracks ({len(g['tracks'])}):")
                for t in g['tracks']:
                    print(f"    - {t['name']} (ID: {t['id']}) | Prio: {t['priority']} | Spd: {t['speed']} | Wgt: {t['weight']} | Pos: {t['timePos']}/{t['length']}s")
                print(f"  Procedural Bones:")
                for bName, bData in g['bones'].items():
                    print(f"    - {bName}: Rot={bData['rotDeg']} PosOffset={bData['offsetPos']}")
    except Exception:
        print("Raw Output:", txt)
    print("\n================================================")
    client.close()

if __name__ == "__main__":
    inspect_animations()
