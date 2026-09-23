import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
pull_dir = r"C:\Users\User\.gemini\antigravity\scratch\studio_pull_20260922\StarterPlayer\StarterPlayerScripts"
for f in sorted(os.listdir(pull_dir)):
    p = os.path.join(pull_dir, f)
    with open(p, encoding='utf-8', errors='replace') as fp:
        lines = fp.readlines()
    print(f"=== {f} ({len(lines)} lines) ===")
    for l in lines[:4]:
        print("  " + l, end='')
