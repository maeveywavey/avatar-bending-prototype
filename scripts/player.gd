class_name Player
extends CharacterBody3D
## Third-person character. Walking and running come from the animation libraries. Standing, the ready
## stance, drawing, holding and striking are the performer's recorded movements (MocapLibrary), moved
## between with short cross-fades and driven by the state of the WaterBody.

const WALK_SPEED := 3.6
const READY_SPEED := 3.6         # a run in the ready stance; a full 600 L load slows it to a jog (2.2)
const STEP_H := 0.42             # m: ledges up to this high are stepped onto
const JUMP_V := 5.0
const SERPENT_RISE := 2.0        # m/s up or down on Serpent's column
const DRAW_RANGE := 8.0
const AIM_TOL_ANGLE := 0.08      # rad (about 4.5 deg) the crosshair may be off a water source
const AIM_TOL_MIN := 0.35        # m: the same margin for a source close by
const HIGHLIGHT_RANGE := 14.0
const REACH_END := 0.4           # fraction of a draw clip spent reaching; the water moves in the rest
const STRIKE_RELEASE := 0.6      # seconds into the strike clip when the water leaves the hand
const STRIKE_END := 1.4
const STEER_MIN := 1.2           # m from the chest: how close and how far the water can be steered
const STEER_MAX := 14.0
const STEER_PUSH := 10.0         # m/s of push or pull at full stick
const QUICK_DRAW_T := 0.5        # s: a draw (FULL_L) from the press to the water held (owner: tap R1)
const FEED_RANGE := 12.0         # m from the source beyond which drawing more stops
const CAM_DIST := 3.4
const CAM_DIST_PRECISE := 2.4
const CAM_FOV := 65.0
const GATHER_MAX := 600.0        # L: most water the bender can draw and hold
const FULL_L := 30.0             # L in a normal draw
const HEAVY_L := 900.0           # L over a normal draw that halve walking speed
const TAP_TIME := 0.28           # s: an R2 press shorter than this is a tap
const SPIKE_SMALL := 6.0         # L in each small ice spike
const SLICE_L := 12.0            # L in each slice (less if less is held)
const WHEEL_SLOW := 0.2          # time scale while the forms wheel is open
const WHEEL_HOLD := 0.2          # s L1 is held before the wheel opens (shorter is a tap: the last form)
const PAD_DOUBLE := 0.35         # s: a second press of the same d-pad direction within this picks its second move
const STATES := ["loco", "loco_ready", "loco_hold", "stand", "ready_in", "ready", "draw1", "draw2", "draw3", "hold", "strike"]
const LOCO_SPACES := ["parameters/loco/blend_position", "parameters/loco_ready/bs/blend_position",
		"parameters/loco_hold/bs/blend_position"]

var cam_yaw := 0.0
var cam_pitch := -0.12
var ready_mode := false
var water: WaterBody
var skel: Skeleton3D
var model: Node3D
var cam: Camera3D
var arm: SpringArm3D
var rig: Node3D
var reticle: Control
var aim_point := Vector3.ZERO
var aim_body: Object             # what the crosshair is on
var aim_normal := Vector3.UP
var _zoom := 0.0                 # 0..1 into precision mode's camera
var draw_variant := 0
var debug_move := Vector2.ZERO   # scripted test runs move with this instead of the stick

var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _lib: AnimationLibrary
var _anim_state := ""
var _speed_s := 0.0
var _shoulder := 0.0
var _strike_t := -1.0
var _released := false
var _draw_src
var _draw_t := 0.0
var _turn_hold := false
var _prev_state := WaterBody.S.NONE
var _hand_bone := {}
var _ring_off := Vector3.ZERO
var _root_motion := Vector3.ZERO
var _ctrl_dist := 2.5
## Moves, picked on the d-pad. They decide what R2 does with held water. (Internally still called
## forms; "forms" for the player are Serpent and Octopus, on the forms wheel.)
enum Form { LASH, SLICE, SPIKE, WALL }
const FORM_NAMES := ["Lash", "Slice", "Ice spike", "Ice wall"]
## The d-pad (up, right, down, left): [one press, two presses] each, a move or -1 (empty, for later
## moves). Eight in all, as on the old moves wheel.
const MOVE_PAD := [[Form.LASH, -1], [Form.SLICE, -1], [Form.SPIKE, -1], [Form.WALL, -1]]
const PAD_ACTIONS := ["moves_up", "moves_right", "moves_down", "moves_left"]
## Forms (body forms with their own water). The forms wheel (hold L1) has eight slots, clockwise from up:
## a form, or -1 (empty, for later forms).
enum BodyForm { NONE, SERPENT, OCTOPUS }
const BODY_FORM_NAMES := ["no form", "Serpent", "Octopus"]
const WHEEL := [BodyForm.SERPENT, -1, -1, -1, BodyForm.OCTOPUS, -1, -1, -1]

func wheel_names() -> Array:
	var out := []
	for f in WHEEL:
		out.append(BODY_FORM_NAMES[f] if f >= 0 else "")
	return out

## The slot of the form the bender is in, or -1.
func wheel_current() -> int:
	return WHEEL.find(body_form())

var form := Form.LASH
var wheel_open := false
var wheel_pick := -1             # slot under the stick while the wheel is open
var _wheel_t := -1.0             # how long L1 has been held, or -1
var _last_body_form := BodyForm.NONE   # L1 tap goes back to it
var _pad_last := -1              # d-pad direction pressed last (for a second press)
var _pad_t := -10.0
var _draw_goal := 0.0            # L: a tap of R1 brings the held water (and the feed) up to this
var notice := ""                 # a short message in the hints (why a form could not be taken)
var _notice_until := -1.0
var _big_z := 0.0
var _r2_t := -1.0                # how long R2 has been held (forms that tell a tap from a hold)
var _slice_i := 0
var _slice_last := -10.0
var _clock := 0.0
var _caster: IceCaster
var _volley: SpikeVolley         # large spikes forming around the bender, thrown together on release
var ground_y := 0.0              # under the bender (Serpent)
var _ride_y := -INF              # Serpent: height the water holds the bender's feet at
var serpent_form: SerpentWater   # Serpent: its own water, round the legs (Triangle)
var octopus: Octopus             # Octopus: its own water, a ring and six tentacles that grab (Circle)
var _stick_raw := Vector2.ZERO   # the left stick before rooting (Octopus picks a tentacle with it)
var _upper: UpperAim
var _gathered := false           # the held water has been fed from the source since this draw

func _ready() -> void:
	add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	model = (load("res://assets/Mannequin_F.glb") as PackedScene).instantiate()
	model.rotation.y = PI
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for vi in model.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = 2     # never marked by wet patches
	for s in ["l", "r"]:
		_hand_bone[s] = skel.find_bone("middle_01_" + s)

	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	anim.root_node = anim.get_path_to(model)
	var lib := AnimationLibrary.new()
	var src: AnimationPlayer = (load("res://assets/UAL1_Standard.glb") as PackedScene).instantiate().find_children("*", "AnimationPlayer", true, false)[0]
	var srclib := src.get_animation_library("")
	for n in ["Idle", "Walk", "Jog_Fwd"]:
		var a: Animation = srclib.get_animation(n).duplicate()
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	anim.add_animation_library("loco", lib)
	_lib = MocapLibrary.build(skel)
	anim.add_animation_library("mocap", _lib)

	_tree = AnimationTree.new()
	add_child(_tree)
	var fingers := _bone_tracks(["hand_l", "hand_r"], true)
	var upper := _bone_tracks(["spine_01"])
	var sm := AnimationNodeStateMachine.new()
	sm.add_node("loco", _loco_space())
	# standing: the recorded body with relaxed hanging arms, fingers loosely curled as in the idle
	sm.add_node("stand", _layered(_anim("mocap/stand"), _anim("loco/Idle"), fingers))
	# walking in the ready stance or holding water: walking legs under the recorded upper body
	sm.add_node("loco_ready", _layered(_loco_space(), _anim("mocap/ready"), upper))
	sm.add_node("loco_hold", _layered(_loco_space(), _anim("mocap/hold"), upper))
	for n in STATES:
		if not sm.has_node(n):
			sm.add_node(n, _anim("mocap/" + n))
	for a in STATES:
		for b in STATES:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = 0.3
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			sm.add_transition(a, b, t)
	_tree.tree_root = sm
	_tree.anim_player = _tree.get_path_to(anim)
	_tree.root_motion_track = NodePath("Armature/Skeleton3D:root")
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	for n in ["stand", "loco_ready", "loco_hold"]:
		_tree.set("parameters/%s/blend/blend_amount" % n, 1.0)
	_playback.start("stand")
	_anim_state = "stand"
	_upper = UpperAim.new()
	skel.add_child(_upper)
	_upper.setup(skel, _lib)
	octopus = Octopus.new()
	add_child(octopus)
	serpent_form = SerpentWater.new()
	serpent_form.player = self
	add_child(serpent_form)
	floor_snap_length = STEP_H + 0.05     # walking off a step keeps the feet on the ground
	floor_max_angle = deg_to_rad(56.0)    # a step's edge under the capsule's round bottom is floor

	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)
	arm = SpringArm3D.new()
	arm.spring_length = 3.4
	arm.margin = 0.2
	arm.add_excluded_object(get_rid())
	rig.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 300.0
	arm.add_child(cam)
	cam.current = true

func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a

func _loco_space() -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 4.0
	for e in [["Idle", 0.0], ["Walk", 1.5], ["Jog_Fwd", 3.6]]:
		bs.add_blend_point(_anim("loco/" + e[0]), e[1], -1, e[0])
	return bs

## Track paths of the given bones and everything below them.
func _bone_tracks(roots: Array, below_only := false) -> Array:
	var out := []
	var stack := []
	for r in roots:
		stack.append(skel.find_bone(r))
	var root_ids := stack.duplicate()
	while not stack.is_empty():
		var b: int = stack.pop_back()
		if not (below_only and b in root_ids):
			out.append(NodePath("Armature/Skeleton3D:" + skel.get_bone_name(b)))
		for c in skel.get_bone_children(b):
			stack.append(c)
	return out

## base, with the listed tracks taken from over instead.
func _layered(base: AnimationRootNode, over: AnimationRootNode, tracks: Array) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var bl := AnimationNodeBlend2.new()
	bl.filter_enabled = true
	for t in tracks:
		bl.set_filter_path(t, true)
	var bn := "bs" if base is AnimationNodeBlendSpace1D else "base"
	bt.add_node(bn, base)
	bt.add_node("over", over)
	bt.add_node("blend", bl)
	bt.connect_node("blend", 0, bn)
	bt.connect_node("blend", 1, "over")
	bt.connect_node("output", 0, "blend")
	return bt

# ---------------------------------------------------------------- input (none while the menu is open)

func _ip(a: String) -> bool:
	return not Controls.blocked() and Input.is_action_pressed(a)

func _ijp(a: String) -> bool:
	return not Controls.blocked() and Input.is_action_just_pressed(a)

func _ijr(a: String) -> bool:
	return Input.is_action_just_released(a)

func _iv(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	return Vector2.ZERO if Controls.blocked() else Input.get_vector(neg_x, pos_x, neg_y, pos_y)

# ---------------------------------------------------------------- per-frame

func _physics_process(dt: float) -> void:
	var move := _iv("move_left", "move_right", "move_forward", "move_back")
	if debug_move != Vector2.ZERO:
		move = debug_move
	var look := _iv("look_left", "look_right", "look_up", "look_down")
	if not wheel_open:
		# the right stick picks a form while the wheel is open; the camera holds still
		var rdt := dt / maxf(Engine.time_scale, 0.01)
		# swinging something on the lash, the bender turns harder (the whip before a throw)
		var turn := 4.2 if water != null and water.lash_latched() else 2.6
		cam_yaw -= look.x * turn * rdt
		cam_pitch = clampf(cam_pitch - look.y * 1.8 * rdt, -1.1, 0.7)
	_stick_raw = move
	if in_octopus():
		# Octopus is rooted: the stick picks a tentacle instead
		move = Vector2.ZERO
	if water != null and water.state == WaterBody.S.STEER:
		# precision mode: the bender stands planted and the left stick pushes the water out or draws it in
		_ctrl_dist = clampf(_ctrl_dist - move.y * STEER_PUSH * dt, STEER_MIN, STEER_MAX)
		move = Vector2.ZERO

	var serpent := in_serpent()
	var riding := serpent and serpent_form.effective()
	var max_speed := READY_SPEED if ready_mode else WALK_SPEED
	var acc := 12.0
	if water != null and water.state != WaterBody.S.NONE and water.state != WaterBody.S.FALL:
		# a large body of water held slows the bender: a jog (about 60%) with a full 600 L
		max_speed /= 1.0 + maxf(water.litres() - FULL_L, 0.0) / HEAVY_L
	if riding:
		# carried by Serpent: faster, and with its momentum (more water, more of both)
		max_speed *= SerpentWater.speed_mult(serpent_form.litres)
		acc = SerpentWater.accel(serpent_form.litres)
	var cam_basis := Basis(Vector3.UP, cam_yaw)
	var dir := cam_basis * Vector3(move.x, 0, move.y)
	var want := dir * max_speed * minf(move.length(), 1.0)
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(want.x, want.z), acc * dt)
	velocity.x = hv.x
	velocity.z = hv.y
	var jump := _ijp("jump")
	if serpent:
		_serpent_height(dt)
	else:
		_ride_y = -INF
		velocity.y -= 20.0 * dt if not is_on_floor() else 0.0
	if jump and is_on_floor() and not (riding and serpent_max_h() > 0.0) and not in_octopus():
		velocity.y = JUMP_V
	var pre := velocity
	move_and_slide()
	_step_up(want, dt, pre)
	# ground covered by the recorded steps
	if _root_motion != Vector3.ZERO:
		move_and_collide(Vector3(_root_motion.x, 0.0, _root_motion.z))
		_root_motion = Vector3.ZERO

	var hs := Vector2(velocity.x, velocity.z).length()
	_speed_s = lerpf(_speed_s, hs, clampf(dt * 8.0, 0.0, 1.0))
	for pth in LOCO_SPACES:
		# carried by Serpent, the legs stand still in it
		_tree.set(pth, 0.0 if riding else _speed_s)

	# facing: toward travel when moving; toward the aim when standing in the ready stance
	var face_target := rotation.y
	var rate := 0.0
	if hs > 0.3 and _strike_t < 0.0:
		face_target = atan2(-velocity.x, -velocity.z)
		rate = 9.0
	elif ready_mode:
		var rel := wrapf(cam_yaw - rotation.y, -PI, PI)
		if _strike_t >= 0.0 or absf(rel) > 1.0 or _turn_hold:
			face_target = cam_yaw
			rate = 12.0 if _strike_t >= 0.0 else 4.5
			_turn_hold = absf(rel) > 0.12
	if rate > 0.0:
		rotation.y = lerp_angle(rotation.y, face_target, clampf(dt * rate, 0.0, 1.0))

## Ledges up to STEP_H (low ice, a kerb) are stepped onto: when walking is blocked by a wall, the body is
## tried a step higher and a little farther on, then set down on what is there.
func _step_up(want: Vector3, dt: float, pre: Vector3) -> void:
	var hw := Vector3(want.x, 0, want.z)
	if hw.length() < 0.3 or _ride_y > -INF and not is_on_floor():
		return
	var blocked := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.7 and Vector3(n.x, 0, n.z).normalized().dot(hw.normalized()) < -0.3:
			blocked = true
	if not blocked:
		return
	# far enough on that the capsule's round bottom comes down on the ledge's edge or top, not its face
	var step := hw.normalized() * (maxf(hw.length() * dt, 0.06) + 0.1)
	var xf := global_transform
	if test_move(xf, Vector3.UP * STEP_H):
		return
	var up_xf := xf.translated(Vector3.UP * STEP_H)
	if test_move(up_xf, step):
		return
	var fwd_xf := up_xf.translated(step)
	var col := KinematicCollision3D.new()
	var down := test_move(fwd_xf, Vector3.DOWN * (STEP_H + 0.05), col)
	# landing on the edge counts (the round bottom meets it at up to 55°); the next steps roll onto it
	if down and col.get_normal().y > 0.55 and col.get_travel().y < -0.02:
		global_position = fwd_xf.origin + col.get_travel()
		# the stride carries on at the speed it had
		velocity = Vector3(pre.x, 0.0, pre.z)

func in_octopus() -> bool:
	return octopus != null and octopus.active

func in_serpent() -> bool:
	return serpent_form != null and serpent_form.active

## Serpent's height: holding Square raises the bender on a column of Serpent's water (up to
## serpent_max_h()); let go, it sinks back down. Moving over a roof keeps the height, so the bender can
## sink onto it.
func _serpent_height(dt: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 60.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	ground_y = (hit["position"] as Vector3).y if not hit.is_empty() else global_position.y - 60.0
	if _ride_y == -INF:
		_ride_y = global_position.y
	var hmax := serpent_max_h()
	var rising := _ip("jump") and hmax > 0.0
	if rising:
		_ride_y = minf(maxf(_ride_y, global_position.y) + SERPENT_RISE * dt, ground_y + hmax)
	else:
		_ride_y -= SERPENT_RISE * dt
	_ride_y = minf(_ride_y, ground_y + hmax)
	if rising or _ride_y > ground_y + 0.04:
		# held up by the water: it moves the bender to the riding height
		velocity.y = clampf((_ride_y - global_position.y) * 8.0, -SERPENT_RISE * 2.0, SERPENT_RISE * 2.0)
	else:
		_ride_y = ground_y
		velocity.y -= 20.0 * dt if not is_on_floor() else 0.0

## Highest Serpent can lift the bender's feet: 1.9 m with 300 L, 4.8 m with 600 L (rooftops are 3 to
## 3.8 m), none at 200 L or less.
func serpent_max_h() -> float:
	return SerpentWater.rise_h(serpent_form.litres) if in_serpent() else 0.0

## How high the bender stands on the water's column (0 on the ground).
func serpent_h() -> float:
	return maxf(global_position.y - ground_y, 0.0) if in_serpent() else 0.0

func _process(dt: float) -> void:
	var rm := _tree.get_root_motion_position()
	if OS.get_cmdline_user_args().has("--rmlog") and rm.length() > 0.004:
		print("RM t=%d node=%s pos=%.3f rm=%s" % [Time.get_ticks_msec(), _playback.get_current_node(), _playback.get_current_play_position(), rm.snapped(Vector3(0.001, 0.001, 0.001))])
	# a clip being reset as another starts reports its whole travel undone in one frame; the recorded steps
	# never exceed about 0.7 m/s, so anything far faster is that artefact and is dropped
	if rm.length() / maxf(dt, 0.001) < 1.6:
		_root_motion += skel.global_transform.basis * rm
	_update_camera(dt)
	_update_aim()
	_update_bending(dt)
	if reticle:
		reticle.visible = ready_mode
		reticle.queue_redraw()

func _update_camera(dt: float) -> void:
	_shoulder = lerpf(_shoulder, 0.55 if ready_mode else 0.0, clampf(dt * 5.0, 0.0, 1.0))
	rig.global_position = global_position + Vector3(0, 1.55, 0)
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0)
	arm.position.x = _shoulder
	# precision mode: the camera closes in and narrows, more so the farther out the water is
	var steering := water != null and (water.state == WaterBody.S.STEER or (in_octopus() and octopus.marking))
	_zoom = move_toward(_zoom, 1.0 if steering else 0.0, dt * 3.0)
	var ez := _zoom * _zoom * (3.0 - 2.0 * _zoom)
	var far := clampf((_ctrl_dist - STEER_MIN) / (STEER_MAX - STEER_MIN), 0.0, 1.0)
	# a large held volume: the camera stands back a little to take it in
	var big := clampf((water.litres() - FULL_L) / (GATHER_MAX - FULL_L), 0.0, 1.0) if water != null else 0.0
	# riding Serpent high: the camera rises with the bender and stands back a little more
	big = maxf(big, clampf(serpent_h() / 4.0, 0.0, 1.0) * 0.8)
	_big_z = lerpf(_big_z, big, clampf(dt * 2.0, 0.0, 1.0))
	arm.spring_length = lerpf(CAM_DIST + 1.0 * _big_z, CAM_DIST_PRECISE, ez)
	cam.fov = CAM_FOV * lerpf(1.0, lerpf(0.9, 0.5, far), ez)

func _update_aim() -> void:
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = _ray_excl()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	aim_point = hit["position"] if not hit.is_empty() else to
	aim_body = hit["collider"] if not hit.is_empty() else null
	aim_normal = hit["normal"] if not hit.is_empty() else Vector3.UP

func _ray_excl() -> Array[RID]:
	var ex: Array[RID] = [get_rid()]
	if water != null and water.grabbed != null and is_instance_valid(water.grabbed):
		ex.append(water.grabbed.get_rid())
	return ex

## The point the steered water goes to: on the crosshair's line, _ctrl_dist from the chest, kept in
## front of whatever the crosshair is on and never behind a wall as seen from the body.
func _steer_point() -> Vector3:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var chest := global_position + Vector3(0, 1.3, 0)
	var oc := o - chest
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - _ctrl_dist * _ctrl_dist)
	var t := -b + sqrt(disc) if disc >= 0.0 else -b
	t = clampf(t, 0.5, maxf(o.distance_to(aim_point) - 0.25, 0.5))
	var p := o + d * t
	var q := PhysicsRayQueryParameters3D.create(chest, p)
	q.exclude = _ray_excl()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		p = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.25
	return p

## The water source (barrel or puddle) the crosshair is on, within DRAW_RANGE.
## The crosshair need not be exactly on it: a source counts when the crosshair line passes within
## AIM_TOL_ANGLE of it (at least AIM_TOL_MIN metres), and nothing stands in front of it. The closest
## one by angle wins.
func _aimed_source():
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var aim_d := o.distance_to(aim_point)
	var best = null
	var bs := INF
	for s in get_tree().get_nodes_in_group("water_source"):
		if s.is_queued_for_deletion():
			continue
		var m: Vector2 = s.aim_miss(o, d)
		if m.x > maxf(AIM_TOL_MIN, AIM_TOL_ANGLE * m.y):
			continue
		if global_position.distance_to(s.near_point(global_position)) > DRAW_RANGE:
			continue
		# blocked: the crosshair stops on something well before the source that isn't part of it
		var own: bool = aim_body is Node and (s as Node).is_ancestor_of(aim_body)
		if not own and aim_d < m.y - 0.8:
			continue
		var score := m.x / maxf(m.y, 1.0)
		if score < bs:
			bs = score
			best = s
	return best

## A hand where it is drawn: after UpperAim's turn (bone poses read here are the unmodified ones).
func hand_world(side: String) -> Vector3:
	var h = _upper.hand(side) if _upper != null else null
	if h != null:
		return skel.global_transform * (h as Vector3)
	return skel.global_transform * skel.get_bone_global_pose(_hand_bone[side]).origin

func _go(state: String) -> void:
	if state != _anim_state:
		_anim_state = state
		_playback.travel(state)

func _clip_len(state: String) -> float:
	return _lib.get_animation(state).length

func _update_bending(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)    # real time; the form wheel slows the world
	_clock += rdt
	var st := water.state
	var holding_any := st == WaterBody.S.DRAW or st == WaterBody.S.HOLD or st == WaterBody.S.STEER \
			or st == WaterBody.S.LASH
	_update_wheel(rdt)
	st = water.state
	holding_any = st == WaterBody.S.DRAW or st == WaterBody.S.HOLD or st == WaterBody.S.STEER \
			or st == WaterBody.S.LASH
	if not wheel_open:
		_update_move_pad()
	# highlight water sources while ready
	for s in get_tree().get_nodes_in_group("water_source"):
		s.highlighted = ready_mode and global_position.distance_to(s.near_point(global_position)) < HIGHLIGHT_RANGE

	# drawing (R1): from the source under the crosshair. A tap draws FULL_L in QUICK_DRAW_T; held, the
	# water keeps coming up a feed stream joined to the held water until R1 is let go. With water already
	# held, a tap adds FULL_L the same way. Letting go of R1 keeps what is held (Circle drops it).
	var draw_held := _ip("draw")
	if _ijp("draw") and not wheel_open and _strike_t < 0.0 and (st == WaterBody.S.NONE or st == WaterBody.S.HOLD):
		var src = _aimed_source()
		if src != null and src.level > 1.0:
			if not ready_mode:
				_set_ready(true)
			if src.has_method("set_draw_point"):
				# a wide body of water is drawn from the part the crosshair is on
				var o := cam.global_position
				var dd := -cam.global_transform.basis.z
				src.set_draw_point(o + dd * (src.aim_miss(o, dd) as Vector2).y)
			_draw_src = src
			_gathered = false
			if st == WaterBody.S.NONE:
				water.begin_draw(src)
				_draw_t = 0.0
				_draw_goal = FULL_L
				_go("draw%d" % (draw_variant + 1))
			else:
				water.source = src
				_draw_goal = water.litres_coming() + FULL_L
	var in_reach: bool = _draw_src != null and is_instance_valid(_draw_src) \
			and global_position.distance_to(_draw_src.near_point(global_position)) < FEED_RANGE
	var short_of_tap := in_reach and water.litres_coming() < _draw_goal - 0.05
	water.feed_quick = short_of_tap
	water.keep_gathering = in_reach and (draw_held or short_of_tap) \
			and (water.state == WaterBody.S.DRAW or water.state == WaterBody.S.HOLD) \
			and water.litres_coming() < GATHER_MAX
	if water.feeding():
		_gathered = true
	elif _gathered and not water.keep_gathering:
		_draw_src = null
		_draw_goal = 0.0
	# Circle: drops the held water (spikes still forming fall with it); with nothing held, relaxes
	if _ijp("drop") and not wheel_open:
		if holding_any or water.state == WaterBody.S.MELD or (_volley != null and is_instance_valid(_volley)):
			_drop()
			_go("ready")
		elif ready_mode and _strike_t < 0.0:
			_set_ready(false)
	# precision mode, toggled by L2 while water is held; R2 held catches what the water reaches
	if _ijp("precise") and not wheel_open and not in_octopus():
		if water.state == WaterBody.S.STEER:
			water.end_steer()
		elif ready_mode and water.state == WaterBody.S.HOLD:
			_ctrl_dist = clampf((water.head_pos() - (global_position + Vector3(0, 1.3, 0))).length() + 1.2, 2.0, STEER_MAX)
			water.steer_target = _steer_point()
			water.steer_basis = cam.global_transform.basis
			water.begin_steer()
	if water.state == WaterBody.S.STEER:
		water.steer_target = _steer_point()
		water.steer_basis = cam.global_transform.basis
		if _ip("strike"):
			if water.grabbed == null:
				water.try_grab(aim_body)
		elif water.grabbed != null:
			water.release_grab()
	if in_octopus():
		if not wheel_open:
			octopus.update(rdt, _ip("strike"), _ijp("strike"),
					_ijp("precise"), _ijp("jump"), _stick_raw)
	elif ready_mode and not wheel_open:
		_update_form(rdt)
	elif _caster != null:
		_caster.stop()

	st = water.state
	if st == WaterBody.S.DRAW:
		# the body reaches first, with the water still; the water moves as the body pulls
		_draw_t += dt
		var u := clampf(_draw_t / QUICK_DRAW_T, 0.0, 1.0)
		water.reach_u = clampf(u / REACH_END, 0.0, 1.0)
		water.pull_u = clampf((u - REACH_END) / (1.0 - REACH_END), 0.0, 1.0)
	if _prev_state == WaterBody.S.DRAW and st == WaterBody.S.HOLD:
		draw_variant = (draw_variant + 1) % 3
	_prev_state = st

	# the held water circles the hands
	var mid := global_transform.affine_inverse() * ((hand_world("l") + hand_world("r")) * 0.5)
	_ring_off = _ring_off.lerp(mid - Vector3(0, 1.15, -0.3), clampf(dt * 4.0, 0.0, 1.0))
	water.ring_offset = _ring_off

	# movement and idle selection, when no water action is playing the body
	var held := st == WaterBody.S.HOLD or st == WaterBody.S.STEER or st == WaterBody.S.LASH or st == WaterBody.S.MELD
	var busy := st == WaterBody.S.DRAW or held
	var moving := _speed_s > 0.4
	# the water arrives before the draw movement ends; the movement is played out before the hold
	var in_draw := _anim_state.begins_with("draw") and _playback.get_current_node() == _anim_state \
			and _playback.get_current_play_position() < _clip_len(_anim_state) - 0.05
	if held:
		if not (in_draw and not moving and st == WaterBody.S.HOLD):
			_go("loco_hold" if moving else "hold")
	elif not busy:
		if moving:
			_go("loco_ready" if ready_mode else "loco")
		elif ready_mode:
			if _anim_state == "ready_in":
				if _playback.get_current_node() == "ready_in" and _playback.get_current_play_position() >= _clip_len("ready_in") - 0.05:
					_go("ready")
			elif _anim_state == "stand" or _anim_state == "loco":
				_go("ready_in")
			else:
				_go("ready")
		else:
			_go("stand")
	# walking: the spine keeps the chest where the stance has it (UpperAim)
	var walking_upper := _anim_state == "loco_ready" or _anim_state == "loco_hold"
	_upper.weight = move_toward(_upper.weight, 1.0 if walking_upper else 0.0, dt / 0.3)
	_upper.clip = "hold" if _anim_state == "loco_hold" else "ready"
	_upper.aim_rel = wrapf(cam_yaw - rotation.y, -PI, PI) if ready_mode else 0.0

## Lets go of the held water: it falls. Spikes still forming fall with it.
func _drop() -> void:
	if _volley != null and is_instance_valid(_volley):
		_volley.drop()
	_volley = null
	_r2_t = -1.0
	if _caster != null:
		_caster.stop()
	water.begin_fall()

# ---------------------------------------------------------------- ready stance, moves (d-pad)

func _set_ready(on: bool) -> void:
	if on == ready_mode:
		return
	ready_mode = on
	_go("ready_in" if on else "stand")

## The d-pad picks a move and takes the ready stance. A second press of the same direction within
## PAD_DOUBLE picks that direction's second move, if it has one.
func _update_move_pad() -> void:
	for d in PAD_ACTIONS.size():
		if not _ijp(PAD_ACTIONS[d]):
			continue
		var second := d == _pad_last and _clock - _pad_t < PAD_DOUBLE
		var f: int = MOVE_PAD[d][0]
		if second and MOVE_PAD[d][1] >= 0:
			f = MOVE_PAD[d][1]
		_pad_last = -1 if second else d
		_pad_t = _clock
		_set_form(f)
		_set_ready(true)

func _set_form(f: int) -> void:
	if f == form:
		return
	form = f
	_r2_t = -1.0
	if _caster != null:
		_caster.stop()

# ---------------------------------------------------------------- forms (L1)

func body_form() -> int:
	if in_serpent():
		return BodyForm.SERPENT
	if in_octopus():
		return BodyForm.OCTOPUS
	return BodyForm.NONE

func _notice(t: String) -> void:
	notice = t
	_notice_until = _clock + 2.0

## L1: a tap goes back to the last form (no form counts as one); held past WHEEL_HOLD, the forms wheel
## opens (time slows) and the right stick picks a form, chosen when L1 is let go. A centred stick
## changes nothing.
func _update_wheel(rdt: float) -> void:
	if _ijp("forms"):
		_wheel_t = 0.0
		wheel_pick = -1
	if _wheel_t < 0.0:
		return
	if _ip("forms"):
		_wheel_t += rdt
		if _wheel_t > WHEEL_HOLD and not wheel_open:
			wheel_open = true
			Engine.time_scale = WHEEL_SLOW
		if wheel_open:
			var v := _iv("look_left", "look_right", "look_up", "look_down")
			# only a firmly pushed stick picks, so the stick springing back to centre changes nothing
			if v.length() > 0.6:
				# slot 0 is up, then clockwise
				var a := fposmod(atan2(v.x, -v.y), TAU)
				wheel_pick = int(round(a / (TAU / WHEEL.size()))) % WHEEL.size()
		return
	# released
	if wheel_open:
		if wheel_pick >= 0 and WHEEL[wheel_pick] >= 0:
			_choose_body_form(WHEEL[wheel_pick])
		_close_wheel()
	elif _strike_t < 0.0:
		if _last_body_form == body_form():
			_notice("No last form yet")
		else:
			_choose_body_form(_last_body_form)
	_wheel_t = -1.0

## Takes form f. Serpent and Octopus each have their own water, and only one is on at a time:
## - from one to the other, the water goes over;
## - from no form, the held water melds in (300 L or more needed);
## - the form it is in again: the held water melds in, or with none held, it leaves the form;
## - no form: leaves it, its water falling as a puddle.
func _choose_body_form(f: int) -> void:
	var cur := body_form()
	var st := water.state
	if f == cur:
		if cur == BodyForm.NONE:
			return
		if st == WaterBody.S.HOLD:
			_meld_into(cur)
		else:
			_leave_body_form()
		return
	if f == BodyForm.NONE:
		_leave_body_form()
		return
	if cur != BodyForm.NONE:
		var l := serpent_form.take_all() if cur == BodyForm.SERPENT else octopus.take_all()
		_begin_body_form(f)
		if f == BodyForm.SERPENT:
			serpent_form.add(l)
		else:
			octopus.add(l)
		_last_body_form = cur
		return
	var need: float = SerpentWater.MIN_ENTER if f == BodyForm.SERPENT else Octopus.MIN_ENTER
	if st != WaterBody.S.HOLD or water.litres() < need:
		_notice("%s needs %d L of held water" % [BODY_FORM_NAMES[f], int(need)])
		return
	_begin_body_form(f)
	_meld_into(f)
	_last_body_form = BodyForm.NONE
	_set_ready(true)

func _begin_body_form(f: int) -> void:
	if f == BodyForm.SERPENT:
		serpent_form.begin()
	else:
		octopus.begin(self)

func _meld_into(f: int) -> void:
	if f == BodyForm.SERPENT:
		water.begin_meld(serpent_form.waist, serpent_form.add)
	else:
		water.begin_meld(octopus.meld_point, octopus.add)

func _leave_body_form() -> void:
	var cur := body_form()
	if cur == BodyForm.NONE:
		return
	serpent_form.drop()
	octopus.drop()
	_last_body_form = cur

func _close_wheel() -> void:
	wheel_open = false
	Engine.time_scale = 1.0

# ---------------------------------------------------------------- forms

func _hands_mid() -> Vector3:
	return (hand_world("l") + hand_world("r")) * 0.5

func _aim_dir_from(o: Vector3) -> Vector3:
	return (aim_point - o).normalized()

## What R2 does with the held water, by form.
func _update_form(rdt: float) -> void:
	var st := water.state
	var r2 := _ip("strike")
	var r2_down := _ijp("strike")
	var r2_up := _ijr("strike")
	if st == WaterBody.S.STEER:
		return       # in precision mode R2 grabs
	if st == WaterBody.S.NONE and (form != Form.WALL or _parting or _wave != null):
		# nothing held: R2 bends a large body of water directly (ice wall instead freezes its surface)
		_update_large(rdt, r2, r2_down)
		return
	match form:
		Form.LASH:
			# R2 lashes out at the crosshair; still held when it hits something loose, it latches on and
			# hauls it in until R2 is let go. Held, it swings round with the bender; let go mid-swing, it
			# flies off (WaterBody._whip_release)
			water.lash_pull_to = global_position + Vector3(0, 1.2, 0) + (-cam.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * WaterBody.LASH_HOLD_R
			water.lash_hold = r2
			if r2_down and st == WaterBody.S.HOLD:
				water.begin_lash(lash_target())
		Form.SLICE:
			if r2_down and st == WaterBody.S.HOLD:
				_fire_slice()
		Form.SPIKE:
			_update_spike(rdt, r2, r2_down, r2_up)
		Form.WALL:
			# a tap throws IceWall.LITRES out to stand as a wall where the crosshair is; held, ice freezes where
			# it is aimed (IceCaster), from the held water or from a water surface
			if r2_down and st == WaterBody.S.HOLD:
				_r2_t = 0.0
			if _r2_t >= 0.0:
				_r2_t += rdt
			if r2 and (_r2_t < 0.0 or _r2_t > TAP_TIME):
				if _caster == null:
					_caster = IceCaster.new()
					get_parent().add_child(_caster)
				_caster.cast(rdt * Engine.time_scale, _ice_target(), _hands_mid(), water)
			elif _caster != null:
				_caster.stop()
			if not r2:
				if _r2_t >= 0.0 and _r2_t <= TAP_TIME + 0.05 and water.holds_water():
					_throw_wall()
				_r2_t = -1.0

# ---------------------------------------------------------------- a large body of water, none held

const LARGE_RANGE := 25.0        # m to the point on the water the crosshair is on
var _wave: WaterWave
var _parting := false
var _part_from := Vector3.ZERO
var _part_dir := Vector3.FORWARD
var _large_t := -1.0
var _large_at := Vector3.ZERO
var _large_pond: Pond

## The stream's surface under the crosshair, within LARGE_RANGE and in front of anything solid:
## [pond, point], or [].
func _large_target() -> Array:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var aim_d := o.distance_to(aim_point) if aim_body != null else INF
	for s in get_tree().get_nodes_in_group("water_source"):
		if s is Pond:
			var p = s.surface_hit(o, d)
			if p != null and o.distance_to(p) < aim_d + 0.05 and global_position.distance_to(p) < LARGE_RANGE:
				return [s, p]
			# on something floating in it (the boat, a crate): the water under it
			if aim_body is RigidBody3D and (s as Pond).aim_hit(Vector3(aim_point.x, s.water_y(), aim_point.z)) 					and aim_point.y < s.water_y() + 1.5 and global_position.distance_to(aim_point) < LARGE_RANGE:
				return [s, Vector3(aim_point.x, s.water_y(), aim_point.z)]
	return []

## R2 tapped: a geyser where the crosshair is on the water. Held: a wave rises there, the crosshair's
## sweep stretching its crest; let go, it runs. L2 and R2 held together: the water parts from the bender
## along the aim, for as long as both are held.
func _update_large(rdt: float, r2: bool, r2_down: bool) -> void:
	var l2 := _ip("precise")
	var tgt := _large_target()
	if _parting or (l2 and r2 and _wave == null and (not tgt.is_empty() or _large_pond != null)):
		var pond: Pond = tgt[0] if not tgt.is_empty() else _large_pond
		if l2 and r2 and pond != null:
			if not _parting:
				_large_pond = pond
				var to: Vector3 = tgt[1] if not tgt.is_empty() else global_position - global_transform.basis.z
				var dir := Vector3(to.x - global_position.x, 0, to.z - global_position.z)
				_part_from = global_position
				_part_dir = dir.normalized()
				_parting = true
				_large_t = -1.0
				if "--demo" in OS.get_cmdline_user_args():
					print("PART from %s dir %s" % [global_position.snapped(Vector3(0.01, 0.01, 0.01)), dir.normalized().snapped(Vector3(0.01, 0.01, 0.01))])
			# it goes with the bender, ahead along the aim
			var aim := -cam.global_transform.basis.z
			_large_pond.hold_part(global_position, Vector3(aim.x, 0, aim.z))
			return
		_parting = false
		_large_pond = null
		return
	if r2_down and not tgt.is_empty():
		_large_t = 0.0
		_large_pond = tgt[0]
		_large_at = tgt[1]
	if _large_t < 0.0:
		return
	_large_t += rdt
	if r2 and _large_t > TAP_TIME and _wave == null:
		_wave = WaterWave.new()
		get_parent().add_child(_wave)
		_wave.begin(_large_pond, _large_at, global_position)
	if _wave != null and r2 and not tgt.is_empty():
		_wave.sweep(tgt[1])
	if not r2:
		if _wave != null:
			_wave.release()
			_wave = null
		elif _large_t <= TAP_TIME + 0.05:
			var g := Geyser.new()
			g.begin(_large_at)
			get_parent().add_child(g)
		_large_t = -1.0
		_large_pond = null

## The angle of the next slice (they cycle while slicing in quick succession).
const SLICE_ANGLES := [0.0, 90.0, 45.0, -45.0]
const SLICE_NAMES := ["horizontal", "vertical", "diagonal", "diagonal"]
func _next_slice() -> int:
	return 0 if _clock - _slice_last > 1.2 else _slice_i % SLICE_ANGLES.size()

func _fire_slice() -> void:
	var l := water.take_litres(minf(SLICE_L, water.litres()))
	if l <= 0.0:
		return
	_slice_i = _next_slice()
	var o := _hands_mid() + (-cam.global_transform.basis.z) * 0.4
	var d := _aim_dir_from(o)
	var right := cam.global_transform.basis.x
	var side := (right - d * right.dot(d)).normalized().rotated(d, deg_to_rad(SLICE_ANGLES[_slice_i]))
	_slice_i += 1
	_slice_last = _clock
	var b := WaterBlade.new()
	get_parent().add_child(b)
	b.begin(o, d, side, l, self)

## Ice spike: a tap throws a small spike. Held, the water spreads up and around the bender and freezes
## into one large spike per SPIKE_BIG litres (SpikeVolley), all thrown at the crosshair on release.
func _update_spike(rdt: float, r2: bool, r2_down: bool, r2_up: bool) -> void:
	var st := water.state
	if r2_down and st == WaterBody.S.HOLD:
		_r2_t = 0.0
	if _r2_t < 0.0:
		return
	_r2_t += rdt
	var front := _hands_mid() + (-cam.global_transform.basis.z) * 0.7
	if r2 and _r2_t > TAP_TIME:
		if _volley == null and water.litres() > SPIKE_SMALL:
			_volley = SpikeVolley.new()
			get_parent().add_child(_volley)
			_volley.begin(self, water)
		if _volley != null:
			_volley.aim = aim_point
	if r2_up or not r2:
		if _volley != null:
			_volley.fire(aim_point)
			_volley = null
		elif _r2_t <= TAP_TIME + 0.05 and water.holds_water():
			var l := water.take_litres(minf(SPIKE_SMALL, water.litres()))
			if l > 0.0:
				var sp := IceSpike.new()
				sp.setup(self)
				get_parent().add_child(sp)
				sp.add_litres(l)
				sp.fire(front, _aim_dir_from(front), 45.0)
		_r2_t = -1.0

## Lash aim assist: a loose body (crate, dummy, person, boat) the crosshair passes close to, within reach
## and in sight, is taken as the target, at its middle. Otherwise the crosshair's point.
const LASH_ASSIST := 0.12        # rad off the crosshair a target may be (at least LASH_ASSIST_MIN m)
const LASH_ASSIST_MIN := 0.6
func lash_target() -> Vector3:
	if aim_body is RigidBody3D or (aim_body is Node and (aim_body as Node).is_in_group("person")):
		return aim_point
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var hands := _hands_mid()
	var best := aim_point
	var bs := INF
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("crate") + get_tree().get_nodes_in_group("person"):
		if not n is Node3D or (n as Node).is_queued_for_deletion():
			continue
		var c: Vector3 = n.lash_point() if n.has_method("lash_point") else (n as Node3D).global_position
		if hands.distance_to(c) > WaterBody.LASH_RANGE + 0.5:
			continue
		var v := c - o
		var t := v.dot(d)
		if t < 0.5:
			continue
		var miss := (v - d * t).length()
		if miss > maxf(LASH_ASSIST_MIN, t * LASH_ASSIST):
			continue
		var score := miss / t
		if score >= bs:
			continue
		# in sight: nothing fixed between the hands and it
		var q := PhysicsRayQueryParameters3D.create(hands, c)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] != n and not (hit["collider"] is RigidBody3D) and not (hit["collider"] as Node).is_in_group("person"):
			continue
		bs = score
		best = c
	return best

## Ice wall, tapped: IceWall.LITRES of the held water flies from it to stand as a wall at the crosshair,
## its face to the bender.
func _throw_wall() -> void:
	var spot = _wall_spot()
	if spot == null:
		return
	var l := water.take_litres(minf(IceWall.LITRES, water.litres()))
	if l <= 0.0:
		return
	var from := water.head_pos() if water.state != WaterBody.S.NONE else _hands_mid()
	var shot := IceWall.new()
	get_parent().add_child(shot)
	shot.begin(from, spot, global_position, l, self)

## Where a tapped wall stands: the ground (or ice, or a water surface) where the crosshair is, within
## IceCaster.RANGE; aimed higher, the ground below the crosshair's line at that range.
func _wall_spot():
	var t := _ice_target()
	if not t.is_empty() and (t["n"] as Vector3).y > 0.6:
		return t["p"]
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var far := minf(o.distance_to(aim_point), IceCaster.RANGE * 0.7)
	var p := o + d * maxf(far - 0.3, 1.5)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 6.0)
	q.exclude = _ray_excl()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		return null
	return hit["position"]

## Where ice would freeze now: on a water surface the crosshair crosses before anything solid, or on the
## solid surface it is on, within IceCaster.RANGE.
func _ice_target() -> Dictionary:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var aim_d := o.distance_to(aim_point) if aim_body != null else INF
	for s in get_tree().get_nodes_in_group("water_source"):
		if s.has_method("surface_hit"):
			var p = s.surface_hit(o, d)
			if p != null and o.distance_to(p) < aim_d - 0.05 and global_position.distance_to(p) < IceCaster.RANGE:
				return {"p": p, "n": Vector3.UP, "kind": IceField.K.WATER, "src": s}
	if aim_body == null or global_position.distance_to(aim_point) > IceCaster.RANGE or aim_body is RigidBody3D:
		return {}
	var n := aim_normal
	# a mesh surface may report its normal from either side: take the side facing the camera
	if n.dot(d) > 0.0:
		n = -n
	if aim_body is IceField:
		if n.y > 0.6:
			return {"p": aim_point, "n": n, "kind": IceField.K.ICE_TOP}
		if absf(n.y) < 0.6:
			return {"p": aim_point, "n": n, "kind": IceField.K.ICE_SIDE}
		return {}
	if n.y > 0.6:
		return {"p": aim_point, "n": n, "kind": IceField.K.GROUND}
	if absf(n.y) < 0.5:
		return {"p": aim_point, "n": n, "kind": IceField.K.LEDGE}
	return {}

# ---------------------------------------------------------------- HUD

## The current bending form for the HUD, or "" when not bending.
func mode_name() -> String:
	if not ready_mode and body_form() == BodyForm.NONE:
		return ""
	var s: String = FORM_NAMES[form]
	if water.state == WaterBody.S.STEER:
		s = "Precision bending"
	if in_octopus():
		s = "Octopus %d L" % int(octopus.litres)
	if in_serpent():
		s = "Serpent %d L · %s" % [int(serpent_form.litres), s]
	var l := water.litres() if water.state != WaterBody.S.NONE and water.state != WaterBody.S.FALL else 0.0
	if l > 0.5:
		s += "   %d L" % int(l)
	return s

## The controls available right now, as [button, what it does], for the HUD. Written with the default
## pad buttons; Controls.relabel puts in the ones actually bound.
func control_hints() -> Array:
	return Controls.relabel(_hints())

func _hints() -> Array:
	var h := []
	var st := water.state
	if _clock < _notice_until:
		h.append(["!", notice])
	if wheel_open:
		h.append(["R stick", "Pick a form"])
		var take := "Take it"
		if wheel_pick >= 0 and WHEEL[wheel_pick] >= 0 and WHEEL[wheel_pick] == body_form():
			take = "Add the held water" if st == WaterBody.S.HOLD else "Leave it (it falls)"
		h.append(["Release L1", take])
		return h
	if not ready_mode:
		h.append(["D-pad", "Ready a move"])
		h.append(["R1", "Draw water (aim at it)"])
		_body_form_hints(h)
		_serpent_hints(h)
		return h
	if st == WaterBody.S.STEER:
		h.append(["L stick", "Push out / pull in"])
		h.append(["R stick", "Aim"])
		h.append(["Release R2", "Let go of object"] if water.grabbed != null else ["Hold R2", "Grab object"])
		h.append(["L2", "Leave precision"])
		h.append(["○", "Drop water"])
		return h
	if in_octopus():
		if octopus.marking:
			h.append(["Aim at things", "Mark them (%d limbs free)" % octopus.free_limbs()])
			h.append(["Release R2", "Grab them"])
			return h
		h.append(["L stick", "Pick a tentacle"])
		if octopus.free_limbs() > 0:
			h.append(["Hold R2", "Mark things to grab"])
		if octopus.current_holds():
			h.append(["R2", "Throw what it holds"])
			h.append(["L2", "Drop it"])
		h.append(["□", "Strike"])
		_draw_hints(h, st)
		if st == WaterBody.S.HOLD:
			h.append(["○", "Drop water"])
		_body_form_hints(h)
		return h
	if _volley != null and is_instance_valid(_volley):
		h.append(["Release R2", "Throw %d spikes" % _volley.count()])
		h.append(["○", "Drop them"])
		return h
	var holding := st == WaterBody.S.DRAW or st == WaterBody.S.HOLD or st == WaterBody.S.LASH or st == WaterBody.S.MELD
	if holding:
		match form:
			Form.LASH:
				if water.lash_latched():
					h.append(["Swing, release R2", "Throw"])
					h.append(["Release R2", "Let go"])
				else:
					h.append(["R2", "Lash"])
					h.append(["Hold R2", "Lash, grab and pull in"])
			Form.SLICE:
				h.append(["R2", "Slice (%s, %d L)" % [SLICE_NAMES[_next_slice()], int(minf(SLICE_L, water.litres()))]])
			Form.SPIKE:
				h.append(["Tap R2", "Small ice spike (%d L)" % int(SPIKE_SMALL)])
				h.append(["Hold R2", "Spike volley (%d)" % SpikeVolley.count_for(water.litres())])
			Form.WALL:
				h.append(["R2", "Ice wall (%d L)" % int(minf(IceWall.LITRES, water.litres()))])
				h.append(["Hold R2", "Freeze ice where you aim"])
		if st == WaterBody.S.HOLD:
			h.append(["L2", "Precision bending"])
		_draw_hints(h, st)
		_serpent_hints(h)
		h.append(["○", "Drop water"])
	else:
		_draw_hints(h, st)
		if form == Form.WALL and not _ice_target().is_empty() and _ice_target().has("src"):
			h.append(["Hold R2", "Freeze the water's surface"])
		elif _parting:
			h.append(["Release L2 / R2", "Let the water close"])
		elif _wave != null:
			h.append(["Sweep", "Stretch the wave"])
			h.append(["Release R2", "Send it"])
		elif form != Form.WALL and not _large_target().is_empty():
			h.append(["R2", "Geyser"])
			h.append(["Hold R2, sweep", "Wave"])
			h.append(["Hold L2 + R2", "Part the water"])
		_serpent_hints(h)
		h.append(["○", "Relax"])
	h.append(["D-pad", "Change move"])
	_body_form_hints(h)
	return h

func _draw_hints(h: Array, st: int) -> void:
	if water.keep_gathering and _ip("draw"):
		h.append(["Release R1", "Stop drawing (%d L)" % int(water.litres_coming())])
	elif st == WaterBody.S.NONE:
		h.append(["R1 / hold R1", "Draw %d L / keep drawing (aim at water)" % int(FULL_L)])
	elif st == WaterBody.S.HOLD:
		h.append(["R1 / hold R1", "Draw %d L more / keep drawing" % int(FULL_L)])

func _body_form_hints(h: Array) -> void:
	var cur := body_form()
	if _last_body_form != cur:
		if _last_body_form == BodyForm.NONE:
			h.append(["L1", "Leave %s (it falls)" % BODY_FORM_NAMES[cur]])
		else:
			h.append(["L1", "Back to %s" % BODY_FORM_NAMES[_last_body_form]])
	h.append(["Hold L1", "Forms"])

func _serpent_hints(h: Array) -> void:
	if in_serpent() and serpent_max_h() > 0.0:
		h.append(["Hold □", "Rise (let go to sink)"])
	else:
		h.append(["□", "Jump"])

func attach_water(w: WaterBody) -> void:
	water = w
	w.player = self
	w.set_hand_provider(func(): return hand_world("r"))
