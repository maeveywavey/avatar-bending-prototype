class_name Geyser
extends Node3D
## R2 tapped at a large body of water with none held: a column of it shoots up where the crosshair is,
## stands a moment, then falls back into it. What is over it (loose bodies, people) is thrown up; a
## person is knocked down. Its water is the stream's and goes back to it (the stream is endless).

const HEIGHT := 7.0
const RADIUS := 0.45
const RISE_T := 0.3
const HOLD_T := 0.5
const FALL_T := 0.7
const LAUNCH := 11.0           # m/s upward given to what is over it

var _base := Vector3.ZERO
var _t := 0.0
var _hit := {}
var _w: WaterSDF
var _spray: GPUParticles3D

func begin(at: Vector3) -> void:
	_base = at

func _ready() -> void:
	top_level = true
	_w = WaterSDF.new()
	add_child(_w)
	_spray = GPUParticles3D.new()
	_spray.amount = 220
	_spray.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	_spray.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.75, 0.9, 1.0, 0.7)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = dm
	_spray.draw_pass_1 = sm
	_spray.layers = 2
	_spray.visibility_aabb = AABB(Vector3(-6, -HEIGHT - 2, -6), Vector3(12, HEIGHT + 6, 12))
	add_child(_spray)
	if "--demo" in OS.get_cmdline_user_args():
		print("GEYSER at %s" % _base.snapped(Vector3(0.01, 0.01, 0.01)))

## Height of the column's top now.
func top() -> float:
	if _t < RISE_T:
		var u := _t / RISE_T
		return HEIGHT * (1.0 - (1.0 - u) * (1.0 - u))
	if _t < RISE_T + HOLD_T:
		return HEIGHT * (1.0 + 0.03 * sin(_t * 20.0))
	var f := clampf((_t - RISE_T - HOLD_T) / FALL_T, 0.0, 1.0)
	return HEIGHT * (1.0 - f * f)

func _process(dt: float) -> void:
	_t += dt
	var h := top()
	_spray.global_position = _base + Vector3(0, h, 0)
	_spray.emitting = _t < RISE_T + HOLD_T + FALL_T * 0.6
	if _t > RISE_T + HOLD_T + FALL_T:
		_w.visible = false
		if _t > RISE_T + HOLD_T + FALL_T + 1.5:
			queue_free()
		return
	_lift(h)
	# the column: flared where it leaves the surface, thinning a little up to a ragged crown. Not drawn
	# under the stream's surface (floor), which it rises out of.
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var n := 8
	var falling := _t > RISE_T + HOLD_T
	for j in n + 1:
		var u := float(j) / n
		var y := h * u
		var r := k("radius") * (1.0 + k("flare") * exp(-y / k("flare_h"))) * lerpf(1.0, k("top"), u)
		r *= 1.0 + 0.08 * sin(u * 23.0 - _t * 30.0)
		if j == n:
			r *= k("crown")
		if falling:
			r *= 1.0 - 0.4 * clampf((_t - RISE_T - HOLD_T) / FALL_T, 0.0, 1.0)
		pts.append(_base + Vector3(0, y - 0.15, 0))
		rad.append(r)
	_w.clear()
	_w.chain(pts, rad)
	_w.look("absorb", k("absorb"))
	_w.look("drift", Vector3(0, k("rise_flow"), 0))
	_w.look("foam", k("foam"))
	_w.commit(k("blend"), _base, k("wave"), _base.y)
	_w.visible = true

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("geyser", n)

## What is over the column is thrown up, once.
func _lift(h: float) -> void:
	var space := get_world_3d().direct_space_state
	var cs := CylinderShape3D.new()
	cs.radius = RADIUS * 1.8
	cs.height = h + 0.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs
	q.transform = Transform3D(Basis(), _base + Vector3(0, h * 0.5, 0))
	for r in space.intersect_shape(q, 12):
		var b: Object = r["collider"]
		if b == null or _hit.has(b.get_instance_id()):
			continue
		if b.has_method("go_limp"):
			_hit[b.get_instance_id()] = true
			b = b.go_limp()
			if b == null:
				continue
		if b is RigidBody3D and not (b as RigidBody3D).freeze:
			var rb := b as RigidBody3D
			_hit[rb.get_instance_id()] = true
			rb.sleeping = false
			var out := Vector3(rb.global_position.x - _base.x, 0, rb.global_position.z - _base.z) * 0.6
			rb.linear_velocity = Vector3(rb.linear_velocity.x, 0, rb.linear_velocity.z) + out + Vector3.UP * LAUNCH * clampf(sqrt(60.0 / maxf(rb.mass, 1.0)), 0.25, 1.0)
			if rb.has_method("struck"):
				rb.struck(rb.global_position, Vector3.UP)
		if b.has_method("water_hit"):
			b.water_hit((b as Node3D).global_position, Vector3.DOWN, Vector3.UP, 200.0)
