class_name Dummy
extends RigidBody3D
## A straw training dummy on a wooden post: a sack body, a sack head and a crossbar of arms. The figure is
## a rigid body held on top of the post by a stiff spring (position) and a softer one (upright), so hits
## make it rock and spin and settle. Pulled hard enough (a latched lash), it tears off the post. It is
## sliceable (Slicer): cut pieces fall away and spill straw, and the piece still sitting on the post stays
## on it.

const POST_H := 1.0
const K_POS := 6000.0          # N/m holding it on the post
const K_UP := 260.0            # N m/rad keeping it upright
const K_YAW := 6.0             # N m s/rad damping its spin about the post
const TEAR := 0.45             # m pulled off the post before it tears loose
const STRAW := Color(0.80, 0.68, 0.40)
const STRAW_IN := Color(0.90, 0.80, 0.52)
const ROPE := Color(0.55, 0.42, 0.25)

const STRAIN := 0.08           # m off its seat that counts as being hauled on
const STRAIN_TIME := 0.4       # s of that before it tears loose

var attached := true
var _strain := 0.0
var _anchor := Vector3.ZERO     # top of the post, world

func _ready() -> void:
	mass = 12.0
	add_to_group("crate")      # a loose body for grabbing, shoving and cutting
	add_to_group("dummy")
	set_meta("stuff", "straw")
	var parts := []
	parts.append(Slicer.part(Slicer.prism_faces(0.2, 0.68, 8, 0.0), STRAW, STRAW_IN))
	parts.append(Slicer.part(Slicer.prism_faces(0.13, 0.26, 8, 0.72), STRAW, STRAW_IN))
	parts.append(Slicer.part(Slicer.box_faces(Vector3(0.46, 0.05, 0.05), Vector3(0, 0.52, 0)), ROPE, STRAW_IN))
	set_meta("parts", parts)
	Slicer.build(self)
	angular_damp = 0.6
	continuous_cd = true

	# the post, planted in the ground
	var post := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.05
	cyl.height = POST_H
	cs.shape = cyl
	cs.position.y = POST_H * 0.5
	post.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = POST_H
	cm.radial_segments = 10
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.33, 0.22)
	wood.roughness = 0.9
	cm.material = wood
	mi.mesh = cm
	mi.position.y = POST_H * 0.5
	post.add_child(mi)
	get_parent().add_child.call_deferred(post)
	post.position = position - Vector3(0, POST_H, 0)
	add_collision_exception_with(post)
	_anchor = position

## Where the dummy sits on its post, in its own space (the cut piece holding it stays on the post).
func keep_point() -> Vector3:
	return Vector3(0, 0.02, 0)

## Where the lash's aim assist aims: the middle of the torso.
func lash_point() -> Vector3:
	return global_transform * Vector3(0, 0.4, 0)

func _physics_process(dt: float) -> void:
	if not attached:
		return
	var at := global_position
	var dx := _anchor - at
	# held off its seat (a latched lash hauling on it) it gives way after a moment; a blow alone does not
	_strain = _strain + dt if dx.length() > STRAIN else 0.0
	if dx.length() > TEAR or _strain > STRAIN_TIME:
		attached = false
		Dummy.straw(at, Vector3.UP, get_parent(), 40)
		return
	# stiffness in proportion to what is left of it, so a cut-down dummy is held the same way
	var k := K_POS * mass / 12.0
	var c := 2.0 * sqrt(k * mass) * 0.6
	apply_force(dx * k - linear_velocity * c, Vector3.ZERO)
	var up := global_transform.basis.y
	var tilt := up.cross(Vector3.UP)
	var w := angular_velocity
	var wy := Vector3.UP * w.dot(Vector3.UP)
	# gains kept within what one physics step can integrate for the body as it now is (a cut-down
	# dummy is lighter and turns far more easily)
	var ii := PhysicsServer3D.body_get_direct_state(get_rid()).inverse_inertia
	var inertia := 1.0 / maxf(maxf(ii.x, maxf(ii.y, ii.z)), 1e-4)
	var ku := minf(K_UP, inertia * pow(0.35 / dt, 2.0))
	var cu := minf(18.0, inertia * 0.8 / dt)
	var cy := minf(K_YAW, inertia * 0.8 / dt)
	apply_torque(tilt * ku - (w - wy) * cu - wy * cy)

## Called when water or ice hits it: a puff of straw.
func struck(p: Vector3, dir: Vector3) -> void:
	Dummy.straw(p, -dir, get_parent(), 14)

## A burst of loose straw at p.
static func straw(p: Vector3, dir: Vector3, parent: Node, amount: int) -> void:
	var sp := GPUParticles3D.new()
	sp.amount = amount
	sp.lifetime = 1.6
	sp.one_shot = true
	sp.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 60.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	sp.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, 0.09)
	var m := StandardMaterial3D.new()
	m.albedo_color = STRAW_IN
	m.roughness = 1.0
	bm.material = m
	sp.draw_pass_1 = bm
	parent.add_child(sp)
	sp.global_position = p
	sp.emitting = true
	sp.get_tree().create_timer(2.5).timeout.connect(sp.queue_free)
