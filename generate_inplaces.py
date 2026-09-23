import bpy
import os

def create_inplace_versions():
    src_path = r'D:\SKYLARK\SKYLARKTEST\Jumping Down.fbx'
    out_dir = r'D:\SKYLARK\SKYLARKTEST'
    
    # -------------------------------------------------------------
    # 1. HORIZONTAL IN-PLACE ONLY (Keep Y vertical motion untouched)
    # -------------------------------------------------------------
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src_path)
    
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    strip = act.layers[0].strips[0]
    cb = strip.channelbags[0]
    
    fcs = {fc.data_path + f'[{fc.array_index}]': fc for fc in cb.fcurves}
    loc_x = fcs['pose.bones["mixamorig:Hips"].location[0]']
    loc_z = fcs['pose.bones["mixamorig:Hips"].location[2]']
    
    start_x = loc_x.keyframe_points[0].co[1]
    start_z = loc_z.keyframe_points[0].co[1]
    
    # Flatten X and Z to start values
    for kp in loc_x.keyframe_points:
        kp.co[1] = start_x
        kp.handle_left[1] = start_x
        kp.handle_right[1] = start_x
        
    for kp in loc_z.keyframe_points:
        kp.co[1] = start_z
        kp.handle_left[1] = start_z
        kp.handle_right[1] = start_z
        
    out_horizontal = os.path.join(out_dir, 'Jumping Down_InPlace_Horizontal.fbx')
    bpy.ops.export_scene.fbx(filepath=out_horizontal, use_selection=False, add_leaf_bones=False, bake_anim=True)
    print(f'Exported: {out_horizontal}')
    
    # -------------------------------------------------------------
    # 2. FULL IN-PLACE (Horizontal locked + Vertical Normalized)
    # Ledge height offset (86.01 units) ramped out during freefall phase
    # so landing frame height matches starting frame height
    # -------------------------------------------------------------
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src_path)
    
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    strip = act.layers[0].strips[0]
    cb = strip.channelbags[0]
    
    fcs = {fc.data_path + f'[{fc.array_index}]': fc for fc in cb.fcurves}
    loc_x = fcs['pose.bones["mixamorig:Hips"].location[0]']
    loc_y = fcs['pose.bones["mixamorig:Hips"].location[1]']
    loc_z = fcs['pose.bones["mixamorig:Hips"].location[2]']
    
    start_x = loc_x.keyframe_points[0].co[1]
    start_z = loc_z.keyframe_points[0].co[1]
    start_y = loc_y.keyframe_points[0].co[1] # +31.029
    end_y = loc_y.keyframe_points[-1].co[1]  # -54.982
    delta_y = end_y - start_y # -86.011
    
    for kp in loc_x.keyframe_points:
        kp.co[1] = start_x
        kp.handle_left[1] = start_x
        kp.handle_right[1] = start_x
        
    for kp in loc_z.keyframe_points:
        kp.co[1] = start_z
        kp.handle_left[1] = start_z
        kp.handle_right[1] = start_z
        
    # For Y: In a jump down, frames 1-28 are on ledge, frames 28-45 are falling, frames 46-76 are landing
    # To normalize Y so landing baseline (-54.98) aligns with starting standing height:
    # We remove the ledge height delta so the landing crouch is relative to standing height.
    # Baseline standing height = start_y (31.03)
    # Landing ground height was end_y (-54.98).
    # If the character landed on the same plane, the ground is 86 units higher!
    # So we add 86.011 to all landing frames, with a smooth transition during the airborne phase (frames 28 to 46).
    for kp in loc_y.keyframe_points:
        f = kp.co[0]
        if f <= 28:
            # Pre-jump on ledge: unchanged
            offset = 0.0
        elif f >= 46:
            # Landed on ground: compensate the full ledge drop
            offset = -delta_y # +86.011
        else:
            # Airborne transition (linear / smoothstep blend)
            t = (f - 28.0) / (46.0 - 28.0)
            # smoothstep
            s = t * t * (3.0 - 2.0 * t)
            offset = -delta_y * s
            
        kp.co[1] += offset
        kp.handle_left[1] += offset
        kp.handle_right[1] += offset
        
    out_full = os.path.join(out_dir, 'Jumping Down_InPlace_Full.fbx')
    bpy.ops.export_scene.fbx(filepath=out_full, use_selection=False, add_leaf_bones=False, bake_anim=True)
    print(f'Exported: {out_full}')

create_inplace_versions()
