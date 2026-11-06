class_name Tube
## Mesh helpers for water shapes: a loft through elliptical rings, and a round tube along a path (the
## water shader reads UV.x as distance along the flow).

## Adds a loft to the arrays in `a` ({v, n, uv, c, i}). rings: [centre, axis_a, a, axis_b, b] with unit
## axes across the section. Ends are closed with a fan when cap_start / cap_end.
static func loft(a: Dictionary, rings: Array, sides: int, flow: float, cap_start := false, cap_end := false) -> void:
	if rings.size() < 2:
		return
	var v: PackedVector3Array = a["v"]
	var nm: PackedVector3Array = a["n"]
	var uv: PackedVector2Array = a["uv"]
	var col: PackedColorArray = a["c"]
	var idx: PackedInt32Array = a["i"]
	var base := v.size()
	var s := 0.0
	for j in rings.size():
		var r: Array = rings[j]
		if j > 0:
			s += (r[0] as Vector3).distance_to(rings[j - 1][0])
		var c: Vector3 = r[0]
		var ea: Vector3 = r[1]
		var ra: float = maxf(r[2], 0.002)
		var eb: Vector3 = r[3]
		var rb: float = maxf(r[4], 0.002)
		for k in sides + 1:
			var th := TAU * float(k) / sides
			v.append(c + ea * (cos(th) * ra) + eb * (sin(th) * rb))
			nm.append((ea * (cos(th) / ra) + eb * (sin(th) / rb)).normalized())
			uv.append(Vector2(s - flow, th))
			col.append(Color(0, 0, 0, 1))
	for j in rings.size() - 1:
		for k in sides:
			var i0 := base + j * (sides + 1) + k
			var i1 := i0 + sides + 1
			idx.append_array([i0, i0 + 1, i1, i0 + 1, i1 + 1, i1])
	for e in [[cap_start, 0, -1.0], [cap_end, rings.size() - 1, 1.0]]:
		if not e[0]:
			continue
		var j: int = e[1]
		var r: Array = rings[j]
		var other: Vector3 = rings[j - 1 if j > 0 else 1][0]
		var out: Vector3 = ((r[0] as Vector3) - other).normalized()
		var ci := v.size()
		v.append(r[0])
		nm.append(out)
		uv.append(Vector2(s, 0))
		col.append(Color(0, 0, 0, 1))
		var ring0 := base + j * (sides + 1)
		for k in sides:
			# Godot front faces are clockwise as seen from outside
			var p0 := v[ring0 + k]
			var p1 := v[ring0 + k + 1]
			if (p0 - v[ci]).cross(p1 - v[ci]).dot(out) > 0.0:
				idx.append_array([ci, ring0 + k + 1, ring0 + k])
			else:
				idx.append_array([ci, ring0 + k, ring0 + k + 1])
	a["v"] = v
	a["n"] = nm
	a["uv"] = uv
	a["c"] = col
	a["i"] = idx

## Rings for a round tube along pts with the given radii (parallel-transported frames).
static func round_rings(pts: PackedVector3Array, radii: PackedFloat32Array) -> Array:
	var rings := []
	var nrm := Vector3.ZERO
	for j in pts.size():
		var t := (pts[mini(j + 1, pts.size() - 1)] - pts[maxi(j - 1, 0)]).normalized()
		if j == 0:
			nrm = t.cross(Vector3.UP)
			if nrm.length() < 0.01:
				nrm = t.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
		else:
			nrm = (nrm - t * nrm.dot(t)).normalized()
		rings.append([pts[j], nrm, radii[j], t.cross(nrm), radii[j]])
	return rings

static func arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"c": PackedColorArray(), "i": PackedInt32Array()}

## Replaces mesh's surfaces with what `a` holds.
static func commit(mesh: ArrayMesh, a: Dictionary) -> void:
	mesh.clear_surfaces()
	if (a["i"] as PackedInt32Array).is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["v"]
	arr[Mesh.ARRAY_NORMAL] = a["n"]
	arr[Mesh.ARRAY_TEX_UV] = a["uv"]
	arr[Mesh.ARRAY_COLOR] = a["c"]
	arr[Mesh.ARRAY_INDEX] = a["i"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

static func water_material(flow_speed := 3.0, tint := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("flow_speed", flow_speed)
	m.set_shader_parameter("tint_amount", tint)
	return m
