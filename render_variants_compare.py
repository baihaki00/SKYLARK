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

world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (0.05, 0.06, 0.08, 1.0)
bg.inputs['Strength'].default_value = 1.0

# Ground plane
bpy.ops.mesh.primitive_plane_add(size=25, location=(0, 0, 0))
floor = bpy.context.active_object
mat_floor = bpy.data.materials.new("Floor")
mat_floor.use_nodes = True
f_bsdf = mat_floor.node_tree.nodes['Principled BSDF']
f_bsdf.inputs['Base Color'].default_value = (0.12, 0.13, 0.15, 1.0)
f_bsdf.inputs['Roughness'].default_value = 0.5
floor.data.materials.append(mat_floor)

# Lighting
bpy.ops.object.light_add(type='SUN', location=(5, -5, 10))
sun = bpy.context.active_object
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(30))

bpy.ops.object.light_add(type='POINT', location=(-3, -3, 3))
fill = bpy.context.active_object
fill.data.energy = 300.0
fill.data.color = (0.7, 0.85, 1.0)

# Camera - Looking from side-quarter angle at the 3 variants
cam_data = bpy.data.cameras.new('MainCam')
cam = bpy.data.objects.new('MainCam', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (4.0, -3.5, 1.8)
cam.rotation_euler = (math.radians(75), 0, math.radians(48))

variants = [
    ("Autofixer_Buggy (+3.87 studs)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace[x0.044].fbx", (-1.2, 0, 0), (0.9, 0.2, 0.2, 1.0)),
    ("Tuned_Locked (0.0 Locked)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Locked[x0.044].fbx", (0.0, 0, 0), (0.2, 0.6, 1.0, 1.0)),
    ("Tuned_Planted (Feet Planted)", r"D:\SKYLARK\NEW ANIMATION\Landing_Hard_Fixed\Landing_Hard_InPlace_Planted[x0.044].fbx", (1.2, 0, 0), (0.2, 0.9, 0.4, 1.0))
]

def build_skeleton_mesh(armature, color, name_prefix):
    # Material
    mat = bpy.data.materials.new(f"Mat_{name_prefix}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = 0.2
    
    # Joint material (white/bright)
    jmat = bpy.data.materials.new(f"JMat_{name_prefix}")
    jmat.use_nodes = True
    jbsdf = jmat.node_tree.nodes['Principled BSDF']
    jbsdf.inputs['Base Color'].default_value = (1.0, 1.0, 1.0, 1.0)
    jbsdf.inputs['Roughness'].default_value = 0.1
    
    mesh_objs = []
    for pb in armature.pose.bones:
        # Head sphere
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.02, location=(0,0,0))
        sph = bpy.context.active_object
        sph.data.materials.append(jmat)
        
        # Add copy transform or constraint to follow bone
        c = sph.constraints.new('COPY_TRANSFORMS')
        c.target = armature
        c.subtarget = pb.name
        mesh_objs.append(sph)
        
        # If has parent, connect cylinder
        if pb.parent:
            # Cylinder bone segment
            bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=1.0, location=(0,0,0))
            cyl = bpy.context.active_object
            cyl.data.materials.append(mat)
            
            # Use stretch to or damped track
            c1 = cyl.constraints.new('COPY_LOCATION')
            c1.target = armature
            c1.subtarget = pb.parent.name
            
            c2 = cyl.constraints.new('STRETCH_TO')
            c2.target = armature
            c2.subtarget = pb.name
            c2.rest_length = 1.0
            mesh_objs.append(cyl)
            
    return mesh_objs

for label, path, offset, color in variants:
    bpy.ops.import_scene.fbx(filepath=path)
    armature = [o for o in bpy.context.selected_objects if o.type == 'ARMATURE'][0]
    armature.location = offset
    
    # Add a glowing yellow origin marker pole
    bpy.ops.mesh.primitive_cylinder_add(radius=0.015, depth=2.5, location=(offset[0], offset[1], 1.25))
    pillar = bpy.context.active_object
    pmat = bpy.data.materials.new("Pillar")
    pmat.use_nodes = True
    pmat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1.0, 0.9, 0.1, 1.0)
    pmat.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (1.0, 0.9, 0.1, 1.0)
    pmat.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = 2.0
    pillar.data.materials.append(pmat)
    
    # Origin ring on the floor (Roblox HumanoidRootPart footprint)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.15, minor_radius=0.01, location=(offset[0], offset[1], 0.005))
    ring = bpy.context.active_object
    ring.data.materials.append(pmat)
    
    build_skeleton_mesh(armature, color, label)

# Render F30 (crouch)
scene.frame_set(30)
bpy.context.view_layer.update()
out_f30 = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\landing_hard_compare_f30.png"
scene.render.filepath = out_f30
bpy.ops.render.render(write_still=True)
print(f"Rendered F30 to {out_f30}")

# Render F98 (standing finish)
scene.frame_set(98)
bpy.context.view_layer.update()
out_f98 = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\landing_hard_compare_f98.png"
scene.render.filepath = out_f98
bpy.ops.render.render(write_still=True)
print(f"Rendered F98 to {out_f98}")
