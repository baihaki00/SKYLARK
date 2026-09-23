import sys
sys.path.append(r'C:\Users\User\.gemini\antigravity\scratch')
from parse_fbx import read_node

with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx', 'rb') as f:
    f.seek(27)
    root = {}
    while True:
        n = read_node(f, True)
        if not n: break
        root[n['name']] = n

objs = root['Objects']['children']
models = [o for o in objs if o['name'] == 'Model']

print(f"Total Models (bones/objects): {len(models)}")
for m in models:
    name = m['props'][1]
    for ch in m['children']:
        if ch['name'] == 'Properties70':
            for p in ch['children']:
                if p['props'][0] == 'Lcl Translation':
                    vals = p['props'][4:7]
                    if any(abs(v) > 1e-4 for v in vals):
                        print(f"  {name:30s} Lcl Translation: {vals}")
