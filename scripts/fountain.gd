class_name Fountain
extends Node3D
## A village fountain: a round stone basin holding several thousand litres, a central column and an upper
## bowl whose water spills over its lip in a falling curtain and is pumped back up (recirculated, so no
## water is created). It is a water source: drawing takes from the basin, wherever the crosshair is on it,
## and water dropped over it lands back in it.

const R_OUT := 2.4            # m: outside of the basin wall
const R_IN := 2.15            # m: water's edge
const WALL_H := 0.55
const FLOOR_Y := 0.08
const BOWL_R := 0.72
const BOWL_Y := 1.32          # m: lip of the upper bowl
const COL_R := 0.18
const SEGS := 64
const SPILL_V := 0.55         # m/s the curtain leaves the lip with, outward

var capacity := 0.0
var level := 0.0
var highlighted := false

var _pool: MeshInstance3D
var _pool_mesh := ArrayMesh.new()
var _rim_mat: StandardMaterial3D
var _rim: MeshInstance3D
var _curtain: MeshInstance3D
var _splash: GPUParticles3D
var _draw_at := Vector3.ZERO
var _built := -1.0
var _hl := 0.0

func _area() -> float:
	return PI * R_IN * R_IN - PI * COL_R * COL_R

func water_y() -> float:
	return FLOOR_Y + level / 1000.0 / _area()

func _ready() -> void:
	add_to_group("water_source")
	capacity = _area() * (WALL_H - 0.05 - FLOOR_Y) * 1000.0
	level = _area() * 0.36 * 1000.0         # 36 cm deep: about 5,200 L
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.86, 0.85, 0.82)
	stone.roughness = 0.95

	# basin: a wall ring with a floor
	var basin := CSGCylinder3D.new()
	basin.radius = R_OUT
	basin.height = WALL_H
	basin.sides = SEGS
	basin.position.y = WALL_H * 0.5
	basin.material = stone
	basin.use_collision = true
	var hollow := CSGCylinder3D.new()
	hollow.radius = R_IN
	hollow.height = WALL_H
	hollow.sides = SEGS
	hollow.position.y = FLOOR_Y
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	basin.add_child(hollow)
	add_child(basin)

	# column and upper bowl
	var col := CSGCylinder3D.new()
	col.radius = COL_R
	col.height = BOWL_Y
	col.sides = 24
	col.position.y = BOWL_Y * 0.5
	col.material = stone
	col.use_collision = true
	add_child(col)
	var bowl := CSGCylinder3D.new()
	bowl.radius = BOWL_R
	bowl.height = 0.2
	bowl.sides = 40
	bowl.cone = false
	bowl.position.y = BOWL_Y - 0.1
	bowl.material = stone
	bowl.use_collision = true
	var bh := CSGCylinder3D.new()
	bh.radius = BOWL_R - 0.07
	bh.height = 0.2
	bh.sides = 40
	bh.position.y = 0.06
	bh.operation = CSGShape3D.OPERATION_SUBTRACTION
	bowl.add_child(bh)
	add_child(bowl)
	var finial := CSGSphere3D.new()
	finial.radius = 0.12
	finial.position.y = BOWL_Y + 0.08
	finial.material = stone
	add_child(finial)

	var wm := _water_mat()
	wm.set_shader_parameter("ripple_strength", 0.3)
	wm.set_shader_parameter("tint_amount", 0.55)
	wm.set_shader_parameter("deep_color", Color(0.05, 0.2, 0.3))
	_pool = MeshInstance3D.new()
	_pool.mesh = _pool_mesh
	_pool.material_override = wm
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool.layers = 2
	add_child(_pool)

	# the bowl's water, level with its lip
	var bw := MeshInstance3D.new()
	bw.mesh = _disc(0.0, BOWL_R - 0.07, BOWL_Y - 0.015, 40, Color(0, 0, 0, 1))
	bw.material_override = _water_mat()
	bw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bw.layers = 2
	add_child(bw)

	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.0)
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim = MeshInstance3D.new()
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.layers = 2
	_rim.visible = false
	add_child(_rim)

	_curtain = MeshInstance3D.new()
	var cm := _water_mat()
	cm.set_shader_parameter("film", true)
	cm.set_shader_parameter("fall_speed", 18.0)
	cm.set_shader_parameter("tint_amount", 0.35)
	cm.set_shader_parameter("ripple_strength", 0.8)
	_curtain.material_override = cm
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_curtain.layers = 2
	add_child(_curtain)
	_make_splash()
	_rebuild()

func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("world_noise", true)
	return m

## A flat ring (r0 = 0 for a full disc) at height y, facing up. Godot front faces are clockwise.
func _disc(r0: float, r1: float, y: float, segs: int, col: Color) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for i in segs:
		var a := TAU * i / segs
		v.append(Vector3(cos(a) * r0, y, sin(a) * r0))
		v.append(Vector3(cos(a) * r1, y, sin(a) * r1))
		n.append_array([Vector3.UP, Vector3.UP])
		c.append_array([col, col])
	for i in segs:
		var j := (i + 1) % segs
		idx.append_array([2 * i, 2 * i + 1, 2 * j, 2 * j, 2 * i + 1, 2 * j + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## The curtain: water leaving the lip at SPILL_V outward and falling freely to the pool, so it curves out
## as it drops. It aerates (foams) and breaks up toward the bottom.
func _curtain_mesh(y_end: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var t_end := sqrt(2.0 * maxf(BOWL_Y - y_end, 0.01) / 9.8)
	var rings := 12
	for k in rings + 1:
		var t := t_end * float(k) / rings
		var r := BOWL_R + SPILL_V * t
		var y := BOWL_Y - 4.9 * t * t
		# surface normal: perpendicular to the path (dr, dy) = (SPILL_V, -9.8 t), pointing outward
		var dr := SPILL_V
		var dy := -9.8 * t
		var tn := Vector2(-dy, dr).normalized()   # (radial, vertical)
		var f := float(k) / rings
		var col := Color(0.15 + 0.5 * f * f, 0, 0, 0.85 - 0.35 * f)
		for i in SEGS + 1:
			var a := TAU * i / SEGS
			v.append(Vector3(cos(a) * r, y, sin(a) * r))
			n.append(Vector3(cos(a) * tn.x, tn.y, sin(a) * tn.x))
			c.append(col)
	for k in rings:
		for i in SEGS:
			var t0 := k * (SEGS + 1) + i
			var b0 := t0 + SEGS + 1
			idx.append_array([t0, b0, t0 + 1, t0 + 1, b0, b0 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _landing_r(y: float) -> float:
	return BOWL_R + SPILL_V * sqrt(2.0 * maxf(BOWL_Y - y, 0.01) / 9.8)

func _make_splash() -> void:
	_splash = GPUParticles3D.new()
	_splash.amount = 160
	_splash.lifetime = 0.45
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.0
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	_splash.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.014
	sm.height = 0.035
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.75, 0.9, 1.0, 0.7)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 0.05
	sm.material = dm
	_splash.draw_pass_1 = sm
	_splash.layers = 2
	add_child(_splash)

func _rebuild() -> void:
	_built = level
	var y := water_y()
	_pool_mesh.clear_surfaces()
	var d := _disc(COL_R, R_IN, y, SEGS, Color(0, 0, 0, 1))
	_pool_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d.surface_get_arrays(0))
	_rim.mesh = _disc(R_IN - 0.08, R_IN - 0.02, y + 0.004, SEGS, Color(1, 1, 1, 1))
	_curtain.mesh = _curtain_mesh(y)
	var lr := _landing_r(y)
	var pm: ParticleProcessMaterial = _splash.process_material
	pm.emission_ring_radius = lr + 0.03
	pm.emission_ring_inner_radius = lr - 0.03
	_splash.position.y = y

func _process(dt: float) -> void:
	if absf(level - _built) > 2.0:
		_rebuild()
	_hl = move_toward(_hl, 1.0 if highlighted else 0.0, dt * 5.0)
	_rim.visible = _hl > 0.01
	_rim_mat.albedo_color.a = _hl * (0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.004))

# ---------------------------------------------------------------- water source

func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	var c := global_position + Vector3(0, water_y(), 0)
	return WaterSource.ray_disc(o, d, c, R_IN)

func aim_hit(p: Vector3) -> bool:
	var l := p - global_position
	return Vector2(l.x, l.z).length() < R_OUT + 0.2 and l.y < WALL_H + 0.3

func near_point(p: Vector3) -> Vector3:
	var h := Vector3(p.x - global_position.x, 0, p.z - global_position.z).limit_length(R_IN)
	return global_position + h + Vector3(0, water_y(), 0)

## Drawing rises from the part of the pool the crosshair was on, kept clear of the wall and the curtain.
func set_draw_point(p: Vector3) -> void:
	var h := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	var r := clampf(h.length(), _landing_r(water_y()) + 0.25, R_IN - 0.25)
	_draw_at = (h.normalized() if h.length() > 0.01 else Vector3.FORWARD) * r

func surface_point() -> Vector3:
	return global_position + _draw_at + Vector3(0, water_y(), 0)

## Where the crosshair line crosses the pool's surface, if it does; otherwise null.
func surface_hit(o: Vector3, d: Vector3):
	if d.y > -0.01:
		return null
	var y := global_position.y + water_y()
	var t := (y - o.y) / d.y
	if t <= 0.0:
		return null
	var p := o + d * t
	var r := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return p if r < R_IN - 0.05 and r > COL_R + 0.05 else null

## True when water landing at p falls into the basin.
func catches(p: Vector3) -> bool:
	var l := p - global_position
	return Vector2(l.x, l.z).length() < R_IN and l.y < WALL_H + 0.05

func take(litres: float) -> float:
	var t := minf(litres, level)
	level -= t
	return t

func give(litres: float) -> void:
	level += litres
	if level > capacity:
		# brim-full: the excess spills over the wall onto the ground beside it
		var over := level - capacity
		level = capacity
		var p := global_position + Vector3(R_OUT + 0.4, 0.0, 0.0)
		Puddle.add_at(p, over, get_tree(), get_parent())
