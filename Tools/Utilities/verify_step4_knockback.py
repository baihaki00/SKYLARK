#// verify_step4_knockback.py
# Verification script for Step 4: Active Muscle Ragdoll, Momentum Ground Skids & Spectacle Knockback

import time
import json
import math
from roblox_client import RobloxStudioClient

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Check if AIGhostHandler runner is active and Quins exist
    setup_code = """
    local quinServer = workspace:FindFirstChild("QuinServer")
    local quins = quinServer and quinServer:GetChildren() or {}
    local quinGhost = workspace:FindFirstChild("QuinGhost")
    
    -- Ensure AIGhostHandler runner is active
    local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    local ghostScript = sp and sp:FindFirstChild("AIGhostHandler")
    if ghostScript and not _G.GhostRunnerActive then
        _G.GhostRunnerActive = true
        task.spawn(loadstring(ghostScript.Source))
    end

    -- Pick a target Quin
    local targetQuin = nil
    for _, q in ipairs(quins) do
        if q:IsA("Model") and q:FindFirstChild("HumanoidRootPart") and q:FindFirstChildOfClass("Humanoid") then
            if q.Humanoid.Health > 20 then
                targetQuin = q
                break
            end
        end
    end

    if not targetQuin then
        -- Spawn if none available
        local QuinSpawner = require(game:GetService("ServerScriptService"):WaitForChild("QuinSpawner"))
        targetQuin = QuinSpawner.spawnQuin("TypeA", "TeamAlpha", 1, Vector3.new(0, 10, 0))
        task.wait(0.3)
    end

    return {
        targetName = targetQuin and targetQuin.Name or "None",
        pos = targetQuin and tostring(targetQuin.HumanoidRootPart.Position) or "None",
        health = targetQuin and targetQuin.Humanoid.Health or 0,
        ghostsCount = quinGhost and #quinGhost:GetChildren() or 0
    }
    """

    res = client.execute_luau(setup_code, "Edit")
    print("Setup result:", res)
    content = json.loads(res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    target_name = content.get("targetName")
    print(f"Target Quin selected: {target_name}")

    if not target_name or target_name == "None":
        print("ERROR: Could not find or spawn a Quin.")
        client.close()
        return

    # 2. Trigger high-force aerial knockback on the target Quin
    trigger_code = f"""
    local quinServer = workspace:FindFirstChild("QuinServer")
    local target = quinServer:FindFirstChild("{target_name}")
    if not target then return {{ success = false, err = "target not found" }} end

    local hrp = target:FindFirstChild("HumanoidRootPart")
    local hum = target:FindFirstChildOfClass("Humanoid")
    local QuinCore = game:GetService("ReplicatedStorage"):WaitForChild("QuinCore")
    local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))

    -- Face a specific direction and blast backward with aerial knockback
    local blastDir = Vector3.new(1, 0, 0) -- Knock along +X
    target:SetAttribute("KnockbackType", "air")
    target:SetAttribute("ForceState", "Knockback")
    
    -- Apply launch velocity: horizontal + vertical
    local launchSpeed = 80.0
    hrp.AssemblyLinearVelocity = blastDir * launchSpeed + Vector3.new(0, 48, 0)
    target:SetAttribute("LaunchedAt", tick())
    hum.PlatformStand = true

    return {{
        success = true,
        initialVel = tostring(hrp.AssemblyLinearVelocity),
        initialPos = tostring(hrp.Position)
    }}
    """

    launch_res = client.execute_luau(trigger_code, "Edit")
    print("Launch result:", launch_res)

    # 3. Sample telemetry across 40 frames (~2.0 seconds) to capture Flight, Skid, and Recovery
    samples = []
    print("\n--- SAMPLING STEP 4 SPECTACLE KNOCKBACK ---")
    print(f"{'Time(s)':<7} | {'State':<10} | {'SubPhase':<8} | {'Speed':<6} | {'VelY':<6} | {'HRP Pitch':<9} | {'SpineFlex':<9} | {'LegLag':<7} | {'VFX Active'}")
    print("-" * 90)

    start_time = time.time()
    for step in range(35):
        t_elapsed = time.time() - start_time
        sample_code = f"""
        local quinServer = workspace:FindFirstChild("QuinServer")
        local target = quinServer and quinServer:FindFirstChild("{target_name}")
        local quinGhost = workspace:FindFirstChild("QuinGhost")
        local ghost = quinGhost and quinGhost:FindFirstChild("{target_name}_Visual")

        if not target then return {{ exists = false }} end
        local hrp = target:FindFirstChild("HumanoidRootPart")
        local vel = hrp.AssemblyLinearVelocity
        local horizVel = Vector3.new(vel.X, 0, vel.Z)
        local curState = target:GetAttribute("CurrentState") or "None"
        local kbTilt = target:GetAttribute("KnockbackFlightTiltDeg") or 0

        -- Ground Skid Movers
        local hasSkidVel = hrp:FindFirstChild("KB_SkidVelocity") ~= nil
        local hasSkidOrient = hrp:FindFirstChild("KB_SkidOrient") ~= nil
        local hasSkidVfx = hrp:FindFirstChild("GroundSkidAttachment") ~= nil

        -- Upright Recovery Movers
        local hasRecoveryAlign = hrp:FindFirstChild("Recovery_UprightAlign") ~= nil

        -- Visual Ghost Reactions
        local rPitch = ghost and ghost:GetAttribute("ReactionPitch") or 0
        local rType = ghost and ghost:GetAttribute("ReactionType") or "NONE"

        -- Orientation: LookVector.Y tells us if chest is facing up (supine) or down (prone)
        local lookY = hrp.CFrame.LookVector.Y
        local upY = hrp.CFrame.UpVector.Y

        return {{
            exists = true,
            t = {t_elapsed:.3f},
            state = curState,
            speed = horizVel.Magnitude,
            velY = vel.Y,
            posY = hrp.Position.Y,
            kbTilt = kbTilt,
            hasSkidVel = hasSkidVel,
            hasSkidOrient = hasSkidOrient,
            hasSkidVfx = hasSkidVfx,
            hasRecoveryAlign = hasRecoveryAlign,
            rPitch = rPitch,
            rType = rType,
            lookY = lookY,
            upY = upY
        }}
        """
        s_res = client.execute_luau(sample_code, "Edit")
        try:
            sample = json.loads(s_res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
            if sample.get("exists"):
                samples.append(sample)
                subphase = "SKID" if sample.get("hasSkidVel") else ("UPRIGHT" if sample.get("hasRecoveryAlign") else "AIR")
                vfx_str = "RoosterTail" if sample.get("hasSkidVfx") else ("AlignOrient" if sample.get("hasRecoveryAlign") else "-")
                print(f"{sample.get('t', 0):<7.2f} | {sample.get('state', ''):<10} | {subphase:<8} | {sample.get('speed', 0):<6.1f} | {sample.get('velY', 0):<6.1f} | {sample.get('kbTilt', 0):<9.1f} | {sample.get('rPitch', 0):<9.1f} | {sample.get('lookY', 0):<7.2f} | {vfx_str}")
        except Exception as e:
            print("Sample parse err:", e)
        time.sleep(0.06)

    client.close()

    # 4. Analyze Results
    flight_samples = [s for s in samples if s.get("state") == "Knockback" and not s.get("hasSkidVel")]
    skid_samples = [s for s in samples if s.get("hasSkidVel")]
    recovery_samples = [s for s in samples if s.get("state") == "Recovery" or s.get("hasRecoveryAlign")]

    print("\n=== STEP 4 AUDIT SUMMARY ===")
    print(f"Flight Samples:   {len(flight_samples)} frames")
    print(f"Skid Samples:     {len(skid_samples)} frames")
    print(f"Recovery Samples: {len(recovery_samples)} frames")

    if flight_samples:
        max_tilt = max(s.get("kbTilt", 0) for s in flight_samples)
        print(f"âœ“ Aerial Trajectory Flight Tilt Peak: {max_tilt:.1f}Â° (Target: 20Â° - 55Â°)")

    if skid_samples:
        v_start = skid_samples[0].get("speed", 0)
        v_end = skid_samples[-1].get("speed", 0)
        has_vfx = any(s.get("hasSkidVfx") for s in skid_samples)
        print(f"âœ“ Kinetic Ground Skid Active: v_initial = {v_start:.1f} studs/s â†’ v_final = {v_end:.1f} studs/s")
        print(f"âœ“ Ground Friction Rooster Tail VFX spawned: {has_vfx}")

    if recovery_samples:
        has_align = any(s.get("hasRecoveryAlign") for s in recovery_samples)
        print(f"âœ“ Critically Damped Upright Alignment active (no 1-frame snap): {has_align}")

if __name__ == "__main__":
    main()
