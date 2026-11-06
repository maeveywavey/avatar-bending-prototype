class_name WaterSource
extends Node3D
## A barrel of water. The water level is a reserve in litres that the bender can draw from and return to.

const RADIUS := 0.30
const HEIGHT := 0.90

var capacity := 230.0
var level := 230.0
var highlighted := false

var _shell_mat: StandardMaterial3D
var _water: MeshInstance3D
var _outline: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _shell_alpha := 1.0
var _hl := 0.0

func _ready() -> void:
	add_to_group("water_source")
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS + 0.02
	cyl.height = HEIGHT
	cs.shape = cyl
	cs.position.y = HEIGHT * 0.5
	body.add_child(cs)
	add_child(body)

	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.93, 0.92, 0.90)
	_shell_mat.roughness = 0.9
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := CSGCylinder3D.new()
	shell.radius = RADIUS + 0.03
	shell.height = HEIGHT
	shell.sides = 32
	shell.position.y = HEIGHT * 0.5
	shell.material = _shell_mat
	var hollow := CSGCylinder3D.new()
	hollow.radius = RADIUS
	hollow.height = HEIGHT
	hollow.sides = 32
	hollow.position.y = 0.04 + HEIGHT * 0.5
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	shell.add_child(hollow)
	add_child(shell)

	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("world_noise", true)
	wm.set_shader_parameter("ripple_strength", 0.35)
	wm.set_shader_parameter("tint_amount", 0.7)
	_water = MeshInstance3D.new()
	var wmesh := CylinderMesh.new()
	wmesh.top_radius = RADIUS - 0.005
	wmesh.bottom_radius = RADIUS - 0.005
	wmesh.height = 1.0
	wmesh.radial_segments = 32
	wmesh.rings = 1
	_water.mesh = wmesh
	_water.material_override = wm
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)

	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.9)
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.no_depth_test = false
	_outline = MeshInstance3D.new()
	var om := CylinderMesh.new()
	om.top_radius = RADIUS + 0.075
	om.bottom_radius = RADIUS + 0.075
	om.height = HEIGHT + 0.1
	om.radial_segments = 32
	_outline.mesh = om
	_outline.material_override = _outline_mat
	_outline.position.y = HEIGHT * 0.5
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.visible = false
	add_child(_outline)
	_update_water()

func _process(dt: float) -> void:
	var target := 1.0 if highlighted else 0.0
	_hl = move_toward(_hl, target, dt * 5.0)
	_outline.visible = _hl > 0.01
	_outline_mat.albedo_color.a = _hl * (0.65 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
	var ta := lerpf(1.0, 0.5, _hl)
	_shell_alpha = ta
	_shell_mat.albedo_color.a = ta
	_update_water()

func _update_water() -> void:
	var h := maxf(level / capacity * (HEIGHT - 0.1), 0.001)
	_water.visible = level > 0.5
	_water.scale = Vector3(1, h, 1)
	_water.position.y = 0.04 + h * 0.5

## True when the crosshair point p is on this barrel.
func aim_hit(p: Vector3) -> bool:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d < RADIUS + 0.3 and p.y < global_position.y + HEIGHT + 0.3

## How far the crosshair line (from o along unit d) passes from the barrel: x = miss in metres,
## y = distance along the line.
func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	var a := global_position + Vector3(0, 0.1, 0)
	var r := ray_seg(o, d, a, a + Vector3(0, HEIGHT, 0))
	return Vector2(maxf(r.x - RADIUS, 0.0), r.y)

## Closest approach of the line o + d*t (t >= 0, d unit) to the segment a..b: x = gap, y = t.
static func ray_seg(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var u := b - a
	var w := o - a
	var bb := d.dot(u)
	var c := u.dot(u)
	var dd := d.dot(w)
	var e := u.dot(w)
	var den := c - bb * bb
	var s := clampf((e - bb * dd) / den, 0.0, 1.0) if den > 1e-6 else 0.0
	var t := maxf(bb * s - dd, 0.0)
	s = clampf((e + bb * t) / c, 0.0, 1.0) if c > 1e-9 else 0.0
	return Vector2((o + d * t).distance_to(a + u * s), t)

## Closest approach of the line o + d*t to a horizontal disc (centre c, radius r): x = gap, y = t.
static func ray_disc(o: Vector3, d: Vector3, c: Vector3, r: float) -> Vector2:
	var q := c
	if d.y < -0.01:
		q = o + d * ((c.y - o.y) / d.y)
	for k in 3:
		var h := Vector3(q.x - c.x, 0, q.z - c.z).limit_length(r)
		q = c + h
		var t := maxf((q - o).dot(d), 0.0)
		q = o + d * t
	var h2 := Vector3(q.x - c.x, 0, q.z - c.z).limit_length(r)
	var on := c + h2
	var t2 := maxf((on - o).dot(d), 0.0)
	return Vector2((o + d * t2).distance_to(on), t2)

## Point of the source nearest to p (for the draw range).
func near_point(p: Vector3) -> Vector3:
	var h := Vector3(p.x - global_position.x, 0, p.z - global_position.z).limit_length(RADIUS)
	return global_position + h + Vector3(0, clampf(p.y - global_position.y, 0.0, HEIGHT), 0)

## World position of the water surface centre.
func surface_point() -> Vector3:
	return global_position + Vector3(0, 0.04 + maxf(level / capacity * (HEIGHT - 0.1), 0.0), 0)

func take(litres: float) -> float:
	var t := minf(litres, level)
	level -= t
	return t

func give(litres: float) -> void:
	level = minf(level + litres, capacity)
