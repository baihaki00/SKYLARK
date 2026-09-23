import bpy

files = {
    'Jump': r'D:\SKYLARK\SKYLARKTEST\Jump.fbx',
    'NoHipsLoc': r'D:\SKYLARK\SKYLARKTEST\Jumping Down_NoHipsLocation.fbx',
    'GroundAnchored': r'D:\SKYLARK\SKYLARKTEST\Jumping Down_GroundAnchored.fbx'
}

for label, fpath in files.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fpath)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    scene = bpy.context.scene
    
    pbone_hips = arm.pose.bones['mixamorig:Hips']
    pbone_foot = arm.pose.bones['mixamorig:LeftFoot']
    
    print(f"\n=== Evaluation: {label} ===")
    act = bpy.data.actions[0]
    frames = [1, int(act.frame_end*0.25), int(act.frame_end*0.5), int(act.frame_end*0.75), int(act.frame_end)]
    for f in frames:
        scene.frame_set(f)
        w_hips = (arm.matrix_world @ pbone_hips.matrix).translation
        w_foot = (arm.matrix_world @ pbone_foot.matrix).translation
        print(f"  Frame {f:2d}: Hips Z={w_hips.z:6.3f}m | Foot Z={w_foot.z:6.3f}m")
