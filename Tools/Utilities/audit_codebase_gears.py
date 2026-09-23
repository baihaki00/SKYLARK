import os
import glob

scratch_dir = r"C:\Users\User\.gemini\antigravity\scratch"
lua_files = [f for f in os.listdir(scratch_dir) if f.endswith(".lua")]

states = []
modules = []
configs = []
servers = []
clients = []

for f in sorted(lua_files):
    fpath = os.path.join(scratch_dir, f)
    size = os.path.getsize(fpath)
    with open(fpath, "r", encoding="utf-8", errors="ignore") as fp:
        lines = len(fp.readlines())
    
    info = (f, size, lines)
    if "State" in f:
        states.append(info)
    elif "Config" in f or "Data" in f or "Ids" in f:
        configs.append(info)
    elif f in ["Server.lua", "QuinSpawner.lua", "QuinRosterService.lua", "BattleSimulationHarness.lua", "GameModeManager.lua", "AnimationLabServer.lua", "DeathDiagnostic.lua", "DebugManager.lua", "QuinDebugTracker.lua", "SmoothLandingAI.lua", "Main.lua"]:
        servers.append(info)
    elif f in ["AnimationLabController.lua", "SmoothCamera.lua", "QuinDebugHUD.lua", "AIGhostHandler.lua", "MasterDebugUI.lua", "TheArchitectCode.lua"]:
        clients.append(info)
    else:
        modules.append(info)

print("="*60)
print(f"STATES ({len(states)} files, {sum(x[2] for x in states)} lines):")
print("="*60)
for f, size, lines in states:
    print(f"  {f:<32} {lines:>4} lines ({size:>5} bytes)")

print("\n" + "="*60)
print(f"MODULES ({len(modules)} files, {sum(x[2] for x in modules)} lines):")
print("="*60)
for f, size, lines in modules:
    print(f"  {f:<32} {lines:>4} lines ({size:>5} bytes)")

print("\n" + "="*60)
print(f"CONFIGS & DATA ({len(configs)} files, {sum(x[2] for x in configs)} lines):")
print("="*60)
for f, size, lines in configs:
    print(f"  {f:<32} {lines:>4} lines ({size:>5} bytes)")

print("\n" + "="*60)
print(f"SERVER & CLIENT INFRASTRUCTURE ({len(servers)+len(clients)} files):")
print("="*60)
for f, size, lines in servers + clients:
    print(f"  {f:<32} {lines:>4} lines ({size:>5} bytes)")
