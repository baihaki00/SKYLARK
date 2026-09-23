import time
import json
import os
import sys
import base64
from collections import defaultdict, deque

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

def cleanup(client):
    code = """
    workspace:SetAttribute("MatchStarted", false)
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)
    QuinSpawner.cleanAll()
    local p = workspace:FindFirstChild("TestVantagePlatform")
    if p then p:Destroy() end
    local w = workspace:FindFirstChild("TestDeadEndWall")
    if w then w:Destroy() end
    local o = workspace:FindFirstChild("TestObstacle")
    if o then o:Destroy() end
    local b = workspace:FindFirstChild("TestDeadEndBox")
    if b then b:Destroy() end
    return "Cleaned"
    """
    client.execute_luau(code, datamodel_type="Server")
    time.sleep(0.3)

def capture_image(client, filename, cam_pos, look_at):
    cap_res = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": filename.replace(".png", ""),
        "camera_position": cam_pos,
        "look_at_position": look_at
    })
    filepath = os.path.join(ARTIFACT_DIR, filename)
    if cap_res and not cap_res.get("isError", False):
        content = cap_res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(filepath, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"  [SCREENSHOT] Saved {filename} ({len(img_data)} bytes)")
                return True
    return False

POLL_LUAU = """
local Http = game:GetService("HttpService")
local CS = game:GetService("CollectionService")

local quins = {}
for _, q in ipairs(CS:GetTagged("Quin")) do
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    if hrp and hum then
        local pos = hrp.Position
        local vel = hrp.AssemblyLinearVelocity
        local ang = hrp.AssemblyAngularVelocity
        local upY = hrp.CFrame.UpVector.Y
        local look = hrp.CFrame.LookVector
        local moveDir = hum.MoveDirection
        
        local nearestDist = 999
        local nearestName = ""
        for _, o in ipairs(CS:GetTagged("Quin")) do
            if o ~= q and o.Parent and o:FindFirstChild("HumanoidRootPart") then
                local d = (o.HumanoidRootPart.Position - pos).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearestName = o.Name
                end
            end
        end

        table.insert(quins, {
            name = q.Name,
            team = q:GetAttribute("Team") or "None",
            qType = q:GetAttribute("QuinType") or "TypeA",
            state = q:GetAttribute("CurrentState") or "None",
            recAction = q:GetAttribute("RecommendedAction") or "None",
            forceState = q:GetAttribute("ForceState") or "None",
            hp = hum.Health,
            maxHp = hum.MaxHealth,
            ws = hum.WalkSpeed,
            floor = tostring(hum.FloorMaterial),
            pos = { math.round(pos.X*10)/10, math.round(pos.Y*10)/10, math.round(pos.Z*10)/10 },
            vel = { math.round(vel.X*10)/10, math.round(vel.Y*10)/10, math.round(vel.Z*10)/10 },
            spd = math.round(vel.Magnitude*10)/10,
            angSpd = math.round(ang.Magnitude*10)/10,
            upY = math.round(upY*1000)/1000,
            moveMag = math.round(moveDir.Magnitude*100)/100,
            nearestDist = math.round(nearestDist*10)/10,
            nearestName = nearestName,
            isGuarding = q:GetAttribute("IsGuarding") or false,
            attacking = q:GetAttribute("Attacking") or false,
            knockbackType = q:GetAttribute("KnockbackType") or "",
            targetQuin = q:GetAttribute("TargetQuin") or "",
            retreatObj = q:GetAttribute("RetreatObjective") or "",
        })
    end
end

return Http:JSONEncode(quins)
"""

class QuinTracker:
    def __init__(self, name):
        self.name = name
        self.samples = []
        self.state_history = []
        self.speeds = []
        self.state_speeds = defaultdict(list)
        
        # Anomaly tracking
        self.current_prone_start = None
        self.prone_episodes = [] # list of (duration, start_time, end_time, states)
        
        self.recent_positions = deque(maxlen=20) # (time, (x, y, z), ws, spd, state)
        self.stalled_episodes = [] # list of (duration, start_time, end_time, avg_spd, state, pos)
        self.current_stalled_start = None
        
        self.collider_lock_episodes = []
        self.current_collider_lock_start = None

        self.last_state = None
        self.state_transitions = [] # (time, from_state, to_state)

    def record(self, t, data):
        self.samples.append((t, data))
        st = data["state"]
        spd = data["spd"]
        upY = data["upY"]
        ws = data["ws"]
        pos = tuple(data["pos"])
        hp = data["hp"]
        nearest_d = data["nearestDist"]

        # Track transitions
        if self.last_state is not None and self.last_state != st:
            self.state_transitions.append((t, self.last_state, st))
        self.last_state = st

        # Speed metrics (only if alive)
        if hp > 0:
            self.speeds.append(spd)
            self.state_speeds[st].append(spd)

        # ----------------------------------------------------
        # 1. Prone Cockroach Check (UpVector.Y < 0.70 while alive)
        # ----------------------------------------------------
        is_prone = (upY < 0.70) and (hp > 0) and (st != "Death")
        if is_prone:
            if self.current_prone_start is None:
                self.current_prone_start = t
        else:
            if self.current_prone_start is not None:
                dur = t - self.current_prone_start
                if dur >= 0.25: # Only record meaningful prone pauses
                    self.prone_episodes.append({
                        "duration": round(dur, 2),
                        "start": round(self.current_prone_start, 2),
                        "end": round(t, 2),
                        "state": st,
                        "upY": upY,
                        "pos": pos
                    })
                self.current_prone_start = None

        # ----------------------------------------------------
        # 2. Moving in Place / Stalled Quin Check
        # (WalkSpeed >= 16 or moveMag > 0, but net displacement < 3 studs over 2.0s)
        # ----------------------------------------------------
        self.recent_positions.append((t, pos, ws, spd, st))
        if len(self.recent_positions) >= 12 and hp > 0 and st not in ("Death", "Idle", "Recovery"):
            oldest_t, oldest_pos, _, _, _ = self.recent_positions[0]
            dt = t - oldest_t
            if dt >= 1.5:
                dx = pos[0] - oldest_pos[0]
                dy = pos[1] - oldest_pos[1]
                dz = pos[2] - oldest_pos[2]
                disp = (dx*dx + dy*dy + dz*dz)**0.5
                
                # If humanoid is supposed to be moving (ws >= 16 or spd > 3), but displacement is tiny
                is_stalled = (disp < 3.0) and (ws >= 16 or spd > 3.0) and (st in ("Chase", "Retreat", "Dash", "Fight", "Circling"))
                if is_stalled:
                    if self.current_stalled_start is None:
                        self.current_stalled_start = t
                else:
                    if self.current_stalled_start is not None:
                        dur = t - self.current_stalled_start
                        if dur >= 1.2:
                            self.stalled_episodes.append({
                                "duration": round(dur, 2),
                                "start": round(self.current_stalled_start, 2),
                                "end": round(t, 2),
                                "disp": round(disp, 1),
                                "state": st,
                                "ws": ws,
                                "pos": pos,
                                "nearestQuin": data["nearestName"],
                                "nearestDist": nearest_d
                            })
                        self.current_stalled_start = None

        # ----------------------------------------------------
        # 3. Collider Lock / Brick Stacking (dist < 2.5 studs)
        # ----------------------------------------------------
        is_collider_locked = (nearest_d < 2.5) and (hp > 0) and (st not in ("Knockback", "Death", "ProjectileJump"))
        if is_collider_locked:
            if self.current_collider_lock_start is None:
                self.current_collider_lock_start = t
        else:
            if self.current_collider_lock_start is not None:
                dur = t - self.current_collider_lock_start
                if dur >= 0.8:
                    self.collider_lock_episodes.append({
                        "duration": round(dur, 2),
                        "start": round(self.current_collider_lock_start, 2),
                        "end": round(t, 2),
                        "with": data["nearestName"],
                        "pos": pos,
                        "dist": nearest_d
                    })
                self.current_collider_lock_start = None

    def finalize(self, total_time):
        if self.current_prone_start is not None:
            dur = total_time - self.current_prone_start
            if dur >= 0.25:
                self.prone_episodes.append({
                    "duration": round(dur, 2),
                    "start": round(self.current_prone_start, 2),
                    "end": round(total_time, 2),
                    "state": self.last_state,
                    "upY": 0.0,
                    "pos": (0, 0, 0)
                })
        if self.current_stalled_start is not None:
            dur = total_time - self.current_stalled_start
            if dur >= 1.2:
                self.stalled_episodes.append({
                    "duration": round(dur, 2),
                    "start": round(self.current_stalled_start, 2),
                    "end": round(total_time, 2),
                    "disp": 0.0,
                    "state": self.last_state,
                    "ws": 0,
                    "pos": (0, 0, 0),
                    "nearestQuin": "",
                    "nearestDist": 0
                })

def run_battle_adversarial_check(client, mode_name, team_size, duration_seconds=40):
    print("\n" + "=" * 70)
    print(f"STARTING ADVERSARIAL & SANITY CHECK: {mode_name} ({team_size}v{team_size}, {duration_seconds}s)")
    print("=" * 70)
    cleanup(client)

    # Start the battle via QuinSpawner
    start_code = f"""
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)
    QuinSpawner.cleanAll()

    local alphaTypes = {{}}
    for i = 1, {team_size} do
        table.insert(alphaTypes, (i % 2 == 1) and "TypeA" or "TypeC")
    end
    local betaTypes = {{}}
    for i = 1, {team_size} do
        table.insert(betaTypes, (i % 2 == 1) and "TypeB" or "TypeD")
    end

    local span = math.max(45, {team_size} * 15)
    QuinSpawner.spawnTeam(alphaTypes, "TeamAlpha", {team_size}, 1, Vector3.new(-span, 2.05, 0), Vector3.new(span, 2.05, 0))
    QuinSpawner.spawnTeam(betaTypes, "TeamBeta", {team_size}, 2, Vector3.new(span, 2.05, 0), Vector3.new(-span, 2.05, 0))

    workspace:SetAttribute("MatchStarted", true)
    return "BattleStarted"
    """
    client.execute_luau(start_code, datamodel_type="Server")
    print(f"  [MATCH] QuinSpawner.spawnTeam({team_size}v{team_size}) triggered. Initializing match...")
    time.sleep(1.0)

    trackers = {}
    start_time = time.time()
    next_screenshot_time = start_time + 4.0
    screenshot_count = 0
    poll_count = 0

    print("  [POLLING] Commencing high-frequency 150ms telemetry harvest...")
    while (time.time() - start_time) < duration_seconds:
        now = time.time()
        t_rel = round(now - start_time, 2)
        
        # Query Studio
        raw = client.execute_luau(POLL_LUAU, datamodel_type="Server")
        data_str = raw.get("result", {}).get("content", [{}])[0].get("text", "[]")
        try:
            quin_snapshots = json.loads(data_str)
        except Exception as e:
            quin_snapshots = []

        for q in quin_snapshots:
            qname = q["name"]
            if qname not in trackers:
                trackers[qname] = QuinTracker(qname)
            trackers[qname].record(t_rel, q)

        # Periodic Screen Captures
        if now >= next_screenshot_time and screenshot_count < 4:
            screenshot_count += 1
            snap_name = f"screen_capture_sanity_{mode_name.lower()}_t{int(t_rel)}s.png"
            capture_image(client, snap_name, [0, 95, 140], [0, 5, 0])
            next_screenshot_time = now + 11.0

        poll_count += 1
        time.sleep(0.15)

    total_time = round(time.time() - start_time, 2)
    for tracker in trackers.values():
        tracker.finalize(total_time)

    # ----------------------------------------------------
    # COMPILE METRICS & ANOMALIES
    # ----------------------------------------------------
    print(f"\n--- {mode_name} TELEMETRY ANALYSIS ({poll_count} samples, {len(trackers)} tracked Quins) ---")

    # 1. Movement Averages
    all_speeds = []
    state_speeds_agg = defaultdict(list)
    for t in trackers.values():
        all_speeds.extend(t.speeds)
        for st, spds in t.state_speeds.items():
            state_speeds_agg[st].extend(spds)

    overall_avg_speed = sum(all_speeds) / max(len(all_speeds), 1)
    print(f"\n  [MOVEMENT AVERAGES]:")
    print(f"    Overall Arena Average Speed: {overall_avg_speed:.1f} studs/s (Samples: {len(all_speeds)})")
    for st, spds in sorted(state_speeds_agg.items()):
        avg_s = sum(spds) / max(len(spds), 1)
        max_s = max(spds) if spds else 0
        print(f"    State '{st:16s}': Avg Speed = {avg_s:5.1f} studs/s | Max = {max_s:5.1f} studs/s | Samples = {len(spds)}")

    # 2. Flagged Anomaly: Prone Cockroaches (UpVector.Y < 0.70)
    all_prone_episodes = []
    for qname, t in trackers.items():
        for ep in t.prone_episodes:
            all_prone_episodes.append((qname, ep))

    print(f"\n  [ANOMALY CHECK 1: PRONE COCKROACHES (HRP laying flat on ground)]: ")
    if len(all_prone_episodes) == 0:
        print("    -> ZERO PRONE COCKROACHES DETECTED! (All Quins remained upright or recovered immediately).")
    else:
        print(f"    -> DETECTED {len(all_prone_episodes)} PRONE COCKROACH EPISODES:")
        for qname, ep in all_prone_episodes:
            print(f"       * Quin '{qname}': Duration={ep['duration']}s (t={ep['start']}s -> {ep['end']}s) | State={ep['state']} | UpY={ep['upY']} | Pos={ep['pos']}")

    # 3. Flagged Anomaly: Moving Quin Stuck in One Place (Displacement < 3 studs over 2s with speed)
    all_stalled_episodes = []
    for qname, t in trackers.items():
        for ep in t.stalled_episodes:
            all_stalled_episodes.append((qname, ep))

    print(f"\n  [ANOMALY CHECK 2: RUNNING IN PLACE / STALLED QUINS (Locomotion without translation)]: ")
    if len(all_stalled_episodes) == 0:
        print("    -> ZERO STALLED QUINS DETECTED! (Continuous net displacement maintained across movement).")
    else:
        print(f"    -> DETECTED {len(all_stalled_episodes)} RUNNING-IN-PLACE EPISODES:")
        for qname, ep in all_stalled_episodes:
            print(f"       * Quin '{qname}': Stalled for {ep['duration']}s (t={ep['start']}s -> {ep['end']}s) | State={ep['state']} | WS={ep['ws']} | Pos={ep['pos']} | Near: {ep['nearestQuin']} ({ep['nearestDist']} studs)")

    # 4. Flagged Anomaly: Collider Lock / Piling
    all_collider_locks = []
    for qname, t in trackers.items():
        for ep in t.collider_lock_episodes:
            all_collider_locks.append((qname, ep))

    print(f"\n  [ANOMALY CHECK 3: COLLIDER LOCK / BRICK STACKING (< 2.5 studs)]: ")
    if len(all_collider_locks) == 0:
        print("    -> ZERO COLLIDER LOCK EPISODES DETECTED.")
    else:
        print(f"    -> DETECTED {len(all_collider_locks)} COLLIDER LOCK EPISODES:")
        for qname, ep in all_collider_locks:
            print(f"       * Quin '{qname}' locked with '{ep['with']}' for {ep['duration']}s at {ep['pos']} (Dist={ep['dist']} studs)")

    # 5. State Transition Analysis (Flapping Check)
    flapping_instances = []
    for qname, t in trackers.items():
        # Count transitions in sliding 1-second windows
        trans = t.state_transitions
        for i, (t_curr, f_st, to_st) in enumerate(trans):
            # check how many transitions occurred within 1.0s of t_curr
            sub = [x for x in trans if 0 <= (x[0] - t_curr) <= 1.0]
            if len(sub) >= 4:
                seq = " -> ".join([x[2] for x in sub])
                flapping_instances.append((qname, t_curr, len(sub), seq))

    # De-duplicate flapping instances within 2 seconds
    dedup_flapping = []
    last_t = -10
    for inst in flapping_instances:
        if (inst[1] - last_t) > 2.0:
            dedup_flapping.append(inst)
            last_t = inst[1]

    print(f"\n  [ANOMALY CHECK 4: RAPID STATE FLAPPING / JITTER (>= 4 transitions in 1s)]: ")
    if len(dedup_flapping) == 0:
        print("    -> ZERO RAPID STATE FLAPPING DETECTED (State machine transitions are stable).")
    else:
        print(f"    -> DETECTED {len(dedup_flapping)} STATE FLAPPING EPISODES:")
        for qname, t_curr, count, seq in dedup_flapping:
            print(f"       * Quin '{qname}' at t={t_curr}s: {count} transitions in 1.0s: [{seq}]")

    cleanup(client)
    return {
        "mode": mode_name,
        "team_size": team_size,
        "duration": total_time,
        "avg_speed": overall_avg_speed,
        "state_speeds": {st: sum(spds)/max(len(spds), 1) for st, spds in state_speeds_agg.items()},
        "prone_count": len(all_prone_episodes),
        "prone_episodes": all_prone_episodes,
        "stalled_count": len(all_stalled_episodes),
        "stalled_episodes": all_stalled_episodes,
        "collider_lock_count": len(all_collider_locks),
        "collider_locks": all_collider_locks,
        "flapping_count": len(dedup_flapping),
        "flapping_episodes": dedup_flapping
    }

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # Run 2v2 Check
    res_2v2 = run_battle_adversarial_check(client, "TeamBattle_2v2", 2, duration_seconds=35)

    # Run 4v4 Check
    res_4v4 = run_battle_adversarial_check(client, "TeamBattle_4v4", 4, duration_seconds=35)

    print("\n" + "=" * 70)
    print("ADVERSARIAL & SANITY CHECK OVERALL SUMMARY:")
    print("=" * 70)
    for res in [res_2v2, res_4v4]:
        print(f"\n[{res['mode']}] (Duration: {res['duration']}s, Team Size: {res['team_size']}):")
        print(f"  * Overall Average Speed: {res['avg_speed']:.1f} studs/s")
        print(f"  * Prone Cockroach Episodes: {res['prone_count']}")
        print(f"  * Stalled / Running-In-Place Episodes: {res['stalled_count']}")
        print(f"  * Collider Lock Episodes: {res['collider_lock_count']}")
        print(f"  * State Flapping Episodes: {res['flapping_count']}")

    # Save summary report to JSON
    out_path = os.path.join(ARTIFACT_DIR, "adversarial_sanity_report.json")
    with open(out_path, "w") as f:
        json.dump([res_2v2, res_4v4], f, indent=2)
    print(f"\n[REPORT] Saved full JSON audit report to {out_path}")

if __name__ == "__main__":
    main()
