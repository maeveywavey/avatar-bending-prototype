class_name IceWall
extends Node3D
## Ice wall, tapped: LITRES of the held water thrown fast from the held body to where the bender aims,
## rising there out of the ground as a wall of ice (IceBlock), its face to the bender. From 30 L it stands
## about 1.25 times the bender's height, 0.75 of it wide and half a crate thick (SIZE); less water makes a
## smaller wall of the same shape. Something in the way stops the throw: the wall rises at its foot.

const LITRES := 30.0
const SIZE := Vector3(1.3, 2.2, 0.25)    # width, height, thickness, for LITRES
const SPEED := 26.0
const RISE_T := 0.22

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _face := Vector3.BACK
var _l := 0.0
var _t := 0.0
var _dur := 0.1
var _prev := Vector3.ZERO
var _owner_rid: RID
var _block: IceBlock
var _rise := -1.0
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _frost: GPUParticles3D

func begin(from: Vector3, to: Vector3, bender_pos: Vector3, litres: float, bender: CollisionObject3D) -> void:
	_from = from
	_to = to
	_prev = from
	_l = litres
	_owner_rid = bender.get_rid()
	_face = Vector3(bender_pos.x - to.x, 0, bender_pos.z - to.z)
	_dur = maxf(from.distance_to(to) / SPEED, 0.08)

func _ready() -> void:
	top_level = true
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = Tube.water_material(7.0, 0.55)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.layers = 2
	_mi.extra_cull_margin = 8.0
	add_child(_mi)

func _arc(u: float) -> Vector3:
	var h := 0.12 * _from.distance_to(_to)
	return _from.lerp(_to, u) + Vector3.UP * (4.0 * h * u * (1.0 - u))

func _process(dt: float) -> void:
	if _rise >= 0.0:
		_rise += dt
		if is_instance_valid(_block):
			_block.set_rise(_rise / RISE_T)
		if _rise >= RISE_T:
			if _frost:
				_frost.emitting = false
			if is_instance_valid(_block):
				_block.set_rise(1.0)
			get_tree().create_timer(1.0).timeout.connect(queue_free)
			_rise = -2.0
		return
	if _rise < -1.5:
		return
	_t += dt
	var u := minf(_t / _dur, 1.0)
	var head := _arc(u)
	var q := PhysicsRayQueryParameters3D.create(_prev, head)
	q.exclude = [_owner_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(_to) > 0.3:
		# in the way: the wall rises at its foot, on this side of it
		var hp: Vector3 = hit["position"]
		var back := Vector3(_face.x, 0, _face.z).normalized() * (SIZE.z * 0.6)
		var dq := PhysicsRayQueryParameters3D.create(hp + back + Vector3.UP * 0.2, hp + back + Vector3.DOWN * 8.0)
		dq.exclude = [_owner_rid]
		var g := get_world_3d().direct_space_state.intersect_ray(dq)
		_freeze_at(g["position"] if not g.is_empty() else Vector3(hp.x, _to.y, hp.z) + back)
		return
	_prev = head
	if u >= 1.0:
		_freeze_at(_to)
		return
	# the thrown water: a short stream following its head
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var r := clampf(sqrt(_l / 1000.0 * 2.3 / (PI * 1.0)), 0.04, 0.16)
	for k in 9:
		var uu := maxf(u - 0.35 * float(k) / 8.0, 0.0)
		pts.append(_arc(uu))
		rad.append(r * lerpf(1.0, 0.35, float(k) / 8.0))
	var a := Tube.arrays()
	Tube.loft(a, Tube.round_rings(pts, rad), 10, _t * 4.0, true, true)
	Tube.commit(_mesh, a)

func _freeze_at(p: Vector3) -> void:
	_mi.visible = false
	var k := pow(maxf(_l, 0.5) / LITRES, 1.0 / 3.0)
	_block = IceBlock.make_wall(get_parent(), p - Vector3(0, 0.05, 0), _face, SIZE * k, _l)
	_block.set_rise(0.05)
	_rise = 0.0
	_frost = GPUParticles3D.new()
	_frost.amount = 60
	_frost.lifetime = 0.6
	_frost.one_shot = true
	_frost.explosiveness = 0.8
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SIZE.x * k * 0.5, 0.1, 0.2)
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -2, 0)
	_frost.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.08)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.9, 0.97, 1.0, 0.6)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = fm
	_frost.draw_pass_1 = qm
	_frost.layers = 2
	add_child(_frost)
	_frost.global_position = p + Vector3(0, 0.1, 0)
	_frost.emitting = true
	if "--demo" in OS.get_cmdline_user_args():
		print("WALL %.1f L at %s, %.2f x %.2f x %.2f m" % [_l, p.snapped(Vector3(0.01, 0.01, 0.01)), SIZE.x * k, SIZE.y * k, SIZE.z * k])
