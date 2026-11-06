class_name WaterBlade
extends Node3D
## Slice: a thin crescent of water thrown edge-first. It spends itself on the first thing it meets: a
## sliceable body is cut along the blade's plane (Slicer; a person, only the part it meets first, as an
## arm), another loose body is shoved, a fixed surface stops it. Its water comes down there, as a puddle.

const SPEED := 30.0
const RANGE := 20.0
const SEGS := 24
const SIDES := 10
# a 12 L blade: 2.4 m tip to tip, 5 cm thick across its plane, 19 cm deep along its flight. Smaller
# blades scale by the cube root of their volume. Its cross-section is an ellipse tapering to the tips:
# volume = WIDTH * pi * a * b * 2/3, which these sizes make 12 L.
const REF_L := 12.0
const REF_WIDTH := 2.4
const REF_A := 0.025            # half-thickness across the plane
const REF_B := 0.095            # half-depth along the flight

var litres := 0.0
var _w := REF_WIDTH
var _a := REF_A
var _b := REF_B
var _c := Vector3.ZERO
var _d := Vector3.FORWARD
var _side := Vector3.RIGHT
var _nb := Vector3.UP           # normal of the blade's plane
var _travel := 0.0
var _cut := {}                  # bodies already cut (instance ids)
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _box := BoxShape3D.new()
var _done := false
var _owner_rid: RID

func begin(o: Vector3, d: Vector3, side: Vector3, l: float, bender: CollisionObject3D) -> void:
	_c = o
	_d = d.normalized()
	_side = (side - _d * side.dot(_d)).normalized()
	_nb = _d.cross(_side).normalized()
	litres = l
	var k := pow(maxf(l, 0.1) / REF_L, 1.0 / 3.0)
	_w = REF_WIDTH * k
	_a = REF_A * k
	_b = REF_B * k
	_owner_rid = bender.get_rid()

func _ready() -> void:
	top_level = true
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("flow_speed", 6.0)
	m.set_shader_parameter("tint_amount", 0.45)
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = m
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = 2
	_mi.extra_cull_margin = 2.0
	add_child(_mi)

func _process(dt: float) -> void:
	if _done:
		return
	var step := _d * SPEED * dt
	var space := get_world_3d().direct_space_state
	# a fixed surface in the way (along the blade's middle) stops it
	var q := PhysicsRayQueryParameters3D.create(_c, _c + step)
	# people are cut through, not stopped at
	var ex: Array[RID] = [_owner_rid]
	for pn in get_tree().get_nodes_in_group("person"):
		ex.append((pn as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	var stop_at := 1.0
	if not hit.is_empty() and not hit["collider"] is RigidBody3D:
		stop_at = _c.distance_to(hit["position"]) / maxf(step.length(), 0.0001)
	# everything loose the blade sweeps through this step
	var sweep := step * stop_at
	_box.size = Vector3(_w, _a * 2.0, sweep.length() + 0.1)
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = _box
	sq.exclude = [_owner_rid]
	sq.transform = Transform3D(Basis(_side, _nb, -_d), _c + sweep * 0.5)
	# what the blade meets first along its flight
	var met := []
	for r in space.intersect_shape(sq, 12):
		var b: Object = r["collider"]
		if b == null or _cut.has(b.get_instance_id()):
			continue
		if not (b.has_method("slice_by") or b is RigidBody3D):
			continue
		met.append([_first_along(b as Node3D), b])
	if not met.is_empty():
		met.sort_custom(func(x, y): return x[0] < y[0])
		var b: Object = met[0][1]
		var at := _c + _d * clampf(float(met[0][0]) - _d.dot(_c), 0.0, sweep.length())
		_cut[b.get_instance_id()] = true
		if b.has_method("slice_by"):
			# a person (or a body cut from one): the blade's plane through the part of them it meets first
			b.slice_by(at, _nb, _side, _w, _d)
		else:
			var rb := b as RigidBody3D
			var stuff: String = rb.get_meta("stuff", "")
			var piece := Slicer.cut(rb, at, _nb)
			if piece != null:
				Wetness.mark(rb.global_position, _nb, 0.5, rb)
				if stuff == "straw":
					Dummy.straw(at, _d, get_parent(), 50)
			else:
				rb.apply_central_impulse(_d * clampf(litres * 1.5, 2.0, 30.0))
			if rb.has_method("struck"):
				rb.struck(_c, _d)
			if rb.has_method("water_hit") and piece == null:
				rb.water_hit(at, -_d, _d, litres)
		_finish(at)
		return
	_c += sweep
	_travel += sweep.length()
	if stop_at < 1.0:
		if (hit["collider"] as Object).has_method("water_hit"):
			hit["collider"].water_hit(hit["position"], hit["normal"], _d, litres)
		Wetness.mark(hit["position"], hit["normal"], 0.7, hit["collider"])
		_finish(hit["position"] + (hit["normal"] as Vector3) * 0.05)
		return
	if _travel > RANGE:
		_finish(_c)
		return
	_build()

## How far along the flight (as d·p) the blade first meets body b: the nearest of its collision shapes'
## surface points toward the blade, found by a ray along the blade's middle, else its middle.
func _first_along(b: Node3D) -> float:
	var q := PhysicsRayQueryParameters3D.create(_c - _d * 0.3, _c + _d * (SPEED * 0.05 + 0.5))
	q.exclude = [_owner_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] == b:
		return _d.dot(hit["position"])
	return _d.dot(b.global_position)

## The blade's water falls apart and lands below where it stopped.
func _finish(p: Vector3) -> void:
	_done = true
	_mi.visible = false
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.1, p + Vector3.DOWN * 30.0)
	q.exclude = [_owner_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and litres > 0.0:
		var gp: Vector3 = hit["position"]
		if hit["collider"] is RigidBody3D:
			gp.y = 0.0
		Puddle.add_at(gp, litres, get_tree(), get_parent())
	litres = 0.0
	queue_free()

func _build() -> void:
	var P := PackedVector3Array()
	for i in SEGS + 1:
		var u := lerpf(-1.0, 1.0, float(i) / SEGS)
		P.append(_c + _side * (u * _w * 0.5) - _d * (u * u * _w * 0.25))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in SEGS + 1:
		var u := lerpf(-1.0, 1.0, float(j) / SEGS)
		var t := (P[mini(j + 1, SEGS)] - P[maxi(j - 1, 0)]).normalized()
		var a := _nb
		var b := t.cross(a)
		var taper := sqrt(maxf(1.0 - u * u, 0.0))
		for k in SIDES + 1:
			var th := TAU * float(k) / SIDES
			# thin across the blade's plane, deeper along its flight; the leading edge is sharp
			var dv := a * cos(th) * _a * taper + b * sin(th) * _b * taper
			verts.append(P[j] + dv)
			norms.append((a * cos(th) * _b + b * sin(th) * _a).normalized())
			uvs.append(Vector2(float(j) / SEGS * _w + _travel, th))
			cols.append(Color(0.3, 0, 0, 1))
	for j in SEGS:
		for k in SIDES:
			var i0 := j * (SIDES + 1) + k
			var i1 := i0 + SIDES + 1
			idx.append_array([i0, i0 + 1, i1, i0 + 1, i1 + 1, i1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
