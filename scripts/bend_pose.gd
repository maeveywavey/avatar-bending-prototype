class_name BendPose
extends SkeletonModifier3D
## Bending layer. Runs after the locomotion animation each frame.
## Standing still, the normal pose has the feet shoulder-width apart and the legs straight. The ready pose
## is a martial-arts stance: feet wide and staggered, knees bent, arms up. While drawing, the whole body follows one of several draw movements
## (VARIANTS): pelvis travel, spine twist and lean, a stepping front foot, and both arms along a
## keyed path. All targets are in the player's local space (forward -Z, right +X, up +Y).

var player: Node3D
var skel: Skeleton3D

# Inputs from the player each frame
var ready_target := 0.0
var draw_target := 0.0
var hold_target := 0.0
var strike_target := 0.0
var draw_variant := 0
var reach_u := 0.0                      # 0..1 reaching out to the water (the water does not move)
var pull_u := 0.0                       # 0..1 pulling the water in (the water moves with this)
var draw_dir := Vector3(0, 0, -1)       # horizontal direction to the source, player space
var src_local := Vector3(0, 0.9, -4.0)  # water surface of the source, player space
var strike_t := 0.0
var aim_dir := Vector3(0, 0, -1)
var weave_t := 0.0
var speed := 0.0

# Smoothed weights
var w_ready := 0.0
var w_draw := 0.0
var w_hold := 0.0
var w_strike := 0.0
var w_stand := 0.0

# Outputs
var hand_world := {"l": Vector3.ZERO, "r": Vector3.ZERO}

const CHEST := Vector3(0, 1.28, 0)

## Three different draw movements. Hand keys are (right, up, forward) from the chest, forward being the
## direction to the water. "hand_l" empty means the left hand mirrors the right. Channel lists are sampled
## evenly across the pull and end at rest; the first value is the pose reached at the end of the reach.
const VARIANTS := [
	# Animation 2 (the draw in use): cloud hands. The hands trade places in opposite phase, circling across
	# the body in the frontal plane, while the whole body turns one way and then the other, shifting
	# weight between the feet.
	{"id": 2, "name": "cloud", "reach_t": 0.5, "hold_t": 0.05, "pull_t": 2.3, "lag": 0.05, "lag_l": 0.0, "ext": 0.90,
		"lean_reach": 0.4, "yaw_reach": -0.2, "pel_reach": Vector3(0, -0.12, 0.10), "step": 0.30, "widen": 0.12,
		"lean": [0.3, 0.2, 0.15, 0.2, 0.1, 0.05],
		"yaw": [-0.6, -0.95, -0.2, 0.7, 0.95, 0.4],
		"pel": [Vector3(0.12, -0.15, 0.06), Vector3(0.18, -0.18, 0.0), Vector3(0.05, -0.14, 0.0), Vector3(-0.12, -0.16, 0.0), Vector3(-0.18, -0.10, 0.0), Vector3(-0.05, -0.05, 0.0)],
		"hand_r": [Vector3(0.55, -0.30, 0.50), Vector3(0.45, -0.55, 0.10), Vector3(-0.20, -0.50, 0.15), Vector3(-0.50, 0.0, 0.30),
			Vector3(-0.30, 0.55, 0.30), Vector3(0.20, 0.72, 0.20)],
		"hand_l": [Vector3(0.50, 0.0, 0.30), Vector3(0.30, 0.55, 0.30), Vector3(-0.20, 0.72, 0.20), Vector3(-0.55, -0.30, 0.50),
			Vector3(-0.45, -0.55, 0.10), Vector3(0.20, -0.50, 0.15)]},
	# Animation 3 (kept, not in rotation): dip and rise. Both hands scoop low beside the hips in a deep
	# squat, then the body drives up, arms swinging wide and overhead, before the hands fall in front.
	{"id": 3, "name": "dip", "reach_t": 0.9, "hold_t": 0.15, "pull_t": 1.7, "lag": 0.22, "lag_l": 0.0, "ext": 0.94,
		"lean_reach": 0.7, "yaw_reach": 0.0, "pel_reach": Vector3(0, -0.20, 0.15), "step": 0.0, "widen": 0.22,
		"lean": [0.9, 0.5, 0.1, -0.35, -0.4, -0.1],
		"yaw": [0.1, 0.35, 0.0, -0.2, -0.1, 0.0],
		"pel": [Vector3(0, -0.30, 0.12), Vector3(0, -0.28, 0.0), Vector3(0, -0.10, -0.05), Vector3(0, 0.04, -0.12), Vector3(0, 0.05, -0.12), Vector3(0, 0.0, -0.04)],
		"hand_r": [Vector3(0.45, -0.55, -0.05), Vector3(0.50, -0.50, -0.30), Vector3(0.75, 0.10, 0.15), Vector3(0.55, 0.85, 0.0),
			Vector3(0.15, 0.95, 0.15), Vector3(0.10, 0.50, 0.45)],
		"hand_l": []},
]

## Indices into VARIANTS that the draw rotates through.
const ACTIVE := [0]

var _b := {}
var _rest_foot := {}
var _rest_thigh_y := 0.0
var _front := "r"
var _step_dir := Vector3(0, 0, -1)      # world, horizontal
var _step_amt := 0.0
var _step_prev := 0.0
var _struck := false
var _lift := 0.0

func setup(s: Skeleton3D, p: Node3D) -> void:
	skel = s
	player = p
	for n in ["root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r",
			"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "middle_01_l", "middle_01_r",
			"thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
		_b[n] = skel.find_bone(n)
	for side in ["l", "r"]:
		_rest_foot[side] = skel.get_bone_global_rest(_b["foot_" + side]).origin
	_rest_thigh_y = skel.get_bone_global_rest(_b["thigh_l"]).origin.y

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _v() -> Dictionary:
	return VARIANTS[draw_variant]

func _reach() -> float:
	return _ease(reach_u)

## Catmull-Rom through evenly spaced keys (floats or vectors).
func _spline(arr: Array, u: float):
	var n := arr.size()
	var x := clampf(u, 0.0, 1.0) * (n - 1)
	var i := mini(int(x), n - 2)
	var t := x - i
	var p0 = arr[maxi(i - 1, 0)]
	var p1 = arr[i]
	var p2 = arr[i + 1]
	var p3 = arr[mini(i + 2, n - 1)]
	return (p1 * 2.0 + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * (t * t) + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * (t * t * t)) * 0.5

## A draw channel: the reach pose while reaching, then the keyed curve back to rest during the pull.
func _ch(key: String, pu: float):
	var vd := _v()
	var first = vd[key + "_reach"]
	var re := _reach()
	if pu <= 0.0:
		return first * re
	var arr: Array = [first]
	arr.append_array(vd[key])
	arr.append(first * 0.0)
	return _spline(arr, _ease(pu))

func _process_modification() -> void:
	if skel == null or player == null:
		return
	var dt := get_process_delta_time()
	w_ready = move_toward(w_ready, ready_target, dt * 4.0)
	w_draw = move_toward(w_draw, draw_target, dt * 5.0)
	w_hold = move_toward(w_hold, hold_target, dt * 3.5)
	w_strike = move_toward(w_strike, strike_target, dt * 9.0)
	w_stand = move_toward(w_stand, 1.0 if speed < 0.3 else 0.0, dt * 6.0)

	var to_skel := skel.global_transform.affine_inverse() * player.global_transform
	var basis_skel := to_skel.basis
	var pb := player.global_transform.basis
	var orig_foot := {}
	for side in ["l", "r"]:
		orig_foot[side] = skel.get_bone_global_pose(_b["foot_" + side]).basis
	var cur_thigh_y := skel.get_bone_global_pose(_b["thigh_l"]).origin.y

	var vd := _v()
	var rch := _reach() * w_draw
	var pul := _ease(pull_u)
	var d_h := draw_dir
	d_h.y = 0.0
	d_h = d_h.normalized()
	var side_v := d_h.cross(Vector3.UP)
	var aim_h := aim_dir
	aim_h.y = 0.0
	aim_h = aim_h.normalized() if aim_h.length() > 0.01 else Vector3(0, 0, -1)
	var ph := Vector2(0, 0)
	if w_strike > 0.0:
		ph = _strike_phase()
	var wind := ph.y

	# --- front foot step (world), from the draw and the strike thrust
	var step_goal := 0.0
	if _step_amt < 0.01:
		_front = "r" if d_h.x >= 0.0 else "l"
	if w_draw > 0.01:
		step_goal = float(vd["step"]) * _ease(reach_u / 0.6) * (1.0 - 0.5 * pul) * w_draw
		_step_dir = pb * d_h
	if w_strike > 0.01 and strike_t > 0.2:
		_struck = true
	if _struck:
		step_goal = maxf(step_goal, 0.30)
		if w_strike > 0.01:
			_step_dir = pb * aim_h
		elif strike_target < 0.5 and draw_target < 0.5 and w_hold < 0.01:
			_struck = false
	_step_amt = move_toward(_step_amt, step_goal, dt * 1.6)
	var foot_speed := absf(_step_amt - _step_prev) / maxf(dt, 0.0001)
	_step_prev = _step_amt
	_lift = lerpf(_lift, clampf(foot_speed * 0.18, 0.0, 0.12), clampf(dt * 12.0, 0.0, 1.0))

	# --- pelvis: stand to full height, then move with the draw / hold / strike
	var off := Vector3.ZERO     # player space
	if w_draw > 0.001:
		var pv: Vector3 = _ch("pel", pull_u)
		off += (side_v * pv.x + Vector3.UP * pv.y + d_h * pv.z) * w_draw
	off += Vector3(sin(weave_t * 0.8) * 0.04, -0.03 + 0.02 * sin(weave_t * 1.6), sin(weave_t * 0.8 + 1.0) * 0.02) * w_hold
	if w_strike > 0.0:
		off += aim_h * 0.14 * maxf(wind, 0.0) * w_strike + Vector3(0, -0.04, 0) * absf(wind) * w_strike
	off *= w_ready * w_stand
	off.y -= 0.09 * w_ready * w_stand      # ready stance: knees bent
	var pel: int = _b["pelvis"]
	var root_basis := skel.get_bone_global_pose(_b["root"]).basis
	var raise := Vector3(0, (_rest_thigh_y - cur_thigh_y) * 0.97 * w_stand, 0)
	skel.set_bone_pose_position(pel, skel.get_bone_pose_position(pel) + root_basis.inverse() * (raise + basis_skel * off))
	var yaw_hip := 0.0
	if w_draw > 0.001:
		yaw_hip = float(_ch("yaw", pull_u)) * 0.4 * w_draw
	var hip_yaw: float = (-sin(weave_t * 0.8) * 0.12 * w_hold + wind * 0.32 * w_strike + yaw_hip) * w_ready
	_rotate_global_raw(pel, Quaternion(Vector3.UP, hip_yaw))

	# --- torso
	if w_ready > 0.001:
		var aim_yaw := atan2(-aim_dir.x, -aim_dir.z)
		var src_yaw := atan2(-d_h.x, -d_h.z)
		var look_yaw := lerpf(aim_yaw, src_yaw, clampf(w_draw, 0.0, 1.0))
		var sway := sin(weave_t * 0.8) * 0.14 * w_hold
		var yaw_base: float = clampf(look_yaw, -1.2, 1.2) * 0.85 * w_ready + sway - hip_yaw * 0.6
		var lean_base: float = 0.03 * w_ready + 0.07 * sin(weave_t * 0.55) * w_hold
		if w_strike > 0.0:
			yaw_base += wind * 0.5 * w_strike
			lean_base += maxf(wind, 0.0) * 0.24 * w_strike
		var right_skel := (basis_skel * Vector3.RIGHT).normalized()
		var names := ["spine_01", "spine_02", "spine_03"]
		var shares := [0.25, 0.35, 0.4]
		var lag: float = vd["lag"]
		var span := maxf(1.0 - lag * 2.0, 0.3)
		var head_lean := 0.0
		for k in 3:
			# each segment trails the one below it, so the body rolls through the movement
			var pk := clampf((pull_u - lag * k) / span, 0.0, 1.0) if pull_u > 0.0 else 0.0
			var lean_k: float = lean_base + float(_ch("lean", pk)) * w_draw
			var yaw_k: float = yaw_base + float(_ch("yaw", pk)) * 0.6 * w_draw
			if k == 2:
				head_lean = lean_k
			var q := Quaternion(Vector3.UP, yaw_k * shares[k])
			var q2 := Quaternion(right_skel, -lean_k * shares[k])
			_rotate_global(_b[names[k]], q * q2)
		var head_yaw := clampf(look_yaw - yaw_base, -0.7, 0.7) * w_ready
		# the head stays level and keeps looking at the water while the torso folds and arches
		var head_pitch := -head_lean * 0.5 * w_draw
		_rotate_global(_b["Head"], Quaternion(Vector3.UP, head_yaw) * Quaternion(right_skel, -head_pitch))

	# --- legs: feet together under the hips when standing; the front foot steps, feet widen in a dip
	if w_stand > 0.001:
		var widen_amt: float = float(vd["widen"]) * clampf(-off.y / 0.2, 0.0, 1.0) if w_draw > 0.01 else 0.0
		var hip_half: float = absf((_rest_foot["r"] as Vector3).x) * skel.global_transform.basis.get_scale().x
		var half := lerpf(0.17, 0.30, w_ready)       # shoulder width standing, wide in the ready stance
		for side in ["l", "r"]:
			var sgn := 1.0 if side == "r" else -1.0
			var off_p := Vector3(sgn * (half - hip_half + widen_amt), 0.0, (-0.08 if side == _front else 0.08) * w_ready)
			if side == _front:
				off_p += pb.inverse() * (_step_dir * _step_amt)
			var tgt: Vector3 = _rest_foot[side] + basis_skel * (off_p + Vector3(0, _lift, 0))
			var pole := basis_skel * Vector3(0.12 * sgn, 0.0, -1.0)
			_ik(_b["thigh_" + side], _b["calf_" + side], _b["foot_" + side], tgt, pole, w_stand)
			var cur := skel.get_bone_global_pose(_b["foot_" + side]).basis
			var q_orig: Basis = orig_foot[side]
			_set_global_basis(_b["foot_" + side], Basis(cur.get_rotation_quaternion().slerp(q_orig.get_rotation_quaternion(), w_stand)))

	# --- arms
	if w_ready > 0.001:
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
			var target_local := _hand_target(side, sh, arm_len, d_h, side_v)
			var tgt := to_skel * target_local
			var out_local := Vector3(1 if side == "r" else -1, 0, 0)
			var pole_local := out_local * 0.9 + Vector3(0, -0.6, 0.35)
			var pole := basis_skel * pole_local
			# a light bend at the elbow: long and reaching at the water, softly bent through the sweep
			var ext := lerpf(0.97, 0.94, rch)
			if pull_u > 0.0:
				ext = lerpf(ext, float(vd["ext"]), w_draw)
			_ik(up_i, lo_i, ha_i, tgt, pole, w_ready, ext)
			hand_world[side] = skel.global_transform * skel.get_bone_global_pose(_b["middle_01_" + side]).origin

# ---------------------------------------------------------------- targets

func _strike_phase() -> Vector2:
	var wind_t := clampf(strike_t / 0.2, 0.0, 1.0)
	var thrust := clampf((strike_t - 0.2) / 0.1, 0.0, 1.0)
	var y := -_ease(wind_t) + _ease(thrust) * 2.0
	y = clampf(y, -1.0, 1.0)
	var rec := clampf((strike_t - 0.45) / 0.4, 0.0, 1.0)
	y = lerpf(y, 0.0, _ease(rec))
	return Vector2(1.0 if strike_t > 0.28 else 0.0, y)

func _guard(side: String) -> Vector3:
	if side == "r":
		return CHEST + Vector3(0.28, -0.02, -0.42)
	return CHEST + Vector3(-0.30, 0.04, -0.30)

func _frame(v: Vector3, d: Vector3, side_v: Vector3, mirror: bool) -> Vector3:
	var r := -v.x if mirror else v.x
	return CHEST + side_v * r + Vector3.UP * v.y + d * v.z

func _draw(side: String, sh: Vector3, arm_len: float, d: Vector3, side_v: Vector3) -> Vector3:
	var s := 1.0 if side == "r" else -1.0
	var vd := _v()
	var lag: float = 0.0 if side == "r" else float(vd["lag_l"])
	var re := _ease(reach_u)
	var to_src := (src_local + Vector3(0, 0.15, 0)) - sh
	var dir := to_src.normalized()
	# long reach straight at the water, a hand either side of the line
	var reach_pos := sh + dir * minf(to_src.length(), arm_len * 0.93) + side_v * 0.10 * s
	var p := _guard(side).lerp(reach_pos, re)
	if pull_u > 0.0:
		var keys: Array = [reach_pos]
		var own_left: bool = side == "l" and not (vd["hand_l"] as Array).is_empty()
		var list: Array = vd["hand_l"] if own_left else vd["hand_r"]
		var mirror: bool = side == "l" and not own_left
		for v in list:
			keys.append(_frame(v, d, side_v, mirror))
		keys.append(_weave(side))
		p = _spline(keys, _ease(pull_u - lag))
	return p

func _weave(side: String) -> Vector3:
	var t := weave_t
	if side == "r":
		return WaterBody.ring_local(0.55 + 0.35 * sin(t * 0.8), t) + Vector3(0.0, 0.02, 0.0)
	return WaterBody.ring_local(-0.55 - 0.35 * sin(t * 0.8 + 1.1), t) + Vector3(0.0, 0.02, 0.0)

func _strike(side: String) -> Vector3:
	var shoulder_r := CHEST + Vector3(0.20, 0.12, 0)
	var back := CHEST + Vector3(0.30, -0.34, 0.12)
	var fwd := shoulder_r + aim_dir.normalized() * 0.66
	var wound := _ease(clampf(strike_t / 0.2, 0.0, 1.0))
	var thrust := _ease(clampf((strike_t - 0.2) / 0.1, 0.0, 1.0))
	var rec := _ease(clampf((strike_t - 0.45) / 0.4, 0.0, 1.0))
	if side == "r":
		var p := _weave("r").lerp(back, wound)
		p = p.lerp(fwd, thrust)
		return p.lerp(_guard("r"), rec)
	var gl := _guard("l")
	var chest_pull := CHEST + Vector3(-0.18, -0.12, -0.12)
	var p2 := _weave("l").lerp(gl + Vector3(0, 0, -0.1), wound)
	p2 = p2.lerp(chest_pull, thrust)
	return p2.lerp(gl, rec)

func _hand_target(side: String, sh: Vector3, arm_len: float, d: Vector3, side_v: Vector3) -> Vector3:
	var t := _guard(side)
	t += Vector3(0, sin(weave_t * 1.3 + (0.0 if side == "r" else 1.7)) * 0.012, 0)
	t = t.lerp(_draw(side, sh, arm_len, d, side_v), w_draw)
	t = t.lerp(_weave(side), w_hold)
	t = t.lerp(_strike(side), w_strike)
	return t

# ---------------------------------------------------------------- skeleton helpers

func _rotate_global(bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	var q_w := Quaternion.IDENTITY.slerp(q, w_ready)
	var g := skel.get_bone_global_pose(bone)
	_set_global_basis(bone, Basis(q_w) * g.basis)

func _rotate_global_raw(bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	var g := skel.get_bone_global_pose(bone)
	_set_global_basis(bone, Basis(q) * g.basis)

func _set_global_basis(bone: int, gb: Basis) -> void:
	var parent := skel.get_bone_parent(bone)
	var pb := Basis.IDENTITY
	if parent >= 0:
		pb = skel.get_bone_global_pose(parent).basis
	skel.set_bone_pose_rotation(bone, (pb.inverse() * gb).orthonormalized().get_rotation_quaternion())

func _swing_bone(bone: int, from_dir: Vector3, to_dir: Vector3, weight: float) -> void:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	if a.length() < 0.5 or b.length() < 0.5:
		return
	var axis := a.cross(b)
	var s := axis.length()
	if s < 0.00001:
		return
	var ang := atan2(s, a.dot(b)) * weight
	var q := Quaternion(axis / s, ang)
	var g := skel.get_bone_global_pose(bone)
	_set_global_basis(bone, Basis(q) * g.basis)

## Two-bone IK in rotations only, so bone lengths never change.
func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3, weight: float, ext: float = 0.999) -> void:
	if a < 0 or b < 0 or c < 0:
		return
	var A := skel.get_bone_global_pose(a).origin
	var B := skel.get_bone_global_pose(b).origin
	var C := skel.get_bone_global_pose(c).origin
	var la := A.distance_to(B)
	var lb := B.distance_to(C)
	var to := target - A
	var d := clampf(to.length(), absf(la - lb) + 0.001, (la + lb) * ext - 0.001)
	var dir := to.normalized()
	var x := (la * la - lb * lb + d * d) / (2.0 * d)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pv := pole - dir * pole.dot(dir)
	if pv.length() < 0.0001:
		pv = Vector3.UP.cross(dir)
	pv = pv.normalized()
	var B2 := A + dir * x + pv * h
	var C2 := A + dir * d
	_swing_bone(a, B - A, B2 - A, weight)
	var B3 := skel.get_bone_global_pose(b).origin
	var C3 := skel.get_bone_global_pose(c).origin
	_swing_bone(b, C3 - B3, C2 - B2, weight)
