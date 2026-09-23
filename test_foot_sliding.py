
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'D:\SKYLARK\NEW ANIMATION\Landing_Hard.fbx')
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
scene = bpy.context.scene

hips_pb = arm.pose.bones['mixamorig:Hips']
lf_pb = arm.pose.bones['mixamorig:LeftFoot']
rf_pb = arm.pose.bones['mixamorig:RightFoot']

# Store original keyframe locations
act = arm.animation_data.action

def evaluate_foot_sliding(mode_name, x_func, z_func):
    prev_lf = None
    prev_rf = None
    total_slide_lf = 0.0
    total_slide_rf = 0.0
    
    # Ground contact frames are roughly frames 6 to 75
    contact_start = 6
    contact_end = 75
    
    for f in range(contact_start, contact_end + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        
        orig_x = hips_pb.location.x
        orig_y = hips_pb.location.y
        orig_z = hips_pb.location.z
        
        hips_pb.location.x = x_func(orig_x, f)
        hips_pb.location.z = z_func(orig_z, f)
        bpy.context.view_layer.update()
        
        lw = arm.matrix_world @ lf_pb.head
        rw = arm.matrix_world @ rf_pb.head
        
        if prev_lf is not None:
            # horizontal delta (X and Y in Blender world)
            dlf = ((lw.x - prev_lf.x)**2 + (lw.y - prev_lf.y)**2)**0.5
            drf = ((rw.x - prev_rf.x)**2 + (rw.y - prev_rf.y)**2)**0.5
            total_slide_lf += dlf
            total_slide_rf += drf
            
        prev_lf = lw.copy()
        prev_rf = rw.copy()
        
    print(f'Mode: {mode_name:30s} | LF Slide: {total_slide_lf:.4f}m ({total_slide_lf/0.044*0.01:.2f} studs) | RF Slide: {total_slide_rf:.4f}m ({total_slide_rf/0.044*0.01:.2f} studs)')

# 1. Original (unmodified)
evaluate_foot_sliding('Original Mixamo', lambda x, f: x, lambda z, f: z)

# 2. Current Autofixer (Z locked to frame 1 = 87.90)
evaluate_foot_sliding('Current Autofixer (Z=87.90 locked)', lambda x, f: 6.946, lambda z, f: 87.902)

# 3. Pure Locked Center (X=0.0, Z=0.0)
evaluate_foot_sliding('Pure Locked Center (X=0, Z=0)', lambda x, f: 0.0, lambda z, f: 0.0)

# 4. Centered Dynamic Recoil (Z relative to end frame 98.12)
evaluate_foot_sliding('Centered Dynamic (Z - 98.12)', lambda x, f: x - (-0.99), lambda z, f: z - 98.12)
