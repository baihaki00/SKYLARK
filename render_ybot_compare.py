import bpy
import mathutils
import math
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080

# Sleek studio backdrop
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.05, 0.06, 0.08, 1.0)

# Ground
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
floor = bpy.context.active_object
mat_floor = bpy.data.materials.new("Floor")
mat_floor.use_nodes = True
mat_floor.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.12, 0.13, 0.15, 1.0)
mat_floor.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.4
floor.data.materials.append(mat_floor)

# Lighting: Key, Fill, Rim
bpy.ops.object.light_add(type='SUN', location=(15, -15, 25))
sun = bpy.context.active_object
sun.data.energy = 5.0
sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(45))

bpy.ops.object.light_add(type='POINT', location=(-8, -12, 10))
fill = bpy.context.active_object
fill.data.energy = 1500.0
fill.data.color = (0.75, 0.88, 1.0)

bpy.ops.object.light_add(type='POINT', location=(0, 10, 8))
rim = bpy.context.active_object
rim.data.energy = 1000.0
rim.data.color = (1.0, 0.95, 0.8)

# Target empty at center of action
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 2.0))
target = bpy.context.active_object

# Camera - Looking closer from side-quarter angle
cam_data = bpy.data.cameras.new('MainCam')
cam_data.lens = 50
cam = bpy.data.objects.new('MainCam', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

tt = cam.constraints.new('TRACK_TO')
tt.target = target
tt.track_axis = 'TRACK_NEGATIVE_Z'
tt.up_axis = 'UP_Y'

# Closer camera
cam.location = (8.0, -8.0, 4.0)

variants = [
    ("Autofixer (Broken +3.87 Studs)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace[x0.044].fbx", (-3.0, 0, 0), (0.9, 0.25, 0.25, 1.0)),
    ("Locked Center (Pelvis Strictly at 0)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Locked[x0.044].fbx", (0.0, 0, 0), (0.2, 0.6, 1.0, 1.0)),
    ("Planted Center (Biomechanical Zero-Drift)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Planted[x0.044].fbx", (3.0, 0, 0), (0.25, 0.9, 0.45, 1.0))
]

ybot_path = r"D:\SKYLARK\YBOT\Y Bot.fbx"

for label, anim_path, offset, color in variants:
    bpy.ops.import_scene.fbx(filepath=ybot_path)
    ybot_objs = list(bpy.context.selected_objects)
    ybot_arm = [o for o in ybot_objs if o.type == 'ARMATURE'][0]
    
    bpy.ops.import_scene.fbx(filepath=anim_path)
    anim_objs = list(bpy.context.selected_objects)
    anim_arm = [o for o in anim_objs if o.type == 'ARMATURE' and o != ybot_arm][0]
    anim_action = anim_arm.animation_data.action
    
    ybot_arm.animation_data.action = anim_action
    ybot_arm.location = offset
    
    bpy.data.objects.remove(anim_arm, do_unlink=True)
    
    mat = bpy.data.materials.new(f"Mat_{label}")
    mat.use_nodes = True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = color
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.35
    for o in ybot_objs:
        if o.type == 'MESH':
            o.data.materials.clear()
            o.data.materials.append(mat)
            
    # Root pillar (HumanoidRootPart center line)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=6.5, location=(offset[0], offset[1], 3.25))
    pillar = bpy.context.active_object
    pmat = bpy.data.materials.new(f"PillarMat_{label}")
    pmat.use_nodes = True
    pmat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1.0, 0.85, 0.1, 1.0)
    pmat.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (1.0, 0.85, 0.1, 1.0)
    pmat.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = 3.5
    pillar.data.materials.append(pmat)
    
    # Root ring (HumanoidRootPart boundary)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.7, minor_radius=0.025, location=(offset[0], offset[1], 0.02))
    ring = bpy.context.active_object
    ring.data.materials.append(pmat)

# Render F30 (Crouch / Ground Impact)
scene.frame_set(30)
bpy.context.view_layer.update()
out_f30 = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\landing_hard_compare_f30.png"
scene.render.filepath = out_f30
bpy.ops.render.render(write_still=True)
print(f"Rendered F30 to {out_f30}")

# Render F98 (Final Standing Pose)
scene.frame_set(98)
bpy.context.view_layer.update()
out_f98 = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\landing_hard_compare_f98.png"
scene.render.filepath = out_f98
bpy.ops.render.render(write_still=True)
print(f"Rendered F98 to {out_f98}")
