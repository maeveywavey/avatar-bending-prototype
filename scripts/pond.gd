class_name Pond
extends Node3D
## The stream behind the houses on the left: a still channel about 29 m across and DEPTH deep in the
## middle, running the length of the ground (Z0 to Z1) with gently winding banks (centre_x, half_w). The
## class is still called Pond (the first version was a round pond). For the bender it is an effectively
## endless source: drawing from it, or freezing its surface, never lowers it measurably (level is a large
## constant). The world cuts its outline out of the ground (outline()) and the bed sits in the cut.
## Loose bodies (group "crate": crates, dummies, the boat, cut pieces) float in it (_buoyancy).

const DEPTH := 1.3
const WATER_Y := -0.2
const Z0 := -81.0
const Z1 := 81.0
const ROW := 2.0                # m between rows of the bed along the stream
const COLS := 16                # across the bed, bank to bank
const RHO_G := 1000.0 * 9.8     # N per m³ of water displaced
const SURF_CELL := 0.3          # m: the surface grid (fine enough for the parted trench's walls)
const SURF_CHUNK := 20.0        # m of stream per surface mesh
# parting (R2 + L2): match part_h in water.gdshader. Its shape is a superellipse, between a long ellipse
# and a rectangle (owner, 2026-11-06: half the earlier 14 m length, a little wider, rounder round the
# bender): from about 1.2 m behind the bender to 5.8 m ahead. Its walls round up into the water pushed
# aside, so the far end cups back up to the normal height. Its numbers are k("name"), editable in
# Options > Visual > Edit Water Shapes (Parting).
const PART_TURN := 5.0          # 1/s it turns after the aim
const PART_OPEN_T := 0.8        # s to open
const PART_CLOSE_T := 0.6       # s to close
var level := 1.0e9             # litres, for the bender's purposes endless
var capacity := 1.0e9
var highlighted := false

var _draw_at := Vector3.ZERO
var _rim_mat: StandardMaterial3D
var _rim: MeshInstance3D
var _hl := 0.0
var _float_cache := {}          # body id -> [time, aabb]
var surface_z0 := Z0            # the surface is built from here
var part_a := Vector3.ZERO
var part_dir := Vector2(0, 1)
var part_open := 0.0
var _part_hold := false
var _wmat: ShaderMaterial

## Middle of the channel at z (world; the node sits at the origin).
static func centre_x(z: float) -> float:
	return -35.0 + 2.5 * sin(0.06 * z) + 1.0 * sin(0.17 * z + 1.0)

## Half the width, bank to bank at ground level.
static func half_w(z: float) -> float:
	return 14.0 + 0.8 * sin(0.11 * z + 2.0)

## The near (east) bank at z: where the ground ends.
static func near_bank_x(z: float) -> float:
	return centre_x(z) + half_w(z)

static func _depth(f: float) -> float:
	return -DEPTH * (1.0 - f * f)

## Where the water meets the bank, as a fraction of the half width.
static func shore_f() -> float:
	return sqrt(1.0 + WATER_Y / DEPTH)

## The hole in the ground, as (x, z) points.
func outline() -> PackedVector2Array:
	var o := PackedVector2Array()
	var n := int((Z1 - Z0) / ROW)
	for i in n + 1:
		var z := Z0 + i * ROW
		o.append(Vector2(centre_x(z) + half_w(z), z))
	for i in range(n, -1, -1):
		var z := Z0 + i * ROW
		o.append(Vector2(centre_x(z) - half_w(z), z))
	return o

func _ready() -> void:
	add_to_group("water_source")
	var n := int((Z1 - Z0) / ROW)
	# the bed: from a lip just under the ground on each side, down to the middle
	var fs := []
	fs.append(-1.06)
	for k in COLS + 1:
		fs.append(lerpf(-1.0, 1.0, float(k) / COLS))
	fs.append(1.06)
	var grid := []
	for i in n + 1:
		var z := Z0 + i * ROW
		var row := []
		for f in fs:
			var y := -0.02 if absf(f) > 1.0 else _depth(f)
			row.append(Vector3(centre_x(z) + half_w(z) * f, y, z))
		grid.append(row)
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	for i in n:
		for k in fs.size() - 1:
			_tri(v, nm, grid[i][k], grid[i][k + 1], grid[i + 1][k + 1])
			_tri(v, nm, grid[i][k], grid[i + 1][k + 1], grid[i + 1][k])
	var bed := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(v)
	cs.shape = sh
	bed.add_child(cs)
	bed.add_child(_mesh_of(v, nm, Color(0.42, 0.40, 0.33)))
	add_child(bed)

	# the surface, reaching just under the banks: a fine grid, so parting can shape it
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("world_noise", true)
	wm.set_shader_parameter("ripple_strength", 0.14)
	wm.set_shader_parameter("tint_amount", 0.72)
	wm.set_shader_parameter("deep_color", Color(0.02, 0.1, 0.16))
	wm.set_shader_parameter("refraction_strength", 0.03)
	wm.set_shader_parameter("parting", true)
	_wmat = wm
	var sf := shore_f() + 0.025
	var zc := surface_z0
	while zc < Z1 - 0.01:
		var z1 := minf(zc + SURF_CHUNK, Z1)
		var rows := ceili((z1 - zc) / SURF_CELL)
		var cols := ceili(2.0 * 15.0 * sf / SURF_CELL)
		var sg := []
		for i in rows + 1:
			var zz := lerpf(zc, z1, float(i) / rows)
			var row := []
			for k in cols + 1:
				row.append(Vector3(centre_x(zz) + half_w(zz) * sf * lerpf(-1.0, 1.0, float(k) / cols), WATER_Y, zz))
			sg.append(row)
		var wv := PackedVector3Array()
		var wn := PackedVector3Array()
		for i in rows:
			for k in cols:
				_tri(wv, wn, sg[i][k], sg[i][k + 1], sg[i + 1][k + 1])
				_tri(wv, wn, sg[i][k], sg[i + 1][k + 1], sg[i + 1][k])
		var warr := []
		warr.resize(Mesh.ARRAY_MAX)
		warr[Mesh.ARRAY_VERTEX] = wv
		warr[Mesh.ARRAY_NORMAL] = wn
		warr[Mesh.ARRAY_COLOR] = _black(wv.size())
		var wmesh := ArrayMesh.new()
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wmesh
		wmi.material_override = wm
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wmi.layers = 2
		wmi.extra_cull_margin = 3.0
		add_child(wmi)
		zc = z1

	# highlight: a glowing band just inside each shore
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.0)
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	for side in [-1.0, 1.0]:
		for i in n:
			var za := Z0 + i * ROW
			var zb := za + ROW
			var q := []
			for e in [[za, 0.93], [zb, 0.93], [zb, 0.97], [za, 0.97]]:
				var z: float = e[0]
				q.append(Vector3(centre_x(z) + side * half_w(z) * shore_f() * e[1], WATER_Y + 0.01, z))
			_tri(rv, rn, q[0], q[1], q[2])
			_tri(rv, rn, q[0], q[2], q[3])
	var ra := []
	ra.resize(Mesh.ARRAY_MAX)
	ra[Mesh.ARRAY_VERTEX] = rv
	ra[Mesh.ARRAY_NORMAL] = rn
	var rmesh := ArrayMesh.new()
	rmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
	_rim = MeshInstance3D.new()
	_rim.mesh = rmesh
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.layers = 2
	_rim.visible = false
	add_child(_rim)

func _mesh_of(v: PackedVector3Array, nm: PackedVector3Array, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	mi.material_override = mat
	return mi

func _black(n: int) -> PackedColorArray:
	var c := PackedColorArray()
	c.resize(n)
	c.fill(Color(0, 0, 0, 1))
	return c

## An upward-facing triangle (Godot front faces are clockwise from above).
func _tri(v: PackedVector3Array, nm: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.y > 0.0:
		var t := b
		b = c
		c = t
		fn = -fn
	var n := -fn.normalized()
	v.append_array([a, b, c])
	nm.append_array([n, n, n])

func _process(dt: float) -> void:
	_step_parting(dt)
	_hl = move_toward(_hl, 1.0 if highlighted else 0.0, dt * 5.0)
	_rim.visible = _hl > 0.01
	_rim_mat.albedo_color.a = _hl * (0.5 + 0.25 * sin(Time.get_ticks_msec() * 0.004))

# ---------------------------------------------------------------- parting

## R2 + L2 held: the water parts ahead of a (the bender), along dir (the aim, horizontal). Called every
## frame it is held, with where the bender is and aims now: it goes with them, turning after the aim, so
## they can walk the bed dry. When no longer called, it closes where it is.
func hold_part(a: Vector3, dir: Vector3) -> void:
	var d := Vector2(dir.x, dir.z)
	if d.length() > 0.01:
		d = d.normalized()
		if part_open < 0.02:
			part_dir = d
		else:
			var t := clampf(get_process_delta_time() * PART_TURN, 0.0, 1.0)
			part_dir = part_dir.slerp(d, t).normalized() if part_dir.dot(d) > -0.99 else d
	part_a = a
	_part_hold = true

func _step_parting(dt: float) -> void:
	var held := _part_hold
	_part_hold = false
	part_open = move_toward(part_open, 1.0 if held else 0.0, dt / (PART_OPEN_T if held else PART_CLOSE_T))
	for n in ["c", "ra", "rb", "n_near", "n_far", "wall", "drop", "ridge"]:
		_wmat.set_shader_parameter("part_" + n, k(n))
	_wmat.set_shader_parameter("part_a", part_a)
	_wmat.set_shader_parameter("part_dir", part_dir)
	_wmat.set_shader_parameter("part_open", part_open)

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## The water's surface height at (x, z), parting included (water.gdshader's part_h).
func surface_y(x: float, z: float) -> float:
	var y := water_y()
	if part_open <= 0.001:
		return y
	return y + part_open * part_shape(x - part_a.x, z - part_a.z, part_dir)

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("parting", n)

## The parting's surface offset at d (from the bender's feet, flat) when fully open: down in the trench,
## up in the ridges beside it. Superellipse: exponent 2 is an ellipse, higher is squarer; the end round
## the bender (behind the centre) has its own, rounder exponent.
static func part_shape(dx: float, dz: float, dir: Vector2) -> float:
	var d := Vector2(dx, dz)
	var a := d.dot(dir) - k("c")
	var c := d.dot(Vector2(-dir.y, dir.x))
	var n := k("n_near") if a < 0.0 else k("n_far")
	var r := pow(pow(absf(a) / k("ra"), n) + pow(absf(c) / k("rb"), n), 1.0 / n)
	var w := _smooth(1.0, 1.0 + k("wall"), r)
	var ridge := w * exp(-maxf(r - 1.0 - k("wall"), 0.0) * k("rb") / 1.8)
	return -k("drop") * (1.0 - w) + k("ridge") * ridge

# ---------------------------------------------------------------- floating

## Loose bodies in the water are held up by the water they displace: four columns under the corners of
## the body's box, each pushing up by the share of it under the surface, with drag where it is wet. A
## body's displaced volume is its meta "disp_vol" when set (an open hull displaces more than its wood),
## else its parts' volume, else most of its box.
func _physics_process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	for b in get_tree().get_nodes_in_group("crate"):
		if not b is RigidBody3D:
			continue
		var rb := b as RigidBody3D
		if not _inside(rb.global_position, 1.05) or rb.global_position.y > WATER_Y + 3.0:
			continue
		var id := rb.get_instance_id()
		var c: Array = _float_cache.get(id, [])
		if c.is_empty() or now - int(c[0]) > 500:
			c = [now, _local_aabb(rb), _disp(rb)]
			_float_cache[id] = c
		var bb: AABB = c[1]
		var vol: float = c[2]
		if bb.size.y <= 0.0:
			continue
		var wy := surface_y(rb.global_position.x, rb.global_position.z)
		var wet := 0.0
		for corner in [Vector3(bb.position.x, bb.position.y, bb.position.z), Vector3(bb.end.x, bb.position.y, bb.position.z),
				Vector3(bb.position.x, bb.position.y, bb.end.z), Vector3(bb.end.x, bb.position.y, bb.end.z)]:
			var wp: Vector3 = rb.global_transform * corner
			var sub := clampf((wy - wp.y) / bb.size.y, 0.0, 1.0)
			if sub <= 0.0:
				continue
			wet += sub * 0.25
			var off := wp - rb.global_position
			var pv := rb.linear_velocity + rb.angular_velocity.cross(off)
			var f := Vector3.UP * RHO_G * vol * 0.25 * sub - pv * rb.mass * 0.6 * sub
			rb.apply_force(f, off)
		if wet > 0.0:
			rb.sleeping = false

func _local_aabb(rb: RigidBody3D) -> AABB:
	var out := AABB()
	var first := true
	for ch in rb.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
			var cs := ch as CollisionShape3D
			var a := cs.transform * cs.shape.get_debug_mesh().get_aabb()
			out = a if first else out.merge(a)
			first = false
	return out

func _disp(rb: RigidBody3D) -> float:
	if rb.has_meta("disp_vol"):
		return float(rb.get_meta("disp_vol"))
	if rb.has_meta("parts"):
		return Slicer._total_volume(rb.get_meta("parts"))
	var a := _local_aabb(rb)
	return a.size.x * a.size.y * a.size.z * 0.8

# ---------------------------------------------------------------- water source

func _inside(p: Vector3, f: float) -> bool:
	if p.z < Z0 or p.z > Z1:
		return false
	return absf(p.x - centre_x(p.z)) < half_w(p.z) * f

func water_y() -> float:
	return global_position.y + WATER_Y

## How far the crosshair line misses the water (m, beside the water where it crosses the surface) and how
## far along the line that is.
func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	if d.y > -0.01:
		return Vector2(INF, INF)
	var t := (water_y() - o.y) / d.y
	if t <= 0.0:
		return Vector2(INF, INF)
	var p := o + d * t
	var zc := clampf(p.z, Z0, Z1)
	var out := maxf(absf(p.x - centre_x(zc)) - half_w(zc) * shore_f() * 0.92, 0.0)
	out = maxf(out, absf(p.z - zc))
	return Vector2(out, t)

func aim_hit(p: Vector3) -> bool:
	return _inside(p, 1.05) and p.y < 0.3

func near_point(p: Vector3) -> Vector3:
	var z := clampf(p.z, Z0 + 1.0, Z1 - 1.0)
	var c := centre_x(z)
	var w := half_w(z) * shore_f() * 0.95
	return Vector3(clampf(p.x, c - w, c + w), water_y(), z)

## Where the crosshair line crosses the water surface, if it does over the stream; otherwise null.
func surface_hit(o: Vector3, d: Vector3):
	if d.y > -0.01:
		return null
	var t := (water_y() - o.y) / d.y
	if t <= 0.0:
		return null
	var p := o + d * t
	return p if _inside(p, shore_f() * 0.97) else null

func set_draw_point(p: Vector3) -> void:
	var q := near_point(p)
	var c := centre_x(q.z)
	var w := half_w(q.z) * shore_f() * 0.85
	_draw_at = Vector3(clampf(q.x, c - w, c + w), 0.0, q.z)

func surface_point() -> Vector3:
	return _draw_at + Vector3(0, water_y(), 0)

func catches(p: Vector3) -> bool:
	return _inside(p, shore_f()) and p.y < global_position.y + 0.05

func take(l: float) -> float:
	return l

func give(_l: float) -> void:
	pass
