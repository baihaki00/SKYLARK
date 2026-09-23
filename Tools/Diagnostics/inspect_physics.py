import os
import sys
import json

# Ensure Tools/Utilities is on python path
util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def inspect_physics():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    code = """
    local Workspace = game:GetService("Workspace")
    local quinServer = Workspace:FindFirstChild("QuinServer")
    local report = {}

    if not quinServer then
        return { error = "Workspace.QuinServer not found" }
    end

    for _, child in ipairs(quinServer:GetChildren()) do
        if child:IsA("Model") then
            local hum = child:FindFirstChildOfClass("Humanoid")
            local hrp = child:FindFirstChild("HumanoidRootPart")
            if hrp then
                local halfHeight = hrp.Size.Y / 2
                local rayOrigin = hrp.Position - Vector3.new(0, halfHeight, 0)
                local rayParams = RaycastParams.new()
                rayParams.FilterDescendantsInstances = { child, quinServer }
                rayParams.FilterType = RaycastFilterType.Exclude

                local hit = Workspace:Raycast(rayOrigin, Vector3.new(0, -20, 0), rayParams)
                local clearance = hit and (rayOrigin.Y - hit.Position.Y) or 999

                -- Check active physical constraints on HRP
                local constraints = {}
                for _, inst in ipairs(hrp:GetChildren()) do
                    if inst:IsA("AlignOrientation") or inst:IsA("VectorForce") or inst:IsA("LinearVelocity") or inst:IsA("BodyVelocity") then
                        table.insert(constraints, {
                            name = inst.Name,
                            className = inst.ClassName,
                            enabled = inst.Enabled,
                        })
                    end
                end

                table.insert(report, {
                    name = child.Name,
                    hrpSize = string.format("(%.2f, %.2f, %.2f)", hrp.Size.X, hrp.Size.Y, hrp.Size.Z),
                    hrpPosition = string.format("(%.2f, %.2f, %.2f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z),
                    linearVelocity = string.format("(%.2f, %.2f, %.2f)", hrp.AssemblyLinearVelocity.X, hrp.AssemblyLinearVelocity.Y, hrp.AssemblyLinearVelocity.Z),
                    speed = math.round(hrp.AssemblyLinearVelocity.Magnitude * 10) / 10,
                    verticalSpeed = math.round(hrp.AssemblyLinearVelocity.Y * 10) / 10,
                    angularVelocity = string.format("(%.2f, %.2f, %.2f)", hrp.AssemblyAngularVelocity.X, hrp.AssemblyAngularVelocity.Y, hrp.AssemblyAngularVelocity.Z),
                    mass = math.round(hrp.AssemblyMass * 10) / 10,
                    platformStand = hum and hum.PlatformStand or false,
                    floorMaterial = hum and hum.FloorMaterial.Name or "N/A",
                    clearanceFromBottom = math.round(clearance * 100) / 100,
                    constraints = constraints,
                })
            end
        end
    end

    return report
    """

    res = client.execute_luau(code, datamodel_type="Server")
    txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("=== PHYSICS & CONTACT DIAGNOSTICS REPORT ===")
    try:
        data = json.loads(txt)
        if isinstance(data, dict) and "error" in data:
            print("Error:", data["error"])
        elif isinstance(data, list):
            print(f"Active Physical Entities Audited: {len(data)}")
            for p in data:
                print(f"\n[{p['name']}] Mass: {p['mass']} | Size: {p['hrpSize']}")
                print(f"  Pos: {p['hrpPosition']} | Vel: {p['linearVelocity']} (Speed: {p['speed']}, Vy: {p['verticalSpeed']})")
                print(f"  AngVel: {p['angularVelocity']}")
                print(f"  PlatformStand: {p['platformStand']} | FloorMaterial: {p['floorMaterial']}")
                print(f"  True Collider Bottom Clearance: {p['clearanceFromBottom']} studs")
                print(f"  Attached Constraints: {len(p['constraints'])}")
                for c in p['constraints']:
                    print(f"    - {c['name']} ({c['className']}) Enabled: {c['enabled']}")
    except Exception:
        print("Raw Output:", txt)
    print("\n============================================")
    client.close()

if __name__ == "__main__":
    inspect_physics()
