extends SceneTree
## Poses the mannequin from a mocap clip and saves a profile-view PNG per requested time, so each can be
## set beside the video frame it came from.
## usage: godot --path . --script res://tools/pose/compare.gd -- <clip name> <view> <t1> <t2> ...
## view: "right" (camera on the character's right, as in full_right) or "left"

var skel: Skeleton3D
var clip: Dictionary
var cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var clip_name: String = args[0]
	var view: String = args[1]
	var times := []
	for i in range(2, args.size()):
		times.append(float(args[i]))
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.88, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	root.add_child(ground)
	var model: Node = (load("res://assets/Mannequin_F.glb") as PackedScene).instantiate()
	root.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	cam = Camera3D.new()
	cam.fov = 38.0
	root.add_child(cam)
	var side := -1.0 if view == "right" else 1.0
	var cpos := Vector3(side * 4.2, 1.0, 0.0)
	if view.begins_with("cam:"):
		# cam:<x>,<y>,<z> camera position in skeleton space (X = character's left, Z = its front)
		var c := view.substr(4).split(",")
		cpos = Vector3(float(c[0]), float(c[1]), float(c[2]))
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - cpos, Vector3.UP), cpos)
	cam.current = true
	get_root().size = Vector2i(540, 960)

	if clip_name != "rest":
		var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join("mocap/clips/%s.json" % clip_name), FileAccess.READ)
		clip = JSON.parse_string(f.get_as_text())
	var out_dir := ProjectSettings.globalize_path("res://").path_join("mocap/compare")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", mi.name, " visible=", mi.is_visible_in_tree(), " aabb=", mi.get_aabb(), " gpos=", mi.global_position, " layers=", mi.layers)
	print("CAM ", cam.global_position, " fwd ", -cam.global_transform.basis.z, " cull ", cam.cull_mask)
	for t in times:
		if clip_name != "rest":
			_apply(float(t) - float(clip["range"][0]))
		await process_frame
		await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png("%s/%s_%05d.png" % [out_dir, clip_name, int(round(t * 10.0))])
	quit()

func _apply(t: float) -> void:
	var fps: float = clip["fps"]
	var i := clampi(int(round(t * fps)), 0, int(clip["frames"]) - 1)
	skel.reset_bone_poses()
	for bn in clip["bones"]:
		var bi := skel.find_bone(bn)
		var q: Array = clip["bones"][bn][i]
		skel.set_bone_pose_rotation(bi, Quaternion(q[0], q[1], q[2], q[3]).normalized())
	var pel := skel.find_bone("pelvis")
	var off: Array = clip["pelvis_offset"][i]
	var root_b := skel.get_bone_global_rest(skel.get_bone_parent(pel)).basis
	skel.set_bone_pose_position(pel, skel.get_bone_rest(pel).origin + root_b.inverse() * Vector3(off[0], off[1], off[2]))
