class_name WaterWave
extends Node3D
## R2 held at a large body of water with none held: a wave rises there and grows while R2 is held; the
## crosshair swept across the water stretches its crest along the sweep. Let go, it runs away from the
## bender, its crest curling over into a breaking lip, shoving what floats in its way. Reaching the shore
## it breaks onto the land as a surge that runs on, spreads, soaks in and leaves its water as a puddle
## (or back in the water it fell into); a wall stops it.
## Its shape is a wave's, not a tube: a long back slope, a crest, a steep front face, and while running a
## lip pitching forward over the front, tapering to nothing at both ends of the crest. It is drawn as one
## surface (WaterSDF) from tubes running along the crest, each at a place in the cross-section (in units
## of the height: back, shoulder, crest, face, lip), blended from standing to breaking as it curls.
## Over water a wave moves energy, not the water itself: its body is the stream's surface raised and let
## down as it passes, and only what it throws onto the land (RUNUP_L) is counted as water there.

enum S { RISE, RUN, LAND, DONE }

const H_MIN := 0.5
const H_MAX := 2.4
const RISE_T := 1.8            # s held to reach full height
const LEN_MIN := 3.0
const LEN_MAX := 16.0
const SPEED := 7.0
const RUNUP_L := 30.0          # L onto the land per metre of crest per metre of height
const SOAK_EVERY := 0.6
const SOAK_L := 1.5            # L soaked per metre of crest per wet patch
const STATIONS := 4            # pieces along the crest, per tube (each piece costs every pixel of the water)

var state := S.RISE
var litres := 0.0
var pond: Pond
var _c := Vector3.ZERO          # the crest's middle, on the surface
var _d := Vector3.FORWARD       # travel
var _side := Vector3.RIGHT
var _e0 := -1.5                 # crest extent along _side from _c
var _e1 := 1.5
var _h := H_MIN
var _curl := 0.0
var _speed := 0.0
var _t := 0.0
var _travel := 0.0
var _soaked_at := 0.0
var _sink := 1.0                # 1 standing; falls to 0 as it dies away over open water
var _hit := {}
var _w: WaterSDF
var _box := BoxShape3D.new()

func begin(p: Pond, at: Vector3, bender_pos: Vector3) -> void:
	pond = p
	_c = at
	var d := Vector3(at.x - bender_pos.x, 0, at.z - bender_pos.z)
	_d = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	_side = _d.cross(Vector3.UP).normalized()
	_e0 = -LEN_MIN * 0.5
	_e1 = LEN_MIN * 0.5
	_log("rise")

## While R2 is held: the crosshair at `at` on the water stretches the crest to reach it.
func sweep(at: Vector3) -> void:
	if state != S.RISE:
		return
	var s := (at - _c).dot(_side)
	if s < _e0:
		_e0 = maxf(s, _e1 - LEN_MAX)
	elif s > _e1:
		_e1 = minf(s, _e0 + LEN_MAX)

func release() -> void:
	if state != S.RISE:
		return
	state = S.RUN
	_speed = SPEED
	_log("run")

func length() -> float:
	return _e1 - _e0

func height() -> float:
	return _h

func _ready() -> void:
	top_level = true
	_w = WaterSDF.new()
	_w.look("ripple_scale", 2.5)
	_w.look("ripple_strength", 0.6)
	add_child(_w)

func _excl() -> Array[RID]:
	var ex: Array[RID] = []
	var p := get_tree().get_first_node_in_group("player")
	if p is CollisionObject3D:
		ex.append((p as CollisionObject3D).get_rid())
	return ex

func _over_water(p: Vector3) -> bool:
	return pond != null and pond._inside(p, Pond.shore_f() * 0.98)

func _process(dt: float) -> void:
	if state == S.DONE:
		return
	_t += dt
	var space := get_world_3d().direct_space_state
	match state:
		S.RISE:
			_h = lerpf(H_MIN, H_MAX, clampf(_t / RISE_T, 0.0, 1.0))
		S.RUN:
			_curl = minf(_curl + dt / 1.2, 1.0)
			_h *= 1.0 - 0.03 * dt
			if _move(dt, space):
				return
			if not _over_water(_c):
				# onto the land: it breaks and surges on, carrying what it throws up
				state = S.LAND
				litres = RUNUP_L * length() * _h
				_soaked_at = _travel
				_log("ashore")
			elif _travel > 40.0:
				# dying away over open water
				_sink -= dt / 0.8
				if _sink <= 0.0:
					_end(false)
					return
		S.LAND:
			_speed = maxf(_speed - (1.6 + 0.25 * _speed) * dt, 0.0)
			_h = maxf(_h - (0.9 * _h + 0.1) * dt, 0.0)
			if _move(dt, space):
				return
			if _travel - _soaked_at > SOAK_EVERY:
				_soaked_at = _travel
				for f in [-0.35, 0.0, 0.35]:
					Wetness.mark(_c + _side * (f * length()) + Vector3.UP * 0.02, Vector3.UP, clampf(length() * 0.3, 0.8, 2.5))
				litres -= minf(SOAK_L * length(), litres)
			if _h < 0.12 or _speed < 0.8 or litres <= 1.0:
				_end(true)
				return
	_shove(dt, space)
	_build(space)

## One step forward. True when it struck a wall and is done.
func _move(dt: float, space: PhysicsDirectSpaceState3D) -> bool:
	var step := _d * _speed * dt
	var y0 := _base_y(_c, space)
	var q := PhysicsRayQueryParameters3D.create(_c + Vector3(0, y0 - _c.y + _h * 0.6, 0), _c + Vector3(0, y0 - _c.y + _h * 0.6, 0) + step + _d * (_h * 0.4))
	q.exclude = _excl()
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and not hit["collider"] is RigidBody3D and (hit["normal"] as Vector3).y < 0.6:
		_log("crash into %s" % hit["collider"])
		Wetness.mark(hit["position"], hit["normal"], clampf(_h * 1.5, 0.8, 2.5), hit["collider"])
		_splash(hit["position"], length())
		if state == S.RUN:
			litres = RUNUP_L * length() * _h * 0.3
		_end(true)
		return true
	_c += step
	_travel += step.length()
	return false

## The surface under p: the water's (parting included) over the stream, else the ground.
func _base_y(p: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	if _over_water(p):
		return pond.surface_y(p.x, p.z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 3.0, p.z), Vector3(p.x, p.y - 6.0, p.z))
	q.exclude = _excl()
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit["collider"] is RigidBody3D:
		return p.y
	return (hit["position"] as Vector3).y

## What floats in the front face is carried along and lifted; a person is knocked down.
func _shove(dt: float, space: PhysicsDirectSpaceState3D) -> void:
	if state == S.RISE:
		return
	var mid := _c + _side * ((_e0 + _e1) * 0.5)
	_box.size = Vector3(length() * 0.9, _h * 1.3 + 0.4, maxf(_h * 1.4, 0.8))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _box
	q.exclude = _excl()
	q.transform = Transform3D(Basis(_side, Vector3.UP, -_d), Vector3(mid.x, _base_y(mid, space) + _h * 0.5, mid.z) + _d * (_h * 0.3))
	for r in space.intersect_shape(q, 12):
		var b: Object = r["collider"]
		if b == null:
			continue
		if b.has_method("go_limp") and not _hit.has(b.get_instance_id()):
			_hit[b.get_instance_id()] = true
			b = b.go_limp()
		if b is RigidBody3D and not (b as RigidBody3D).freeze:
			var rb := b as RigidBody3D
			var rel := _d * _speed * 1.1 - rb.linear_velocity
			if rel.dot(_d) > 0.0:
				var k := clampf(_h * 1.5, 0.5, 4.0) * clampf(sqrt(80.0 / maxf(rb.mass, 1.0)), 0.35, 1.0)
				rb.sleeping = false
				rb.apply_central_impulse((rel + Vector3.UP * _h * 0.8) * rb.mass * k * dt)
				if not _hit.has(rb.get_instance_id()):
					_hit[rb.get_instance_id()] = true
					Wetness.mark(rb.global_position - _d * 0.2, -_d, 0.6, rb)

func _log(s: String) -> void:
	if "--demo" in OS.get_cmdline_user_args():
		print("WAVE %s c=%s h=%.2f len=%.1f v=%.1f L=%.1f travel=%.1f" % [s, _c.snapped(Vector3(0.01, 0.01, 0.01)), _h, length(), _speed, litres, _travel])

## Done: what it carried onto the land lies as a puddle (or rejoins the water it fell into).
func _end(spill: bool) -> void:
	_log("end")
	state = S.DONE
	_w.visible = false
	if spill and litres > 0.0:
		var mid := _c + _side * ((_e0 + _e1) * 0.5)
		var g := _base_y(mid, get_world_3d().direct_space_state)
		Puddle.add_at(Vector3(mid.x, g, mid.z), litres, get_tree(), get_parent())
	_splash(_c + _side * ((_e0 + _e1) * 0.5), length())
	litres = 0.0
	get_tree().create_timer(1.5).timeout.connect(queue_free)

func _splash(p: Vector3, w: float) -> void:
	var sp := GPUParticles3D.new()
	sp.amount = 200
	sp.lifetime = 1.1
	sp.one_shot = true
	sp.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.45, 0.2, 0.4)
	pm.direction = Vector3.UP
	pm.spread = 45.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	sp.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.75, 0.9, 1.0, 0.7)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = dm
	sp.draw_pass_1 = sm
	sp.layers = 2
	add_child(sp)
	sp.global_transform = Transform3D(Basis(_side, Vector3.UP, -_d), p + Vector3.UP * 0.3)
	sp.emitting = true

# ---------------------------------------------------------------- shape

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("wave", n)

## The tubes along the crest: [x along the travel, y up, radius], in units of the local height; standing
## (curl 0) blended to breaking (curl 1).
func _tubes(c: float) -> Array:
	return [
		[k("back_x"), k("back_y"), k("back_r")],
		[k("shoulder_x"), k("shoulder_y"), k("shoulder_r")],
		[lerpf(k("crest_x"), k("crest_x_break"), c), k("crest_y"), k("crest_r")],
		[lerpf(k("face_x"), k("face_x_break"), c), lerpf(k("face_y"), k("face_y_break"), c), lerpf(k("face_r"), k("face_r_break"), c)],
		[k("lip_x"), k("lip_y"), k("lip_r") * c],
	]

func _build(space: PhysicsDirectSpaceState3D) -> void:
	var len := length()
	var h := _h * maxf(_sink, 0.0)
	var c := _curl * _curl * (3.0 - 2.0 * _curl)
	var tubes := _tubes(c)
	_w.clear()
	# the stations along the crest: where they stand and how high the wave is there
	var at := []
	for i in STATIONS + 1:
		var f := float(i) / STATIONS
		var u := lerpf(-1.0, 1.0, f)
		# the middle of a running crest leads its ends a little
		var q := _c + _side * lerpf(_e0, _e1, f) + _d * ((1.0 - u * u) * len * 0.05 * _curl)
		var taper := pow(maxf(1.0 - u * u, 0.0), k("end_taper"))
		at.append([Vector3(q.x, _base_y(q, space), q.z), h * taper])
	for tb in tubes:
		for i in STATIONS:
			var a: Array = at[i]
			var b: Array = at[i + 1]
			var ha: float = maxf(a[1], 0.05)
			var hb: float = maxf(b[1], 0.05)
			var pa: Vector3 = a[0] + _d * (tb[0] * ha) + Vector3.UP * (tb[1] * ha)
			var pb: Vector3 = b[0] + _d * (tb[0] * hb) + Vector3.UP * (tb[1] * hb)
			_w.seg(pa, tb[2] * a[1], pb, tb[2] * b[1])
	var mid := _c + _side * ((_e0 + _e1) * 0.5)
	# over the stream it rises out of the surface, which is not in the depth buffer: not drawn below it
	var floor_y := pond.surface_y(mid.x, mid.z) if _over_water(mid) else -100000.0
	_w.look("absorb", k("absorb"))
	_w.look("foam", (0.25 + _curl * 0.7) * k("foam") if state != S.RISE else 0.2 * k("foam"))
	_w.commit(k("blend") * maxf(h, 0.3), mid, k("wave"), floor_y)
	_w.visible = _w.count > 0
