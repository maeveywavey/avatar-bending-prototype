class_name IceSpike
extends Node3D
## Water frozen into a spike and thrown point-first. Its size follows its volume: an irregular crystal
## ASPECT times as long as it is wide, with flat faces, a long point at the front and a short blunt one at
## the back. It sticks into what it hits: fixed surfaces hold it (a large spike can then be stood on),
## loose bodies are knocked by its momentum and carry it. Ice melts: after MELT_START it shrinks over
## MELT_TIME and its water lands below as a puddle.

const ASPECT := 6.0
const ICE_KG_PER_L := 1.0       # the ice weighs what its water did
# m³ of ice per m³ of water. Real ice is 1.09; the owner set a 30 L spike to be as big as the 68 L one
# was, so spikes are 68/30 times their water's volume (a game allowance).
const EXPAND := 68.0 / 30.0
const EMBED_FIXED := 0.45       # of its length sunk into a wall or the ground
const EMBED_BODY := 0.3         # into a loose body
const MELT_START := 90.0
const MELT_TIME := 12.0

enum S { FORMING, FLYING, STUCK, FALLING }

var state := S.FORMING
var litres := 0.0
var _vel := Vector3.ZERO
var _dir := Vector3.FORWARD
var _len := 0.1
var _r := 0.02
var _age := 0.0
var _mi: MeshInstance3D
var _mesh := ArrayMesh.new()
var _owner_rid: RID
var _body: StaticBody3D
var _scale := 1.0
var _unit := PackedVector3Array()   # the crystal's triangles at unit size (radius 1, length 1)
var _unit_vol := 1.0

static var _ice: StandardMaterial3D
static func ice_material() -> StandardMaterial3D:
	if _ice == null:
		_ice = StandardMaterial3D.new()
		_ice.albedo_color = Color(0.80, 0.92, 1.0, 0.78)
		_ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		_ice.roughness = 0.12
		_ice.metallic_specular = 0.8
		_ice.rim_enabled = true
		_ice.rim = 0.6
		_ice.rim_tint = 0.3
		_ice.clearcoat_enabled = true
		_ice.clearcoat = 0.6
		_ice.emission_enabled = true
		_ice.emission = Color(0.12, 0.2, 0.28)
	return _ice

func setup(bender: CollisionObject3D) -> void:
	_owner_rid = bender.get_rid()

func _ready() -> void:
	_make_crystal()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = ice_material()
	_mi.layers = 2
	add_child(_mi)
	_resize()

func add_litres(l: float) -> void:
	litres += l
	if is_inside_tree():
		_resize()

## The crystal at unit size, along +Y from 0 (back point) to 1 (front point), radius about 1: a blunt back
## point, an irregular six-sided body (two rings, each face flat), and a long front point. Each spike's
## shape is its own.
func _make_crystal() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var sides := 6
	var rings := [[0.12, 1.0], [0.34, 0.92]]      # [height, radius]
	var ring_pts := []
	var twist := rng.randf_range(0.0, TAU)
	for rg in rings:
		var pr := []
		for k in sides:
			var a: float = twist + TAU * k / sides + rng.randf_range(-0.22, 0.22)
			var r: float = rg[1] * rng.randf_range(0.78, 1.12)
			pr.append(Vector3(cos(a) * r, rg[0] + rng.randf_range(-0.02, 0.02), sin(a) * r))
		ring_pts.append(pr)
		twist += rng.randf_range(0.15, 0.4)
	var back := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
	var front := Vector3(rng.randf_range(-0.05, 0.05), 1.0, rng.randf_range(-0.05, 0.05))
	var tris := []
	for k in sides:
		var j := (k + 1) % sides
		tris.append([back, ring_pts[0][j], ring_pts[0][k]])
		tris.append([ring_pts[0][k], ring_pts[0][j], ring_pts[1][j]])
		tris.append([ring_pts[0][k], ring_pts[1][j], ring_pts[1][k]])
		tris.append([ring_pts[1][k], ring_pts[1][j], front])
	_unit = PackedVector3Array()
	_unit_vol = 0.0
	var mid := Vector3(0, 0.3, 0)
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		# Godot front faces are clockwise: (b-a)x(c-a) points inward
		var out := (a + b + c) / 3.0 - mid
		if (b - a).cross(c - a).dot(out) > 0.0:
			var s := b
			b = c
			c = s
		_unit.append_array([a, b, c])
		_unit_vol += absf((a - mid).dot((b - mid).cross(c - mid))) / 6.0

func _resize() -> void:
	# volume = unit volume x r^2 x length, with length = ASPECT x 2r
	var vol := maxf(litres, 0.05) / 1000.0 * EXPAND
	_r = pow(vol / (_unit_vol * 2.0 * ASPECT), 1.0 / 3.0)
	_len = _r * 2.0 * ASPECT
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, _unit.size(), 3):
		var tri := []
		for k in 3:
			var u: Vector3 = _unit[i + k]
			tri.append(Vector3(u.x * _r, (u.y - 0.5) * _len, u.z * _r))
		var n: Vector3 = -((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0]).normalized()
		for k in 3:
			verts.append(tri[k])
			norms.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

func spike_length() -> float:
	return _len

func _orient(d: Vector3) -> void:
	_dir = d.normalized()
	var up := Vector3.UP if absf(_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(_dir).normalized()
	var z := x.cross(_dir)
	# the cylinder's +Y is the point
	global_transform = Transform3D(Basis(x, _dir, z), global_position)

## While forming: held in front of the hands, pointing where the bender aims.
func hold_at(p: Vector3, d: Vector3) -> void:
	global_position = p
	_orient(d)

func fire(from: Vector3, d: Vector3, speed: float) -> void:
	state = S.FLYING
	global_position = from
	_orient(d)
	_vel = _dir * speed

## Let go while forming: it simply falls.
func drop() -> void:
	state = S.FLYING
	_vel = Vector3.ZERO

func _process(dt: float) -> void:
	_age += dt
	match state:
		S.FLYING:
			_vel.y -= (4.0 if _vel.length() > 8.0 else 9.8) * dt
			var tip := global_position + _dir * _len * 0.5
			var np := global_position + _vel * dt
			var q := PhysicsRayQueryParameters3D.create(tip, np + _dir * _len * 0.5)
			q.exclude = [_owner_rid]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				_hit(hit["position"], hit["normal"], hit["collider"])
				return
			global_position = np
			if _vel.length() > 0.5:
				_orient(_vel)
			if _age > 12.0:
				_melt_away()
		S.STUCK:
			if _age > MELT_START:
				var k := clampf(1.0 - (_age - MELT_START) / MELT_TIME, 0.0, 1.0)
				_mi.scale = Vector3.ONE * maxf(k, 0.05)
				if k <= 0.0:
					_melt_away()

func _hit(p: Vector3, n: Vector3, col: Object) -> void:
	var sp := _vel.length()
	if col != null and col.has_method("spike_hit"):
		# a person: hurt, and falls as a body the spike stays in
		col = col.spike_hit(p, _dir)
	# its point sunk into what it hit, deeper into fixed surfaces
	var embed := EMBED_BODY if col is RigidBody3D else EMBED_FIXED
	global_position = p - _dir * (_len * 0.5 - _len * embed)
	state = S.STUCK
	_age = 0.0
	var target: Object = col
	if target != null and not target.has_method("water_hit") and target.has_meta("sign"):
		target = target.get_meta("sign")
	if target != null and target.has_method("water_hit"):
		target.water_hit(p, n, _dir, litres)
	if col is RigidBody3D:
		var rb := col as RigidBody3D
		# most of a sticking spike's momentum goes into piercing; what knocks the body is capped at a
		# brisk shove for its weight
		var j := minf(litres * ICE_KG_PER_L * sp * 0.3, rb.mass * 8.0)
		rb.apply_impulse(_dir * j, p - rb.global_position)
		if rb.has_method("struck"):
			rb.struck(p, _dir)
		# carried by the body it is stuck in
		var xf := global_transform
		get_parent().remove_child(self)
		rb.add_child(self)
		global_transform = xf
	elif litres > 25.0:
		# a large spike in a fixed surface is solid to stand on
		_body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := ConvexPolygonShape3D.new()
		cy.points = _mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		cs.shape = cy
		_body.add_child(cs)
		add_child(_body)

func _melt_away() -> void:
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * 30.0)
	q.exclude = [_owner_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and litres > 0.0:
		var gp: Vector3 = hit["position"]
		if hit["collider"] is RigidBody3D:
			gp.y = 0.0
		var world := get_tree().current_scene
		Puddle.add_at(gp, litres, get_tree(), world)
	litres = 0.0
	queue_free()
