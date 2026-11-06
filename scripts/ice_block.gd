class_name IceBlock
extends RigidBody3D
## Ice as a body: the tapped ice wall (frozen in place on the ground) and the pieces cut or broken off it
## (loose: they can be grabbed, lashed, thrown, and float). Its shape is Slicer parts, so a slice cuts it.
## Its water is counted: it holds l_per_m3 litres per m³ of ice, shared by volume when it is cut or
## broken. It is a water source: drawn from, it shrinks (and is gone when drawn dry). Water hits (strikes,
## spikes, lashes) add up; past BREAK_K of its own litres it breaks into pieces round the hit, the part
## standing on the ground staying put.

const BREAK_K := 0.8
const ICE := Color(0.80, 0.92, 1.0)

var highlighted := false
var capacity := 1.0e9
var l_per_m3 := 40.0
var level: float:
	get:
		return volume() * l_per_m3
var _damage := 0.0
var _dirty := false
var _rebuild_t := 0.0
var _hl := 0.0

static var _glow: StandardMaterial3D

## A wall standing on base (world), its face toward face (horizontal), size (width, height, thickness),
## made from litres of water. Slightly narrower at the top; faces flat.
static func make_wall(parent: Node, base: Vector3, face: Vector3, size: Vector3, litres: float) -> IceBlock:
	var b := IceBlock.new()
	var w := size.x * 0.5
	var t := size.z * 0.5
	var h := size.y
	var bot := [Vector3(-w, 0, -t), Vector3(w, 0, -t), Vector3(w, 0, t), Vector3(-w, 0, t)]
	var top := [Vector3(-w * 0.9, h, -t * 0.7), Vector3(w * 0.9, h, -t * 0.7), Vector3(w * 0.9, h, t * 0.7), Vector3(-w * 0.9, h, t * 0.7)]
	var faces := []
	faces.append({"p": PackedVector3Array(bot), "n": Vector3.DOWN, "cap": false})
	faces.append({"p": PackedVector3Array(top), "n": Vector3.UP, "cap": false})
	for i in 4:
		var j := (i + 1) % 4
		var q := PackedVector3Array([bot[i], bot[j], top[j], top[i]])
		var n: Vector3 = ((bot[j] as Vector3) - bot[i]).cross((top[i] as Vector3) - bot[i]).normalized()
		if n.dot(((bot[i] + bot[j]) as Vector3) * Vector3(1, 0, 1)) < 0.0:
			n = -n
		faces.append({"p": q, "n": n, "cap": false})
	var pa := Slicer.part(faces, ICE, ICE)
	pa["mat"] = IceSpike.ice_material()
	pa["cap_mat"] = IceSpike.ice_material()
	b.set_meta("parts", [pa])
	b.set_meta("stuff", "ice")
	b.l_per_m3 = litres / maxf(Slicer.volume(faces), 1e-4)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	b.mass = maxf(litres, 0.5)      # the ice weighs what its water did (as the spikes)
	var f := Vector3(face.x, 0, face.z).normalized()
	if f.length() < 0.1:
		f = Vector3.BACK
	var x := Vector3.UP.cross(f).normalized()
	parent.add_child(b)
	b.global_transform = Transform3D(Basis(x, Vector3.UP, f), base)
	return b

func _ready() -> void:
	add_to_group("water_source")
	add_to_group("ice")
	if not freeze:
		add_to_group("crate")
	continuous_cd = true
	if has_meta("parts"):
		Slicer.build(self)

## Slicer.cut makes the cut-off part with this: ice like this one, loose.
func make_piece() -> RigidBody3D:
	var p := IceBlock.new()
	p.l_per_m3 = l_per_m3
	return p

## Slicer keeps this point's side on the body: the base, for a standing wall; the bulk, for a loose piece.
func keep_point() -> Vector3:
	if freeze:
		return Vector3(0, 0.02, 0)
	return _centre_local()

func volume() -> float:
	var v := 0.0
	if has_meta("parts"):
		for pa in get_meta("parts"):
			v += Slicer.volume(pa["faces"])
	return v

func _all_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if has_meta("parts"):
		for pa in get_meta("parts"):
			out.append_array(Slicer._points(pa["faces"]))
	return out

func _centre_local() -> Vector3:
	var pts := _all_points()
	var c := Vector3.ZERO
	for v in pts:
		c += v
	return c / maxf(pts.size(), 1)

func _bounds_local() -> AABB:
	var pts := _all_points()
	if pts.is_empty():
		return AABB()
	var bb := AABB(pts[0], Vector3.ZERO)
	for v in pts:
		bb = bb.expand(v)
	return bb

var _full: Array = []

## Rising out of the ground as it freezes: k of its height (0..1). The water is all there already; the
## litres are counted as the full block's (its l_per_m3 is set from the full size).
func set_rise(k: float) -> void:
	if _full.is_empty():
		_full = (get_meta("parts") as Array).duplicate(true)
		_full_lpm = l_per_m3
	k = clampf(k, 0.05, 1.0)
	var parts := _full.duplicate(true)
	for pa in parts:
		for f in pa["faces"]:
			var p: PackedVector3Array = f["p"]
			for i in p.size():
				p[i].y *= k
			f["p"] = p
	set_meta("parts", parts)
	# the same water in a lower block, until it has risen
	l_per_m3 = _full_lpm / k
	Slicer.build(self)

var _full_lpm := 0.0

## Loose from now on (broken off a wall).
func loosen() -> void:
	if freeze:
		freeze = false
		add_to_group("crate")
	sleeping = false

# ---------------------------------------------------------------- as a water source

func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	var bb := _bounds_local()
	var a := global_transform * Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	var b := global_transform * Vector3(bb.get_center().x, bb.end.y, bb.get_center().z)
	var r := WaterSource.ray_seg(o, d, a, b)
	return Vector2(maxf(r.x - maxf(bb.size.x, bb.size.z) * 0.4, 0.0), r.y)

func near_point(_p: Vector3) -> Vector3:
	return global_transform * _bounds_local().get_center()

func surface_point() -> Vector3:
	var bb := _bounds_local()
	return global_transform * Vector3(bb.get_center().x, bb.end.y, bb.get_center().z)

## Drawn from: the ice melts into the stream and the block shrinks (about its base when standing).
func take(litres: float) -> float:
	var have := level
	var t := minf(litres, have)
	if have - t < 0.3:
		t = have
		_gone()
		return t
	var k := pow((have - t) / have, 1.0 / 3.0)
	var piv := Vector3(0, 0, 0) if freeze else _centre_local()
	var parts: Array = get_meta("parts")
	for pa in parts:
		for f in pa["faces"]:
			var p: PackedVector3Array = f["p"]
			for i in p.size():
				p[i] = piv + (p[i] - piv) * k
			f["p"] = p
	_dirty = true
	return t

## Water cannot go back into ice: it lands below as a puddle.
func give(litres: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 20.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit["position"] if not hit.is_empty() else global_position
	Puddle.add_at(at, litres, get_tree(), get_parent())

func _gone() -> void:
	# nothing left to draw, even later this frame
	set_meta("parts", [])
	remove_from_group("water_source")
	remove_from_group("crate")
	queue_free()

# ---------------------------------------------------------------- hits

func water_hit(p: Vector3, _n: Vector3, dir: Vector3, litres: float) -> void:
	_damage += litres
	if _damage >= level * BREAK_K:
		shatter(p, dir)

## Broken at p: three cracks through about there; every piece but the one standing on the ground flies
## loose along dir.
func shatter(p: Vector3, dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id() + int(_damage * 10.0)
	var bodies: Array = [self]
	for k in 3:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)).normalized()
		var c := p + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.2, 0.2))
		var made := []
		for b in bodies:
			if is_instance_valid(b):
				var piece := Slicer.cut(b, c, n)
				if piece != null:
					made.append(piece)
		bodies.append_array(made)
	_damage = 0.0
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var ib := b as IceBlock
		if ib == self and freeze:
			continue
		# only the pieces near the hit fly; ones far from it just come loose and fall
		ib.loosen()
		var off := ib.global_transform * ib._centre_local() - p
		var push := clampf(1.0 - off.length() / 1.2, 0.0, 1.0)
		ib.apply_central_impulse((dir * 3.0 + off.normalized() * 1.5) * ib.mass * push)
	if "--demo" in OS.get_cmdline_user_args():
		print("ICE broke into %d pieces" % bodies.size())

func _process(dt: float) -> void:
	if not freeze and level < 0.25 and not is_queued_for_deletion():
		# a sliver: it melts away where it lies
		give(level)
		_gone()
		return
	_rebuild_t -= dt
	if _dirty and _rebuild_t <= 0.0:
		_dirty = false
		_rebuild_t = 0.05
		Slicer.build(self)
	_hl = move_toward(_hl, 1.0 if highlighted else 0.0, dt * 5.0)
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Color(0.55, 0.9, 1.0, 0.35)
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.grow = true
		_glow.grow_amount = 0.03
	for ch in get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).material_overlay = _glow if _hl > 0.5 else null
