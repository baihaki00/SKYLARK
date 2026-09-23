import os
import sys
import json

# Ensure Tools/Utilities is on python path
util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def inspect_characters():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    code = """
    local Workspace = game:GetService("Workspace")
    local quinServer = Workspace:FindFirstChild("QuinServer")
    local quinGhost = Workspace:FindFirstChild("QuinGhost")

    local report = {
        serverQuins = {},
        ghostQuins = {},
        worldQuinsExcluded = {}
    }

    -- 1. Server Arena Quins
    if quinServer then
        for _, child in ipairs(quinServer:GetChildren()) do
            if child:IsA("Model") then
                local hum = child:FindFirstChildOfClass("Humanoid")
                local hrp = child:FindFirstChild("HumanoidRootPart")
                local pos = hrp and hrp.Position or Vector3.zero
                local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
                
                table.insert(report.serverQuins, {
                    name = child.Name,
                    quinId = child:GetAttribute("QuinId") or "N/A",
                    state = child:GetAttribute("CurrentState") or "N/A",
                    target = child:GetAttribute("TargetQuin") or "N/A",
                    element = child:GetAttribute("Element") or "N/A",
                    type = child:GetAttribute("Type") or child:GetAttribute("ChassisType") or "N/A",
                    health = hum and math.round(hum.Health) or 0,
                    maxHealth = hum and math.round(hum.MaxHealth) or 0,
                    position = string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z),
                    speed = math.round(vel.Magnitude * 10) / 10,
                    platformStand = hum and hum.PlatformStand or false,
                })
            end
        end
    end

    -- 2. Client Ghosts
    if quinGhost then
        for _, ghost in ipairs(quinGhost:GetChildren()) do
            if ghost:IsA("Model") then
                local hrp = ghost:FindFirstChild("HumanoidRootPart")
                local pos = hrp and hrp.Position or Vector3.zero
                table.insert(report.ghostQuins, {
                    name = ghost.Name,
                    lookMode = ghost:GetAttribute("LookMode") or "N/A",
                    reactionType = ghost:GetAttribute("ReactionType") or "NONE",
                    position = string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z),
                })
            end
        end
    end

    -- 3. Check for any world rigs in raw Workspace
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") and (child.Name == "QuinTest" or child.Name == "QuinTypeA") then
            table.insert(report.worldQuinsExcluded, {
                name = child.Name,
                position = child.PrimaryPart and string.format("(%.1f, %.1f, %.1f)", child.PrimaryPart.Position.X, child.PrimaryPart.Position.Y, child.PrimaryPart.Position.Z) or "N/A",
                status = "Correctly Isolated from Arena"
            })
        end
    end

    return report
    """

    res = client.execute_luau(code, datamodel_type="Server")
    txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("=== CHARACTER INSPECTION REPORT ===")
    try:
        data = json.loads(txt)
        def to_list(val):
            if isinstance(val, dict):
                return list(val.values())
            elif isinstance(val, list):
                return val
            return []

        server_quins = to_list(data.get('serverQuins', []))
        ghost_quins = to_list(data.get('ghostQuins', []))
        world_excluded = to_list(data.get('worldQuinsExcluded', []))

        print(f"Arena Quins in Workspace.QuinServer: {len(server_quins)}")
        for q in server_quins:
            print(f"  - [{q['name']}] State: {q['state']} | Target: {q['target']} | HP: {q['health']}/{q['maxHealth']} | Type: {q['type']} | Elem: {q['element']} | Pos: {q['position']} | Spd: {q['speed']} | PlatStand: {q['platformStand']}")

        print(f"\nClient Ghosts in Workspace.QuinGhost: {len(ghost_quins)}")
        for g in ghost_quins:
            print(f"  - Ghost [{g['name']}] Look: {g['lookMode']} | Reaction: {g['reactionType']} | Pos: {g['position']}")

        print(f"\nWorld Test Rigs Excluded: {len(world_excluded)}")
        for w in world_excluded:
            print(f"  - [{w['name']}] Pos: {w['position']} -> {w['status']}")
    except Exception as e:
        print("Parse/Format Error:", e)
        print("Raw Output:", txt)
    print("===================================")
    client.close()

if __name__ == "__main__":
    inspect_characters()
