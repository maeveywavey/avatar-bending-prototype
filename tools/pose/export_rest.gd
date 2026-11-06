extends SceneTree
## Writes mocap/skeleton_rest.json: the mannequin's rest pose (local and global, skeleton space) and the
## hinge axis of each elbow and knee, measured from the locomotion libraries (the axis, in the bone's own
## frame, about which that bone rotates when it bends).

func _q(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]

func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _init() -> void:
	var m: Node = (load("res://assets/Mannequin_F.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var out := {"bones": [], "hinge": {}}
	for i in sk.get_bone_count():
		var rl := sk.get_bone_rest(i)
		var rg := sk.get_bone_global_rest(i)
		out["bones"].append({
			"name": sk.get_bone_name(i), "parent": sk.get_bone_parent(i),
			"rest_local_q": _q(rl.basis.get_rotation_quaternion()), "rest_local_o": _v(rl.origin),
			"rest_global_q": _q(rg.basis.get_rotation_quaternion()), "rest_global_o": _v(rg.origin),
		})
	# hinge axes: average the rotation axis of the bone's local rotation relative to rest, weighted by angle
	var acc := {}
	for f in ["UAL1_Standard", "UAL2_Standard"]:
		var s: Node = (load("res://assets/%s.glb" % f) as PackedScene).instantiate()
		var ap: AnimationPlayer = s.find_children("*", "AnimationPlayer", true, false)[0]
		var lib := ap.get_animation_library("")
		for an in lib.get_animation_list():
			if an not in ["Walk", "Jog_Fwd", "Punch_Cross", "Punch_Jab", "Sword_Attack", "Push", "Spell_Simple_Shoot", "Crouch_Fwd", "Sprint", "Roll", "Jump", "Farm_Watering", "Consume", "PickUp_Table", "Melee_Hook", "OverhandThrow", "TreeChopping", "Sword_Regular_A", "Walk_Carry"]:
				continue
			var a := lib.get_animation(an)
			for t in a.get_track_count():
				if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				var path := str(a.track_get_path(t))
				var bn := path.get_slice(":", 1)
				if bn not in ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]:
					continue
				var bi := sk.find_bone(bn)
				var rest_q := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
				if not acc.has(bn):
					acc[bn] = Vector3.ZERO
				for k in a.track_get_key_count(t):
					var q: Quaternion = a.track_get_key_value(t, k)
					var rel := rest_q.inverse() * q
					var ang := rel.get_angle()
					var ax := rel.get_axis()
					if ang > PI:
						ang = TAU - ang
						ax = -ax
					# keep the sign consistent with the running sum
					if acc[bn].dot(ax) < 0.0:
						ax = -ax
					acc[bn] += ax * ang
	for bn in acc:
		out["hinge"][bn] = _v(acc[bn].normalized())
	var path := ProjectSettings.globalize_path("res://").path_join("mocap/skeleton_rest.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	print("writing ", path, " ", f)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote ", out["bones"].size(), " bones; hinge: ", out["hinge"])
	quit()
