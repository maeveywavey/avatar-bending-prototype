class_name SignBoard
extends Node3D
## A flat signboard hanging from a post arm by a hinge. A strong water hit breaks the hinge.

var board: RigidBody3D
var joint: HingeJoint3D
var _mat: ShaderMaterial
var _wet_tween: Tween
var broken := false

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/wet_surface.gdshader")
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.93, 0.92, 0.90)
	white.roughness = 0.9

	var post := StaticBody3D.new()
	post.add_child(_box(Vector3(0.16, 3.0, 0.16), Vector3(0, 1.5, 0), white))
	post.add_child(_box(Vector3(1.5, 0.12, 0.12), Vector3(0.75, 2.94, 0), white))
	add_child(post)

	board = RigidBody3D.new()
	board.mass = 4.0
	board.position = Vector3(1.0, 2.88, 0)
	var bm := _box(Vector3(1.2, 0.6, 0.07), Vector3(0, -0.3, 0), _mat)
	board.add_child(bm)
	board.add_child(_body_col(Vector3(1.2, 0.6, 0.07), Vector3(0, -0.3, 0)))
	board.set_meta("sign", self)
	board.add_to_group("water_hit")
	add_child(board)

	joint = HingeJoint3D.new()
	joint.position = Vector3(1.0, 2.88, 0)
	joint.rotation = Vector3(0, PI * 0.5, 0)
	add_child(joint)
	joint.node_a = post.get_path()
	joint.node_b = board.get_path()

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	return mi

func _body_col(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	return cs

func water_hit(point: Vector3, _normal: Vector3, dir: Vector3, litres: float) -> void:
	var impulse := dir.normalized() * litres * 1.1
	board.apply_impulse(impulse, point - board.global_position)
	if not broken and litres > 15.0:
		broken = true
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.queue_free()
	_mat.set_shader_parameter("wet_center", board.to_local(point))
	if _wet_tween:
		_wet_tween.kill()
	_wet_tween = create_tween()
	_wet_tween.tween_method(func(v: float): _mat.set_shader_parameter("wet_radius", v), 0.0, 1.4, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wet_tween.parallel().tween_method(func(v: float): _mat.set_shader_parameter("wet_all", v), 0.0, 1.0, 3.0).set_delay(1.2)
