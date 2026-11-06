class_name Wetness
extends Node3D
## Wet patches left wherever water touches a surface. Each patch is a decal that darkens the surface and
## makes it glossy, then dries out. Patches on a moving body are parented to it so they move with it.
## The bender, the water and anything else on render layer 2 are never marked.

const MAX := 180
const DRY_START := 25.0       # seconds fully wet
const DRY_TIME := 40.0        # seconds to dry out
const WET_COLOR := Color(0.34, 0.36, 0.39)   # the white surfaces sit near full exposure, so wet is much darker

static var inst: Wetness

var _tex_a: ImageTexture
var _tex_orm: ImageTexture
var _decals: Array[Decal] = []

func _enter_tree() -> void:
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null

func _ready() -> void:
	_build_textures()

## Marks a wet patch of the given diameter at p, on the surface facing n.
static func mark(p: Vector3, n: Vector3, size: float, on: Object = null) -> void:
	if inst:
		inst._mark(p, n, size, on)

func _mark(p: Vector3, n: Vector3, size: float, on: Object) -> void:
	if n.length() < 0.01:
		n = Vector3.UP
	var d := Decal.new()
	d.texture_albedo = _tex_a
	d.texture_orm = _tex_orm
	d.size = Vector3(size, 0.24, size)
	d.cull_mask = 1
	d.upper_fade = 0.35
	d.lower_fade = 0.35
	d.albedo_mix = 1.0
	d.modulate = Color(1, 1, 1, 0)
	var parent: Node = self
	if on is RigidBody3D:
		parent = on
	parent.add_child(d)
	var y := n.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var b := Basis(x, y, x.cross(y)).orthonormalized()
	b = Basis(y, randf() * TAU) * b
	d.global_transform = Transform3D(b, p)
	var tw := d.create_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.2)
	tw.tween_interval(DRY_START * randf_range(0.8, 1.2))
	tw.tween_property(d, "modulate:a", 0.0, DRY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(d.queue_free)
	_decals.append(d)
	if OS.get_cmdline_user_args().has("--demo"):
		print("WET %d at %s n=%s size=%.2f on=%s" % [_decals.size(), p.snapped(Vector3(0.01, 0.01, 0.01)), y.snapped(Vector3(0.01, 0.01, 0.01)), size, str(on)])
	while _decals.size() > MAX:
		var old: Decal = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func _build_textures() -> void:
	# an irregular blot: soft edged, with ragged fingers where the water ran
	const S := 128
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var a := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var orm := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var u := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(S) * 2.0 - Vector2.ONE
			var r := u.length()
			var nz := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var v := (1.0 - r) * 2.0 + (nz - 0.5) * 1.1 - 0.15
			v = smoothstep(0.0, 0.3, v) * (1.0 - smoothstep(0.85, 1.0, r))
			a.set_pixel(x, y, Color(WET_COLOR.r, WET_COLOR.g, WET_COLOR.b, v))
			orm.set_pixel(x, y, Color(1.0, 0.18, 0.0, v))
	a.generate_mipmaps()
	orm.generate_mipmaps()
	_tex_a = ImageTexture.create_from_image(a)
	_tex_orm = ImageTexture.create_from_image(orm)
