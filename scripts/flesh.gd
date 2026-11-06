class_name Flesh
## Cutting people. A person's skinned mesh is baked in its current pose (world space) with each
## vertex's main bone, then split by the blade's plane:
##  - bones whose segment the plane crosses within the blade's width are cut; the skeleton falls apart into
##    groups of bones joined on the same side (a union-find over (bone, side) nodes);
##  - each triangle goes to the group of its main bone on its side of the plane; triangles that cross
##    the plane near a cut are clipped, and the cut edges become the caps (flesh) of each group;
##  - every group but the one with the pelvis becomes a loose FleshPiece. The person lives on (an
##    amputee) if the pelvis group still has the head and both feet; otherwise the rest falls too.
## Also: blood (sprays from cut faces, splats on the ground) and pieces' further cuts (FleshPiece).

const REASSIGN := 0.25          # m: flesh of an uncut bone this close to a cut is split with it
const LIFE := 5.0               # s a hurt person and everything from them stays before despawning
const KG := 60.0                # a whole person
const SPLAT_N := 4

static var _mats := {}

static func cap_material() -> StandardMaterial3D:
	if not _mats.has("cap"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.04, 0.05)
		m.roughness = 0.45
		m.metallic_specular = 0.7
		_mats["cap"] = m
	return _mats["cap"]

static func blood_material() -> StandardMaterial3D:
	if not _mats.has("blood"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.01, 0.02, 0.92)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.2
		_mats["blood"] = m
	return _mats["blood"]

# ---------------------------------------------------------------- baking

## The skinned mesh in its current pose, in world space: per surface {P, N, D (main bone of each vertex),
## I (indices)}.
## Skinned here on the CPU (bone pose x bind pose, blended by the weights) rather than with
## MeshInstance3D.bake_mesh_from_current_skeleton_pose, which needs the skin registered with the renderer
## and so fails in headless test runs.
static func bake(mi: MeshInstance3D, sk: Skeleton3D, poses: Array = []) -> Array:
	var skin := mi.skin
	var bind_bone := PackedInt32Array()
	var M: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bb := skin.get_bind_bone(i)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(i))
		bind_bone.append(bb)
		M.append(sk.global_transform * _gp(sk, poses, maxi(bb, 0)) * skin.get_bind_pose(i))
	var out := []
	for s in mi.mesh.get_surface_count():
		var oa := mi.mesh.surface_get_arrays(s)
		var V: PackedVector3Array = oa[Mesh.ARRAY_VERTEX]
		var VN: PackedVector3Array = oa[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = oa[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = oa[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(V.size(), 1)
		var P := PackedVector3Array()
		var N := PackedVector3Array()
		var D := PackedInt32Array()
		P.resize(V.size())
		N.resize(V.size())
		D.resize(V.size())
		for v in V.size():
			var p := Vector3.ZERO
			var nr := Vector3.ZERO
			var best := 0
			var bw := -1.0
			for k in per:
				var w := wts[v * per + k]
				if w <= 0.0:
					continue
				var bi := bones[v * per + k]
				var m := M[bi]
				p += (m * V[v]) * w
				nr += (m.basis * VN[v]) * w
				if w > bw:
					bw = w
					best = bi
			P[v] = p
			N[v] = nr.normalized()
			D[v] = bind_bone[best]
		out.append({"P": P, "N": N, "D": D, "I": oa[Mesh.ARRAY_INDEX]})
	return out

## Each bone's segment in world space: [origin, tip]. A bone's tip is the middle of its children's
## origins; a leaf bone reaches a little past its origin.
static func _gp(sk: Skeleton3D, poses: Array, b: int) -> Transform3D:
	return poses[b] if b < poses.size() else sk.get_bone_global_pose(b)

static func segments(sk: Skeleton3D, poses: Array = []) -> Array:
	var segs := []
	var xf := sk.global_transform
	for b in sk.get_bone_count():
		var o := xf * _gp(sk, poses, b).origin
		var kids := sk.get_bone_children(b)
		var tip := Vector3.ZERO
		if kids.is_empty():
			var par := sk.get_bone_parent(b)
			var dir := (o - xf * _gp(sk, poses, par).origin).normalized() if par >= 0 else Vector3.UP
			tip = o + dir * 0.08
		else:
			for c in kids:
				tip += xf * _gp(sk, poses, c).origin
			tip /= kids.size()
		segs.append([o, tip])
	return segs

# ---------------------------------------------------------------- clipping

## A triangle split by the plane (sides sa, sb, sc). Returns [front tris, back tris, cut segment], tris as
## flat arrays [p0, n0, p1, n1, p2, n2, ...]; the segment is the two points where the plane crosses it.
static func clip_tri(p: Array, nr: Array, s: Array) -> Array:
	var front := []
	var back := []
	var fpoly := []
	var bpoly := []
	var seg := []
	for i in 3:
		var j := (i + 1) % 3
		if s[i] >= 0.0:
			fpoly.append([p[i], nr[i]])
		if s[i] <= 0.0:
			bpoly.append([p[i], nr[i]])
		if (s[i] > 0.0 and s[j] < 0.0) or (s[i] < 0.0 and s[j] > 0.0):
			var t: float = s[i] / (s[i] - s[j])
			var q: Vector3 = (p[i] as Vector3).lerp(p[j], t)
			var qn: Vector3 = (nr[i] as Vector3).lerp(nr[j], t).normalized()
			fpoly.append([q, qn])
			bpoly.append([q, qn])
			seg.append(q)
	for poly_out in [[fpoly, front], [bpoly, back]]:
		var poly: Array = poly_out[0]
		var dst: Array = poly_out[1]
		for k in range(1, poly.size() - 1):
			dst.append_array([poly[0][0], poly[0][1], poly[k][0], poly[k][1], poly[k + 1][0], poly[k + 1][1]])
	return [front, back, seg]

## A cap closing a cut: a fan over the cut points (sorted round their middle in the plane), facing out
## along outward. Appends to tris as [p, n, ...].
static func cap(points: PackedVector3Array, outward: Vector3, tris: Array) -> void:
	if points.size() < 3:
		return
	var c := Vector3.ZERO
	for q in points:
		c += q
	c /= points.size()
	var u := outward.cross(Vector3.UP)
	if u.length() < 0.1:
		u = outward.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := outward.cross(u)
	var order := []
	for q in points:
		var d: Vector3 = q - c
		order.append([atan2(d.dot(v), d.dot(u)), q])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for k in order.size():
		var a: Vector3 = order[k][1]
		var b: Vector3 = order[(k + 1) % order.size()][1]
		if a.distance_squared_to(b) < 1e-8:
			continue
		# Godot front faces are clockwise: (b-a)x(c-a) points inward
		if (a - c).cross(b - c).dot(outward) > 0.0:
			tris.append_array([c, outward, b, outward, a, outward])
		else:
			tris.append_array([c, outward, a, outward, b, outward])

# ---------------------------------------------------------------- cutting a person

## Cuts baked (world) along the plane through p with normal n; the blade is w wide along side. Returns
## {groups: {root id: {"surf": [tris per surface + caps as surface 2], "bones": [...]}}, "root": id,
## "cut": {bone: t along its segment}, "alive": bool} or {} when no bone was cut (only a wound).
## dir: the blade's flight. When given, only the bones it meets first (within FIRST_DEPTH along dir of the
## first) are cut: the blade spends itself on them.
const FIRST_DEPTH := 0.14
const FIRST_NEAR := 0.15
static func cut_person(baked: Array, sk: Skeleton3D, p: Vector3, n: Vector3, side: Vector3, w: float, poses: Array = [], dir := Vector3.ZERO) -> Dictionary:
	var segs := segments(sk, poses)
	var nb := sk.get_bone_count()
	var bside := PackedFloat32Array()
	bside.resize(nb)
	var cutb := {}                    # bone -> crossing point
	var cut_t := {}
	var skx := sk.global_transform
	for b in nb:
		var o: Vector3 = segs[b][0]
		var so := n.dot(o - p)
		bside[b] = 1.0 if so >= 0.0 else -1.0
		# each link from the bone to a child (the pelvis reaches up the spine and down each leg), or to
		# its tip for a leaf; the plane crossing any of them within the blade cuts the bone
		var ends := []
		for c in sk.get_bone_children(b):
			ends.append(skx * _gp(sk, poses, c).origin)
		if ends.is_empty():
			ends.append(segs[b][1])
		var bd := INF
		for q in ends:
			var sq := n.dot((q as Vector3) - p)
			if (so > 0.0) == (sq > 0.0) or absf(so - sq) < 1e-5:
				continue
			var t := so / (so - sq)
			var x := o.lerp(q, t)
			if absf((x - p).dot(side)) <= w * 0.5 and x.distance_to(p) < bd:
				bd = x.distance_to(p)
				cutb[b] = x
				cut_t[b] = t
	if cutb.is_empty():
		return {}
	if dir != Vector3.ZERO:
		# the part met first, and only bones right by it (the same limb)
		var first := INF
		var fx := Vector3.ZERO
		for cb in cutb:
			var dd := (cutb[cb] as Vector3).dot(dir)
			if dd < first:
				first = dd
				fx = cutb[cb]
		for cb in cutb.keys():
			var x: Vector3 = cutb[cb]
			if x.dot(dir) > first + FIRST_DEPTH or x.distance_to(fx) > FIRST_NEAR:
				cutb.erase(cb)
				cut_t.erase(cb)
	# union-find over (bone, side part) nodes. A plain Array: the lambdas below must share it (a packed
	# array would be copied into each)
	var parent := []
	for i in nb * 2:
		parent.append(i)
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for c in nb:
		var pb := sk.get_bone_parent(c)
		if pb < 0:
			continue
		var j := 1.0 if n.dot(segs[c][0] - p) >= 0.0 else -1.0
		var pn := pb * 2 + (1 if cutb.has(pb) and j != bside[pb] else 0)
		var a: int = find.call(pn)
		var bb: int = find.call(c * 2)
		if a != bb:
			parent[a] = bb
	var node_for := func(b: int, s: float) -> int:
		if cutb.has(b):
			return b * 2 + (0 if s == bside[b] else 1)
		return b * 2
	var cut_list := cutb.keys()
	var nearest_cut := func(q: Vector3) -> Array:
		var best := -1
		var bd := INF
		for cb in cut_list:
			var d := q.distance_to(cutb[cb])
			if d < bd:
				bd = d
				best = cb
		return [best, bd]
	var groups := {}                 # group id -> {"surf": [[], [], []], "caps": {key: PackedVector3Array}}
	var add := func(g: int, s: int, tris: Array) -> void:
		var gid: int = find.call(g)
		if not groups.has(gid):
			groups[gid] = {"surf": [[], [], []], "caps": {}}
		(groups[gid]["surf"][s] as Array).append_array(tris)
	var add_cap := func(g: int, key: int, a: Vector3, b: Vector3, s: float) -> void:
		var gid: int = find.call(g)
		if not groups.has(gid):
			groups[gid] = {"surf": [[], [], []], "caps": {}}
		var k := key * 2 + (1 if s > 0.0 else 0)
		if not groups[gid]["caps"].has(k):
			groups[gid]["caps"][k] = PackedVector3Array()
		groups[gid]["caps"][k].append(a)
		groups[gid]["caps"][k].append(b)
	for si in baked.size():
		var P: PackedVector3Array = baked[si]["P"]
		var N: PackedVector3Array = baked[si]["N"]
		var D: PackedInt32Array = baked[si]["D"]
		var I: PackedInt32Array = baked[si]["I"]
		for t in range(0, I.size(), 3):
			var ia := I[t]
			var ib := I[t + 1]
			var ic := I[t + 2]
			var b := D[ib] if D[ib] == D[ic] else D[ia]
			var sa := n.dot(P[ia] - p)
			var sb := n.dot(P[ib] - p)
			var sc := n.dot(P[ic] - p)
			var tri := [P[ia], N[ia], P[ib], N[ib], P[ic], N[ic]]
			var centroid := (P[ia] + P[ib] + P[ic]) / 3.0
			var near := cutb.has(b)
			var nc := [-1, INF]
			if not near:
				nc = nearest_cut.call(centroid)
				near = float(nc[1]) < REASSIGN
			var allpos := sa >= 0.0 and sb >= 0.0 and sc >= 0.0
			var allneg := sa <= 0.0 and sb <= 0.0 and sc <= 0.0
			if allpos or allneg or not near:
				var s := 1.0 if allpos else (-1.0 if allneg else bside[b])
				var g: int
				if cutb.has(b):
					g = node_for.call(b, s)
				elif s == bside[b] or not near:
					g = b * 2
				else:
					g = node_for.call(nc[0], s)
				add.call(g, si, tri)
				continue
			var r := clip_tri([P[ia], P[ib], P[ic]], [N[ia], N[ib], N[ic]], [sa, sb, sc])
			var key: int = b if cutb.has(b) else int(nc[0])
			var gf: int = node_for.call(b, 1.0) if cutb.has(b) else (b * 2 if bside[b] > 0.0 else node_for.call(key, 1.0))
			var gb: int = node_for.call(b, -1.0) if cutb.has(b) else (b * 2 if bside[b] < 0.0 else node_for.call(key, -1.0))
			add.call(gf, si, r[0])
			add.call(gb, si, r[1])
			if (r[2] as Array).size() == 2:
				add_cap.call(gf, key, r[2][0], r[2][1], 1.0)
				add_cap.call(gb, key, r[2][0], r[2][1], -1.0)
	# caps: the piece in front of the plane is closed by a face looking back along -n, and so on
	for gid in groups:
		var caps: Dictionary = groups[gid]["caps"]
		for k in caps:
			cap(caps[k], -n if k % 2 == 1 else n, groups[gid]["surf"][2])
	var root: int = find.call(sk.find_bone("pelvis") * 2)
	var alive: bool = find.call(sk.find_bone("Head") * 2) == root \
			and find.call(sk.find_bone("foot_l") * 2) == root and find.call(sk.find_bone("foot_r") * 2) == root
	# the bones to hide on a living amputee: each cut bone whose far part went, and what hangs below it
	var hide := {}
	if alive:
		for cb in cutb:
			var far: int = cb * 2 + 1
			if find.call(far) != root:
				hide[cb] = cut_t[cb]
	return {"groups": groups, "root": root, "alive": alive, "hide": hide, "caps_root": groups.get(root, {}).get("caps", {}), "n": n}

# ---------------------------------------------------------------- blood

## A spray of blood from a cut face, for secs seconds, along normal (local to parent).
static func spray(parent: Node3D, at: Vector3, normal: Vector3, secs: float, strength := 1.0) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = int(90 * strength) + 10
	g.lifetime = 0.9
	g.explosiveness = 0.1
	g.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 28.0
	pm.initial_velocity_min = 1.2 * strength
	pm.initial_velocity_max = 3.2 * strength
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	g.process_material = pm
	var qm := SphereMesh.new()
	qm.radius = 0.012
	qm.height = 0.024
	qm.radial_segments = 4
	qm.rings = 2
	qm.material = blood_material()
	g.draw_pass_1 = qm
	parent.add_child(g)
	g.position = at
	# the emitter's up along the cut's outward normal
	var nn := normal.normalized()
	var x := nn.cross(Vector3.FORWARD)
	if x.length() < 0.1:
		x = nn.cross(Vector3.RIGHT)
	x = x.normalized()
	g.basis = Basis(x, nn, x.cross(nn))
	g.emitting = true
	# bound to the emitter, so the call is dropped if it is freed first
	g.get_tree().create_timer(secs).timeout.connect(Callable(g, "set").bind("emitting", false))
	return g

## Blood on the ground under p: a few dark splats, gone after secs.
static func splats(world: Node, p: Vector3, secs: float, count := SPLAT_N) -> void:
	var space := (world as Node3D).get_world_3d().direct_space_state
	for i in count:
		var at := p + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 4.0)
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit["collider"] is RigidBody3D or (hit["collider"] as Node).is_in_group("person"):
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := randf_range(0.06, 0.22)
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.004
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = blood_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(randf_range(0.7, 1.4), 1.0, randf_range(0.7, 1.4))
		world.add_child(mi)
		mi.global_position = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.004
		mi.rotation.y = randf_range(0, TAU)
		world.get_tree().create_timer(secs).timeout.connect(mi.queue_free)

# ---------------------------------------------------------------- pieces

## A loose body from world-space triangles (per surface: [p, n, ...]; surface 2 is cut flesh), with
## materials mats (one per surface), a share of KG by its size, moving at vel. Despawns after life seconds.
static func make_piece(world: Node, surf: Array, mats: Array, vel: Vector3, life: float, total_tris: int) -> FleshPiece:
	var c := Vector3.ZERO
	var cnt := 0
	for s in surf:
		for i in range(0, (s as Array).size(), 2):
			c += s[i]
			cnt += 1
	if cnt < 9:
		return null
	c /= cnt
	var local := []
	var tris := 0
	for s in surf:
		var l := []
		for i in range(0, (s as Array).size(), 2):
			l.append((s[i] as Vector3) - c)
			l.append(s[i + 1])
		local.append(l)
		tris += (s as Array).size() / 6
	var fp := FleshPiece.new()
	fp.surf = local
	fp.mats = mats
	fp.life = life
	fp.mass = maxf(KG * float(tris) / maxf(total_tris, 1), 0.4)
	world.add_child(fp)
	fp.global_position = c
	fp.linear_velocity = vel
	return fp
