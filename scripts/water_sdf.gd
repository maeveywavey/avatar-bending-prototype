class_name WaterSDF
extends MeshInstance3D
## Draws a body of water as one implicit surface (shaders/water_sdf.gdshader). Each frame its owner calls
## clear(), adds pieces (seg, sphere, chain), then commit(). A piece is a round cone: a sphere of radius ra
## at a and one of radius rb at b, joined by a cone; optionally flattened along an axis. The shader joins
## all pieces with a smooth minimum (blend), so they read as one continuous body of water.
## The node is a box round the pieces; it is drawn only where the ray-marched surface is.

const MAX := 64                  # match the shader's arrays

var count := 0
var _sa := PackedVector4Array()
var _sb := PackedVector4Array()
var _sc := PackedVector4Array()
var _lo := Vector3.ZERO
var _hi := Vector3.ZERO
var _mat: ShaderMaterial

static var _box: BoxMesh

func _init() -> void:
	_sa.resize(MAX)
	_sb.resize(MAX)
	_sc.resize(MAX)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/water_sdf.gdshader")
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	mesh = _box
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = 2                   # never marked by wet patches
	top_level = true
	visible = false

func clear() -> void:
	count = 0

## One piece. flat_axis (unit) and flat (0..1) squash it along that axis: 1 is round.
func seg(a: Vector3, ra: float, b: Vector3, rb: float, flat_axis := Vector3.UP, flat := 1.0) -> void:
	if count >= MAX or maxf(ra, rb) < 0.002:
		return
	_sa[count] = Vector4(a.x, a.y, a.z, ra)
	_sb[count] = Vector4(b.x, b.y, b.z, rb)
	_sc[count] = Vector4(flat_axis.x, flat_axis.y, flat_axis.z, flat)
	var r := maxf(ra, rb)
	var lo := a.min(b) - Vector3.ONE * r
	var hi := a.max(b) + Vector3.ONE * r
	if count == 0:
		_lo = lo
		_hi = hi
	else:
		_lo = _lo.min(lo)
		_hi = _hi.max(hi)
	count += 1

func sphere(c: Vector3, r: float, flat_axis := Vector3.UP, flat := 1.0) -> void:
	seg(c, r, c, r, flat_axis, flat)

## A chain of pieces through the points, with a radius at each.
func chain(p: PackedVector3Array, r: PackedFloat32Array) -> void:
	for i in p.size() - 1:
		seg(p[i], r[i], p[i + 1], r[i + 1])

func room() -> int:
	return MAX - count

## Sends the pieces to the shader. blend: how wide joins round over (m). origin: the point waves and
## ripples are fixed to. floor_y: the surface of a stream the water stands in (it is not drawn under it).
func commit(blend: float, origin: Vector3, wave_amp := 0.004, floor_y := -100000.0) -> void:
	if count == 0:
		visible = false
		return
	var pad := Vector3.ONE * (blend * 0.5 + wave_amp * 2.0 + 0.03)
	var lo := _lo - pad
	var hi := _hi + pad
	if floor_y > -1000.0:
		lo.y = maxf(lo.y, floor_y - 0.05)
		if hi.y <= lo.y:
			visible = false
			return
	global_transform = Transform3D(Basis.from_scale(hi - lo), (lo + hi) * 0.5)
	_mat.set_shader_parameter("seg_a", _sa)
	_mat.set_shader_parameter("seg_b", _sb)
	_mat.set_shader_parameter("seg_c", _sc)
	_mat.set_shader_parameter("seg_count", count)
	_mat.set_shader_parameter("blend_k", blend)
	_mat.set_shader_parameter("box_min", lo)
	_mat.set_shader_parameter("box_max", hi)
	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("wave_amp", wave_amp)
	_mat.set_shader_parameter("floor_y", floor_y)

## Any of the shader's look settings: absorb, tint_amount, refraction_strength, ripple_strength,
## ripple_scale, drift, foam, shallow_color, deep_color.
func look(param: String, v) -> void:
	_mat.set_shader_parameter(param, v)

## The pieces' bounds, without padding.
func bounds() -> AABB:
	return AABB(_lo, _hi - _lo)
