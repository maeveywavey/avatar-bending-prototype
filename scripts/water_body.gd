class_name WaterBody
extends Node3D
## The bender's water: one conserved body of water kept as a chain of points that trail a leading head.
## The chain is drawn as a continuous tube. Every state moves the same points, so the water is never
## swapped for an effect: it is drawn out of a source, held orbiting the body, gathered, thrown along the
## path of its head, and finally folded into whatever it hits.

enum S { NONE, DRAW, HOLD, GATHER, STRIKE, IMPACT, RETURN, STEER, FALL, LASH, MELD }

signal impacted(point: Vector3, normal: Vector3)

const N := 46                 # points in the chain
const SUB := 2                # render subdivisions per segment
const FEED_PIECES := 12        # pieces drawing the feed stream
const R0 := 0.08             # stream radius (m)
# litres per metre of stream at normal thickness. A true pi r^2 would be 20; the owner set a full stream
# (MAX_LEN at R0) to be 30 L, so the held water reads about 2.3 times its volume. Puddles, ice and
# everything the water turns into still count the real litres.
const L_PER_M := 30.0 / 3.4
const MAX_LEN := 3.4
const DRAW_RATE := 2.4        # m of stream per second
const STRIKE_SPEED := 30.0
const GRAVITY := 9.8
# precision mode (STEER): the water's head chases a point the player places, with a slightly
# underdamped spring so it lags, swings past and settles like a moving mass
const STEER_K := 45.0
const STEER_ZETA := 0.72
const STEER_MAX_SPEED := 14.0
const STEER_MAX_ACC := 70.0
const LOOP_R := 0.32          # a still water body keeps circulating in a loop of this radius
const LOOP_W := 4.2           # rad/s around that loop
const GRAB_K := 16.0
const GRAB_MAX_F := 700.0     # N: a 6 kg crate is carried briskly, a 35 kg one is hauled
const WET_SPACING := 0.22     # m between wet patches left on a surface
const WET_COST := 0.15        # litres left behind in each patch
const GRAB_REACH := 1.1       # m from the water's head at which a loose body can be caught
const GRAB_AIM_REACH := 2.6   # m from the head for a body the crosshair is on
# a caught body is covered by a sheet of the same water: the stream pours into the sheet, which spreads
# out from where the water touched. Its thickness is the water's volume over the body's surface area.
# R1 kept on the source after a full draw: more water comes up a stream joined to the held water's tail,
# at a rate rising the longer it is held (a little at first, for small amounts; 30 L to 600 L in 3.5 s)
const GATHER_R0 := 26.0       # L/s at first
const GATHER_TAU := 1.0       # s for the rate to grow e-fold
const FEED_SPEED := 14.0      # m/s the water runs up the feed stream
const QUICK_RATE := 60.0      # L/s at least while a tap of R1 is still bringing its 30 L (30 L in 0.5 s)
const MELD_T := 0.45          # s for the held water to run into Serpent
const LASH_RANGE := 9.0       # m from the hands the lash reaches
const LASH_SPEED := 32.0      # m/s out
const LASH_BACK := 18.0       # m/s back to the hands
const LASH_PULL_K := 30.0     # 1/s² spring toward the hold point (stiff enough to follow a swing)
const LASH_MAX_F := 900.0     # N a latched lash pulls with, at least (more for heavier bodies, below)
const LASH_F_PER_KG := 150.0  # N per kg, up to LASH_F_CAP
const LASH_F_CAP := 4000.0
const LASH_HOLD_R := 2.3      # m from the bender's middle where a latched body is held
const WHIP_GAIN := 2.2        # throw speed per m/s of the hold point's swing (the rope adds reach)
const WHIP_MIN := 2.0         # m/s of swing below which letting go just drops the body
const WHIP_MAX := 26.0        # m/s top throw speed for a body of 25 kg or less
const LIFT_MAX_N := 1000.0    # N upward the lash can pull: bodies heavier than about 100 kg (the boat) are
                              # dragged, never lifted or thrown
const FILM_SPREAD := 0.9      # s to cover the body
const FILM_PEEL := 0.35       # s to gather off it again
const FILM_DRAIN := 0.6       # s to run off it when let go
const FILM_MAX_T := 0.06      # m: thickest sheet; any more water stays as a stream hanging from it
const FILM_G := 10            # grid cells per face

var state := S.NONE
## Stream thickness relative to normal (radius scale). A large mass drawn in deep bending is held as a
## thicker stream of the same length: litres per metre grow with thick^2.
var thick := 1.0
var gather_cap := 600.0             # most the feed brings in (the player's GATHER_MAX)
var keep_gathering := false          # set by the player: R1 held, or a tap's water still to come
var feed_quick := false              # set by the player: a tap's FULL_L still to come, at least QUICK_RATE
# lash: the stream stays in the hands and its head shoots out to the crosshair, then comes back
var lash_hold := false               # set by the player: R2 still held (latch on what it hits)
var lash_pull_to := Vector3.ZERO     # where a latched body is pulled to
var _lash_phase := 0                 # 0 out, 1 latched, 2 back
var _lash_head := Vector3.ZERO
var _lash_end := Vector3.ZERO
var _lash_body: RigidBody3D
var _lash_local := Vector3.ZERO
var _hold_v := Vector3.ZERO          # smoothed velocity of the hold point while latched
var _prev_pull := Vector3.INF
var _stretch := 1.0                  # radius factor while the stream is stretched thin
var _meld_to: Callable              # MELD: where the water runs to (Serpent's waist)
var _meld_put: Callable             # MELD: takes litres, returns what it took
var _meld_rate := 0.0
var _feed_on := false               # the feed stream from the source is there
var _feed_l := 0.0                  # litres on their way up it
var _feed_t := 0.0                  # s it has been feeding
var _feed_cut := 0.0                # 0 joined to the source; rising to 1 as its foot leaves the source
var _feed_a := Vector3.ZERO         # its foot, at the source
var _feed_rate := 0.0
var _feed_show := false             # the feed stream is drawn (with the held water, as one surface)
var _feed_P := PackedVector3Array()
var _feed_R := PackedFloat32Array()
var player: Node3D
var source       # a WaterSource (barrel) or a Puddle
var length := 0.0
var t_state := 0.0
var clock := 0.0

var pts := PackedVector3Array()
var trail: Array[Vector3] = []
var head_vel := Vector3.ZERO
var consumed := 0.0
var hit_normal := Vector3.UP
var hit_obj: Object
var draw_u := 0.0
var ring_offset := Vector3.ZERO     # moves the held water's loop to circle the hands
var reach_u := 0.0
var pull_u := 0.0
var _w: WaterSDF                    # draws the held water and its feed stream as one surface
var _show := false                  # the held water is drawn
var _splash: GPUParticles3D
var _hand_provider: Callable

var steer_target := Vector3.ZERO    # set by the player every frame while steering
var steer_basis := Basis()          # camera orientation; the idle loop faces the camera
var grabbed: RigidBody3D
var _grab_r := 0.3
var _head_v := Vector3.ZERO
var _loop_a := 0.0
var _settling := false              # the head is travelling back to the body's loop
var _prev_pts := PackedVector3Array()
var _last_dt := 1.0 / 60.0
var _pt_vel := PackedVector3Array()
var _alive := PackedFloat32Array()  # FALL: 1 in the air, falling to 0 once landed
var _last_wet := Vector3(INF, INF, INF)
var _wet_t := 0.0
var _splashed := false
var _sphere := SphereShape3D.new()
var _fall_lpp := 0.0                # FALL: litres carried by each point

var _film: MeshInstance3D
var _film_mesh := ArrayMesh.new()
var _film_obj: RigidBody3D          # body the sheet is on (stays set while it peels or drains off)
var _film_xf := Transform3D()       # collision shape's frame within that body
var _film_half := Vector3.ONE * 0.25
var _film_u := 0.0                  # 0..1 of the body covered
var _film_dir := 0.0                # +1 spreading, -1 gathering, 0 waiting for the water to arrive
var _film_drain := false            # running off into a puddle rather than back into the stream
var _film_cap := 0.0                # litres in the sheet when fully spread
var _film_l := 0.0
var _film_drained := 0.0
var _film_t := 0.03                 # sheet thickness (m)
var _film_rc := 0.03
var _contact := Vector3.ZERO        # where the water first touched, in the shape frame
var _contact_n := Vector3.UP        # normal of the face it touched, in the shape frame
var _flare := 0.0                   # 0..1: the stream's front splaying out flat onto the body
var _flare_max := 3.0               # widest the front splays, in stream radii
var _f_inner := PackedVector3Array()
var _f_n := PackedVector3Array()
var _f_d := PackedFloat32Array()
var _f_noise := PackedFloat32Array()
var _f_sorted := PackedFloat32Array()
var _f_idx := PackedInt32Array()

func _ready() -> void:
	top_level = true
	pts.resize(N)
	_pt_vel.resize(N)
	_alive.resize(N)
	_alive.fill(1.0)
	_sphere.radius = R0 * 0.9
	_w = WaterSDF.new()
	add_child(_w)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/water.gdshader")
	fm.set_shader_parameter("film", true)
	fm.set_shader_parameter("tint_amount", 0.5)
	fm.set_shader_parameter("ripple_strength", 0.4)
	_film = MeshInstance3D.new()
	_film.mesh = _film_mesh
	_film.material_override = fm
	_film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_film.layers = 2
	_film.top_level = true
	_film.visible = false
	add_child(_film)
	_show = false
	_make_splash()

func _make_splash() -> void:
	_splash = GPUParticles3D.new()
	_splash.top_level = true
	_splash.amount = 60
	_splash.lifetime = 0.9
	_splash.one_shot = true
	_splash.explosiveness = 0.95
	_splash.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	_splash.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.05
	sm.radial_segments = 8
	sm.rings = 4
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.55, 0.8, 0.95, 0.75)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 0.05
	sm.material = dm
	_splash.draw_pass_1 = sm
	_splash.layers = 2
	add_child(_splash)

# ---------------------------------------------------------------- ring shared with the hands

## A point on the loop the held water travels, in the player's local space.
static func ring_local(a: float, t: float) -> Vector3:
	var r := 0.62 + 0.05 * sin(t * 0.9)
	var y := 1.12 + 0.30 * sin(a + t * 0.35) + 0.07 * sin(2.0 * a - t * 0.8)
	return Vector3(r * sin(a), y, -r * cos(a))

static func head_angle(t: float) -> float:
	return t * 1.05

func ring_world(a: float) -> Vector3:
	# a thicker body of water circles wider and a little higher, clear of the bender
	var l := ring_local(a, clock)
	var w := 1.0 + 0.55 * (thick - 1.0)
	l.x *= w
	l.z *= w
	l.y += 0.12 * (thick - 1.0)
	return player.global_transform * (l + ring_offset)

func lpm() -> float:
	return L_PER_M * thick * thick

func litres() -> float:
	return length * lpm()

func set_thick(t: float) -> void:
	thick = maxf(t, 1.0)
	_sphere.radius = R0 * 0.9 * thick

## Takes up to l litres out of the held water (a slice, an ice spike, ice): the stream thins back toward
## normal first, then shortens. Returns what was taken; the water is gone when nothing is left.
func take_litres(l: float) -> float:
	if state != S.HOLD and state != S.LASH and state != S.STEER and state != S.DRAW:
		return 0.0
	var have := litres()
	var t := minf(maxf(l, 0.0), have)
	if have - t <= 0.3:
		t = have      # the last dregs go with it rather than vanish
	_set_litres(have - t)
	return t

## Puts l litres back into the held water.
func add_litres(l: float) -> void:
	if state == S.HOLD or state == S.LASH or state == S.STEER:
		_set_litres(litres() + l)

func _set_litres(v: float) -> void:
	if v <= 0.3:
		length = 0.0
		set_thick(1.0)
		release_grab()
		_lash_body = null
		state = S.NONE
		_show = false
		return
	var full := MAX_LEN * L_PER_M
	if v >= full:
		set_thick(sqrt(v / full))
		length = MAX_LEN
	else:
		set_thick(1.0)
		length = v / L_PER_M

# ---------------------------------------------------------------- lash

## The head shoots out toward target and hits what is there; with lash_hold still set when it hits a
## loose body, it latches on and pulls it toward lash_pull_to until lash_hold is cleared.
func begin_lash(target: Vector3) -> void:
	if state != S.HOLD:
		return
	var hand := _hands()
	var d := target - hand
	_lash_end = hand + d.normalized() * minf(d.length() + 0.3, LASH_RANGE)
	# it shoots from the hands along the line to the target, so it strikes where it was aimed (from the
	# head's place on the loop, up to 1.6 m off to the side with a lot of water, it would cross other things)
	_lash_head = hand + d.normalized() * 0.3
	_lash_phase = 0
	_lash_body = null
	state = S.LASH
	t_state = 0.0

func lash_latched() -> bool:
	return state == S.LASH and _lash_phase == 1 and _lash_body != null

func _hands() -> Vector3:
	if _hand_provider.is_valid():
		return _hand_provider.call()
	return ring_world(head_angle(clock))

func _step_lash(dt: float) -> void:
	var hand := _hands()
	match _lash_phase:
		0:
			var np := _lash_head.move_toward(_lash_end, LASH_SPEED * dt)
			var q := PhysicsRayQueryParameters3D.create(_lash_head, np + (np - _lash_head).normalized() * R0 * thick)
			q.exclude = _excl()
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				_lash_hit(hit["position"], hit["normal"], hit["collider"], (np - _lash_head).normalized())
			else:
				_lash_head = np
				if _lash_head.distance_to(_lash_end) < 0.01:
					_lash_phase = 2
		1:
			if _lash_body == null or not is_instance_valid(_lash_body) or not lash_hold:
				if _lash_body != null and is_instance_valid(_lash_body):
					_whip_release(_lash_body)
				_lash_body = null
				_lash_phase = 2
			else:
				_lash_head = _lash_body.global_transform * _lash_local
				# stretched past its reach, the water lets go
				if _lash_head.distance_to(hand) > LASH_RANGE + 1.5:
					_lash_body = null
					_lash_phase = 2
		2:
			var home := ring_world(head_angle(clock))
			_lash_head = _lash_head.move_toward(home, LASH_BACK * dt)
			if _lash_head.distance_to(home) < 0.15:
				_lash_pts(hand, _lash_head)
				# back in the hands: the stream rejoins the loop along the path it lies on
				trail.clear()
				for i in range(N - 1, -1, -1):
					trail.append(pts[i])
				_stretch = 1.0
				state = S.HOLD
				_settling = true
				return
	_lash_pts(hand, _lash_head)

## Lays the stream from the hands to the head along a curve that sags as it flies out.
func _lash_pts(hand: Vector3, head: Vector3) -> void:
	var d := head - hand
	var dist := d.length()
	var sag := 0.25 if _lash_phase != 1 else 0.05
	var ctrl := hand + d * 0.45 + Vector3.UP * (sag * dist * 0.3)
	var arc := 0.0
	var prev := head
	for i in N:
		var u := float(i) / float(N - 1)
		var p := _curve(head, ctrl, hand, u)
		pts[i] = p
		arc += p.distance_to(prev)
		prev = p
	# the same water stretched over a longer path is thinner
	_stretch = sqrt(clampf(length / maxf(arc, 0.01), 0.15, 1.0))

func _lash_hit(p: Vector3, n: Vector3, col: Object, dir: Vector3) -> void:
	_lash_head = p - dir * 0.05
	var l := litres()
	if "--demo" in OS.get_cmdline_user_args():
		print("LASH hit %s at %s" % [col, p.snapped(Vector3(0.01, 0.01, 0.01))])
	if col != null and col.has_method("go_limp"):
		# a person is knocked down; their body can then be grabbed and hauled like anything loose
		col = col.go_limp()
	_splash_at(p, n, dir)
	var target: Object = col
	if target != null and not target.has_method("water_hit") and target.has_meta("sign"):
		target = target.get_meta("sign")
	if target != null and target.has_method("water_hit"):
		target.water_hit(p, n, dir, l)
	else:
		Wetness.mark(p, n, clampf(0.4 + sqrt(l) * 0.06, 0.4, 1.4), col)
	if col is RigidBody3D:
		var rb := col as RigidBody3D
		# a heavier body of water hits harder
		rb.apply_impulse(dir * minf(clampf(l * 0.35, 8.0, 400.0), rb.mass * 7.0), p - rb.global_position)
		if rb.has_method("struck"):
			rb.struck(p, dir)
		if lash_hold:
			_lash_body = rb
			_lash_local = rb.global_transform.affine_inverse() * p
			_lash_phase = 1
			_hold_v = Vector3.ZERO
			_prev_pull = Vector3.INF
			return
	_lash_phase = 2

## Let go while swinging: the body leaves along the swing, faster than the hold point moved (the water
## rope's length adds to the bender's turn, like a sling). Heavier bodies leave slower.
func _whip_release(rb: RigidBody3D) -> void:
	var s := _hold_v.length()
	if s < WHIP_MIN or rb.mass * GRAVITY > LIFT_MAX_N:
		return
	var top := WHIP_MAX * clampf(sqrt(25.0 / maxf(rb.mass, 0.1)), 0.3, 1.0)
	var v := minf(s * WHIP_GAIN, top)
	var dir := (_hold_v / s + Vector3.UP * 0.18).normalized()
	rb.sleeping = false
	rb.linear_velocity = dir * v
	if OS.get_cmdline_user_args().has("--demo"):
		print("THROW swing %.1f m/s -> %.1f m/s, %.1f kg" % [s, v, rb.mass])

# ---------------------------------------------------------------- state entry points

## litres: how much to draw; 0 is a normal draw (one stream, MAX_LEN long). More makes the stream thicker.
func begin_draw(src, litres := 0.0) -> void:
	set_thick(sqrt(maxf(litres, 0.0) / (MAX_LEN * L_PER_M)))
	source = src
	state = S.DRAW
	t_state = 0.0
	reach_u = 0.0
	pull_u = 0.0
	# the first few centimetres of stream are taken from the source like the rest
	length = maxf(src.take(0.05 * lpm()) / lpm(), 0.001)
	consumed = 0.0
	trail.clear()
	trail.append(src.surface_point())
	trail.append(src.surface_point())
	_alive.fill(1.0)
	_settling = false
	_sample_trail(0.0)
	_show = true

func begin_return() -> void:
	if state != S.HOLD and state != S.DRAW and state != S.STEER:
		return
	release_grab()
	state = S.RETURN
	t_state = 0.0
	consumed = 0.0

func begin_gather() -> void:
	if state == S.HOLD:
		state = S.GATHER
		t_state = 0.0

## Throws the water from the hand toward the target. The chain keeps following its head's path.
func launch(hand: Vector3, target: Vector3) -> void:
	var dist := hand.distance_to(target)
	var tt := maxf(dist / STRIKE_SPEED, 0.05)
	head_vel = (target - hand) / tt + Vector3(0, 0.5 * GRAVITY * 0.3 * tt, 0)
	state = S.STRIKE
	t_state = 0.0
	consumed = 0.0

## Precision mode: the held water leaves the body's loop and follows steer_target.
func begin_steer() -> void:
	if state != S.HOLD:
		return
	_head_v = (pts[0] - _prev_pts[0]) / _last_dt if _prev_pts.size() == N else Vector3.ZERO
	_loop_a = 0.0
	state = S.STEER
	t_state = 0.0

## Back to the loop around the body, travelling there under the same spring.
func end_steer() -> void:
	if state != S.STEER:
		return
	release_grab()
	state = S.HOLD
	_settling = true

## Serpent: the held water runs off the loop into the Serpent form at its waist (to(), a Callable giving
## the point) over MELD_T; put(l) takes the litres as they arrive and returns what it took. Once all of it
## has gone the bender holds nothing; what Serpent cannot take stays held.
func begin_meld(to: Callable, put: Callable) -> void:
	if state != S.HOLD:
		return
	_meld_to = to
	_meld_put = put
	_meld_rate = maxf(litres() / MELD_T, 60.0)
	_head_v = Vector3.ZERO
	state = S.MELD
	t_state = 0.0

func _step_meld(dt: float) -> void:
	var tgt: Vector3 = _meld_to.call()
	var head := trail[trail.size() - 1]
	_push_head(_follow(head, tgt, STEER_K * 3.0, dt))
	_sample_trail(0.0)
	# the water goes in as its head reaches the waist
	if head.distance_to(tgt) > 0.6 and t_state < MELD_T:
		return
	var have := litres()
	var t := minf(_meld_rate * dt, have)
	if have - t <= 0.3:
		t = have
	var took: float = _meld_put.call(t)
	if took < t - 0.01:
		# Serpent is full: the rest stays held
		_set_litres(have - took)
		state = S.HOLD
		_settling = true
		return
	_set_litres(have - took)

## Holding water in any way (the loop, precision, lash, Serpent): moves can take from it.
func holds_water() -> bool:
	return state == S.HOLD

## The bender lets go: every part of the water falls from where it is, at the speed it had.
func begin_fall() -> void:
	if state != S.STEER and state != S.HOLD and state != S.DRAW and state != S.LASH and state != S.MELD:
		return
	_feed_stop(true)
	_lash_body = null
	_stretch = 1.0
	if _film_obj != null:
		# the sheet runs off the body it covered and lands under it
		_film_drain = true
		_film_dir = -1.0
	grabbed = null
	for i in N:
		_pt_vel[i] = (pts[i] - _prev_pts[i]) / _last_dt if _prev_pts.size() == N else Vector3.ZERO
	_alive.fill(1.0)
	_splashed = false
	_fall_lpp = length * lpm() / float(N)
	state = S.FALL
	t_state = 0.0

## Catches a loose body: the nearest one within GRAB_REACH of the water, or the one under the crosshair
## (aim_body) if it is within GRAB_AIM_REACH. The water then reaches it and spreads over it.
func try_grab(aim_body: Object = null) -> bool:
	if state != S.STEER or grabbed != null or _film_obj != null:
		return false
	var best: RigidBody3D = null
	if aim_body is RigidBody3D and _dist_to_body(aim_body, pts[0]) < GRAB_AIM_REACH:
		best = aim_body
	else:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = GRAB_REACH
		q.shape = sh
		q.exclude = _excl()
		q.transform = Transform3D(Basis(), pts[0])
		var bd := INF
		for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
			var c: Object = r["collider"]
			if c is RigidBody3D:
				var d := _dist_to_body(c, pts[0])
				if d < bd:
					bd = d
					best = c
	if best == null:
		return false
	var cs: CollisionShape3D = null
	for ch in best.get_children():
		if ch is CollisionShape3D:
			cs = ch
			break
	if cs == null:
		return false
	grabbed = best
	_film_begin(best, cs)
	return true

func _dist_to_body(b: Node3D, p: Vector3) -> float:
	for ch in b.get_children():
		if ch is CollisionShape3D and ch.shape is BoxShape3D:
			var xf: Transform3D = b.global_transform * (ch as CollisionShape3D).transform
			var h: Vector3 = (ch.shape as BoxShape3D).size * 0.5
			var l := xf.affine_inverse() * p
			return (xf * l.clamp(-h, h)).distance_to(p)
	return b.global_position.distance_to(p)

## Lets go of the body: the sheet gathers back off it into the stream.
func release_grab() -> void:
	grabbed = null
	if _film_obj != null and not _film_drain:
		_film_dir = -1.0

func carrying() -> bool:
	return grabbed != null and _film_u > 0.15

# ---------------------------------------------------------------- the sheet over a caught body

func _film_begin(obj: RigidBody3D, cs: CollisionShape3D) -> void:
	_film_obj = obj
	_film_xf = cs.transform
	var h := Vector3.ONE * 0.25
	if cs.shape is BoxShape3D:
		h = (cs.shape as BoxShape3D).size * 0.5
	elif cs.shape is SphereShape3D:
		h = Vector3.ONE * (cs.shape as SphereShape3D).radius
	elif cs.shape is ConvexPolygonShape3D:
		# a cut piece: the sheet covers its bounding box
		var pp := (cs.shape as ConvexPolygonShape3D).points
		if pp.size() > 0:
			var bb := AABB(pp[0], Vector3.ZERO)
			for v in pp:
				bb = bb.expand(v)
			h = (bb.size * 0.5).max(Vector3.ONE * 0.03)
			_film_xf = cs.transform * Transform3D(Basis(), bb.get_center())
	_film_half = h
	_film_rc = minf(0.035, minf(h.x, minf(h.y, h.z)) * 0.6)
	var inner_h := h - Vector3.ONE * _film_rc
	_f_inner.clear()
	_f_n.clear()
	_f_noise.clear()
	_f_idx.clear()
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 3.0
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var b := (ax + 1) % 3
			var c := (ax + 2) % 3
			var base := _f_inner.size()
			for i in FILM_G + 1:
				for j in FILM_G + 1:
					var v := Vector3.ZERO
					v[ax] = sg * h[ax]
					v[b] = lerpf(-h[b], h[b], float(i) / FILM_G)
					v[c] = lerpf(-h[c], h[c], float(j) / FILM_G)
					var inn := v.clamp(-inner_h, inner_h)
					var nn := v - inn
					nn = nn.normalized() if nn.length() > 0.0001 else Vector3.ZERO
					if nn == Vector3.ZERO:
						nn[ax] = sg
					_f_inner.append(inn)
					_f_n.append(nn)
					_f_noise.append(noise.get_noise_3dv(v) * 0.5 + 0.5)
			var fn := Vector3.ZERO
			fn[ax] = sg
			for i in FILM_G:
				for j in FILM_G:
					var a0 := base + i * (FILM_G + 1) + j
					var a1 := a0 + 1
					var b0 := a0 + FILM_G + 1
					var b1 := b0 + 1
					var p0 := _f_inner[a0]
					var t1 := [a0, b0, a1]
					var t2 := [a1, b0, b1]
					# Godot draws clockwise faces as front faces
					if (_f_inner[b0] - p0).cross(_f_inner[a1] - p0).dot(fn) > 0.0:
						t1 = [a0, a1, b0]
						t2 = [a1, b1, b0]
					_f_idx.append_array(t1 + t2)
	# where the water touches first: the head's closest point on the body's surface
	var l: Vector3 = (obj.global_transform * _film_xf).affine_inverse() * pts[0]
	var cp := l.clamp(-h, h)
	if cp == l:
		var k := 0
		var best := INF
		for a in 3:
			var gap := h[a] - absf(cp[a])
			if gap < best:
				best = gap
				k = a
		cp[k] = signf(cp[k]) * h[k] if cp[k] != 0.0 else h[k]
	_contact = cp
	var ka := 0
	for a in 3:
		if absf(cp[a]) / h[a] > absf(cp[ka]) / h[ka]:
			ka = a
	_contact_n = Vector3.ZERO
	_contact_n[ka] = signf(cp[ka]) if cp[ka] != 0.0 else 1.0
	_flare_max = clampf(maxf(h.x, maxf(h.y, h.z)) * 0.9 / (R0 * thick), 1.2, 5.0)
	_f_d.clear()
	var maxd := 0.0
	for i in _f_inner.size():
		var d := (_f_inner[i] + _f_n[i] * _film_rc).distance_to(cp)
		_f_d.append(d)
		maxd = maxf(maxd, d)
	# the spreading edge is ragged: noise warps distance in proportion to the body's size
	for i in _f_d.size():
		_f_d[i] += (_f_noise[i] - 0.5) * 0.35 * maxd
	_f_sorted = _f_d.duplicate()
	_f_sorted.sort()
	var area := 8.0 * (h.x * h.y + h.y * h.z + h.x * h.z)
	var litres := length * lpm()
	_film_t = minf(litres / 1000.0 / area, FILM_MAX_T)
	_film_cap = _film_t * area * 1000.0
	_film_u = 0.0
	_film_l = 0.0
	_film_dir = 0.0
	_film_drain = false
	_film_drained = 0.0

func _contact_world() -> Vector3:
	return _film_obj.global_transform * _film_xf * _contact

## Moves volume between the stream and the sheet as the sheet spreads or gathers.
func _film_step(dt: float) -> void:
	if _film_obj == null:
		return
	if not is_instance_valid(_film_obj):
		_film_obj = null
		_film.visible = false
		return
	if _film_dir == 0.0 and pts[0].distance_to(_contact_world()) < 0.15:
		_film_dir = 1.0
	var dur := FILM_DRAIN if _film_drain else (FILM_SPREAD if _film_dir > 0.0 else FILM_PEEL)
	_film_u = clampf(_film_u + _film_dir * dt / dur, 0.0, 1.0)
	var want := _film_cap * _film_u
	if _film_drain:
		_film_drained += maxf(_film_l - want, 0.0)
	elif state != S.NONE:
		length = maxf(length - (want - _film_l) / lpm(), 0.0)
	_film_l = want
	if _film_u <= 0.0 and _film_dir < 0.0:
		if _film_drain and _film_drained > 0.0:
			# the run-off lands under the body
			var c := _film_obj.global_position
			var q := PhysicsRayQueryParameters3D.create(c, c + Vector3.DOWN * 20.0)
			q.exclude = [_film_obj.get_rid()] + _excl()
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				Puddle.add_at(hit["position"], _film_drained, get_tree(), get_parent())
				Wetness.mark(hit["position"], hit["normal"], 0.9, hit["collider"])
		_film_obj = null
		_film.visible = false

func _film_mesh_build() -> void:
	if _film_obj == null or _film_u <= 0.0:
		_film.visible = false
		return
	_film.visible = true
	_film.global_transform = _film_obj.global_transform * _film_xf
	var e := _film_u * _film_u * (3.0 - 2.0 * _film_u)
	var n := _f_sorted.size()
	var w := 0.06
	var r := _f_sorted[int(e * (n - 1))] + w * (2.0 * e - 1.0) * 1.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n)
	norms.resize(n)
	cols.resize(n)
	for i in n:
		var cov := 1.0 - smoothstep(r - w * 1.5, r + w * 1.5, _f_d[i])
		# thickest behind the front, thinning at it; it swells and settles slightly as it moves
		var th := _film_t * cov * (0.8 + 0.4 * _f_noise[i] + 0.1 * sin(clock * 3.0 + _f_noise[i] * 9.0))
		verts[i] = _f_inner[i] + _f_n[i] * (_film_rc + 0.004 + th)
		norms[i] = _f_n[i]
		cols[i] = Color(0, 0, 0, clampf(cov * 1.4, 0.0, 1.0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = _f_idx
	_film_mesh.clear_surfaces()
	_film_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

func is_holding() -> bool:
	return state == S.HOLD

func head_pos() -> Vector3:
	return pts[0]

func seg() -> float:
	return maxf(length, 0.01) / float(N - 1)

func set_hand_provider(c: Callable) -> void:
	_hand_provider = c

# ---------------------------------------------------------------- drawing more (the feed stream)

## litres held plus those on their way up the feed.
func litres_coming() -> float:
	return litres() + _feed_l

func feeding() -> bool:
	return _feed_on and _feed_cut == 0.0

## R1 held, or a tap's water still to come (keep_gathering, set by the player): a stream runs from the source up to the held
## water's tail, and the held water grows only by what arrives through it. Off the source, its foot
## leaves the source and the rest of it runs up into the held water.
func _feed_step(dt: float) -> void:
	var want := keep_gathering and state == S.HOLD and is_instance_valid(source)
	if want and (not _feed_on or _feed_cut > 0.0):
		if not _feed_on:
			_feed_t = 0.0
			_feed_l = 0.0
		_feed_on = true
		_feed_cut = 0.0
	if not _feed_on:
		_feed_show = false
		return
	if state != S.HOLD and state != S.LASH and state != S.STEER:
		_feed_stop(true)
		return
	var tail_p := pts[N - 1]
	if want:
		_feed_a = source.surface_point()
		_feed_t += dt
		_feed_rate = minf(maxf(GATHER_R0 * exp(_feed_t / GATHER_TAU), QUICK_RATE if feed_quick else 0.0), 600.0)
		_feed_l += source.take(minf(_feed_rate * dt, maxf(gather_cap - litres_coming(), 0.0)))
	var span := _feed_len(tail_p)
	if not want:
		_feed_cut = minf(_feed_cut + dt * FEED_SPEED / maxf(span, 0.5), 1.0)
	# what reaches the top joins the held water
	var arrive := minf(_feed_l, _feed_l * dt * FEED_SPEED / maxf(span * (1.0 - _feed_cut), 0.3))
	if _feed_cut >= 1.0:
		arrive = _feed_l
	_feed_l -= arrive
	if arrive > 0.0:
		add_litres(arrive)
	if _feed_cut >= 1.0 and _feed_l <= 0.001:
		_feed_on = false
		_feed_show = false
		return
	_feed_build(tail_p)

## Feed gone at once (the water was let go): what is on its way falls back where it came from.
func _feed_stop(spill: bool) -> void:
	if not _feed_on:
		return
	if spill and _feed_l > 0.0:
		if is_instance_valid(source):
			source.give(_feed_l)
		else:
			Puddle.add_at(_feed_a, _feed_l, get_tree(), get_parent())
	_feed_l = 0.0
	_feed_on = false
	_feed_show = false

func _feed_ctrl(b: Vector3) -> Vector3:
	return (_feed_a + b) * 0.5 + Vector3.UP * (0.6 + 0.12 * _feed_a.distance_to(b))

func _feed_len(b: Vector3) -> float:
	var c := _feed_ctrl(b)
	var l := 0.0
	var prev := _feed_a
	for k in range(1, 9):
		var q := _curve(_feed_a, c, b, k / 8.0)
		l += prev.distance_to(q)
		prev = q
	return l

func _feed_build(b: Vector3) -> void:
	var c := _feed_ctrl(b)
	# as thick as the flow it carries, at the held stream's look (L_PER_M), never thinner than a trickle
	var look := (PI * R0 * R0 * 1000.0) / L_PER_M          # m³ shown per m³ of water
	var r := clampf(sqrt(_feed_rate / 1000.0 * look / (PI * FEED_SPEED)), k("feed_min"), k("feed_max"))
	if _feed_cut > 0.0:
		r *= sqrt(1.0 - _feed_cut * 0.6)
	var n := FEED_PIECES
	_feed_P.resize(n + 1)
	_feed_R.resize(n + 1)
	for i in n + 1:
		var u := lerpf(_feed_cut, 1.0, float(i) / n)
		_feed_P[i] = _curve(_feed_a, c, b, u)
		# it meets the held water's tail at that tail's thickness
		var end := clampf((1.0 - u) / 0.15, 0.0, 1.0)
		_feed_R[i] = lerpf(R0 * thick * 0.6, r, end) * (k("feed_foot") if i == 0 and _feed_cut == 0.0 else 1.0)
	_feed_show = true

# ---------------------------------------------------------------- simulation

func _process(frame_dt: float) -> void:
	# a slow frame is simulated in several steps so the water keeps real time with the physics
	var n := clampi(ceili(frame_dt * 60.0), 1, 6)
	for i in n:
		_step(minf(frame_dt / n, 1.0 / 30.0))
	# the front of the stream splays out against the body as it arrives, before the sheet spreads
	var fg := 0.0
	if _film_obj != null and is_instance_valid(_film_obj) and not _film_drain and state == S.STEER:
		if _film_dir != 0.0:
			fg = 1.0
		else:
			fg = clampf(1.0 - (pts[0].distance_to(_contact_world()) - 0.15) / 0.9, 0.0, 1.0) * 0.45
	_flare = move_toward(_flare, fg, frame_dt * 3.0)
	_film_mesh_build()
	_show = not (state == S.NONE or length < 0.015)
	_w.clear()
	if _show:
		_build_mesh()
	if _feed_show and _feed_on:
		_w.chain(_feed_P, _feed_R)
	_w.visible = _w.count > 0
	if _w.visible:
		var origin := player.global_position if player != null else pts[0]
		_w.look("absorb", k("absorb"))
		_w.look("foam", k("strike_foam") if state == S.STRIKE or state == S.IMPACT else 0.0)
		_w.commit(k("blend") * thick, origin, k("wave"))

func _step(dt: float) -> void:
	clock += dt
	_film_step(dt)
	_feed_step(dt)
	if state == S.NONE:
		return
	_prev_pts = pts.duplicate()
	_last_dt = maxf(dt, 0.001)
	t_state += dt
	match state:
		S.DRAW: _step_draw(dt)
		S.HOLD: _step_hold(dt)
		S.GATHER: _step_gather(dt)
		S.STRIKE: _step_strike(dt)
		S.IMPACT: _step_impact(dt)
		S.RETURN: _step_return(dt)
		S.STEER: _step_steer(dt)
		S.FALL: _step_fall(dt)
		S.LASH: _step_lash(dt)
		S.MELD: _step_meld(dt)

## Moves the live head to p and records the path it has travelled.
func _push_head(p: Vector3) -> void:
	var n := trail.size()
	if n >= 2 and trail[n - 1].distance_to(trail[n - 2]) > 0.03:
		trail.append(p)
	else:
		trail[n - 1] = p
	# forget path older than the water needs
	var keep := length + 1.0
	var acc := 0.0
	var i := trail.size() - 1
	while i > 0 and acc < keep:
		acc += trail[i].distance_to(trail[i - 1])
		i -= 1
	if i > 4:
		trail = trail.slice(i - 1)

func _curve(p0: Vector3, p1: Vector3, p2: Vector3, u: float) -> Vector3:
	return p0.lerp(p1, u).lerp(p1.lerp(p2, u), u)

func _step_draw(dt: float) -> void:
	# reach_u and pull_u come from the bender's body. The water rises a little toward the hands while
	# they reach, and only travels to the body as the pull happens.
	# a puddle drawn dry is gone; the water already drawn carries on from where it left
	var anchor: Vector3 = source.surface_point() if is_instance_valid(source) else trail[0]
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
	if want > length and is_instance_valid(source):
		var got: float = source.take((want - length) * lpm())
		length += got / lpm()
	_push_head(_curve(anchor, ctrl, dest, ut))
	_sample_trail(0.0)
	if pull_u >= 1.0:
		state = S.HOLD
		t_state = 0.0

func _step_hold(dt: float) -> void:
	var tgt := ring_world(head_angle(clock))
	if _settling:
		# coming back from precision mode: the head swings back in and joins the loop
		var head := trail[trail.size() - 1]
		_push_head(_follow(head, tgt, STEER_K * 1.6, dt))
		if head.distance_to(tgt) < 0.08:
			_settling = false
	else:
		_push_head(tgt)
	_sample_trail(0.0)

## One step of the head chasing tgt, with collision. Returns the new head position.
func _follow(head: Vector3, tgt: Vector3, k: float, dt: float, tgt_vel := Vector3.ZERO) -> Vector3:
	var c := 2.0 * sqrt(k) * STEER_ZETA
	var acc := ((tgt - head) * k + (tgt_vel - _head_v) * c).limit_length(STEER_MAX_ACC)
	_head_v = (_head_v + acc * dt).limit_length(STEER_MAX_SPEED)
	return _move_head(head, _head_v * dt, dt)

func _step_steer(dt: float) -> void:
	var center := steer_target
	var r := LOOP_R
	var w := LOOP_W
	var axis: Vector3
	var k := STEER_K
	var tv := Vector3.ZERO
	if grabbed != null and is_instance_valid(grabbed) and _film_obj == grabbed:
		# the head goes to where the water touches the body and stays there, moving with it, while the
		# stream pours into the sheet spreading over the body
		var cw := _contact_world()
		tv = grabbed.linear_velocity + grabbed.angular_velocity.cross(cw - grabbed.global_position)
		_push_head(_follow(trail[trail.size() - 1], cw, STEER_K * 3.0, dt, tv))
		_sample_trail(0.0)
		_wet_grabbed(dt)
		return
	else:
		grabbed = null
		# a resting water body circulates in a loop roughly facing the bender, tilting slowly;
		# moving fast, the loop closes up and the water runs out into a stream behind its head
		axis = (steer_basis.z + steer_basis.x * 0.35 * sin(clock * 0.6) + steer_basis.y * 0.25 * sin(clock * 0.45 + 0.7)).normalized()
		r *= clampf(1.0 - _head_v.length() / 9.0, 0.25, 1.0)
	_loop_a += w * dt
	var e1 := axis.cross(Vector3.UP)
	if e1.length() < 0.1:
		e1 = axis.cross(Vector3.RIGHT)
	e1 = e1.normalized()
	var e2 := axis.cross(e1)
	var tgt := center + (e1 * cos(_loop_a) + e2 * sin(_loop_a)) * r
	_push_head(_follow(trail[trail.size() - 1], tgt, k, dt, tv))
	_sample_trail(0.0)

func _physics_process(dt: float) -> void:
	if lash_latched() and is_instance_valid(_lash_body):
		# hauled in by the water rope, at the point it holds; the hold point swings with the bender
		var rb := _lash_body
		if _prev_pull != Vector3.INF and dt > 0.0:
			_hold_v = _hold_v.lerp((lash_pull_to - _prev_pull) / dt, clampf(dt * 15.0, 0.0, 1.0))
		_prev_pull = lash_pull_to
		var at := rb.global_transform * _lash_local
		var pv := rb.linear_velocity + rb.angular_velocity.cross(at - rb.global_position)
		# the spring moves toward the hold point at its own speed, so a swung body keeps up with it
		var f := ((lash_pull_to - at) * LASH_PULL_K - (pv - _hold_v) * 2.0 * sqrt(LASH_PULL_K) * 0.8) * rb.mass
		f += Vector3.UP * GRAVITY * rb.mass * 0.4
		rb.sleeping = false
		var fmax := clampf(rb.mass * LASH_F_PER_KG, LASH_MAX_F, LASH_F_CAP)
		f = f.limit_length(fmax)
		# the water can drag anything but lift only so much: a boat is hauled along, not raised
		f.y = minf(f.y, LIFT_MAX_N)
		rb.apply_force(f, at - rb.global_position)
	if grabbed == null:
		return
	if not is_instance_valid(grabbed) or state != S.STEER:
		grabbed = null
		return
	if not carrying():
		return     # the water has not reached it yet
	# carried by the water: pulled toward the bender's point, its weight borne, its spin damped
	var m := grabbed.mass
	var to := steer_target - grabbed.global_position
	var f := (to * GRAB_K - grabbed.linear_velocity * 2.0 * sqrt(GRAB_K) * 0.85) * m
	f += Vector3.UP * GRAVITY * m * grabbed.gravity_scale
	grabbed.sleeping = false
	grabbed.apply_central_force(f.limit_length(GRAB_MAX_F))
	grabbed.apply_torque(-grabbed.angular_velocity * m * 0.4)

func _excl() -> Array[RID]:
	var ex: Array[RID] = []
	if player:
		ex.append((player as CollisionObject3D).get_rid())
	if grabbed != null and is_instance_valid(grabbed):
		ex.append(grabbed.get_rid())
	if _film_obj != null and is_instance_valid(_film_obj) and _film_obj != grabbed:
		ex.append(_film_obj.get_rid())
	return ex

## Moves the head by motion as a sphere of water: it stops at surfaces and slides along them, wetting
## what it touches and shoving loose bodies it runs into.
func _move_head(from: Vector3, motion: Vector3, dt: float) -> Vector3:
	if motion.length() < 0.00001:
		return from
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.exclude = _excl()
	q.transform = Transform3D(Basis(), from)
	q.motion = motion
	var res := space.cast_motion(q)
	if res.is_empty() or res[0] >= 1.0 or res[1] <= 0.0:
		return from + motion
	var safe := from + motion * res[0]
	q.transform = Transform3D(Basis(), from + motion * res[1])
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return safe
	var n: Vector3 = info["normal"]
	_touch(info["point"], n, instance_from_id(info["collider_id"]), motion / dt)
	var rest := motion * (1.0 - res[0])
	rest -= n * rest.dot(n)
	_head_v -= n * minf(_head_v.dot(n), 0.0)
	q.transform = Transform3D(Basis(), safe)
	q.motion = rest
	var r2 := space.cast_motion(q)
	if r2.is_empty():
		return safe
	return safe + rest * r2[0]

func _touch(p: Vector3, n: Vector3, col: Object, vel: Vector3) -> void:
	if p.distance_to(_last_wet) > WET_SPACING and length > 0.6:
		_last_wet = p
		Wetness.mark(p, n, randf_range(0.4, 0.6), col)
		length -= WET_COST / lpm()
	if col is RigidBody3D:
		# about a hand's length of the stream (a few kg) striking it
		var into := maxf(-vel.dot(n), 0.0)
		var rb := col as RigidBody3D
		rb.apply_impulse((-n * into + vel * 0.3) * 2.5, p - rb.global_position)

func _wet_grabbed(dt: float) -> void:
	_wet_t += dt
	if _wet_t < 0.2:
		return
	_wet_t = 0.0
	var q := PhysicsRayQueryParameters3D.create(pts[0], grabbed.global_position)
	if player:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] == grabbed:
		Wetness.mark(hit["position"], hit["normal"], randf_range(0.3, 0.45), grabbed)

## Water that has landed at p collects into a puddle on the ground: where it hit if that is level, fixed
## ground; otherwise it runs off and collects on the ground below.
func _pool(p: Vector3, n: Vector3, col: Object, litres: float) -> void:
	var gp := p
	if n.y < 0.7 or col is RigidBody3D:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.05, p + Vector3.DOWN * 20.0)
		var ex := _excl()
		if col is CollisionObject3D:
			ex.append((col as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return
		gp = hit["position"]
	Puddle.add_at(gp, litres, get_tree(), get_parent())

func _step_fall(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if player:
		ex.append((player as CollisionObject3D).get_rid())
	var flying := 0
	var any := false
	for i in N:
		if _alive[i] < 1.0:
			# landed: this part spreads out on the surface
			_alive[i] = maxf(_alive[i] - dt * 4.0, 0.0)
			any = any or _alive[i] > 0.0
			continue
		flying += 1
		any = true
		var v := _pt_vel[i]
		v.y -= GRAVITY * dt
		v *= 1.0 - 0.15 * dt
		var np := pts[i] + v * dt
		var q := PhysicsRayQueryParameters3D.create(pts[i], np)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			pts[i] = np
			_pt_vel[i] = v
			continue
		pts[i] = hit["position"]
		_alive[i] = 0.999
		var hp: Vector3 = hit["position"]
		if not _splashed:
			# where the bulk of the water lands it soaks a patch sized by its volume (about 1.6 m for a barrel's draw)
			_splashed = true
			_splash_at(hp, hit["normal"], v.normalized())
			Wetness.mark(hp, hit["normal"], clampf(sqrt(length * lpm()) * 0.2, 0.8, 2.0), hit["collider"])
			_last_wet = hp
		if hp.distance_to(_last_wet) > 0.3:
			_last_wet = hp
			Wetness.mark(hp, hit["normal"], randf_range(0.6, 0.9), hit["collider"])
		if hit["collider"] is RigidBody3D:
			var rb: RigidBody3D = hit["collider"]
			rb.apply_impulse(v * _fall_lpp * 0.5, hp - rb.global_position)
		_pool(hp, hit["normal"], hit["collider"], _fall_lpp)
	# the airborne water holds together a little as it falls
	for it in 2:
		for i in N - 1:
			if _alive[i] < 1.0 or _alive[i + 1] < 1.0:
				continue
			var d := pts[i + 1] - pts[i]
			var l := d.length()
			if l < 0.0001:
				continue
			var corr := d * ((l - seg()) / l) * 0.12
			pts[i] += corr
			pts[i + 1] -= corr
	if not any or t_state > 5.0:
		state = S.NONE
		length = 0.0
		_alive.fill(1.0)
		_show = false

func _step_gather(dt: float) -> void:
	# the head is drawn into the hand; the rest of the water follows its path
	var h: Vector3 = pts[0]
	if _hand_provider.is_valid():
		h = _hand_provider.call()
	_push_head(trail[trail.size() - 1].lerp(h, clampf(dt * 14.0, 0.0, 1.0)))
	_sample_trail(0.0)

func _step_strike(dt: float) -> void:
	var old := trail[trail.size() - 1]
	head_vel.y -= GRAVITY * 0.3 * dt
	var np := old + head_vel * dt
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(old, np)
	if player:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_impact(hit["position"], hit["normal"], hit["collider"])
		return
	_push_head(np)
	_sample_trail(0.0)
	if t_state > 1.5:
		_impact(np, Vector3.UP, null)

func _impact(p: Vector3, n: Vector3, obj: Object) -> void:
	hit_normal = n
	hit_obj = obj
	trail[trail.size() - 1] = p
	state = S.IMPACT
	t_state = 0.0
	consumed = 0.0
	var dir := head_vel.normalized()
	if obj != null:
		var target: Object = obj
		if not target.has_method("water_hit") and target.has_meta("sign"):
			target = target.get_meta("sign")
		if target.has_method("water_hit"):
			target.water_hit(p, n, dir, length * lpm())
		else:
			Wetness.mark(p, n, randf_range(0.9, 1.2), obj)
	_splash_at(p, n, dir)
	# the thrown water does not vanish: it falls from what it hit and collects below
	var litres := length * lpm()
	get_tree().create_timer(0.5).timeout.connect(func(): _pool(p + n * 0.1, Vector3.DOWN, null, litres))
	impacted.emit(p, n)

func _splash_at(p: Vector3, n: Vector3, dir: Vector3) -> void:
	var out := dir.bounce(n).normalized()
	_splash.global_position = p + n * 0.03
	var pm: ParticleProcessMaterial = _splash.process_material
	pm.direction = (out + n * 0.6).normalized()
	_splash.restart()
	_splash.emitting = true

func _step_impact(dt: float) -> void:
	consumed += 16.0 * dt
	_sample_trail(consumed)
	if consumed >= length + 0.2:
		state = S.NONE
		length = 0.0
		_show = false

func _step_return(dt: float) -> void:
	var tgt: Vector3 = source.surface_point()
	var head := trail[trail.size() - 1]
	if head.distance_to(tgt) > 0.3 and consumed == 0.0:
		var to := tgt + Vector3.UP * 0.2 - head
		_push_head(head + to.normalized() * minf(to.length(), 7.0 * dt))
		_sample_trail(0.0)
	else:
		var before := consumed
		consumed += 7.0 * dt
		source.give((minf(consumed, length) - minf(before, length)) * lpm())
		_sample_trail(consumed)
		if consumed >= length + 0.1:
			length = 0.0
			state = S.NONE
			_show = false

## Places every point at its arc distance behind the head along the head's recorded path.
func _sample_trail(extra: float) -> void:
	var s := seg()
	var idx := trail.size() - 1
	var acc := 0.0
	for i in N:
		var d_next := maxf(0.0, i * s - extra)
		while idx > 0 and acc + trail[idx].distance_to(trail[idx - 1]) < d_next:
			acc += trail[idx].distance_to(trail[idx - 1])
			idx -= 1
		if idx == 0:
			pts[i] = trail[0]
		else:
			var seglen := trail[idx].distance_to(trail[idx - 1])
			var f := (d_next - acc) / maxf(seglen, 0.0001)
			pts[i] = trail[idx].lerp(trail[idx - 1], clampf(f, 0.0, 1.0))

# ---------------------------------------------------------------- mesh

func _profile(i: int) -> float:
	var w := float(i) / float(N - 1)     # 0 head .. 1 tail
	var r := 1.0
	if state == S.STRIKE or state == S.IMPACT:
		r = lerpf(k("strike_head"), k("strike_tail"), pow(w, k("strike_taper")))
	else:
		r = 1.0 + k("swell") * sin(TAU * (w * 2.0 - clock * 0.7))
	# rounded head and tail
	var cap := k("cap") / float(N - 1)
	var he := clampf(w / cap, 0.0, 1.0)
	var te := clampf((1.0 - w) / cap, 0.0, 1.0)
	r *= sqrt(1.0 - pow(1.0 - he, 2.0)) * sqrt(1.0 - pow(1.0 - te, 2.0))
	var vol := clampf(length / 0.5, 0.05, 1.0)
	if state == S.FALL:
		r *= _alive[i]
	if state == S.LASH:
		r *= _stretch
	return r * sqrt(vol) * R0 * thick * k("radius")

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("held", n)

func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)

## The held water as pieces of one surface: a round cone between each pair of points along it. Where it
## arrives on a body (precision bending), its front splays out flat onto the face before the sheet spreads.
func _build_mesh() -> void:
	var rad := PackedFloat32Array()
	rad.resize(N)
	for i in N:
		rad[i] = _profile(i)
	var fl := _flare if _film_obj != null and is_instance_valid(_film_obj) else 0.0
	var fn := Vector3.UP
	if fl > 0.001:
		var fx := _film_obj.global_transform * _film_xf
		fn = (fx.basis * _contact_n).normalized()
		var flen := 0.3 + 0.35 * fl
		var arc := 0.0
		for i in N:
			if i > 0:
				arc += pts[i].distance_to(pts[i - 1])
			var g := clampf(1.0 - arc / flen, 0.0, 1.0)
			rad[i] *= 1.0 + (_flare_max - 1.0) * g * g * fl
	var room := _w.room() - (FEED_PIECES if _feed_show and _feed_on else 0)
	# a piece every other point (23 for the 46 points; each piece costs every pixel of the water), every
	# third if there is not room
	var step := 2 if (N - 1) / 2 <= room else 3
	var i := 0
	while i < N - 1:
		var j := mini(i + step, N - 1)
		if rad[i] > 0.003 or rad[j] > 0.003:
			if fl > 0.001 and i < 6:
				# the front pressed flat onto the face
				_w.seg(pts[i], rad[i], pts[j], rad[j], fn, lerpf(1.0, 0.3, fl * (1.0 - i / 6.0)))
			else:
				_w.seg(pts[i], rad[i], pts[j], rad[j])
		i = j
