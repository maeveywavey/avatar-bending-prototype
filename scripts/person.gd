class_name Person
extends CharacterBody3D
## A villager (the player's mannequin, in other colours) who idles and wanders about aimlessly, keeping
## out of the stream. Called out by the blue button (SpawnButton); any number at once.
## Hurt, they bleed and despawn LIFE seconds later with everything that came off them:
##  - a slice cuts through them (Flesh.cut_person): limbs come off as loose pieces with cut flesh and
##    blood; with the head and both feet still on the pelvis they live on as an amputee (the lost part is
##    hidden on the skeleton, Severed, and the stump capped), otherwise they fall apart;
##  - a spike, a strike or a lash knocks them down limp (go_limp: the body as one loose piece).

const WALK := 1.3
const HOME_R := 12.0

var wander := true               # tests stand them still

static var _anims: AnimationLibrary

var _model: Node3D
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _ap: AnimationPlayer
var _sev: Severed
var _mats := []
var _home := Vector3.ZERO
var _walking := false
var _t := 0.0
var _heading := 0.0
var life := -1.0                # s left once hurt (game time), or -1
var _stumps := []               # [follower Node3D, bone, local point (unscaled), t, local normal]

## Hides what a cut took off a living person: the cut bone shortened to where it was cut, everything
## below it shrunk away.
## It also records every bone's final pose (bone poses read outside a modifier are the unmodified ones),
## so a cut is made through the body as it is drawn.
class Severed extends SkeletonModifier3D:
	var scales := {}
	var poses: Array[Transform3D] = []

	func _process_modification() -> void:
		var sk := get_skeleton()
		for b in scales:
			sk.set_bone_pose_scale(b, scales[b])
		poses.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			poses[b] = sk.get_bone_global_pose(b)

func _ready() -> void:
	add_to_group("person")
	_home = global_position
	_heading = rotation.y
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.72
	cs.shape = cap
	cs.position.y = 0.86
	add_child(cs)
	_model = (load("res://assets/Mannequin_F.glb") as PackedScene).instantiate()
	_model.rotation.y = PI
	add_child(_model)
	_sk = _model.find_children("*", "Skeleton3D", true, false)[0]
	_mi = _model.find_children("*", "MeshInstance3D", true, false)[0]
	# villager colours: skin, and the joint bands as clothing
	var cols := [Color(0.86, 0.66, 0.52), Color(0.24, 0.30, 0.42)]
	for s in _mi.mesh.get_surface_count():
		var m := (_mi.mesh.surface_get_material(s) as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = cols[mini(s, 1)]
		_mi.set_surface_override_material(s, m)
		_mats.append(m)
	while _mats.size() < 2:
		_mats.append(_mats[0])
	_mats.append(Flesh.cap_material())
	_ap = AnimationPlayer.new()
	add_child(_ap)
	_ap.root_node = _ap.get_path_to(_model)
	_ap.add_animation_library("loco", _lib())
	_ap.play("loco/Idle")
	_sev = Severed.new()
	_sk.add_child(_sev)
	_t = randf_range(0.5, 2.0)

static func _lib() -> AnimationLibrary:
	if _anims == null:
		_anims = AnimationLibrary.new()
		var src: AnimationPlayer = (load("res://assets/UAL1_Standard.glb") as PackedScene).instantiate().find_children("*", "AnimationPlayer", true, false)[0]
		for n in ["Idle", "Walk"]:
			var a: Animation = src.get_animation_library("").get_animation(n).duplicate()
			a.loop_mode = Animation.LOOP_LINEAR
			_anims.add_animation(n, a)
	return _anims

func _physics_process(dt: float) -> void:
	if not wander:
		_walking = false
		_t = 1.0
	_t -= dt
	if _t <= 0.0:
		_walking = not _walking
		_t = randf_range(3.0, 7.0) if _walking else randf_range(2.0, 5.0)
		if _walking:
			var to_home := _home - global_position
			if to_home.length() > HOME_R:
				_heading = atan2(-to_home.x, -to_home.z) + randf_range(-0.5, 0.5)
			else:
				_heading = randf_range(-PI, PI)
	# never into the stream
	if wander and global_position.x < Pond.near_bank_x(global_position.z) + 2.5:
		_heading = -PI * 0.5 + randf_range(-0.3, 0.3)
		_walking = true
	var want := Vector3(-sin(_heading), 0, -cos(_heading)) * (WALK if _walking else 0.0)
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(want.x, want.z), 4.0 * dt)
	velocity.x = hv.x
	velocity.z = hv.y
	velocity.y = velocity.y - 20.0 * dt if not is_on_floor() else 0.0
	move_and_slide()
	if _walking:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_normal().y < 0.5:
				_heading += PI * randf_range(0.5, 1.0)
				break
		rotation.y = lerp_angle(rotation.y, _heading, clampf(dt * 4.0, 0.0, 1.0))
	var anim := "loco/Walk" if hv.length() > 0.4 else "loco/Idle"
	if _ap.current_animation != anim:
		_ap.play(anim, 0.3)

func _process(dt: float) -> void:
	if life >= 0.0:
		life -= dt
		if life <= 0.0:
			queue_free()
			return
	# stump caps and their blood ride the shortened bones
	var skx := _sk.global_transform
	for s in _stumps:
		var f: Node3D = s[0]
		var gp := _pose(s[1])
		var l: Vector3 = s[2]
		var t: float = s[3]
		f.global_position = skx * gp * Vector3(l.x, l.y / t, l.z)
		f.global_basis = (skx.basis * gp.basis).orthonormalized()

## Where the lash's aim assist aims: the chest.
func lash_point() -> Vector3:
	return global_position + Vector3(0, 1.15, 0)

func _hurt() -> void:
	if life < 0.0:
		life = Flesh.LIFE
		if "--demo" in OS.get_cmdline_user_args():
			print("PERSON hurt at %s" % global_position.snapped(Vector3(0.1, 0.1, 0.1)))

func _secs_left() -> float:
	return maxf(life, 0.3)

## The blade's plane through them (point p, normal n; w wide along side, flying along dir). Returns the
## pieces cut off.
func slice_by(p: Vector3, n: Vector3, side: Vector3, w: float, dir: Vector3) -> Array:
	_hurt()
	var baked := Flesh.bake(_mi, _sk, _sev.poses)
	var r := Flesh.cut_person(baked, _sk, p, n, side, w, _sev.poses, dir)
	var world := get_parent()
	if r.is_empty():
		# a gash: no bone cut through
		var at := to_local(p)
		Flesh.spray(self, at, -dir, minf(_secs_left(), 3.0), 0.5)
		Flesh.splats(world, p, _secs_left(), 2)
		return []
	var total := 0
	for b in baked:
		total += (b["I"] as PackedInt32Array).size() / 3
	var pieces := []
	var groups: Dictionary = r["groups"]
	for gid in groups:
		if r["alive"] and gid == r["root"]:
			continue
		var g: Dictionary = groups[gid]
		var c := _centre(g["surf"])
		var s := 1.0 if n.dot(c - p) >= 0.0 else -1.0
		var piece := Flesh.make_piece(world, g["surf"], _mats, velocity + n * s * 0.8 + dir * 1.2, life, total)
		if piece == null:
			continue
		pieces.append(piece)
		for k in g["caps"]:
			var pts: PackedVector3Array = g["caps"][k]
			var cc := _avg(pts)
			var outward := -n if k % 2 == 1 else n
			Flesh.spray(piece, piece.to_local(cc), piece.global_basis.inverse() * outward, minf(_secs_left(), 3.0), 0.8)
	Flesh.splats(world, p, _secs_left())
	if "--demo" in OS.get_cmdline_user_args():
		print("SLICE person: %d pieces, %s, cut bones %s" % [pieces.size(), "alive" if r["alive"] else "dead", str((r["hide"] as Dictionary).keys().map(func(b): return _sk.get_bone_name(b)))])
	if not r["alive"]:
		queue_free()
		return pieces
	# an amputee: the lost part hidden, the stump closed and bleeding
	for cb in r["hide"]:
		var t: float = maxf(r["hide"][cb], 0.05)
		_sev.scales[cb] = Vector3(1.0, t, 1.0)
		for ch in _sk.get_bone_children(cb):
			_sev.scales[ch] = Vector3.ONE * 0.001
	var root_caps: Dictionary = groups[r["root"]]["caps"]
	var skx := _sk.global_transform
	for k in root_caps:
		var cb: int = k / 2
		if not r["hide"].has(cb):
			continue
		var pts: PackedVector3Array = root_caps[k]
		var cc := _avg(pts)
		var outward: Vector3 = -n if k % 2 == 1 else n
		var gp := _pose(cb)
		var bw := skx * gp
		var f := Node3D.new()
		add_child(f)
		var fb := bw.basis.orthonormalized()
		f.global_transform = Transform3D(fb, cc)
		# the cap, in the follower's frame
		var tris := []
		Flesh.cap(pts, outward, tris)
		var v := PackedVector3Array()
		var nm := PackedVector3Array()
		for i in range(0, tris.size(), 2):
			v.append(fb.inverse() * ((tris[i] as Vector3) - cc))
			nm.append(fb.inverse() * (tris[i + 1] as Vector3))
		if v.size() >= 3:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_NORMAL] = nm
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var cmi := MeshInstance3D.new()
			cmi.mesh = am
			cmi.material_override = Flesh.cap_material()
			f.add_child(cmi)
		Flesh.spray(f, Vector3.ZERO, fb.inverse() * outward, minf(_secs_left(), 4.0), 1.0)
		_stumps.append([f, cb, bw.affine_inverse() * cc, maxf(r["hide"][cb], 0.05)])
	return pieces

## Knocked down: the body in its pose becomes one loose piece (it is not a ragdoll), and the person goes.
func go_limp() -> FleshPiece:
	_hurt()
	var baked := Flesh.bake(_mi, _sk, _sev.poses)
	var surf := [[], [], []]
	var total := 0
	for si in baked.size():
		var P: PackedVector3Array = baked[si]["P"]
		var N: PackedVector3Array = baked[si]["N"]
		var I: PackedInt32Array = baked[si]["I"]
		total += I.size() / 3
		for t in I:
			surf[si].append(P[t])
			surf[si].append(N[t])
	var piece := Flesh.make_piece(get_parent(), surf, _mats, velocity, life, total)
	queue_free()
	if piece != null:
		piece.mass = Flesh.KG
	return piece

## A spike strikes: they fall, bleeding where it went in; the spike stays in the body.
func spike_hit(p: Vector3, dir: Vector3) -> Object:
	var world := get_parent()
	var piece := go_limp()
	Flesh.splats(world, p, _secs_left(), 2)
	if piece == null:
		return null
	Flesh.spray(piece, piece.to_local(p), piece.global_basis.inverse() * -dir, minf(_secs_left(), 3.0), 0.6)
	return piece

## A strike of water knocks them down.
func water_hit(_p: Vector3, _n: Vector3, dir: Vector3, litres: float) -> void:
	var piece := go_limp()
	if piece != null:
		piece.apply_central_impulse(dir * clampf(litres * 2.0, 20.0, 400.0))

## A bone's pose as drawn (after Severed), skeleton space.
func _pose(b: int) -> Transform3D:
	return _sev.poses[b] if b < _sev.poses.size() else _sk.get_bone_global_pose(b)

func _centre(surf: Array) -> Vector3:
	var c := Vector3.ZERO
	var k := 0
	for s in surf:
		for i in range(0, (s as Array).size(), 12):
			c += s[i]
			k += 1
	return c / maxf(k, 1)

func _avg(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for q in pts:
		c += q
	return c / maxf(pts.size(), 1)
