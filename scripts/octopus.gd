class_name Octopus
extends Node3D
## Octopus form (Circle; owner's design and reference images): its own body of water, apart from the held
## water, like Serpent (the two are exclusive; Triangle and Circle switch between them). A wide ring of
## water flush with the ground round the bender, a dry gap of about half a metre round their feet, and six
## long tentacles rising from it, thick at the base and tapering to a soft point. Rooted: the bender does
## not walk; the left stick instead picks the active tentacle by its direction.
##  - Taking it: Circle with 300 L or more held melds the held water into it (or Circle in Serpent turns
##    Serpent's water into it). The bender then holds nothing and can let go of R1; Circle while holding
##    water adds it. L1 (relaxing) drops it as a puddle.
##  - Size (owner's numbers, not physical): 300 L, tentacles 0.3 m wide at the base and shoulder high;
##    600 L, 0.6 m wide and a foot over head high.
##  - Marking (hold R2): time slows a little, the camera closes in, everything grabbable within reach is
##    highlighted and each the crosshair is put directly on (no leeway) is marked, numbered in order, as
##    Dead Eye in Red Dead Redemption. Let go: a free tentacle (the one facing it) reaches for each in turn
##    in that order and holds it up at its tip.
##  - The active tentacle (left stick toward it) stands raised and a little thicker where it is planted.
##    R2 tapped throws what it holds at the crosshair; Square strikes with it (rears back, then whips down
##    at the crosshair, knocking down and away what it meets, held or not); L2 drops what it holds.
## Its look is set by the owner's sizes (a game allowance); its litres are counted exactly.

const N := 6
const MIN_ENTER := 300.0
const MAX_L := 1200.0
const RING_PIECES := 10         # pieces round the ring (each piece costs every pixel of the water)
const LIMB_PIECES := 4          # pieces along each tentacle
const REACH := 9.0               # m from a tentacle's base
const REACH_SPEED := 22.0
const BACK_SPEED := 14.0
const STAGGER := 0.12
const SLOW := 0.5
const F_PER_L := 40.0
const F_MIN := 600.0
const F_MAX := 4000.0
const HOLD_K := 30.0
const THROW_SPEED := 20.0
const GROW_T := 0.5
# strike: rear back, whip down, recover (s). An empty tentacle whips much faster; one holding something
# swings heavier (owner)
const STRIKE_EMPTY := [0.11, 0.07, 0.3]
const STRIKE_HELD := [0.3, 0.17, 0.55]
const TAP_TIME := 0.25

enum P { IDLE, REACH, HOLD, BACK }

class Limb:
	var phase := 0
	var angle := 0.0              # where it stands on the ring (world yaw)
	var body: RigidBody3D
	var local := Vector3.ZERO
	var tip := Vector3.ZERO
	var start := 0.0
	var target: Node3D
	var raise := 0.0              # 0..1, eased toward 1 while active
	var hit := {}

var active := false
var marking := false
var litres := 0.0
var bender: Player
var limbs: Array = []
var marked: Array = []
var current := 0                 # the active tentacle
var _centre := Vector3.ZERO
var _grow := 0.0
var _clock := 0.0
var _r2_t := -1.0
var _strike_t := -1.0
var _strike_to := Vector3.ZERO
var _st: Array = STRIKE_EMPTY      # the strike's timings
var _prev_tip := Vector3.ZERO
var _labels := {}
var _lit := {}
var _w: WaterSDF                 # the ring and the tentacles, drawn as one surface

static var _glow: StandardMaterial3D

func _ready() -> void:
	top_level = true
	_w = WaterSDF.new()
	add_child(_w)

# ---------------------------------------------------------------- size (owner's numbers)

## Tentacle length (m): shoulder high (1.45) at 300 L, a foot over head (2.05) at 600 L.
static func length_for(v: float) -> float:
	if v <= 600.0:
		return maxf(k("len_300") + k("len_per_300") * (v - 300.0) / 300.0, k("len_min"))
	return k("len_600") + k("len_over") * sqrt((v - 600.0) / 600.0)

## Tentacle radius at its base (m): 0.3 m wide at 300 L, 0.6 m at 600 L.
static func base_r_for(v: float) -> float:
	if v <= 600.0:
		return maxf(k("base_r_300") + k("base_r_per_300") * (v - 300.0) / 300.0, k("base_r_min"))
	return k("base_r_600") * pow(v / 600.0, k("base_r_pow"))

func ring_width() -> float:
	return clampf(k("ring_w_300") + k("ring_w_per_300") * (litres - 300.0) / 300.0, k("ring_w_min"), k("ring_w_max"))

func ring_height() -> float:
	return clampf(k("ring_h_300") + k("ring_h_per_300") * (litres - 300.0) / 300.0, k("ring_h_min"), k("ring_h_max"))

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("octopus", n)

func litres_per_limb() -> float:
	return litres / N

# ---------------------------------------------------------------- taking and leaving it

func begin(b: Player) -> void:
	bender = b
	active = true
	litres = 0.0
	_grow = 0.0
	_centre = b.global_position
	var face := b.cam_yaw
	limbs.clear()
	for i in N:
		var l := Limb.new()
		# two either side of straight ahead, two at the sides, two behind
		l.angle = face + deg_to_rad(30.0 + 60.0 * i)
		limbs.append(l)
	current = _limb_toward(-Basis(Vector3.UP, face).z)
	for i in N:
		(limbs[i] as Limb).tip = _rest_tip(i)
	_log("begin")

## Takes in up to l litres; returns what it took.
func add(l: float) -> float:
	if not active:
		return 0.0
	var t := clampf(l, 0.0, MAX_L - litres)
	litres += t
	return t

## Where held water melds in: the ring in front of the bender.
func meld_point() -> Vector3:
	return _centre + Vector3(0, 0.3, 0)

## Leaves the form keeping its water (switching to Serpent): returns the litres.
func take_all() -> float:
	var l := litres
	_release_all()
	litres = 0.0
	_close()
	return l

## Relaxing: the water falls where it is, as a puddle.
func drop() -> void:
	if not active:
		return
	_release_all()
	if litres > 0.0:
		Puddle.add_at(Vector3(_centre.x, bender.global_position.y, _centre.z), litres, get_tree(), bender.get_parent())
	litres = 0.0
	_close()

func _release_all() -> void:
	for i in limbs.size():
		_let_go(i, Vector3.ZERO)

func _close() -> void:
	active = false
	_set_marking(false)
	limbs.clear()
	_w.visible = false

func _log(s: String) -> void:
	if "--demo" in OS.get_cmdline_user_args():
		print("OCTO " + s)

# ---------------------------------------------------------------- geometry

func _out(i: int) -> Vector3:
	var a: float = (limbs[i] as Limb).angle
	return Vector3(-sin(a), 0, -cos(a))

func _ground_y() -> float:
	return bender.global_position.y

func _base(i: int) -> Vector3:
	var r := k("gap") + ring_width() * 0.5
	return Vector3(_centre.x, _ground_y() + ring_height() * 0.5, _centre.z) + _out(i) * r

## Where a tentacle's tip stands at rest: up and leaning out, swaying; the active one raised higher.
func _rest_tip(i: int) -> Vector3:
	var l: Limb = limbs[i]
	var L := length_for(litres) * _grow
	var up := L * lerpf(0.86, 1.15, l.raise)
	var sway := Vector3(sin(_clock * 0.9 + i * 1.7), 0, cos(_clock * 0.7 + i * 2.3)) * 0.08 * L
	return _base(i) + Vector3.UP * up + _out(i) * (L * lerpf(0.32, 0.18, l.raise)) + sway

## Where what tentacle i holds is kept: at its tip's rest place.
func hold_point(i: int) -> Vector3:
	if i == current and _strike_t >= 0.0:
		return (limbs[i] as Limb).tip
	return _rest_tip(i)

func _limb_toward(dir: Vector3) -> int:
	var best := 0
	var bd := -INF
	var d := Vector3(dir.x, 0, dir.z).normalized()
	for i in limbs.size():
		var s := _out(i).dot(d)
		if s > bd:
			bd = s
			best = i
	return best

# ---------------------------------------------------------------- what can be grabbed

func grabbable() -> Array:
	var out := []
	var taken := {}
	for l in limbs:
		var lb := l as Limb
		if lb.body != null and is_instance_valid(lb.body):
			taken[lb.body.get_instance_id()] = true
		if lb.target != null and is_instance_valid(lb.target):
			taken[lb.target.get_instance_id()] = true
	for n in get_tree().get_nodes_in_group("crate") + get_tree().get_nodes_in_group("person"):
		if not n is Node3D or (n as Node).is_queued_for_deletion() or taken.has(n.get_instance_id()):
			continue
		if n is RigidBody3D and (n as RigidBody3D).freeze:
			continue
		if n.is_in_group("person") and n.get("life") != null and float(n.life) >= 0.0:
			continue
		if _centre.distance_to(_point_of(n)) > REACH + 1.0:
			continue
		out.append(n)
	return out

func _point_of(n: Node3D) -> Vector3:
	if n.has_method("lash_point"):
		return n.lash_point()
	if n.is_in_group("person"):
		return n.global_position + Vector3(0, 1.0, 0)
	return n.global_position

func _under_crosshair(cands: Array):
	var b = bender.aim_body
	if b == null:
		return null
	for n in cands:
		if n == b or (n is Node and (n as Node).is_ancestor_of(b)):
			return n
	return null

func free_limbs() -> int:
	var n := 0
	for l in limbs:
		if (l as Limb).phase == P.IDLE or (l as Limb).phase == P.BACK:
			n += 1
	return n

func held_count() -> int:
	var n := 0
	for l in limbs:
		if (l as Limb).phase == P.HOLD:
			n += 1
	return n

func current_holds() -> bool:
	return active and current < limbs.size() and (limbs[current] as Limb).phase == P.HOLD

# ---------------------------------------------------------------- per frame (from the player)

## rdt: real time. stick: the left stick (picks the active tentacle by direction, camera-relative).
func update(rdt: float, r2: bool, r2_down: bool, l2_down: bool, square_down: bool, stick: Vector2) -> void:
	if not active:
		return
	if stick.length() > 0.6 and _strike_t < 0.0:
		var dir := Basis(Vector3.UP, bender.cam_yaw) * Vector3(stick.x, 0, stick.y)
		var c := _limb_toward(dir)
		if c != current:
			current = c
			_log("active %d" % c)
	if r2_down:
		_r2_t = 0.0
	if _r2_t >= 0.0:
		_r2_t += rdt
		if r2 and _r2_t > TAP_TIME and not marking and free_limbs() > 0:
			_set_marking(true)
		if not r2:
			if marking:
				_set_marking(false)
				_send()
			elif _r2_t <= TAP_TIME + 0.05:
				_throw()
			_r2_t = -1.0
	if marking:
		var cands := grabbable()
		_highlight(cands)
		var n = _under_crosshair(cands)
		if n != null and not marked.has(n) and marked.size() < free_limbs():
			marked.append(n)
			_label(n, str(marked.size()))
			_log("mark %d %s" % [marked.size(), n.name])
		if not bender.wheel_open:
			Engine.time_scale = SLOW
	if l2_down and current_holds():
		_log("drop")
		_let_go(current, Vector3.ZERO)
	if square_down and _strike_t < 0.0:
		_strike_t = 0.0
		var l: Limb = limbs[current]
		l.hit.clear()
		_st = STRIKE_HELD if l.phase == P.HOLD else STRIKE_EMPTY
		# down at the crosshair, as far as the tentacle stretches
		var b := _base(current)
		var reach := length_for(litres) * 2.0
		var to := bender.aim_point - b
		_strike_to = b + to.limit_length(reach)
		_log("strike with %d" % current)

func _set_marking(on: bool) -> void:
	if on == marking:
		return
	marking = on
	if not on:
		if bender != null and not bender.wheel_open:
			Engine.time_scale = 1.0
		_highlight([])
		for k in _labels:
			if is_instance_valid(_labels[k]):
				(_labels[k] as Node).queue_free()
		_labels.clear()
	else:
		marked.clear()
		_log("marking")

## After marking: for each marked thing in turn, the free tentacle facing it reaches for it.
func _send() -> void:
	var k := 0
	for n in marked:
		if not is_instance_valid(n):
			continue
		var best := -1
		var bd := -INF
		var d := (_point_of(n) - _centre) * Vector3(1, 0, 1)
		d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		for i in limbs.size():
			var lb: Limb = limbs[i]
			if (lb.phase == P.IDLE or lb.phase == P.BACK) and _out(i).dot(d) > bd:
				bd = _out(i).dot(d)
				best = i
		if best < 0:
			break
		var l: Limb = limbs[best]
		l.phase = P.REACH
		l.target = n
		l.body = null
		l.start = _clock + k * STAGGER
		k += 1
	_log("send %d" % k)
	marked.clear()

func _throw() -> void:
	if not current_holds():
		return
	var l: Limb = limbs[current]
	if l.body == null or not is_instance_valid(l.body):
		return
	var rb := l.body
	var v := THROW_SPEED * clampf(sqrt(25.0 / maxf(rb.mass, 0.1)), 0.25, 1.0)
	if rb.mass * WaterBody.GRAVITY > WaterBody.LIFT_MAX_N:
		v = 0.0
	var dir := ((bender.aim_point - rb.global_position).normalized() + Vector3.UP * 0.08).normalized()
	_log("throw %s at %.1f m/s" % [rb.name, v])
	_let_go(current, dir * v)

func _let_go(i: int, vel: Vector3) -> void:
	var l: Limb = limbs[i]
	if l.body != null and is_instance_valid(l.body):
		l.body.sleeping = false
		if vel != Vector3.ZERO:
			l.body.linear_velocity = vel
	l.body = null
	l.target = null
	if l.phase != P.IDLE:
		l.phase = P.BACK

func _process(dt: float) -> void:
	if not active:
		return
	_clock += dt
	_grow = minf(_grow + dt / GROW_T, 1.0)
	_centre = Vector3(bender.global_position.x, _centre.y, bender.global_position.z)
	for i in limbs.size():
		var l: Limb = limbs[i]
		l.raise = move_toward(l.raise, 1.0 if i == current else 0.0, dt * 4.0)
		_step_limb(i, dt)
	_step_strike(dt)
	_w.clear()
	_build_ring()
	for i in limbs.size():
		_build_limb(i)
	_w.look("absorb", k("absorb"))
	_w.commit(k("blend"), _centre, k("wave"))
	_w.visible = true
	for k in _labels.keys():
		var lab: Label3D = _labels[k]
		var n = instance_from_id(k)
		if is_instance_valid(lab) and n is Node3D:
			lab.global_position = _point_of(n) + Vector3(0, 0.8, 0)

func _step_limb(i: int, dt: float) -> void:
	var l: Limb = limbs[i]
	if i == current and _strike_t >= 0.0:
		return       # the strike moves it
	match l.phase:
		P.IDLE:
			l.tip = l.tip.lerp(_rest_tip(i), clampf(dt * 6.0, 0.0, 1.0))
		P.REACH:
			if _clock < l.start:
				l.tip = l.tip.lerp(_rest_tip(i), clampf(dt * 6.0, 0.0, 1.0))
				return
			if l.target == null or not is_instance_valid(l.target):
				l.phase = P.BACK
				return
			var tp := _point_of(l.target)
			if _base(i).distance_to(tp) > REACH + 1.5:
				l.phase = P.BACK
				return
			l.tip = l.tip.move_toward(tp, REACH_SPEED * dt)
			if l.tip.distance_to(tp) < 0.35:
				_catch(i)
		P.HOLD:
			if l.body == null or not is_instance_valid(l.body):
				l.phase = P.BACK
				return
			l.tip = l.body.global_transform * l.local
		P.BACK:
			var rt := _rest_tip(i)
			l.tip = l.tip.move_toward(rt, BACK_SPEED * dt)
			if l.tip.distance_to(rt) < 0.2:
				l.phase = P.IDLE

func _catch(i: int) -> void:
	var l: Limb = limbs[i]
	var n: Node = l.target
	if n.has_method("go_limp"):
		n = n.go_limp()
	if not n is RigidBody3D or not is_instance_valid(n):
		l.phase = P.BACK
		return
	var rb := n as RigidBody3D
	l.body = rb
	l.local = rb.global_transform.affine_inverse() * l.tip
	l.phase = P.HOLD
	_log("caught %s (%.1f kg) with %d" % [rb.name, rb.mass, i])
	if rb.has_method("struck"):
		rb.struck(l.tip, (l.tip - _centre).normalized())

# ---------------------------------------------------------------- the strike

## Rears back (up and away from the target), whips down at it fast, then settles back.
func _step_strike(dt: float) -> void:
	if _strike_t < 0.0:
		return
	_strike_t += dt
	var l: Limb = limbs[current]
	var b := _base(current)
	var L := length_for(litres)
	var f := (_strike_to - b) * Vector3(1, 0, 1)
	f = f.normalized() if f.length() > 0.01 else _out(current)
	var rear := b + Vector3.UP * (L * 1.25) - f * (L * 0.45)
	var prev := l.tip
	var rear_t: float = _st[0]
	var whip_t: float = _st[1]
	var rec_t: float = _st[2]
	if _strike_t < rear_t:
		var u := _strike_t / rear_t
		l.tip = l.tip.lerp(rear, clampf(dt * 6.0 / rear_t * 0.4 + u * 0.15, 0.0, 1.0))
	elif _strike_t < rear_t + whip_t:
		var u := (_strike_t - rear_t) / whip_t
		# accelerating down an arc over the top
		var e := u * u
		var over := rear.lerp(_strike_to, e) + Vector3.UP * (sin(PI * e) * L * 0.35)
		l.tip = over
		_strike_hits(prev, l.tip, dt)
	elif _strike_t < rear_t + whip_t + rec_t:
		l.tip = l.tip.lerp(_rest_tip(current), clampf(dt * 6.0, 0.0, 1.0))
	else:
		_strike_t = -1.0

## What the whipping tip sweeps through this frame is hit: a person knocked down, a loose body knocked
## away at the tip's speed, a fixed surface wetted (and anything that answers water, as the button).
func _strike_hits(a: Vector3, b: Vector3, dt: float) -> void:
	var l: Limb = limbs[current]
	# the tip's speed, as hits feel it (a frame's jump can read faster than the swing is)
	var vel := ((b - a) / maxf(dt, 0.001)).limit_length(30.0)
	var space := get_world_3d().direct_space_state
	var sp := SphereShape3D.new()
	sp.radius = base_r_for(litres) * 0.6 + 0.25
	for k in 4:
		var p := a.lerp(b, (k + 1) / 4.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sp
		q.transform = Transform3D(Basis(), p)
		var ex: Array[RID] = [bender.get_rid()]
		# not what the tentacles themselves hold
		for lo in limbs:
			if (lo as Limb).body != null and is_instance_valid((lo as Limb).body):
				ex.append((lo as Limb).body.get_rid())
		q.exclude = ex
		for r in space.intersect_shape(q, 8):
			var o: Object = r["collider"]
			if o == null or l.hit.has(o.get_instance_id()):
				continue
			l.hit[o.get_instance_id()] = true
			if o.has_method("go_limp"):
				var piece = o.go_limp()
				if piece is RigidBody3D:
					(piece as RigidBody3D).linear_velocity = vel * 0.4 + Vector3.UP * 2.0
				_log("strike knocked down a person")
			elif o is RigidBody3D and not (o as RigidBody3D).freeze:
				var rb := o as RigidBody3D
				rb.apply_central_impulse(vel * minf(rb.mass, 40.0) * 0.5)
				if rb.has_method("struck"):
					rb.struck(p, vel.normalized())
				_log("strike hit %s at %.1f m/s" % [rb.name, vel.length()])
			if o.has_method("water_hit"):
				o.water_hit(p, -vel.normalized(), vel.normalized(), litres_per_limb())
			elif not o is RigidBody3D:
				Wetness.mark(p, Vector3.UP, 0.9, o)

func _physics_process(_dt: float) -> void:
	if not active:
		return
	var fmax := clampf(litres_per_limb() * F_PER_L, F_MIN, F_MAX)
	for i in limbs.size():
		var l: Limb = limbs[i]
		if l.phase != P.HOLD or l.body == null or not is_instance_valid(l.body):
			continue
		var rb := l.body
		var at := rb.global_transform * l.local
		var pv := rb.linear_velocity + rb.angular_velocity.cross(at - rb.global_position)
		var striking := i == current and _strike_t >= 0.0
		var k := HOLD_K * (8.0 if striking else 1.0)
		var f := ((hold_point(i) - at) * k - pv * 2.0 * sqrt(k) * 0.8) * rb.mass
		f += Vector3.UP * WaterBody.GRAVITY * rb.mass * 0.4
		f = f.limit_length(fmax * (4.0 if striking else 1.0))
		f.y = minf(f.y, WaterBody.LIFT_MAX_N * (2.0 if striking else 1.0))
		rb.sleeping = false
		rb.apply_force(f, at - rb.global_position)
		rb.apply_torque(-rb.angular_velocity * rb.mass * 0.3)

# ---------------------------------------------------------------- looks

func _highlight(cands: Array) -> void:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Color(0.55, 0.9, 1.0, 0.3)
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.grow = true
		_glow.grow_amount = 0.025
	var want := {}
	for n in cands:
		want[n.get_instance_id()] = n
	for k in _lit.keys():
		if not want.has(k):
			for mi in _lit[k]:
				if is_instance_valid(mi):
					(mi as MeshInstance3D).material_overlay = null
			_lit.erase(k)
	for k in want:
		if not _lit.has(k):
			var mis := (want[k] as Node).find_children("*", "MeshInstance3D", true, false)
			for mi in mis:
				(mi as MeshInstance3D).material_overlay = _glow
			_lit[k] = mis

func _label(n: Node3D, text: String) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.0015
	lab.font_size = 40
	lab.outline_size = 10
	lab.modulate = Color(1.0, 0.85, 0.3)
	lab.layers = 2
	add_child(lab)
	lab.global_position = _point_of(n) + Vector3(0, 0.8, 0)
	_labels[n.get_instance_id()] = lab

## The ring: flush with the ground, a low rounded band from the dry gap outward (pieces round a circle,
## flattened to the ring's height).
func _build_ring() -> void:
	var w := ring_width() * 0.5 * _grow
	var h := ring_height() * _grow
	var r := k("gap") + ring_width() * 0.5
	var flat := clampf(h / maxf(w, 0.01), 0.05, 1.0)
	var c0 := Vector3(_centre.x, _ground_y() + h * 0.25, _centre.z)
	var prev := Vector3.ZERO
	var prev_w := 0.0
	for j in RING_PIECES + 1:
		var th := TAU * float(j) / RING_PIECES
		var out := Vector3(-sin(th), 0, -cos(th))
		var c := c0 + out * r
		var ww := w * (1.0 + k("ring_wobble") * sin(th * 5.0 + _clock * 0.8))
		if j > 0:
			_w.seg(prev, prev_w, c, ww, Vector3.UP, flat)
		prev = c
		prev_w = ww

## A tentacle: from its base in the ring, thick and flaring into it, bowing up then out to its tip, a soft
## point. The active one a little thicker. Stretched out to reach, it thins.
func _build_limb(i: int) -> void:
	var l: Limb = limbs[i]
	var b := _base(i) - Vector3(0, ring_height() * 0.3, 0)
	var t := l.tip
	var L := length_for(litres) * maxf(_grow, 0.05)
	var up := Vector3.UP * (L * 0.5)
	var p1 := b + up
	var p2 := t + (b + Vector3.UP * L - t) * 0.3 - _out(i) * (L * 0.12)
	var pts := PackedVector3Array()
	var n := LIMB_PIECES
	var arc := 0.0
	var prev := b
	for j in n + 1:
		var u := float(j) / n
		var p := b.lerp(p1, u).lerp(p1.lerp(p2, u), u).lerp(p1.lerp(p2, u).lerp(p2.lerp(t, u), u), u)
		arc += p.distance_to(prev)
		prev = p
		pts.append(p)
	var stretch := clampf(sqrt(L / maxf(arc, 0.01)), 0.45, 1.0)
	var r0 := base_r_for(litres) * maxf(_grow, 0.05) * lerpf(1.0, k("raised_thick"), l.raise) * stretch
	var rad := PackedFloat32Array()
	for j in n + 1:
		var u := float(j) / n
		var r := r0 * (1.0 - k("taper") * pow(u, k("taper_pow")))
		if j == 0:
			r *= k("base_flare")          # flaring into the ring
		r *= 1.0 + 0.04 * sin(u * 9.0 + _clock * 1.5 + i)
		rad.append(maxf(r, 0.015))
	_w.chain(pts, rad)
