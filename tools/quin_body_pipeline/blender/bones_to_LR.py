"""Rename the Mixamo bones to Blender's left/right style so X-Axis Mirror and Symmetrize work:
mixamorig:LeftArm -> mixamorig:Arm.L, mixamorig:RightArm -> mixamorig:Arm.R. Turns X-Axis Mirror on.
Run it in Blender (Scripting tab -> Open -> Run Script) with the armature in the scene.
UNDO with bones_back_to_mixamo.py BEFORE skinning and exporting (Roblox needs the Mixamo names)."""
import bpy, re
n = 0
# (renamed in Edit Mode: a file saved in Edit Mode keeps the edit bones' names over plain renames)
for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    arm.hide_set(False)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm.data.edit_bones:
        new = re.sub(r"^mixamorig:Left(.+)$", r"mixamorig:\1.L", b.name)
        new = re.sub(r"^mixamorig:Right(.+)$", r"mixamorig:\1.R", new)
        if new != b.name:
            b.name = new
            n += 1
    arm.data.use_mirror_x = True
    bpy.ops.object.mode_set(mode='OBJECT')
print("renamed %d bones to .L/.R; X-Axis Mirror on" % n)
