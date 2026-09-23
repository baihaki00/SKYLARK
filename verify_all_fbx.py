import bpy
import os

files = ['Jump.fbx', 'Jumping Down.fbx', 'Jumping Down_InPlace_Horizontal.fbx', 'Jumping Down_InPlace_Full.fbx']

for fname in files:
    fpath = os.path.join(r'D:\SKYLARK\SKYLARKTEST', fname)
    print('\n' + '='*75)
    print(f'EVALUATION: {fname}')
    print('='*75)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fpath)
    
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    act = bpy.data.actions[0]
    strip = act.layers[0].strips[0]
    cb = strip.channelbags[0]
    
    fcs = {fc.data_path + f'[{fc.array_index}]': fc for fc in cb.fcurves}
    loc_x = fcs.get('pose.bones["mixamorig:Hips"].location[0]')
    loc_y = fcs.get('pose.bones["mixamorig:Hips"].location[1]')
    loc_z = fcs.get('pose.bones["mixamorig:Hips"].location[2]')
    
    if loc_x and loc_y and loc_z:
        x_vals = [kp.co[1] for kp in loc_x.keyframe_points]
        y_vals = [kp.co[1] for kp in loc_y.keyframe_points]
        z_vals = [kp.co[1] for kp in loc_z.keyframe_points]
        
        print(f"Hips Local X: Start={x_vals[0]:8.2f} | End={x_vals[-1]:8.2f} | Net={x_vals[-1]-x_vals[0]:8.2f} | Span={max(x_vals)-min(x_vals):8.2f}")
        print(f"Hips Local Y: Start={y_vals[0]:8.2f} | End={y_vals[-1]:8.2f} | Net={y_vals[-1]-y_vals[0]:8.2f} | Span={max(y_vals)-min(y_vals):8.2f}")
        print(f"Hips Local Z: Start={z_vals[0]:8.2f} | End={z_vals[-1]:8.2f} | Net={z_vals[-1]-z_vals[0]:8.2f} | Span={max(z_vals)-min(z_vals):8.2f}")
        
    scene = bpy.context.scene
    pbone = arm.pose.bones['mixamorig:Hips']
    
    scene.frame_set(1)
    w_start = (arm.matrix_world @ pbone.matrix).translation.copy()
    scene.frame_set(int(act.frame_end))
    w_end = (arm.matrix_world @ pbone.matrix).translation.copy()
    w_delta = w_end - w_start
    print(f"Net World Displacement: (X={w_delta.x:6.2f}m, Y={w_delta.y:6.2f}m, Z={w_delta.z:6.2f}m) | Distance: {w_delta.length:6.2f}m")
