class_name SpikeVolley
extends Node3D
## Ice spike, held R2: the held water spreads up and around the bender in arcs and freezes into one large
## spike per PER_SPIKE litres, waiting in a fan around and above the bender, each pointing at the
## crosshair. On release they all fly from where they are toward the crosshair, each to a slightly
## different spot, so they strike at different angles like a shotgun's spread. The water is taken from
## the held water as each spike grows, running up to it from the nearest part of the held body; what is
## left over after the last whole spike goes into the last one, so none stays held.

const PER_SPIKE := 30.0
const MAX_SPIKES := 20
const GROW_T := 0.45            # s for one spike to freeze
const STAGGER := 0.07           # s between spikes starting
const SPEED := 34.0
const SPREAD := 0.06            # scatter at the target, per m of distance (plus SPREAD_MIN)
const SPREAD_MIN := 0.35
const ARC_PIECES := 5            # pieces along each arc

var aim := Vector3.ZERO
var _bender: Player
var _water: WaterBody
var _spikes: Array[IceSpike] = []
var _want: PackedFloat32Array = []    # litres each spike will hold
var _slots: Array[Vector3] = []       # in the bender's frame (x right, y up, z back), about its middle
var _t := 0.0
var _arcs: WaterSDF                # the water running up to the spikes still freezing

static func count_for(v: float) -> int:
	if v < PER_SPIKE:
		return 1
	return mini(int(floor(v / PER_SPIKE)), MAX_SPIKES)

func count() -> int:
	return _spikes.size()

func begin(bender: Player, water: WaterBody) -> void:
	_bender = bender
	_water = water
	var v := water.litres()
	var n := count_for(v)
	for i in n:
		_want.append(PER_SPIKE if v >= PER_SPIKE else v)
	if v >= PER_SPIKE:
		# the remainder melds into the last spike
		_want[n - 1] += v - PER_SPIKE * n
	# a fan of rows around and above the bender, wider and higher as there are more
	var per_row := 7
	for i in n:
		var row := i / per_row
		var in_row := mini(per_row, n - row * per_row)
		var k := i % per_row
		var f := 0.5 if in_row == 1 else float(k) / float(in_row - 1)
		var span := 1.9 * pow(0.85, row)
		var az := lerpf(-span, span, f)
		var r := 1.5 + 0.45 * row
		var y := 1.6 + 0.7 * row + 0.25 * sin(f * PI)
		# az 0 is straight ahead; the fan reaches round both sides
		_slots.append(Vector3(sin(az) * r, y, -cos(az) * r * 0.55))

func _ready() -> void:
	top_level = true
	_arcs = WaterSDF.new()
	add_child(_arcs)

func _slot_world(i: int) -> Vector3:
	var yaw := _bender.cam_yaw
	var s := _slots[i]
	return _bender.global_position + Basis(Vector3.UP, yaw) * Vector3(s.x, s.y, s.z)

func _process(dt: float) -> void:
	if _bender == null:
		return
	_t += dt
	var arcs := []
	for i in _want.size():
		var start := i * STAGGER
		if _t < start:
			continue
		if i >= _spikes.size():
			var sp := IceSpike.new()
			sp.setup(_bender)
			get_parent().add_child(sp)
			_spikes.append(sp)
		var spk := _spikes[i]
		var at := _slot_world(i)
		var grow := clampf((_t - start) / GROW_T, 0.0, 1.0)
		var need := _want[i] * grow - spk.litres
		var from = _nearest_water(at)
		if need > 0.0 and _water.holds_water():
			spk.add_litres(_water.take_litres(minf(need, _water.litres())))
		spk.hold_at(at, (aim - at).normalized())
		if grow < 1.0 and from != null:
			arcs.append([from, at, 1.0 - grow])
	_build_arcs(arcs)

## The point of the held water nearest p, or null when nothing is held.
func _nearest_water(p: Vector3):
	if not _water.holds_water():
		return null
	var best := Vector3.ZERO
	var bd := INF
	for q in _water.pts:
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("volley", n)

## The water running from the held body up to each spike still freezing, as arcs that thin as it finishes.
func _build_arcs(arcs: Array) -> void:
	_arcs.clear()
	for a in arcs:
		if _arcs.room() < ARC_PIECES:
			break
		var p0: Vector3 = a[0]
		var p2: Vector3 = a[1]
		var left: float = a[2]
		var ctrl := (p0 + p2) * 0.5 + Vector3.UP * (k("rise") + k("rise_per_m") * p0.distance_to(p2))
		# as thick as the held stream where it leaves it, thinning toward the spike
		var r := clampf(WaterBody.R0 * _water.thick * k("thick"), k("min_r"), k("max_r")) * sqrt(left)
		var prev := p0
		var prev_r := r
		for j in range(1, ARC_PIECES + 1):
			var u := float(j) / ARC_PIECES
			var p := p0.lerp(ctrl, u).lerp(ctrl.lerp(p2, u), u)
			var pr := r * (1.0 - k("thin_to") * u)
			_arcs.seg(prev, prev_r, p, pr)
			prev = p
			prev_r = pr
	_arcs.look("absorb", k("absorb"))
	_arcs.commit(k("blend"), _bender.global_position if _bender != null else Vector3.ZERO, 0.002)
	_arcs.visible = _arcs.count > 0

## Release: every spike formed so far flies at the crosshair, each aimed at its own spot near it.
func fire(target: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for sp in _spikes:
		if not is_instance_valid(sp):
			continue
		if sp.litres < 0.5:
			_give_back(sp)
			continue
		var from := sp.global_position
		var d := target - from
		var r := SPREAD_MIN + SPREAD * d.length()
		var side := d.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(d).normalized()
		var ang := rng.randf() * TAU
		var off := (side * cos(ang) + up * sin(ang)) * r * sqrt(rng.randf())
		sp.fire(from, (target + off - from).normalized(), SPEED * rng.randf_range(0.9, 1.1))
	_spikes.clear()
	_bender = null      # nothing more forms, even in this frame's update
	queue_free()

## R1 let go while they form: they fall where they are.
func drop() -> void:
	for sp in _spikes:
		if is_instance_valid(sp):
			if sp.litres < 0.5:
				_give_back(sp)
			else:
				sp.drop()
	_spikes.clear()
	_bender = null
	queue_free()

## A spike that had barely begun: its water goes back into the held water (or falls as a puddle).
func _give_back(sp: IceSpike) -> void:
	if _water.holds_water():
		_water.add_litres(sp.litres)
	elif sp.litres > 0.0:
		Puddle.add_at(sp.global_position * Vector3(1, 0, 1), sp.litres, get_tree(), get_parent())
	sp.litres = 0.0
	sp.queue_free()
