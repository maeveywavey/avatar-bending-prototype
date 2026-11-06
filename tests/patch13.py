p = 'scripts/world.gd'
s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)
rep('''	if "--mocap" in OS.get_cmdline_user_args():
		_run_mocap_demo()
		return''', '''	if "--mocap" in OS.get_cmdline_user_args():
		_run_mocap_demo()
		return
	if "--play" in OS.get_cmdline_user_args():
		_run_play_demo()
		return''')
rep('''	_run_demo_script()
	var rate''', '''	_run_demo_script()
	if "--play" in OS.get_cmdline_user_args():
		_play_capture(dt)
		return
	var rate''')
s += '''
# ---------------------------------------------------------------- full playthrough check
# stand, ready, walk in ready, stop, draw, hold, walk holding, strike, release, stand, walk.
# A camera follows from the side; every frame the largest single-frame bone rotation is logged so pops
# show up as numbers, not only in pictures.

var _play_cam: Camera3D
var _prev_pose := {}
var _play_events := [
	[1.0, "tap", "ready_toggle"], [4.0, "press", "move_forward"], [5.6, "release", "move_forward"],
	[7.5, "press", "draw"], [11.5, "press", "move_forward"], [12.8, "release", "move_forward"],
	[14.5, "tap", "strike"], [17.0, "release", "draw"], [18.0, "tap", "ready_toggle"],
	[20.0, "press", "move_forward"], [21.2, "release", "move_forward"]]

func _run_play_demo() -> void:
	while not _play_events.is_empty() and _demo_t >= float(_play_events[0][0]):
		var e: Array = _play_events.pop_front()
		match e[1]:
			"tap": _tap(e[2])
			"press": Input.action_press(e[2], 0.5)
			"release": Input.action_release(e[2])
		print("EVENT t=%.2f %s %s" % [_demo_t, e[1], e[2]])

func _play_capture(dt: float) -> void:
	if _play_cam == null:
		_play_cam = Camera3D.new()
		add_child(_play_cam)
		_play_cam.fov = 50.0
		_play_cam.current = true
	var side := "--front" not in OS.get_cmdline_user_args()
	var pp := player.global_position
	var f := player.global_transform.basis.z   # the model faces -Z of the player... use world axes instead
	var off := Vector3(4.2, 1.3, 0.0) if side else Vector3(0.0, 1.4, -4.2)
	_play_cam.global_position = pp + off
	_play_cam.look_at(pp + Vector3(0, 0.9, 0))
	# largest bone rotation change since the last frame
	var sk := player.skel
	var worst := 0.0
	var worst_b := ""
	for b in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(b)
		if _prev_pose.has(b):
			var d := rad_to_deg((_prev_pose[b] as Quaternion).angle_to(q))
			if d > worst:
				worst = d
				worst_b = sk.get_bone_name(b)
		_prev_pose[b] = q
	var pel := sk.get_bone_pose_position(sk.find_bone("pelvis"))
	print("F t=%.3f state=%s node=%s worst=%.1f %s pel=%s" % [_demo_t, player._anim_state, player._playback.get_current_node(), worst, worst_b, pel.snapped(Vector3(0.01, 0.01, 0.01))])
	if _demo_t >= _next_cap:
		_next_cap = _demo_t + 1.0 / 10.0
		get_viewport().get_texture().get_image().save_png("%s/p%05d.png" % [_demo_dir, int(_demo_t * 100.0)])
	if _demo_t > 22.5:
		get_tree().quit()
'''
open(p, 'w').write(s)
