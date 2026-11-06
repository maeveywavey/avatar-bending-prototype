class_name UpperAim
extends SkeletonModifier3D
## Walking in the ready stance or holding water, the legs walk (loco clips) under the recorded upper body
## (mocap "ready" / "hold"). The recorded clips turn the whole body at the pelvis (MocapLibrary.AIM_YAW),
## and the walking legs do not carry that turn, so without this the chest faced about 75° to the left of
## where it faces standing. This turns the spine so the hips-to-chest relation is the clip's own, plus the
## aim's offset from the direction of travel, within what a trunk can twist (TWIST_MAX), spread over the
## three spine bones; the hips turn for the rest (HIP_MAX). The player fades it in with `weight` while a
## walking state plays.
## Bone poses read outside a modifier (e.g. from _process) are the unmodified ones: Godot restores them
## after the modifiers run. So this records the hands' positions after its turn (hand()), which is where
## they are drawn; the player places the held water by those. Measure the result here (--twist does).

const TWIST_MAX := 0.9           # rad of total spine twist (a trunk turns about 50° on its hips)
const HIP_MAX := 0.45            # rad the hips turn for the rest (the stance turns them 75° in all)
const SPINE := ["spine_01", "spine_02", "spine_03"]

var clip := "ready"              # which recorded upper body is playing
var aim_rel := 0.0               # rad the aim is to the left of the body's facing
var weight := 0.0                # 0..1, eased in and out by the player
var _ref := {}                   # clip name -> yaw of the hip line in that clip (skeleton space)
var _b := {}
var _hands := {}                 # "l"/"r" -> skeleton-space position after the turn
const LEGS := ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
var _legs := {}                  # bone name -> skeleton-space position as drawn (Serpent wraps them)
var _have := false

func setup(sk: Skeleton3D, lib: AnimationLibrary) -> void:
	for n in SPINE + LEGS + ["middle_01_l", "middle_01_r", "clavicle_l", "clavicle_r"]:
		_b[n] = sk.find_bone(n)
	var pel: int = _b["pelvis"]
	var parent_rest := sk.get_bone_global_rest(sk.get_bone_parent(pel)).basis
	# the thighs' offsets in the pelvis' frame
	var hip := sk.get_bone_rest(_b["thigh_r"]).origin - sk.get_bone_rest(_b["thigh_l"]).origin
	for name in ["ready", "hold"]:
		var a := lib.get_animation(name)
		var tr := a.find_track(NodePath("Armature/Skeleton3D:pelvis"), Animation.TYPE_ROTATION_3D)
		if tr < 0:
			continue
		var s := 0.0
		var c := 0.0
		for i in 24:
			var q := a.rotation_track_interpolate(tr, a.length * i / 24.0)
			var v := parent_rest * Basis(q) * hip
			var y := atan2(v.x, v.z)
			s += sin(y)
			c += cos(y)
		_ref[name] = atan2(s, c)

static func _yaw(v: Vector3) -> float:
	return atan2(v.x, v.z)

## A hand's position as drawn (skeleton space), or null before the first frame.
func hand(side: String):
	return _hands.get(side) if _have else null

## A leg bone's position as drawn (skeleton space), or null before the first frame.
func leg(name: String):
	return _legs.get(name) if _have else null

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if weight > 0.0001 and _ref.has(clip):
		var live := _yaw(sk.get_bone_global_pose(_b["thigh_r"]).origin - sk.get_bone_global_pose(_b["thigh_l"]).origin)
		var want := wrapf(float(_ref[clip]) - live, -PI, PI) + aim_rel
		var twist := clampf(want, -TWIST_MAX, TWIST_MAX)
		# what the trunk cannot take, the hips do (the legs stride a little turned, as in a fighting stance)
		var hips := clampf(want - twist, -HIP_MAX, HIP_MAX) * weight
		twist *= weight
		if absf(hips) > 0.0001:
			var pb: int = _b["pelvis"]
			var pg := sk.get_bone_global_pose(pb)
			sk.set_bone_global_pose(pb, Transform3D(Basis(Vector3.UP, hips) * pg.basis, pg.origin))
		var part := Basis(Vector3.UP, twist / SPINE.size())
		for n in SPINE:
			var b: int = _b[n]
			var gp := sk.get_bone_global_pose(b)
			sk.set_bone_global_pose(b, Transform3D(part * gp.basis, gp.origin))
		if "--twist" in OS.get_cmdline_user_args() and Engine.get_process_frames() % 30 == 0:
			# the shoulder line after the turn (skeleton space)
			var cl := sk.get_bone_global_pose(_b["clavicle_r"]).origin - sk.get_bone_global_pose(_b["clavicle_l"]).origin
			print("UPPER ref=%.1f live_hips=%.1f twist=%.1f hips=%.1f w=%.2f shoulders_after=%.1f" % [rad_to_deg(_ref[clip]), rad_to_deg(live), rad_to_deg(twist), rad_to_deg(hips), weight, rad_to_deg(_yaw(cl))])
	_hands["l"] = sk.get_bone_global_pose(_b["middle_01_l"]).origin
	_hands["r"] = sk.get_bone_global_pose(_b["middle_01_r"]).origin
	for n in LEGS:
		if _b[n] >= 0:
			_legs[n] = sk.get_bone_global_pose(_b[n]).origin
	_have = true
