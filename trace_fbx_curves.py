import struct
import zlib
from parse_fbx import read_node

with open(r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx', 'rb') as f:
    f.seek(27) # past header
    root_nodes = {}
    while True:
        node = read_node(f, True)
        if node is None:
            break
        root_nodes[node['name']] = node
        
objects = root_nodes['Objects']['children']
connections = root_nodes['Connections']['children']

print(f"Total objects: {len(objects)}")
print(f"Total connections: {len(connections)}")

# Find Model nodes (bones)
models = {}
for obj in objects:
    if obj['name'] == 'Model':
        model_id = obj['props'][0]
        model_name = obj['props'][1]
        models[model_id] = model_name
        if 'Hips' in model_name:
            print(f"Found Hips Model: ID={model_id}, Name={model_name}")

# Find AnimationCurveNode connected to Hips Translation
# In FBX, connections are: ["OO", child_id, parent_id] or ["OP", child_id, parent_id, prop_name]
anim_curve_nodes = {}
for obj in objects:
    if obj['name'] == 'AnimationCurveNode':
        acn_id = obj['props'][0]
        acn_name = obj['props'][1]
        anim_curve_nodes[acn_id] = {'name': acn_name, 'curves': {}}
        
anim_curves = {}
for obj in objects:
    if obj['name'] == 'AnimationCurve':
        ac_id = obj['props'][0]
        anim_curves[ac_id] = obj

print(f"AnimationCurveNodes: {len(anim_curve_nodes)}")
print(f"AnimationCurves: {len(anim_curves)}")

# Trace connections to find Hips T (Translation)
for conn in connections:
    props = conn['props']
    # conn['props'] is usually ['OO'/'OP', child_id, parent_id, optional prop_name]
    conn_type = props[0]
    child_id = props[1]
    parent_id = props[2]
    prop_name = props[3] if len(props) > 3 else None
    
    if parent_id in models and 'Hips' in models[parent_id]:
        print(f"Connected to Hips ({models[parent_id]}): type={conn_type}, child_id={child_id}, prop={prop_name}")
        if child_id in anim_curve_nodes:
            print(f"  -> AnimCurveNode: {anim_curve_nodes[child_id]['name']}")

    if parent_id in anim_curve_nodes:
        acn = anim_curve_nodes[parent_id]
        if prop_name:
            acn['curves'][prop_name] = child_id
            
# Print the curves connected to Hips's translation curve node
for acn_id, acn in anim_curve_nodes.items():
    if 'T' in acn['name'] and any(parent_id in models and 'Hips' in models[parent_id] for conn in connections if conn['props'][1] == acn_id):
        print(f"\nHips Translation CurveNode {acn_id} ({acn['name']}) has curves:")
        for axis, c_id in acn['curves'].items():
            curve_obj = anim_curves[c_id]
            # Inspect curve children: KeyTime, KeyValueFloat
            times = None
            vals = None
            for child in curve_obj['children']:
                if child['name'] == 'KeyTime':
                    times = child['props'][0]
                elif child['name'] == 'KeyValueFloat':
                    vals = child['props'][0]
            print(f"  Axis '{axis}': CurveID={c_id}, KeysCount={vals[1] if vals else 0}")
            if vals:
                floats = struct.unpack(f'<{vals[1]}f', vals[2])
                print(f"    Sample values (first 3): {floats[:3]}")
                print(f"    Sample values (last 3): {floats[-3:]}")
