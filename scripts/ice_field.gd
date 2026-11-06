class_name IceField
extends StaticBody3D
## Ice frozen in place by the ice wall form, kept as columns on a grid of CELL-wide cells (one column per
## cell: a base and a top height). Where the bender aims:
##  - on the ground: ice forms and rises the longer it is aimed at (walls, pillars; graded heights make
##    ramps, since the tops are smoothed into slopes between neighbouring columns);
##  - on a water surface: a slab freezes at the waterline, floating, that can be walked on;
##  - on a wall: a ledge sticks out from it;
##  - on the side of existing ice: the ice extends sideways at its top (bridges, platforms);
##  - on the top of existing ice: it rises further.
## Ice is water: every cubic metre frozen takes ICE_L_PER_M3 litres from the held water, or from the water
## body under it (a slab on the pond grows from the pond).
## Built as one trimesh per chunk of cells, for both looks and collision, rebuilt as it changes.

enum K { GROUND, WATER, LEDGE, ICE_TOP, ICE_SIDE }

const CELL := 0.35
const CHUNK := 8
# Litres of water per m³ of ice. Real ice takes 917; the owner set ice wall to a tenth of that so it can
# build at a useful scale (a game allowance, like the stream's look).
const ICE_L_PER_M3 := 91.7
const RAISE := 0.9             # m/s a column rises while aimed at
const MAX_H := 4.0
const BRUSH := 0.42            # m: cells whose centres are this close to the aim point are affected
const SLAB_DOWN := 0.32        # a floating slab reaches this far below the waterline
const SLAB_UP := 0.08          # and stands this far above it
const LINK := 0.5              # m: neighbouring tops closer than this join in one smooth surface

static var inst: IceField

var cells := {}                # Vector2i -> {"b": base, "t": top, "src": water body it grew from or null}
var _chunks := {}              # Vector2i -> [MeshInstance3D, CollisionShape3D]
var _dirty := {}
var _rebuild_t := 0.0

var highlighted := false
var capacity := 1.0e9
var level: float:
	get:
		var l := 0.0
		for c in cells.values():
			l += (c["t"] - c["b"]) * CELL * CELL * ICE_L_PER_M3
		return l
var _aim_c := Vector2i.ZERO
var _aim_ok := false
var _aim_p := Vector3.ZERO
var _draw_c := Vector2i.ZERO

func _ready() -> void:
	inst = self
	# ice can be drawn back up as water (a water source like any other)
	add_to_group("water_source")

# ---------------------------------------------------------------- as a water source

## The crosshair line on the ice: a hit on it counts as dead on (the cell it hits is remembered).
func aim_miss(o: Vector3, d: Vector3) -> Vector2:
	_aim_ok = false
	if cells.is_empty():
		return Vector2(1e9, 1e9)
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 40.0)
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit["collider"] != self:
		return Vector2(1e9, 1e9)
	var p: Vector3 = hit["position"]
	var c := cell_of(p - (hit["normal"] as Vector3) * 0.05)
	if not cells.has(c):
		return Vector2(1e9, 1e9)
	_aim_ok = true
	_aim_c = c
	_aim_p = p
	return Vector2(0.0, o.distance_to(p))

func near_point(p: Vector3) -> Vector3:
	return _aim_p if _aim_ok else p + Vector3(1e9, 0, 0)

func set_draw_point(_p: Vector3) -> void:
	_draw_c = _aim_c

func surface_point() -> Vector3:
	if cells.has(_draw_c):
		return centre(_draw_c) + Vector3(0, cells[_draw_c]["t"], 0)
	return _aim_p

## Drawn from: the ice melts from the top of the cell drawn from, then from its nearest neighbours.
func take(litres: float) -> float:
	var left := litres
	var guard := 0
	while left > 0.0001 and guard < 12:
		guard += 1
		if not cells.has(_draw_c):
			var best := Vector2i.ZERO
			var bd := INF
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					var n := _draw_c + Vector2i(dx, dz)
					if cells.has(n) and Vector2(dx, dz).length() < bd:
						bd = Vector2(dx, dz).length()
						best = n
			if bd == INF:
				break
			_draw_c = best
		var e: Dictionary = cells[_draw_c]
		var have: float = (e["t"] - e["b"]) * CELL * CELL * ICE_L_PER_M3
		if have <= left + 0.01:
			left -= have
			cells.erase(_draw_c)
		else:
			e["t"] -= left / (CELL * CELL * ICE_L_PER_M3)
			left = 0.0
		_mark(_draw_c)
	return litres - left

## Water cannot freeze back by itself: it lands as a puddle.
func give(litres: float) -> void:
	Puddle.add_at(surface_point(), litres, get_tree(), get_parent())

static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

static func centre(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)

func src_at(p: Vector3, n: Vector3):
	var c := cell_of(p - n * 0.05)
	if cells.has(c):
		var s = cells[c]["src"]
		return s if s != null and is_instance_valid(s) else null
	return null

## Freezes ice at p (surface normal n) for dt seconds, using at most budget litres of water. Returns the
## litres used.
func paint(p: Vector3, n: Vector3, kind: int, src, dt: float, budget: float) -> float:
	var hit_c := cell_of(p - n * 0.05)
	var targets := []
	match kind:
		K.LEDGE:
			var lp := p + Vector3(n.x, 0, n.z).normalized() * CELL * 0.55
			for c in _brush(lp):
				targets.append([c, lp.y - 0.12, lp.y + 0.12])
		K.ICE_SIDE:
			if not cells.has(hit_c):
				return 0.0
			var top: float = cells[hit_c]["t"]
			var hn := Vector3(n.x, 0, n.z).normalized()
			var ep := p + hn * CELL * 0.6
			for c in _brush(ep):
				if c != hit_c:
					targets.append([c, top - 0.3, top])
		K.WATER:
			for c in _brush(p):
				targets.append([c, p.y - SLAB_DOWN, p.y + SLAB_UP])
		_:
			for c in _brush(p):
				targets.append([c, p.y - 0.05, p.y + 0.12])
	var want := 0.0
	var plan := []
	for t in targets:
		var c: Vector2i = t[0]
		var fall := clampf(1.0 - Vector3(centre(c).x - p.x, 0, centre(c).z - p.z).length() / (BRUSH + CELL), 0.3, 1.0)
		if cells.has(c):
			var e: Dictionary = cells[c]
			# raised where aimed: the column grows upward
			if kind == K.GROUND or kind == K.ICE_TOP or kind == K.WATER:
				var nt := minf(e["t"] + RAISE * dt * fall, e["b"] + MAX_H)
				plan.append([c, e["b"], nt, e["src"]])
				want += (nt - e["t"]) * CELL * CELL * ICE_L_PER_M3
		else:
			plan.append([c, t[1], t[2], src if kind == K.WATER else null])
			want += (t[2] - t[1]) * CELL * CELL * ICE_L_PER_M3
	if want <= 0.0 or budget <= 0.0:
		return 0.0
	# nearest cells first; the water runs out before the farther ones when there is not enough
	var p2 := Vector2(p.x, p.z)
	plan.sort_custom(func(a, b): return Vector2(centre(a[0]).x, centre(a[0]).z).distance_to(p2) < Vector2(centre(b[0]).x, centre(b[0]).z).distance_to(p2))
	var left := budget
	for e in plan:
		var c: Vector2i = e[0]
		if cells.has(c):
			var old: Dictionary = cells[c]
			var cost: float = (e[2] - old["t"]) * CELL * CELL * ICE_L_PER_M3
			var f := minf(1.0, left / maxf(cost, 1e-6))
			var nt: float = old["t"] + (e[2] - old["t"]) * f
			left -= (nt - old["t"]) * CELL * CELL * ICE_L_PER_M3
			old["t"] = nt
		else:
			var cost: float = (e[2] - e[1]) * CELL * CELL * ICE_L_PER_M3
			if cost > left:
				continue
			cells[c] = {"b": e[1], "t": e[2], "src": e[3]}
			left -= cost
		_mark(c)
		if left <= 0.0:
			break
	return budget - left

func _brush(p: Vector3) -> Array:
	var out := []
	var c0 := cell_of(p)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var c := c0 + Vector2i(dx, dz)
			var cc := centre(c)
			if Vector2(cc.x - p.x, cc.z - p.z).length() <= BRUSH or c == c0:
				out.append(c)
	return out

func _mark(c: Vector2i) -> void:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var n := c + Vector2i(dx, dz)
			_dirty[Vector2i(floori(float(n.x) / CHUNK), floori(float(n.y) / CHUNK))] = true

func _process(dt: float) -> void:
	_rebuild_t -= dt
	if _dirty.is_empty() or _rebuild_t > 0.0:
		return
	_rebuild_t = 0.08
	for ch in _dirty.keys():
		_build_chunk(ch)
	_dirty.clear()

# ---------------------------------------------------------------- mesh

func _linked(a: Dictionary, c: Vector2i) -> bool:
	return cells.has(c) and absf(cells[c]["t"] - a["t"]) < LINK and absf(cells[c]["b"] - a["b"]) < LINK + 0.6

## Height of the top surface at the corner of cell c at offset (ox, oz) in {0, 1}: the average of the
## tops of the cells meeting there that join this one.
func _corner(c: Vector2i, ox: int, oz: int) -> float:
	var e: Dictionary = cells[c]
	var s: float = e["t"]
	var n := 1
	for d in [Vector2i(ox * 2 - 1, 0), Vector2i(0, oz * 2 - 1), Vector2i(ox * 2 - 1, oz * 2 - 1)]:
		var nb: Vector2i = c + d
		if _linked(e, nb):
			s += cells[nb]["t"]
			n += 1
	return s / n

func _tri(v: PackedVector3Array, nm: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-10:
		return
	# Godot front faces are clockwise as seen from outside
	if fn.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		fn = -fn
	var n := -fn.normalized()
	v.append_array([a, b, c])
	nm.append_array([n, n, n])

func _quad(v: PackedVector3Array, nm: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	_tri(v, nm, a, b, c, out)
	_tri(v, nm, a, c, d, out)

func _build_chunk(ch: Vector2i) -> void:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	for x in range(ch.x * CHUNK, ch.x * CHUNK + CHUNK):
		for z in range(ch.y * CHUNK, ch.y * CHUNK + CHUNK):
			var c := Vector2i(x, z)
			if not cells.has(c):
				continue
			var e: Dictionary = cells[c]
			var b: float = e["b"]
			var x0 := x * CELL
			var x1 := x0 + CELL
			var z0 := z * CELL
			var z1 := z0 + CELL
			var h00 := _corner(c, 0, 0)
			var h10 := _corner(c, 1, 0)
			var h11 := _corner(c, 1, 1)
			var h01 := _corner(c, 0, 1)
			var t00 := Vector3(x0, h00, z0)
			var t10 := Vector3(x1, h10, z0)
			var t11 := Vector3(x1, h11, z1)
			var t01 := Vector3(x0, h01, z1)
			_quad(v, nm, t00, t10, t11, t01, Vector3.UP)
			_quad(v, nm, Vector3(x0, b, z0), Vector3(x1, b, z0), Vector3(x1, b, z1), Vector3(x0, b, z1), Vector3.DOWN)
			# sides where the neighbour does not continue the surface
			if not _linked(e, c + Vector2i(0, -1)):
				_quad(v, nm, Vector3(x0, b, z0), Vector3(x1, b, z0), t10, t00, Vector3.BACK * -1.0)
			if not _linked(e, c + Vector2i(0, 1)):
				_quad(v, nm, Vector3(x0, b, z1), Vector3(x1, b, z1), t11, t01, Vector3.BACK)
			if not _linked(e, c + Vector2i(-1, 0)):
				_quad(v, nm, Vector3(x0, b, z0), Vector3(x0, b, z1), t01, t00, Vector3.LEFT)
			if not _linked(e, c + Vector2i(1, 0)):
				_quad(v, nm, Vector3(x1, b, z0), Vector3(x1, b, z1), t11, t10, Vector3.RIGHT)
	if not _chunks.has(ch):
		var mi := MeshInstance3D.new()
		mi.material_override = IceSpike.ice_material()
		add_child(mi)
		var cs := CollisionShape3D.new()
		add_child(cs)
		_chunks[ch] = [mi, cs]
	var mi: MeshInstance3D = _chunks[ch][0]
	var cs: CollisionShape3D = _chunks[ch][1]
	if v.size() == 0:
		mi.mesh = null
		cs.shape = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(v)
	cs.shape = sh
