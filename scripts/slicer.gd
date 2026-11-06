class_name Slicer
## Cuts rigid bodies along a plane. A sliceable body keeps its shape as convex parts in its meta "parts":
##   [{ "faces": [{ "p": PackedVector3Array (body-local, in order), "n": Vector3 outward, "cap": bool }],
##      "color": Color, "cap_color": Color }]
## and "stuff" ("wood", "straw") for what shows where it is cut. Cutting splits every part the plane
## crosses into two convex parts, closes each with a cap face, and gives the parts on one side to a new
## body. Mass is shared by volume; both halves keep the body's motion.

const EPS := 0.0005
const MIN_VOL := 4e-5          # m^3 (40 cm^3): smaller pieces are not kept

# ---------------------------------------------------------------- building shapes

static func box_faces(h: Vector3, c := Vector3.ZERO) -> Array:
	var f := []
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var b := (ax + 1) % 3
			var cc := (ax + 2) % 3
			var n := Vector3.ZERO
			n[ax] = sg
			var p := PackedVector3Array()
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var v := Vector3.ZERO
				v[ax] = sg * h[ax]
				v[b] = k[0] * h[b]
				v[cc] = k[1] * h[cc]
				p.append(c + v)
			f.append({"p": p, "n": n, "cap": false})
	return f

## A prism standing on y0 (radius r, height ht, sides sides).
static func prism_faces(r: float, ht: float, sides: int, y0: float) -> Array:
	var f := []
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		top.append(Vector3(cos(a) * r, y0 + ht, sin(a) * r))
		bot.append(Vector3(cos(a) * r, y0, sin(a) * r))
	f.append({"p": top, "n": Vector3.UP, "cap": false})
	f.append({"p": bot, "n": Vector3.DOWN, "cap": false})
	for i in sides:
		var j := (i + 1) % sides
		var a := TAU * (i + 1.0) / sides
		f.append({"p": PackedVector3Array([bot[i], bot[j], top[j], top[i]]), "n": Vector3(cos(a), 0, sin(a)), "cap": false})
	return f

static func part(faces: Array, color: Color, cap_color: Color) -> Dictionary:
	return {"faces": faces, "color": color, "cap_color": cap_color}

# ---------------------------------------------------------------- geometry

static func _points(faces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for f in faces:
		for v in (f["p"] as PackedVector3Array):
			var dup := false
			for w in out:
				if w.distance_squared_to(v) < EPS * EPS:
					dup = true
					break
			if not dup:
				out.append(v)
	return out

static func volume(faces: Array) -> float:
	var pts := _points(faces)
	if pts.size() < 4:
		return 0.0
	var c := Vector3.ZERO
	for v in pts:
		c += v
	c /= pts.size()
	var vol := 0.0
	for f in faces:
		var p: PackedVector3Array = f["p"]
		for i in range(1, p.size() - 1):
			vol += absf((p[0] - c).dot((p[i] - c).cross(p[i + 1] - c))) / 6.0
	return vol

## Splits a convex part's faces by the plane n.x = d. Returns [front faces, back faces]; either is empty
## when the plane misses the part.
static func clip(faces: Array, n: Vector3, d: float) -> Array:
	var front := []
	var back := []
	var cut := PackedVector3Array()
	for f in faces:
		var p: PackedVector3Array = f["p"]
		var fp := PackedVector3Array()
		var bp := PackedVector3Array()
		for i in p.size():
			var a := p[i]
			var b := p[(i + 1) % p.size()]
			var da := n.dot(a) - d
			var db := n.dot(b) - d
			if da >= -EPS:
				fp.append(a)
			if da <= EPS:
				bp.append(a)
			if absf(da) <= EPS:
				cut.append(a)
			if (da > EPS and db < -EPS) or (da < -EPS and db > EPS):
				var x := a.lerp(b, da / (da - db))
				fp.append(x)
				bp.append(x)
				cut.append(x)
		if fp.size() >= 3:
			front.append({"p": fp, "n": f["n"], "cap": f["cap"]})
		if bp.size() >= 3:
			back.append({"p": bp, "n": f["n"], "cap": f["cap"]})
	# faces lying in the plane belong to one side only
	var fv := volume(front)
	var bv := volume(back)
	if fv < 1e-7 or bv < 1e-7:
		return [[], []]
	# the cut closes each side with a cap: the cut points ordered round their centre
	var cp := PackedVector3Array()
	for v in cut:
		var dup := false
		for w in cp:
			if w.distance_squared_to(v) < EPS * EPS * 4.0:
				dup = true
				break
		if not dup:
			cp.append(v)
	if cp.size() < 3:
		return [[], []]
	var c := Vector3.ZERO
	for v in cp:
		c += v
	c /= cp.size()
	var u := (cp[0] - c).normalized()
	var w2 := n.cross(u)
	var ang := []
	for v in cp:
		ang.append([atan2((v - c).dot(w2), (v - c).dot(u)), v])
	ang.sort_custom(func(x, y): return x[0] < y[0])
	var cap := PackedVector3Array()
	for e in ang:
		cap.append(e[1])
	front.append({"p": cap, "n": -n, "cap": true})
	back.append({"p": cap.duplicate(), "n": n, "cap": true})
	return [front, back]

# ---------------------------------------------------------------- bodies

## Replaces a body's meshes and collision shapes with ones built from its parts.
static func build(body: RigidBody3D) -> void:
	for ch in body.get_children():
		if ch is MeshInstance3D or ch is CollisionShape3D:
			body.remove_child(ch)
			ch.queue_free()
	for pa in body.get_meta("parts"):
		var faces: Array = pa["faces"]
		# a part may carry its own materials (ice)
		var outer: Material = pa["mat"] if pa.has("mat") else _mat(pa["color"])
		var inner: Material = pa["cap_mat"] if pa.has("cap_mat") else _mat(pa["cap_color"])
		var st_o := PackedVector3Array()
		var nm_o := PackedVector3Array()
		var st_i := PackedVector3Array()
		var nm_i := PackedVector3Array()
		for f in faces:
			var p: PackedVector3Array = f["p"]
			var n: Vector3 = f["n"]
			for i in range(1, p.size() - 1):
				var a := p[0]
				var b := p[i]
				var c := p[i + 1]
				# Godot front faces are clockwise as seen from outside
				if (b - a).cross(c - a).dot(n) > 0.0:
					var t := b
					b = c
					c = t
				if f["cap"]:
					st_i.append_array([a, b, c])
					nm_i.append_array([n, n, n])
				else:
					st_o.append_array([a, b, c])
					nm_o.append_array([n, n, n])
		var mesh := ArrayMesh.new()
		for s in [[st_o, nm_o, outer], [st_i, nm_i, inner]]:
			if (s[0] as PackedVector3Array).size() == 0:
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = s[0]
			arr[Mesh.ARRAY_NORMAL] = s[1]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[2])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		sh.points = _points(faces)
		cs.shape = sh
		body.add_child(cs)

static var _mats := {}
static func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.95
		_mats[c] = m
	return _mats[c]

## A part like pa (its colours and materials) with other faces.
static func _like(pa: Dictionary, faces: Array) -> Dictionary:
	var d := pa.duplicate()
	d["faces"] = faces
	return d

static func _total_volume(parts: Array) -> float:
	var v := 0.0
	for pa in parts:
		v += volume(pa["faces"])
	return v

## Cuts body along the world plane through point p with normal n. Returns the new body holding the
## parts in front of the plane, or null when the plane misses. The body keeps the back side, unless it
## defines keep_point() (a local point that must stay on it, such as where a dummy sits on its post).
static func cut(body: RigidBody3D, p: Vector3, n: Vector3) -> RigidBody3D:
	if not body.has_meta("parts"):
		return null
	var inv := body.global_transform.affine_inverse()
	var ln := (inv.basis * n).normalized()
	var ld := ln.dot(inv * p)
	var fr := []
	var bk := []
	var any_cut := false
	for pa in body.get_meta("parts"):
		var faces: Array = pa["faces"]
		var r := clip(faces, ln, ld)
		if not (r[0] as Array).is_empty():
			any_cut = true
			# a sliver too thin to hold as a solid is shaved off (it would upset the physics)
			if volume(r[0]) > MIN_VOL:
				fr.append(_like(pa, r[0]))
			if volume(r[1]) > MIN_VOL:
				bk.append(_like(pa, r[1]))
		else:
			# whole part on one side: which, by its centre
			var c := Vector3.ZERO
			var pts := _points(faces)
			for v in pts:
				c += v
			c /= maxf(pts.size(), 1)
			if ln.dot(c) > ld:
				fr.append(pa)
			else:
				bk.append(pa)
	if not any_cut or fr.is_empty() or bk.is_empty():
		return null
	var keep_back := true
	if body.has_method("keep_point"):
		keep_back = ln.dot(body.keep_point()) <= ld
	else:
		keep_back = _total_volume(bk) >= _total_volume(fr)
	var mine: Array = bk if keep_back else fr
	var other: Array = fr if keep_back else bk
	var vm := _total_volume(mine)
	var vo := _total_volume(other)
	if "--demo" in OS.get_cmdline_user_args():
		print("CUT %s keep=%d parts %.5f m3, off=%d parts %.5f m3" % [body.name, mine.size(), vm, other.size(), vo])
	if vm < MIN_VOL or vo < MIN_VOL:
		return null
	var total_m := body.mass
	body.set_meta("parts", mine)
	body.mass = maxf(total_m * vm / maxf(vm + vo, 1e-6), 0.2)
	build(body)
	# a body may make its own kind of piece (ice makes ice)
	var nb: RigidBody3D = body.make_piece() if body.has_method("make_piece") else RigidBody3D.new()
	nb.set_meta("parts", other)
	nb.set_meta("stuff", body.get_meta("stuff", "wood"))
	nb.mass = maxf(total_m * vo / maxf(vm + vo, 1e-6), 0.2)
	nb.continuous_cd = true
	nb.angular_damp = 0.3
	# a loose piece: grabbable and cuttable, but not whatever the body itself was (a dummy)
	if body.is_in_group("crate"):
		nb.add_to_group("crate")
	body.get_parent().add_child(nb)
	nb.global_transform = body.global_transform
	build(nb)
	nb.linear_velocity = body.linear_velocity
	nb.angular_velocity = body.angular_velocity
	# the two halves part along the cut
	var away := n if keep_back else -n
	nb.apply_central_impulse(away * nb.mass * 0.6)
	body.apply_central_impulse(-away * body.mass * 0.3)
	return nb
