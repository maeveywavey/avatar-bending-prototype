class_name SpawnButton
extends StaticBody3D
## A big blue button on a wall (facing +Z). Pressed by water: a strike, lash, slice or ice spike hitting
## it (water_hit), or the water in precision mode pushed into it. Each press calls a new person out at
## spawn_at; any number can be about at once.

const R := 0.42
const COOLDOWN := 0.8

var spawn_at := Vector3.ZERO
var _cap: MeshInstance3D
var _t := 10.0
var _push := 0.0

func _ready() -> void:
	add_to_group("button")
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.2, 1.2, 0.06)
	plate.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.25, 0.27, 0.3)
	plate.material_override = pmat
	plate.position.z = 0.03
	add_child(plate)
	_cap = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R
	cm.bottom_radius = R
	cm.height = 0.16
	_cap.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.35, 0.95)
	cmat.emission_enabled = true
	cmat.emission = Color(0.05, 0.15, 0.5)
	cmat.roughness = 0.35
	_cap.material_override = cmat
	_cap.rotation.x = PI * 0.5        # the cylinder's axis out of the wall
	_cap.position.z = 0.14
	add_child(_cap)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.2, 0.24)
	cs.shape = bs
	cs.position.z = 0.12
	add_child(cs)

## Anything of water striking it presses it.
func water_hit(_p: Vector3, _n: Vector3, _dir: Vector3, _litres: float) -> void:
	press()

func press() -> void:
	if _t < COOLDOWN:
		return
	_t = 0.0
	_push = 1.0
	var p := Person.new()
	p.position = spawn_at + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	p.rotation.y = randf_range(-PI, PI)
	get_parent().add_child(p)
	if "--demo" in OS.get_cmdline_user_args():
		print("BUTTON pressed: person at %s" % p.position.snapped(Vector3(0.1, 0.1, 0.1)))

func _physics_process(dt: float) -> void:
	_t += dt
	_push = move_toward(_push, 0.0, dt * 3.0)
	_cap.position.z = 0.14 - 0.08 * _push
	# the water in precision mode pushed against it
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.water != null and pl.water.state == WaterBody.S.STEER:
		var head: Vector3 = pl.water.head_pos()
		var local := to_local(head)
		if Vector2(local.x, local.y).length() < R + 0.15 and local.z < 0.7 and local.z > -0.1:
			press()
