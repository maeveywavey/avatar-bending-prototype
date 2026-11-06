p = 'scripts/bend_pose.gd'
s = open(p).read()

s = s.replace('''var draw_u := 0.0                       # 0..1 progress of the draw
var draw_dir := Vector3(0, 0, -1)       # horizontal direction to the source, player space''', '''var draw_variant := 0
var reach_u := 0.0                      # 0..1 reaching out to the water (the water does not move)
var pull_u := 0.0                       # 0..1 pulling the water in (the water moves with this)
var draw_dir := Vector3(0, 0, -1)       # horizontal direction to the source, player space
var src_local := Vector3(0, 0.9, -4.0)  # water surface of the source, player space''')

s = s.replace('''const CHEST := Vector3(0, 1.28, 0)''', '''const CHEST := Vector3(0, 1.28, 0)

## Three attempts at the draw. Times in seconds. Angles in radians, positive turns left.
## lag: how far each spine segment trails the one below it (a rolling body wave).
## depth/back: how far the hands sweep down and back in the pull. spiral: extra circling of the hands.
const VARIANTS := [
	{"name": "sweep", "reach_t": 0.75, "hold_t": 0.12, "pull_t": 1.6, "lean_peak": 0.55, "lean_back": 0.10,
		"depth": 0.50, "back": 0.22, "yaw_reach": -0.15, "yaw_end": 0.35, "lag": 0.10, "step": 0.40,
		"drop": 0.11, "spiral": 0.0, "elbow_up": 0.0, "sway": 0.0},
	{"name": "spiral", "reach_t": 0.65, "hold_t": 0.08, "pull_t": 1.8, "lean_peak": 0.45, "lean_back": 0.18,
		"depth": 0.58, "back": 0.35, "yaw_reach": 0.35, "yaw_end": -0.70, "lag": 0.18, "step": 0.35,
		"drop": 0.14, "spiral": 0.12, "elbow_up": 0.3, "sway": 0.0},
	{"name": "wave", "reach_t": 0.90, "hold_t": 0.15, "pull_t": 2.0, "lean_peak": 0.70, "lean_back": 0.22,
		"depth": 0.38, "back": 0.15, "yaw_reach": 0.0, "yaw_end": 0.25, "lag": 0.30, "step": 0.45,
		"drop": 0.16, "spiral": 0.0, "elbow_up": 0.8, "sway": 0.07},
]''')

a = s.index("func _reach() -> float:")
b = s.index("func _process_modification()")
s = s[:a] + '''func _v() -> Dictionary:
	return VARIANTS[draw_variant]

func _reach() -> float:
	return _ease(reach_u)

func _pull() -> float:
	return _ease(pull_u)

''' + s[b:]

s = s.replace('''	var rch := _reach() * w_draw
	var pul := _pull()''', '''	var vd := _v()
	var rch := _reach() * w_draw
	var pul := _pull()''')
s = s.replace('''		step_goal = 0.40 * _reach() * (1.0 - 0.5 * pul) * w_draw''', '''		step_goal = vd["step"] * _ease(reach_u / 0.6) * (1.0 - 0.5 * pul) * w_draw''')
s = s.replace('''	off += d_h * 0.15 * rch * (1.0 - 0.75 * pul) + Vector3(0, -0.11 * rch * (1.0 - pul) + 0.02 * pul * w_draw, 0)''', '''	off += d_h * 0.15 * rch * (1.0 - 0.75 * pul) + Vector3(0, -vd["drop"] * rch * (1.0 - pul) + 0.02 * pul * w_draw, 0)
	off += Vector3(sin(pull_u * TAU) * vd["sway"], 0, 0) * w_draw * sin(PI * pull_u)''')
s = s.replace('''	var hip_yaw := (-sin(weave_t * 0.8) * 0.12 * w_hold + wind * 0.32 * w_strike
			+ atan2(-d_h.x, -d_h.z) * 0.25 * rch) * w_ready''', '''	var hip_draw := (vd["yaw_reach"] * rch * (1.0 - pul) + vd["yaw_end"] * sin(PI * pul)) * 0.5 * w_draw
	var hip_yaw := (-sin(weave_t * 0.8) * 0.12 * w_hold + wind * 0.32 * w_strike
			+ atan2(-d_h.x, -d_h.z) * 0.25 * rch + hip_draw) * w_ready''')

a = s.index("	var sway := sin(weave_t * 0.8) * 0.14 * w_hold")
b = s.index("	var head_yaw :=")
s = s[:a] + '''	var sway := sin(weave_t * 0.8) * 0.14 * w_hold
	var yaw_base := clampf(look_yaw, -1.2, 1.2) * 0.85 * w_ready + sway - hip_yaw * 0.6
	var lean_base := 0.08 * w_ready + 0.07 * sin(weave_t * 0.55) * w_hold
	if w_strike > 0.0:
		yaw_base += wind * 0.5 * w_strike
		lean_base += maxf(wind, 0.0) * 0.24 * w_strike
	var right_skel := (basis_skel * Vector3.RIGHT).normalized()
	var names := ["spine_01", "spine_02", "spine_03"]
	var shares := [0.25, 0.35, 0.4]
	var span := maxf(1.0 - vd["lag"] * 2.0, 0.3)
	for k in 3:
		# each segment trails the one below it, so the body rolls through the motion
		var pk := _ease((pull_u - vd["lag"] * k) / span)
		var lean_k := lean_base + (vd["lean_peak"] * _reach() * (1.0 - pk) - vd["lean_back"] * sin(PI * pk)) * w_draw
		var yaw_k := yaw_base + (vd["yaw_reach"] * _reach() * (1.0 - pk) + vd["yaw_end"] * sin(PI * pk)) * w_draw
		var q := Quaternion(Vector3.UP, yaw_k * shares[k])
		var q2 := Quaternion(right_skel, -lean_k * shares[k])
		_rotate_global(_b[names[k]], q * q2)
	var yaw_total := yaw_base
''' + s[b:]

a = s.index("	# --- arms\n	for side in")
b = s.index("func _capture_pins()")
s = s[:a] + '''	# --- arms
	var sc := skel.global_transform.basis.get_scale().x
	var to_local := to_skel.affine_inverse()
	for side in ["l", "r"]:
		var up_i: int = _b["upperarm_" + side]
		var lo_i: int = _b["lowerarm_" + side]
		var ha_i: int = _b["hand_" + side]
		var sh_s := skel.get_bone_global_pose(up_i).origin
		var sh := to_local * sh_s
		var arm_len := (sh_s.distance_to(skel.get_bone_global_pose(lo_i).origin)
				+ skel.get_bone_global_pose(lo_i).origin.distance_to(skel.get_bone_global_pose(ha_i).origin)) * sc
		var target_local := _hand_target(side, sh, arm_len)
		var tgt := to_skel * target_local
		var out_local := Vector3(1 if side == "r" else -1, 0, 0)
		var raise: float = vd["elbow_up"] * sin(PI * pul) * w_draw
		var pole_local := out_local * 0.9 + Vector3(0, -0.6 + raise, 0.35)
		var pole := basis_skel * pole_local
		# a light bend at the elbow: long and reaching at the water, softer while pulling
		var ext := lerpf(0.97, 0.94, rch) - 0.13 * sin(PI * pul) * w_draw
		_ik(up_i, lo_i, ha_i, tgt, pole, w_ready, ext)
		var palm := skel.global_transform * skel.get_bone_global_pose(_b["middle_01_" + side]).origin
		hand_world[side] = palm

''' + s[b:]

a = s.index("func _draw(side: String) -> Vector3:")
b = s.index("func _weave(side: String)")
s = s[:a] + '''func _draw(side: String, sh: Vector3, arm_len: float) -> Vector3:
	var s := 1.0 if side == "r" else -1.0
	var vd := _v()
	var lag := 0.0 if side == "r" else 0.08
	var re := _ease(reach_u)
	var pe := _ease(pull_u - lag)
	var to_src := (src_local + Vector3(0, 0.15, 0)) - sh
	var dir := to_src.normalized()
	var flat := Vector3(dir.x, 0, dir.z)
	var side_v := Vector3.RIGHT
	if flat.length() > 0.01:
		side_v = flat.normalized().cross(Vector3.UP)
	# long reach straight at the water, a hand either side of the line
	var reach_pos := sh + dir * minf(to_src.length(), arm_len * 0.93) + side_v * 0.10 * s
	var p := _guard(side).lerp(reach_pos, re)
	if pull_u > 0.0:
		var e := _weave(side)
		# the hands sweep down and back along an arc, then up and in to the weave
		var k := (reach_pos + e) * 0.5 + Vector3(0.22 * s, -vd["depth"], vd["back"])
		p = reach_pos.lerp(k, pe).lerp(k.lerp(e, pe), pe)
		if vd["spiral"] > 0.0:
			var a := pe * TAU * 1.25 + (0.0 if side == "r" else PI)
			p += Vector3(cos(a), sin(a) * 0.8, 0.0) * vd["spiral"] * sin(PI * pe)
	return p

''' + s[b:]

s = s.replace('''func _hand_target(side: String) -> Vector3:
	var t := _guard(side)''', '''func _hand_target(side: String, sh: Vector3, arm_len: float) -> Vector3:
	var t := _guard(side)''')
s = s.replace("	t = t.lerp(_draw(side), w_draw)", "	t = t.lerp(_draw(side, sh, arm_len), w_draw)")
s = s.replace("func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3, weight: float) -> void:", "func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3, weight: float, ext: float = 0.999) -> void:")
s = s.replace("var d := clampf(to.length(), absf(la - lb) + 0.001, la + lb - 0.001)", "var d := clampf(to.length(), absf(la - lb) + 0.001, (la + lb) * ext - 0.001)")
open(p, 'w').write(s)

p = 'scripts/water_body.gd'
s = open(p).read()
a = s.index("func _step_draw(dt: float) -> void:")
b = s.index("func _step_hold(")
s = s[:a] + '''func _step_draw(_dt: float) -> void:
	# reach_u and pull_u come from the bender's body. The water rises a little toward the hands while
	# they reach, and only travels to the body as the pull happens.
	var anchor := source.surface_point()
	var dest := ring_world(head_angle(clock))
	var ctrl := (anchor + dest) * 0.5 + Vector3.UP * 1.3
	var clen := 0.0
	var prev := anchor
	for k in range(1, 13):
		var q := _curve(anchor, ctrl, dest, k / 12.0)
		clen += prev.distance_to(q)
		prev = q
	var re := reach_u * reach_u * (3.0 - 2.0 * reach_u)
	var pe := pull_u * pull_u * (3.0 - 2.0 * pull_u)
	var ut := 0.05 * re + 0.95 * pe
	draw_u = pull_u
	var want := minf(ut * clen, MAX_LEN)
	if want > length:
		length += source.take((want - length) * L_PER_M) / L_PER_M
	_push_head(_curve(anchor, ctrl, dest, ut))
	_sample_trail(0.0)
	if pull_u >= 1.0:
		state = S.HOLD
		t_state = 0.0

''' + s[b:]
s = s.replace("var head_s := 0.0\nvar draw_u := 0.0\n", "var draw_u := 0.0\nvar reach_u := 0.0\nvar pull_u := 0.0\n")
s = s.replace("	head_s = 0.0\n", "	reach_u = 0.0\n	pull_u = 0.0\n")
open(p, 'w').write(s)
print("patched")
