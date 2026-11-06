class_name SerpentWater
extends Node3D
## Serpent form: a body of water of its own, wrapped round the bender's hips and legs and pooling into a
## tail on the ground behind, which carries the bender. Separate from the held water: Triangle melds the
## held water into it (the first time 300 L or more is needed), after which R1 draws and holds water as
## usual, and the moves use that. L1 (back to the relaxed stance) lets it fall.
## Above ACTIVE_L it speeds the bender and, with Square held, raises them on a column of itself; at
## ACTIVE_L or less it does nothing and lies as a thin layer on the hips and legs. Moving, it slowly runs
## off (LEAK_PER_M), leaving the ground wet. More water: faster, higher, with diminishing returns, and the
## movement carries more momentum.
## Its size on screen is set by look (a game allowance, like the held stream's); its litres are counted
## exactly.

### Beeferly's notes are noted with 3 #s

const MIN_ENTER := 300.0        # L held to take the form
const ACTIVE_L := 200.0         # at or below this it gives nothing
const MAX_L := 1200.0
const LEAK_PER_M := 1.0         # L lost per metre the bender moves (600 L lasts about 400 m)
const WET_EVERY := 0.6          # m between the wet patches it leaves
# speed: x1.5 at 300 L, x2 at 600 L, about x2.1 at most
const SPEED_A := 1.096
const SPEED_B := 164.0
# rise (feet above the ground): 1.9 m at 300 L (half a 3.8 m house), 4.8 m at 600 L (feet a waist's
# height above that roof), about 6 m at most
const RISE_A := 6.3
const RISE_B := 278.7
# the drawn shape: round cones (two end spheres) joined smoothly into one surface (WaterSDF). Its numbers
# are k("name"): editable in Options > Visual > Edit Water Shapes, defaults in water_shapes.gd.
const TAIL_SEGS := 5

var litres := 0.0
var active := false
var player: Player
var _tail := PackedVector3Array()     # ground points the bender has passed, newest last
var _m := 0.0                         # drawn margin of water beyond the legs
var _tl := 0.0                        # drawn tail length
var _thin := 1.0                      # 0: the full form, 1: the thin layer
var _last := Vector3.INF
var _wet_d := 0.0
var _filled := false                  # it has had water (until then it is still forming)
var _w: WaterSDF                      # draws the water

static func speed_mult(v: float) -> float:
	return 1.0 if v <= ACTIVE_L else 1.0 + SPEED_A * (1.0 - exp(-(v - ACTIVE_L) / SPEED_B))

static func rise_h(v: float) -> float:
	return 0.0 if v <= ACTIVE_L else RISE_A * (1.0 - exp(-(v - ACTIVE_L) / RISE_B))

## m/s² the bender's speed changes by: lower with more water (smoother, more momentum).
static func accel(v: float) -> float:
	return 12.0 if v <= ACTIVE_L else 2.5 + 7.0 * exp(-maxf(v - MIN_ENTER, 0.0) / 200.0)

## Margin of water beyond the legs, and tail length, for v litres in the full form.
static func margin(v: float) -> float:
	return k("margin_base") + k("margin_add") * (1.0 - exp(-maxf(v - ACTIVE_L, 0.0) / k("margin_scale")))

static func tail_len(v: float) -> float:
	return k("tail_base") + k("tail_add") * (1.0 - exp(-maxf(v - ACTIVE_L, 0.0) / k("tail_scale")))
### originally: return 1.0 + 2.4 * (1.0 - exp(-maxf(v - ACTIVE_L, 0.0) / 350.0))
func effective() -> bool:
	return active and litres > ACTIVE_L

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("serpent", n)

func _ready() -> void:
	top_level = true
	_w = WaterSDF.new()
	add_child(_w)

func begin() -> void:
	active = true
	litres = 0.0
	_thin = 1.0
	_m = 0.0
	_tl = 0.0
	_tail.clear()
	_last = Vector3.INF
	_filled = false

## Takes in up to l litres; returns what it took (it holds at most MAX_L).
func add(l: float) -> float:
	if not active:
		return 0.0
	var t := clampf(l, 0.0, MAX_L - litres)
	litres += t
	if litres > 2.0:
		_filled = true
	return t

## Where held water melds in: the waist.
func waist() -> Vector3:
	var p = _leg("pelvis")
	return (p as Vector3) + Vector3(0, 0.1, 0) if p != null else player.global_position + Vector3(0, 1.0, 0)

## Leaves the form keeping its water (switching to Octopus): returns the litres.
func take_all() -> float:
	var l := litres
	litres = 0.0
	active = false
	_w.visible = false
	return l

## Back to the relaxed stance: the water falls where it is and lies as a puddle.
func drop() -> void:
	if not active:
		return
	active = false
	var g := Vector3(player.global_position.x, player.ground_y, player.global_position.z)
	if litres > 0.0:
		Puddle.add_at(g, litres, get_tree(), player.get_parent())
	litres = 0.0
	_w.visible = false

func _physics_process(_dt: float) -> void:
	if not active or player == null:
		return
	var p := player.global_position
	if _last != Vector3.INF:
		var d := p.distance_to(_last)
		if d < 2.0:
			# moving, it runs off a little: the ground it passes is left wet
			var lost := minf(d * LEAK_PER_M, litres)
			litres -= lost
			_wet_d += d
			if _wet_d > WET_EVERY:
				_wet_d = 0.0
				Wetness.mark(Vector3(p.x, player.ground_y + 0.01, p.z), Vector3.UP, clampf(0.5 + _m * 2.0, 0.5, 1.4))
	_last = p
	if litres < 2.0 and _filled:
		# run dry: what is left soaks the ground
		Wetness.mark(Vector3(p.x, player.ground_y + 0.01, p.z), Vector3.UP, 0.6)
		litres = 0.0
		active = false
		_w.visible = false

func _leg(n: String):
	var u: UpperAim = player._upper
	var l = u.leg(n) if u != null else null
	if l == null:
		var b := player.skel.find_bone(n)
		if b < 0:
			return null
		l = player.skel.get_bone_global_pose(b).origin
	return player.skel.global_transform * (l as Vector3)

func _process(dt: float) -> void:
	if not active or player == null:
		return
	_thin = move_toward(_thin, 1.0 if litres <= ACTIVE_L else 0.0, dt * 2.0)
	var full := clampf(1.0 - _thin / 0.7, 0.0, 1.0)
	_m = lerpf(_m, margin(litres) * full, clampf(dt * 6.0, 0.0, 1.0))
	_tl = lerpf(_tl, tail_len(litres) * full, clampf(dt * 4.0, 0.0, 1.0))
	var g := Vector3(player.global_position.x, player.ground_y, player.global_position.z)
	if _tail.is_empty() or _tail[_tail.size() - 1].distance_to(g) > 0.12:
		_tail.append(g)
		if _tail.size() > 300:
			_tail = _tail.slice(_tail.size() - 300)
	_w.clear()
	_shape(full)
	_w.visible = litres > 0.5 and _w.count > 0
	if _w.visible:
		_w.look("absorb", k("absorb"))
		_w.commit(lerpf(k("blend_thin"), k("blend_full"), full), player.global_position,
				k("wave_thin") + k("wave_full") * full)

func _h(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

## The shape, as round cones. full is 0 for the thin layer (each leg wrapped on its own, a band round
## the hips) and 1 for the full form (legs, hips, a body between the legs, the pool or column under the
## feet and the tail, run together into one); it changes smoothly between them.
## Radii here are the water's outer surface (m): the leg's own thickness plus the water over it.
func _shape(full: float) -> void:
	var m := _m                                       # margin, already scaled by full
	var t := k("thin_t") + k("thin_t_add") * clampf(litres / ACTIVE_L, 0.0, 1.0)   # the thin layer's thickness
	var x := k("full_add") * full + m                 # what the full form adds round each leg
	var pel: Vector3 = _leg("pelvis")
	var tl: Vector3 = _leg("thigh_l")
	var tr: Vector3 = _leg("thigh_r")
	var kl: Vector3 = _leg("calf_l")
	var kr: Vector3 = _leg("calf_r")
	var fl: Vector3 = _leg("foot_l")
	var fr: Vector3 = _leg("foot_r")
	# the legs: hip to knee, knee to ankle, ankle to the ball of the foot
	for s in ["l", "r"]:
		var th: Vector3 = _leg("thigh_" + s)
		var kn: Vector3 = _leg("calf_" + s)
		var ft: Vector3 = _leg("foot_" + s)
		var bl = _leg("ball_" + s)
		_w.seg(th, k("hip_r") + t + x, kn, k("knee_r") + t + x)
		_w.seg(kn, k("knee_r") + t + x, ft, k("ankle_r") + t + x)
		if bl != null:
			_w.seg(ft, k("ankle_r") + t + x * 0.9, bl, k("ball_r") + t + x * 0.8)
	# the hips, across from one hip joint to the other, and above them a band that rounds over at the
	# waist (its top is the top of the water)
	var up := Vector3(0, 0.1, 0)
	_w.seg(tl, k("hips_r") + t + x * 0.9, tr, k("hips_r") + t + x * 0.9)
	var wc := pel + Vector3(0, k("waist_up"), 0)
	var half := _h(tr - tl) * 0.5 * k("waist_w")
	_w.seg(wc - half, k("waist_r") + t + x * 0.6, wc + half, k("waist_r") + t + x * 0.6)
	var hc := (tl + tr) * 0.5
	var kc := (kl + kr) * 0.5
	var fc := (fl + fr) * 0.5
	var ground := player.ground_y
	var base := Vector3(fc.x, ground, fc.z)
	if full < 0.01:
		return
	# the body between the legs, so the two read as one
	var mr := (k("between_r") + x) * full
	_w.seg(hc - up * 0.5, mr * 1.1, kc, mr)
	_w.seg(kc, mr, fc, mr * 1.05)
	var feet_half := _h(fr - fl).length() * 0.5
	var raised := fc.y - ground > 0.25
	if not raised:
		# pooling on the ground round the feet: a sphere mostly below the ground, so only a low dome shows
		var pr := (feet_half + k("pool_add") + m * 1.1) * full
		_w.sphere(base - Vector3(0, pr * k("pool_sink"), 0), pr)
	else:
		# the column holding the bender up, from under the feet down to a pool on the ground; it lags behind
		# the moving bender and spreads where it meets the ground
		var cr := (k("column_r") + m * 0.6) * full
		var prev := fc
		var prev_r := cr * 1.1
		var steps := 3
		for i in range(1, steps + 1):
			var u := float(i) / steps
			var c := fc.lerp(base, u) + _h(player.velocity) * (-0.06 * u * u)
			var r := cr * lerpf(1.0, k("column_flare"), pow(u, 4.0))
			_w.seg(prev, prev_r, c, r)
			prev = c
			prev_r = r
		var pool := cr * k("column_flare")
		_w.sphere(base - Vector3(0, pool * 0.5, 0), pool)
	_tail_segs(base, k("tail_r") + m * k("tail_r_m"))

## The tail along the ground where the bender has been (or straight back when standing), from the feet
## to a point. Each sphere sits mostly in the ground, so it lies low and flat.
func _tail_segs(base: Vector3, r0: float) -> void:
	if _tl < 0.1:
		return
	# the path back from the feet, with its length along the way
	var path := PackedVector3Array([base])
	var arc := PackedFloat32Array([0.0])
	var acc := 0.0
	var prev := base
	var i := _tail.size() - 1
	while i >= 0 and acc < _tl:
		var p := _tail[i]
		var d := p.distance_to(prev)
		if d > 0.05:
			acc += d
			path.append(p)
			arc.append(acc)
			prev = p
		i -= 1
	if acc < _tl:
		var back := _h(player.global_transform.basis.z)     # the bender faces -Z
		back = back.normalized() if back.length() > 0.1 else Vector3.BACK
		path.append(prev + back * (_tl - acc))
		arc.append(_tl)
	# even steps along it
	var j := 0
	var last := base
	var last_r := r0
	for k in range(1, TAIL_SEGS + 1):
		var s := _tl * k / TAIL_SEGS
		while j < arc.size() - 2 and arc[j + 1] < s:
			j += 1
		var span := maxf(arc[j + 1] - arc[j], 0.0001)
		var c := path[j].lerp(path[j + 1], clampf((s - arc[j]) / span, 0.0, 1.0))
		var u := float(k) / TAIL_SEGS
		var r := r0 * lerpf(1.0, k("tail_tip"), pow(u, k("tail_taper")))
		var cc := c + Vector3(0, -r * 0.1, 0)
		_w.seg(last, last_r, cc, r)
		last = cc
		last_r = r
