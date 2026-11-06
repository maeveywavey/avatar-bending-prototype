class_name WaterShapes
extends RefCounted
## The numbers that set the shapes of the water, editable in Options > Visual > Edit Water Shapes.
## Each water thing is a group. Its LINES are the lines of its code that use those numbers, as they read in
## its script with every k("name") written as {name=default}. The menu shows the lines with a box for each
## number (the default as the grey placeholder); the scripts read the numbers each frame with
## WaterShapes.f(group, name), so an edit shows at once.
## The values in use are saved to user://water_shapes.cfg (loaded at start); named saves per group go to
## user://water_shape_saves.cfg.
## Keep each group's lines in step with its script: a name used in a script and missing here is an error.

const ACTIVE_PATH := "user://water_shapes.cfg"
const SAVES_PATH := "user://water_shape_saves.cfg"

## [id, name in the menu, script, lines]. A line starting with "#" is a comment.
const GROUPS := [
	["serpent", "Serpent", "scripts/serpent_water.gd", [
		"# margin of water beyond the legs, for v litres (full form): base + most added * (1 - e^(-(v - 200) / scale))",
		"static func margin(v: float) -> float:",
		"	return {margin_base=0.005} + {margin_add=0.10} * (1.0 - exp(-maxf(v - ACTIVE_L, 0.0) / {margin_scale=300.0}))",
		"# tail length (m), the same way",
		"static func tail_len(v: float) -> float:",
		"	return {tail_base=0.1} + {tail_add=4.0} * (1.0 - exp(-maxf(v - ACTIVE_L, 0.0) / {tail_scale=600.0}))",
		"# _process: how wide the joins round over (m): thin layer (each leg its own) to full form (one body)",
		"_w.commit(lerpf({blend_thin=0.035}, {blend_full=0.5}, full), player.global_position,",
		"		{wave_thin=0.003} + {wave_full=0.004} * full)          # the light wave across the surface (m)",
		"_w.look(\"absorb\", {absorb=2.4})          # how fast it deepens with thickness, per m",
		"# _shape: the thin layer's thickness, and what the full form adds round each leg",
		"var t := {thin_t=0.012} + {thin_t_add=0.025} * clampf(litres / ACTIVE_L, 0.0, 1.0)",
		"var x := {full_add=0.04} * full + m",
		"# the legs (radius at hip, knee, ankle, ball of the foot, before t and x)",
		"_w.seg(th, {hip_r=0.085} + t + x, kn, {knee_r=0.06} + t + x)",
		"_w.seg(kn, k(\"knee_r\") + t + x, ft, {ankle_r=0.048} + t + x)",
		"_w.seg(ft, k(\"ankle_r\") + t + x * 0.9, bl, {ball_r=0.035} + t + x * 0.8)",
		"# the hips, and the band above them that rounds over at the waist",
		"_w.seg(tl, {hips_r=0.12} + t + x * 0.9, tr, k(\"hips_r\") + t + x * 0.9)",
		"var wc := pel + Vector3(0, {waist_up=0.12}, 0)",
		"var half := _h(tr - tl) * 0.5 * {waist_w=0.6}",
		"_w.seg(wc - half, {waist_r=0.1} + t + x * 0.6, wc + half, k(\"waist_r\") + t + x * 0.6)",
		"# the body between the legs (full form)",
		"var mr := ({between_r=0.07} + x) * full",
		"# the pool round the feet: a sphere sunk in the ground by a part of its radius",
		"var pr := (feet_half + {pool_add=0.09} + m * 1.1) * full",
		"_w.sphere(base - Vector3(0, pr * {pool_sink=0.45}, 0), pr)",
		"# the column when raised: radius, and how much it spreads at the ground",
		"var cr := ({column_r=0.12} + m * 0.6) * full",
		"var r := cr * lerpf(1.0, {column_flare=2.6}, pow(u, 4.0))",
		"# the tail: radius at the feet, then thinning to the tip (a part of that radius)",
		"_tail_segs(base, {tail_r=0.08} + m * {tail_r_m=1.15})",
		"var r := r0 * lerpf(1.0, {tail_tip=0.15}, pow(u, {tail_taper=0.8}))",
	]],
	["held", "Held water (stream and feed)", "scripts/water_body.gd", [
		"# _profile: the radius along the stream (R0 = 0.08 m, thick: the held amount's thickness)",
		"return r * sqrt(vol) * R0 * thick * {radius=1.0}",
		"# striking: fat at the head, thin at the tail",
		"r = lerpf({strike_head=1.25}, {strike_tail=0.35}, pow(w, {strike_taper=0.7}))",
		"# held: a slow swell along it",
		"r = 1.0 + {swell=0.035} * sin(TAU * (w * 2.0 - clock * 0.7))",
		"# how many of its 46 points round off the head and the tail",
		"var cap := {cap=4.0} / float(N - 1)",
		"# _process: one surface for the stream and its feed",
		"_w.look(\"absorb\", {absorb=2.4})",
		"_w.look(\"foam\", {strike_foam=0.5} if state == S.STRIKE or state == S.IMPACT else 0.0)",
		"_w.commit({blend=0.04} * thick, origin, {wave=0.003})",
		"# _feed_build: the feed stream's radius (from the flow it carries), and its foot at the source",
		"var r := clampf(sqrt(_feed_rate / 1000.0 * look / (PI * FEED_SPEED)), {feed_min=0.03}, {feed_max=0.2})",
		"_feed_R[i] = lerpf(R0 * thick * 0.6, r, end) * ({feed_foot=1.3} if i == 0 and _feed_cut == 0.0 else 1.0)",
	]],
	["octopus", "Octopus", "scripts/octopus.gd", [
		"# tentacle length (m), for v litres",
		"static func length_for(v: float) -> float:",
		"	if v <= 600.0:",
		"		return maxf({len_300=1.45} + {len_per_300=0.6} * (v - 300.0) / 300.0, {len_min=0.9})",
		"	return {len_600=2.05} + {len_over=0.6} * sqrt((v - 600.0) / 600.0)",
		"# tentacle radius at its base (m)",
		"static func base_r_for(v: float) -> float:",
		"	if v <= 600.0:",
		"		return maxf({base_r_300=0.152} + {base_r_per_300=0.152} * (v - 300.0) / 300.0, {base_r_min=0.08})",
		"	return {base_r_600=0.305} * pow(v / 600.0, {base_r_pow=0.4})",
		"# the ring's width and height (m)",
		"func ring_width() -> float:",
		"	return clampf({ring_w_300=0.6} + {ring_w_per_300=0.6} * (litres - 300.0) / 300.0, {ring_w_min=0.45}, {ring_w_max=1.6})",
		"func ring_height() -> float:",
		"	return clampf({ring_h_300=0.16} + {ring_h_per_300=0.12} * (litres - 300.0) / 300.0, {ring_h_min=0.12}, {ring_h_max=0.4})",
		"# _base: the dry gap round the bender's feet (m to the ring's inner edge)",
		"var r := {gap=0.7} + ring_width() * 0.5",
		"# _build_ring: the ring's slow wobble",
		"var ww := w * (1.0 + {ring_wobble=0.05} * sin(th * 5.0 + _clock * 0.8))",
		"# _build_limb: the active one thicker; tapering to the tip; flaring into the ring",
		"var r0 := base_r_for(litres) * maxf(_grow, 0.05) * lerpf(1.0, {raised_thick=1.2}, l.raise) * stretch",
		"var r := r0 * (1.0 - {taper=0.9} * pow(u, {taper_pow=1.15}))",
		"r *= {base_flare=1.35}          # flaring into the ring",
		"# _process: one surface for the ring and the tentacles",
		"_w.look(\"absorb\", {absorb=2.4})",
		"_w.commit({blend=0.2}, _centre, {wave=0.004})",
	]],
	["geyser", "Geyser", "scripts/geyser.gd", [
		"# the column's radius at height y (of h), flaring where it leaves the surface",
		"var r := {radius=0.45} * (1.0 + {flare=1.6} * exp(-y / {flare_h=0.35})) * lerpf(1.0, {top=0.8}, u)",
		"r *= {crown=1.5}          # the crown at the top",
		"_w.look(\"absorb\", {absorb=1.6})",
		"_w.look(\"drift\", Vector3(0, {rise_flow=6.0}, 0))          # m/s the ripples run up",
		"_w.look(\"foam\", {foam=0.35})",
		"_w.commit({blend=0.25}, _base, {wave=0.01}, _base.y)",
	]],
	["wave", "Wave", "scripts/water_wave.gd", [
		"# _tubes: tubes along the crest, [x along the travel, y up, radius] in units of the wave's height there",
		"[{back_x=-1.6}, {back_y=0.0}, {back_r=0.35}],",
		"[{shoulder_x=-0.75}, {shoulder_y=0.42}, {shoulder_r=0.42}],",
		"[lerpf({crest_x=0.0}, {crest_x_break=0.25}, c), {crest_y=0.7}, {crest_r=0.3}],",
		"[lerpf({face_x=0.65}, {face_x_break=0.62}, c), lerpf({face_y=0.28}, {face_y_break=0.78}, c), lerpf({face_r=0.25}, {face_r_break=0.2}, c)],",
		"[{lip_x=0.38}, {lip_y=0.42}, {lip_r=0.12} * c],          # the lip, only as it breaks",
		"# _build: how fast the crest's ends taper",
		"var taper := pow(maxf(1.0 - u * u, 0.0), {end_taper=0.45})",
		"_w.look(\"absorb\", {absorb=1.4})",
		"_w.look(\"foam\", (0.25 + _curl * 0.7) * {foam=1.0} if state != S.RISE else 0.2 * k(\"foam\"))",
		"_w.commit({blend=0.35} * maxf(h, 0.3), mid, {wave=0.02}, floor_y)",
	]],
	["parting", "Parting (the stream)", "scripts/pond.gd", [
		"# part_shape: the trench, a superellipse: its centre ahead of the bender, half its length and width (m)",
		"var a := d.dot(dir) - {c=2.3}",
		"var r := pow(pow(absf(a) / {ra=3.5}, n) + pow(absf(c) / {rb=2.5}, n), 1.0 / n)",
		"# squareness: 2 an ellipse, higher nearer a rectangle; the end round the bender, and the far end",
		"var n := {n_near=2.0} if a < 0.0 else {n_far=3.0}",
		"# its walls round up over this much more of the shape, into ridges of the water pushed aside",
		"var w := _smooth(1.0, 1.0 + {wall=0.4}, r)",
		"# how far the surface drops in it (m, to below the bed), and how high the ridges stand",
		"return -{drop=2.2} * (1.0 - w) + {ridge=0.9} * ridge",
	]],
	["volley", "Volley (water to the spikes)", "scripts/spike_volley.gd", [
		"# _build_arcs: how high each arc bows, and its thickness",
		"var ctrl := (p0 + p2) * 0.5 + Vector3.UP * ({rise=0.15} + {rise_per_m=0.15} * p0.distance_to(p2))",
		"var r := clampf(WaterBody.R0 * _water.thick * {thick=0.6}, {min_r=0.03}, {max_r=0.12}) * sqrt(left)",
		"var pr := r * (1.0 - {thin_to=0.5} * u)          # thinning toward the spike",
		"_arcs.look(\"absorb\", {absorb=2.4})",
		"_arcs.commit({blend=0.03}, _bender.global_position, 0.002)",
	]],
	["ice_stream", "Ice wall (water to the ice)", "scripts/ice_caster.gd", [
		"# _build: how high it bows, and its thickness (thinner the farther it reaches)",
		"var ctrl := a + d * 0.5 + Vector3.UP * ({rise_per_m=0.15} * d.length())",
		"var r := clampf({radius=0.05} * sqrt(water.thick) * sqrt(3.0 / maxf(d.length(), 1.0)), {min_r=0.015}, {max_r=0.08})",
		"var rr := r * (1.0 + {pulse=0.15} * sin(u * 20.0 - _clock * 12.0))          # pulses running along it",
		"_mi.look(\"absorb\", {absorb=2.4})",
		"_mi.commit({blend=0.03}, a, 0.002)",
	]],
]

static var _ready := false
static var _defaults := {}       # "group.name" -> float
static var _vals := {}           # "group.name" -> float (only those changed from the default)
static var _re: RegEx
static var revision := 0         # goes up with every change (what builds its shape only on change reads it)

## A shape number now.
static func f(group: String, n: String) -> float:
	if not _ready:
		setup()
	var key := group + "." + n
	if _vals.has(key):
		return _vals[key]
	if not _defaults.has(key):
		push_error("WaterShapes: no number '%s' (add it to the group's lines)" % key)
		_defaults[key] = 0.0
	return _defaults[key]

static func setup() -> void:
	if _ready:
		return
	_ready = true
	_re = RegEx.new()
	_re.compile("\\{([a-z0-9_]+)=([-0-9.eE]+)\\}")
	for g in GROUPS:
		for line in g[3]:
			for m in _re.search_all(line):
				_defaults[g[0] + "." + m.get_string(1)] = m.get_string(2).to_float()
	var cf := ConfigFile.new()
	if cf.load(ACTIVE_PATH) == OK and cf.has_section("active"):
		for key in cf.get_section_keys("active"):
			if _defaults.has(key):
				_vals[key] = float(cf.get_value("active", key))

## A line split into pieces: Strings (code) and [name, default] (a number).
static func pieces(line: String) -> Array:
	if not _ready:
		setup()
	var out := []
	var at := 0
	for m in _re.search_all(line):
		out.append(line.substr(at, m.get_start() - at))
		out.append([m.get_string(1), m.get_string(2).to_float()])
		at = m.get_end()
	out.append(line.substr(at))
	return out

static func group(id: String) -> Array:
	for g in GROUPS:
		if g[0] == id:
			return g
	return []

static func default_of(group_id: String, n: String) -> float:
	if not _ready:
		setup()
	return _defaults.get(group_id + "." + n, 0.0)

## The value set for it, or null when it is at its default.
static func changed(group_id: String, n: String):
	if not _ready:
		setup()
	return _vals.get(group_id + "." + n)

static func set_value(group_id: String, n: String, v) -> void:
	revision += 1
	var key := group_id + "." + n
	if v == null or is_equal_approx(float(v), _defaults.get(key, 0.0)):
		_vals.erase(key)
	else:
		_vals[key] = float(v)

static func _names(group_id: String) -> Array:
	var out := []
	for key in _defaults:
		if (key as String).begins_with(group_id + "."):
			out.append((key as String).substr(group_id.length() + 1))
	return out

## Back to the defaults (not saved until Save).
static func reset(group_id: String) -> void:
	revision += 1
	for n in _names(group_id):
		_vals.erase(group_id + "." + n)

## Saves the group's values under a name, and as the values used from now on (also after a restart).
static func save(group_id: String, save_name: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVES_PATH)
	var sec := group_id + "/" + save_name
	if cf.has_section(sec):
		cf.erase_section(sec)
	for n in _names(group_id):
		cf.set_value(sec, n, f(group_id, n))
	cf.save(SAVES_PATH)
	_save_active()

static func _save_active() -> void:
	var cf := ConfigFile.new()
	for key in _vals:
		cf.set_value("active", key, _vals[key])
	cf.save(ACTIVE_PATH)

## The group's saved names, newest last.
static func saves(group_id: String) -> PackedStringArray:
	var cf := ConfigFile.new()
	var out := PackedStringArray()
	if cf.load(SAVES_PATH) != OK:
		return out
	for sec in cf.get_sections():
		if sec.begins_with(group_id + "/"):
			out.append(sec.substr(group_id.length() + 1))
	return out

## Loads a named save into the group (used from now on; also after a restart).
static func load_save(group_id: String, save_name: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVES_PATH) != OK or not cf.has_section(group_id + "/" + save_name):
		return false
	reset(group_id)
	for n in cf.get_section_keys(group_id + "/" + save_name):
		set_value(group_id, n, cf.get_value(group_id + "/" + save_name, n))
	_save_active()
	return true

static func delete_save(group_id: String, save_name: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVES_PATH) != OK:
		return
	if cf.has_section(group_id + "/" + save_name):
		cf.erase_section(group_id + "/" + save_name)
		cf.save(SAVES_PATH)
