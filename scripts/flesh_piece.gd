class_name FleshPiece
extends RigidBody3D
## A loose part of a person (or a whole one gone limp): their posed mesh as triangles in this body's
## space (surf: per surface [p, n, ...]; surface 2 is cut flesh), with a convex hull to collide. It can
## be cut again (slice_by) and grabbed, lashed and floated like any loose body. Gone after life seconds (game time), with
## the person it came from.

const HULL_POINTS := 96

var surf := []
var mats := []
var life := -1.0
var _mi: MeshInstance3D

func _ready() -> void:
	add_to_group("crate")
	add_to_group("flesh")
	continuous_cd = true
	angular_damp = 0.6
	_mi = MeshInstance3D.new()
	add_child(_mi)
	_rebuild()

func _rebuild() -> void:
	var m := ArrayMesh.new()
	var hull := PackedVector3Array()
	var all := PackedVector3Array()
	for si in surf.size():
		var s: Array = surf[si]
		if s.size() < 6:
			continue
		var v := PackedVector3Array()
		var nm := PackedVector3Array()
		for i in range(0, s.size(), 2):
			v.append(s[i])
			nm.append(s[i + 1])
		all.append_array(v)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nm
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, mats[si])
	_mi.mesh = m
	var step := maxi(all.size() / HULL_POINTS, 1)
	for i in range(0, all.size(), step):
		hull.append(all[i])
	for ch in get_children():
		if ch is CollisionShape3D:
			ch.queue_free()
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = hull
	cs.shape = sh
	add_child(cs)

func _process(dt: float) -> void:
	if life >= 0.0:
		life -= dt
		if life <= 0.0:
			queue_free()

func tri_count() -> int:
	var n := 0
	for s in surf:
		n += (s as Array).size() / 6
	return n

## The blade's plane through this piece: it splits in two, each closed with flesh where it was cut.
## Returns the new piece (in an array), or [] when the plane misses.
func slice_by(p: Vector3, n: Vector3, _side: Vector3, _w: float, dir: Vector3) -> Array:
	var inv := global_transform.affine_inverse()
	var lp := inv * p
	var ln := (inv.basis * n).normalized()
	var front := [[], [], []]
	var back := [[], [], []]
	var cut_pts := PackedVector3Array()
	for si in surf.size():
		var s: Array = surf[si]
		for i in range(0, s.size(), 6):
			var ps := [s[i], s[i + 2], s[i + 4]]
			var ns := [s[i + 1], s[i + 3], s[i + 5]]
			var sd := [ln.dot(ps[0] - lp), ln.dot(ps[1] - lp), ln.dot(ps[2] - lp)]
			if sd[0] >= 0.0 and sd[1] >= 0.0 and sd[2] >= 0.0:
				front[si].append_array([ps[0], ns[0], ps[1], ns[1], ps[2], ns[2]])
			elif sd[0] <= 0.0 and sd[1] <= 0.0 and sd[2] <= 0.0:
				back[si].append_array([ps[0], ns[0], ps[1], ns[1], ps[2], ns[2]])
			else:
				var r := Flesh.clip_tri(ps, ns, sd)
				front[si].append_array(r[0])
				back[si].append_array(r[1])
				if (r[2] as Array).size() == 2:
					cut_pts.append(r[2][0])
					cut_pts.append(r[2][1])
	var nf := 0
	var nbk := 0
	for si in 3:
		nf += (front[si] as Array).size()
		nbk += (back[si] as Array).size()
	if nf < 18 or nbk < 18:
		return []
	Flesh.cap(cut_pts, -ln, front[2])
	Flesh.cap(cut_pts, ln, back[2])
	var total := tri_count()
	# this body keeps the back; the front becomes a new piece
	var wf := []
	for si in 3:
		var l := []
		var s: Array = front[si]
		for i in range(0, s.size(), 2):
			l.append(global_transform * (s[i] as Vector3))
			l.append(global_transform.basis * (s[i + 1] as Vector3))
		wf.append(l)
	var m0 := mass
	surf = back
	mass = maxf(m0 * float(nbk) / float(nf + nbk), 0.3)
	_rebuild()
	var piece := Flesh.make_piece(get_parent(), wf, mats, linear_velocity + n * 0.6 + dir * 0.8, life, total)
	if piece == null:
		return []
	piece.mass = maxf(m0 * float(nf) / float(nf + nbk), 0.3)
	var c := Vector3.ZERO
	for q in cut_pts:
		c += q
	c = global_transform * (c / maxf(cut_pts.size(), 1))
	var secs := maxf(life, 0.5)
	Flesh.spray(self, inv * c, ln, minf(secs, 3.0), 0.6)
	Flesh.splats(get_parent(), c, secs, 2)
	return [piece]
