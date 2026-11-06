class_name IceCaster
extends Node3D
## Ice wall form, R2 held: water runs from the held body of water to where the crosshair is and
## freezes there (IceField.paint). Aimed at a water surface, or at ice grown from one, the water body
## itself freezes and nothing is taken from the hands. Shows the running stream and the frost where it
## freezes.

const RANGE := 14.0
const PIECES := 8                # pieces along the stream

var active := false
var _mi: WaterSDF                # the stream running to where it freezes
var _frost: GPUParticles3D
var _clock := 0.0

func _ready() -> void:
	top_level = true
	_mi = WaterSDF.new()
	add_child(_mi)
	_frost = GPUParticles3D.new()
	_frost.amount = 70
	_frost.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0))
	curve.curve = cv
	pm.scale_curve = curve
	_frost.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.9, 0.97, 1.0, 0.55)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = fm
	_frost.draw_pass_1 = qm
	_frost.layers = 2
	_frost.emitting = false
	add_child(_frost)

## One frame of casting. target: {p, n, kind, src} from the player. water: the held water, or null.
## Returns false when nothing could be frozen (no water to use).
func cast(dt: float, target: Dictionary, hands: Vector3, water: WaterBody) -> bool:
	_clock += dt
	if target.is_empty() or IceField.inst == null:
		stop()
		return false
	var p: Vector3 = target["p"]
	var n: Vector3 = target["n"]
	var kind: int = target["kind"]
	var src = target.get("src")
	if src == null and (kind == IceField.K.ICE_TOP or kind == IceField.K.ICE_SIDE):
		src = IceField.inst.src_at(p, n)
	var from_hands := src == null
	var budget := 0.0
	if from_hands:
		budget = water.litres() if water != null and water.holds_water() else 0.0
	else:
		budget = src.level
	if budget <= 0.01:
		stop()
		return false
	var used := IceField.inst.paint(p, n, kind, src, dt, budget)
	if from_hands:
		water.take_litres(used)
	else:
		src.take(used)
	active = true
	_frost.global_position = p
	_frost.emitting = true
	_mi.visible = from_hands and water != null and water.holds_water()
	if _mi.visible:
		# the water runs out of the held body (its head), not out of the hands
		_build(water.head_pos(), p, water)
	return true

func stop() -> void:
	active = false
	_mi.visible = false
	if _frost:
		_frost.emitting = false

## A shape number (Options > Visual > Edit Water Shapes).
static func k(n: String) -> float:
	return WaterShapes.f("ice_stream", n)

## The stream from the hands to the target, arcing a little, thinner the farther it reaches.
func _build(a: Vector3, b: Vector3, water: WaterBody) -> void:
	var d := b - a
	var ctrl := a + d * 0.5 + Vector3.UP * (k("rise_per_m") * d.length())
	var r := clampf(k("radius") * sqrt(water.thick) * sqrt(3.0 / maxf(d.length(), 1.0)), k("min_r"), k("max_r"))
	_mi.clear()
	var prev := a
	var prev_r := r
	for j in range(1, PIECES + 1):
		var u := float(j) / PIECES
		var p := a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
		var rr := r * (1.0 + k("pulse") * sin(u * 20.0 - _clock * 12.0))
		_mi.seg(prev, prev_r, p, rr)
		prev = p
		prev_r = rr
	_mi.look("absorb", k("absorb"))
	_mi.commit(k("blend"), a, 0.002)
	_mi.visible = true
