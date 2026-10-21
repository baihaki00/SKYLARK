"""Put the Mixamo bone names back: mixamorig:Arm.L -> mixamorig:LeftArm, mixamorig:Arm.R -> mixamorig:RightArm.
Run it (Scripting tab -> Open -> Run Script) when you're done fitting, BEFORE skinning and exporting.
(If a mesh is already skinned, Blender renames its vertex groups along with the bones.)"""
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
        new = re.sub(r"^mixamorig:(.+)\.L$", r"mixamorig:Left\1", b.name)
        new = re.sub(r"^mixamorig:(.+)\.R$", r"mixamorig:Right\1", new)
        if new != b.name:
            b.name = new
            n += 1
    arm.data.use_mirror_x = False
    bpy.ops.object.mode_set(mode='OBJECT')
left = [b.name for a in bpy.data.objects if a.type == 'ARMATURE' for b in a.data.bones if b.name.endswith((".L", ".R"))]
print("restored %d Mixamo names; still .L/.R: %s" % (n, left or "none"))
