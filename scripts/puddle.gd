class_name Puddle
extends Node3D
## Water lying on the ground after the bender lets it go. It keeps its litres as a thin sheet whose area
## follows its volume, so drawing from it shrinks it and more water landing on it widens it. It is a
## water source like a barrel: it can be aimed at and drawn from again.
## (Soaking into the ground over time is planned, not built.)

const THICK := 0.015          # m: depth of the sheet; 68 L (one full draw) covers about 1.2 m radius
const SEGS := 56
const MIN_LITRES := 0.3

var level := 0.0
var capacity := 1.0e9
var highlighted := false

var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _rim: MeshInstance3D
var _rim_mesh := ArrayMesh.new()
var _rim_mat: StandardMaterial3D
var _edge := PackedFloat32Array()   # ragged edge: radius factor per segment
var _built := -1.0
var _hl := 0.0

## Adds water landing at p (on the ground) to the puddle there, or starts a new one.
static func add_at(p: Vector3, litres: float, tree: SceneTree, parent: Node) -> Puddle:
	if litres <= 0.0:
		return null
	for s in tree.get_nodes_in_group("water_source"):
		# water falling into a basin joins it
		if s.has_method("catches") and s.catches(p):
			s.give(litres)
			return null
	for s in tree.get_nodes_in_group("water_source"):
		if s is Puddle and not s.is_queued_for_deletion():
			var pd: Puddle = s
			var d := Vector2(pd.global_position.x - p.x, pd.global_position.z - p.z).length()
			if d < pd.radius() + 0.6 and absf(pd.global_position.y - p.y) < 0.3:
				pd.absorb(p, litres)
				return pd
	var np := Puddle.new()
	parent.add_child(np)
	np.global_position = p
	np.level = litres
	return np

func _ready() -> void:
	add_to_group("water_source")
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.9
	for i in SEGS:
		var a := TAU * i / SEGS
		_edge.append(1.0 + 0.22 * noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0))
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("world_noise", true)
	# a centimetre or two of water: mostly the wet ground seen through it, with the sky on its surface
	wm.set_shader_parameter("ripple_strength", 0.12)
	wm.set_shader_parameter("tint_amount", 0.14)
	wm.set_shader_parameter("deep_color", Color(0.2, 0.32, 0.38))
	wm.set_shader_parameter("refraction_strength", 0.02)
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = wm
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = 2
	add_child(_mi)
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.0)
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim = MeshInstance3D.new()
	_rim.mesh = _rim_mesh
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.layers = 2
	add_child(_rim)
	_rebuild()

func radius() -> float:
	return sqrt(maxf(level, 0.0) / 1000.0 / (PI * THICK))

## More water joins: the centre shifts toward where it landed, weighted by volume.
func absorb(p: Vector3, litres: float) -> void:
	var w := litres / maxf(level + litres, 0.001)
	var g := global_position
	global_position = Vector3(lerpf(g.x, p.x, w), g.y, lerpf(g.z, p.z, w))
	level += litres

func aim_hit(p: Vector3) -> bool:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	return d < radius() + 0.25 and absf(p.y - global_position.y) < 0.35

func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	return WaterSource.ray_disc(o, d, global_position, radius())

func near_point(p: Vector3) -> Vector3:
	return global_position + Vector3(p.x - global_position.x, 0, p.z - global_position.z).limit_length(radius())

func surface_point() -> Vector3:
	return global_position + Vector3(0, 0.01, 0)

func take(litres: float) -> float:
	var t := minf(litres, level)
	level -= t
	return t

func give(litres: float) -> void:
	level += litres

func _process(dt: float) -> void:
	if level < MIN_LITRES:
		remove_from_group("water_source")
		queue_free()
		return
	if absf(level - _built) > 0.15:
		_rebuild()
	_hl = move_toward(_hl, 1.0 if highlighted else 0.0, dt * 5.0)
	_rim.visible = _hl > 0.01
	_rim_mat.albedo_color.a = _hl * (0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.004))

func _rebuild() -> void:
	_built = level
	var r := radius()
	# a shallow sheet: thickest in the middle, thinning to nothing at the ragged edge
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var rings := [0.0, 0.55, 0.85, 1.0]
	var hts := [0.009, 0.008, 0.006, 0.003]
	verts.append(Vector3(0, hts[0], 0))
	norms.append(Vector3.UP)
	for k in range(1, rings.size()):
		for i in SEGS:
			var a := TAU * i / SEGS
			var rr: float = r * float(rings[k]) * _edge[i]
			verts.append(Vector3(cos(a) * rr, hts[k], sin(a) * rr))
			norms.append(Vector3.UP)
	for i in SEGS:
		idx.append_array([0, 1 + i, 1 + (i + 1) % SEGS])
	for k in range(1, rings.size() - 1):
		var b0 := 1 + (k - 1) * SEGS
		var b1 := 1 + k * SEGS
		for i in SEGS:
			var j := (i + 1) % SEGS
			idx.append_array([b0 + i, b1 + i, b0 + j, b0 + j, b1 + i, b1 + j])
	_mesh.clear_surfaces()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# highlight: a thin glowing band just outside the edge
	var rv := PackedVector3Array()
	var ri := PackedInt32Array()
	for i in SEGS:
		var a := TAU * i / SEGS
		var e: float = r * _edge[i]
		rv.append(Vector3(cos(a) * (e + 0.03), 0.012, sin(a) * (e + 0.03)))
		rv.append(Vector3(cos(a) * (e + 0.08), 0.012, sin(a) * (e + 0.08)))
	for i in SEGS:
		var j := (i + 1) % SEGS
		ri.append_array([2 * i, 2 * i + 1, 2 * j, 2 * j, 2 * i + 1, 2 * j + 1])
	_rim_mesh.clear_surfaces()
	var ra := []
	ra.resize(Mesh.ARRAY_MAX)
	ra[Mesh.ARRAY_VERTEX] = rv
	ra[Mesh.ARRAY_INDEX] = ri
	_rim_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
