extends Node3D
## Builds the white-box village, the player, the water and the input map. Pass `-- --demo` to run a
## scripted walkthrough that saves frames to the user data folder (used to check the slice without a pad).

var player: Player
var water: WaterBody
var _white: StandardMaterial3D
var _demo := false
var _demo_t := 0.0
var _demo_dir := ""
var _demo_frame := 0
var _sign: SignBoard

func _ready() -> void:
	_setup_input()
	_white = StandardMaterial3D.new()
	_white.albedo_color = Color(0.93, 0.92, 0.90)
	_white.roughness = 0.92
	_build_environment()
	_build_ground()
	_build_village()
	add_child(Wetness.new())
	add_child(IceField.new())
	_build_props()
	_build_dummies()
	_build_button()

	var barrel := WaterSource.new()
	barrel.position = Vector3(-1.6, 0, -4.2)
	add_child(barrel)
	var barrel2 := WaterSource.new()
	barrel2.position = Vector3(6.5, 0, -5.0)
	add_child(barrel2)
	var fountain := Fountain.new()
	fountain.position = Vector3(1.0, 0, -17.0)
	add_child(fountain)

	_sign = SignBoard.new()
	_sign.position = Vector3(5.5, 0, -13.0)
	add_child(_sign)

	player = Player.new()
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	water = WaterBody.new()
	add_child(water)
	player.attach_water(water)
	player.reticle = _make_hud()
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	add_child(OptionsMenu.new())

	_demo = "--demo" in OS.get_cmdline_user_args()
	if "--v3" in OS.get_cmdline_user_args():
		player.draw_variant = 1
	if _demo:
		_demo_dir = ProjectSettings.globalize_path("user://demo")
		DirAccess.make_dir_recursive_absolute(_demo_dir)

# ---------------------------------------------------------------- input

## The actions and their bindings live in Controls (defaults, the player's saved changes, the menu).
func _setup_input() -> void:
	Controls.setup()
	# the frame rate is capped: past 60 the GPU only heats up (the ray-marched water is costly per frame)
	Engine.max_fps = 40

# ---------------------------------------------------------------- scene

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.45, 0.35, 0.92)
	sm.sky_horizon_color = Color(0.2, 0.1, 0.3)
	sm.ground_horizon_color = Color(0.2, 0.1, 0.3)
	sm.ground_bottom_color = Color(0.2, 0.1, 0.3)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

## Where the --pond test stands: on the stream's near bank, level with the old pond.
const POND_AT := Vector3(-23.0, 0.0, -11.0)
const DOCK_Z := -3.0

## The ground, with the stream's channel cut through it (its bed sits in the cut).
func _build_ground() -> void:
	var pond := Pond.new()
	var g := CSGBox3D.new()
	g.size = Vector3(160, 1, 160)
	g.position.y = -0.5
	g.material = _white
	g.use_collision = true
	var hole := CSGPolygon3D.new()
	hole.polygon = pond.outline()
	hole.mode = CSGPolygon3D.MODE_DEPTH
	hole.depth = 1.4
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	# the outline is drawn in the polygon's x-y; turned so its y runs along world z and it extrudes upward
	hole.rotation_degrees.x = 90.0
	hole.position = Vector3(0, -1.2 + 0.5, 0)
	g.add_child(hole)
	add_child(g)
	add_child(pond)
	_build_dock()

## A small wooden dock from the near bank out over the stream, and a one-person fishing boat moored by it.
func _build_dock() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.82, 0.48)
	wood.roughness = 0.9
	var bank := Pond.near_bank_x(DOCK_Z)
	var x0 := bank + 1.6          # on land
	var x1 := bank - 6.5          # out over the water
	var dock := StaticBody3D.new()
	var deck_y := 0.22
	var parts := [[Vector3((x0 + x1) * 0.5, deck_y, DOCK_Z), Vector3(absf(x0 - x1), 0.08, 1.6)]]
	var x := x1 + 0.3
	while x < bank + 0.5:
		for sz in [-0.7, 0.7]:
			parts.append([Vector3(x, (deck_y - 1.5) * 0.5, DOCK_Z + sz), Vector3(0.14, deck_y + 1.5, 0.14)])
		x += 2.0
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = wood
		mi.position = p[0]
		dock.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p[1]
		cs.shape = bs
		cs.position = p[0]
		dock.add_child(cs)
	add_child(dock)
	var boat := Boat.new()
	boat.position = Vector3(bank - 4.2, Pond.WATER_Y + 0.05, DOCK_Z - 2.0)
	boat.rotation.y = PI * 0.5 + 0.15
	add_child(boat)

## The big blue button on the near side of the first house on the right: water pressed into it calls a
## person out.
func _build_button() -> void:
	var b := SpawnButton.new()
	b.position = Vector3(10.0, 1.3, -2.5)     # the house's side facing the start, away from door and windows
	b.spawn_at = Vector3(6.0, 0.05, -1.0)
	add_child(b)

## Straw training dummies on posts.
func _build_dummies() -> void:
	for p in [Vector3(3.6, 0, -2.6), Vector3(-2.8, 0, -7.2), Vector3(4.8, 0, -11.8)]:
		var d := Dummy.new()
		d.position = p + Vector3(0, Dummy.POST_H, 0)
		d.rotation.y = randf_range(-0.6, 0.6)
		add_child(d)

func _house(pos: Vector3, size: Vector3, yaw_deg: float) -> void:
	var root := CSGBox3D.new()
	root.size = size
	root.material = _white
	root.use_collision = true
	root.position = pos + Vector3(0, size.y * 0.5, 0)
	root.rotation_degrees.y = yaw_deg
	var door := CSGBox3D.new()
	door.size = Vector3(1.2, 2.1, 1.0)
	door.position = Vector3(0, -size.y * 0.5 + 1.05, size.z * 0.5)
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(door)
	for wx in [-size.x * 0.3, size.x * 0.3]:
		var w := CSGBox3D.new()
		w.size = Vector3(0.9, 0.9, 1.0)
		w.position = Vector3(wx, 0.4, size.z * 0.5)
		w.operation = CSGShape3D.OPERATION_SUBTRACTION
		root.add_child(w)
	add_child(root)

func _village_layout() -> Array:
	return [
		[Vector3(-8, 0, -6), Vector3(5, 3.2, 6), 90.0],
		[Vector3(-9, 0, -16), Vector3(6, 3.6, 5), 80.0],
		[Vector3(10, 0, -5), Vector3(5, 3.0, 6), -90.0],
		[Vector3(11, 0, -17), Vector3(7, 3.4, 5), -100.0],
		[Vector3(-2, 0, -24), Vector3(8, 3.8, 5), 0.0],
		[Vector3(-14, 0, 4), Vector3(5, 3.0, 5), 60.0],
		[Vector3(13, 0, 5), Vector3(5, 3.0, 5), -60.0],
	]

func _build_village() -> void:
	for h in _village_layout():
		_house(h[0], h[1], h[2])

## Loose crates for precision mode to wash over, shove, grab and carry: three small ones (6 kg), stacked,
## and one heavy one (35 kg).
func _build_props() -> void:
	for c in [[Vector3(2.2, 0.25, -8.5), 0.5, 6.0], [Vector3(2.9, 0.25, -8.1), 0.5, 6.0],
			[Vector3(2.55, 0.76, -8.3), 0.5, 6.0], [Vector3(-3.4, 0.45, -10.0), 0.9, 35.0]]:
		var rb := RigidBody3D.new()
		rb.mass = c[2]
		rb.position = c[0]
		rb.rotation.y = randf_range(-0.3, 0.3)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * float(c[1])
		mi.mesh = bm
		mi.material_override = _white
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * float(c[1])
		cs.shape = bs
		rb.add_child(cs)
		rb.add_to_group("crate")
		add_child(rb)

func _make_hud() -> Control:
	var layer := CanvasLayer.new()
	add_child(layer)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var ctr := c.size * 0.5
		c.draw_arc(ctr, 9.0, 0.0, TAU, 28, Color(1, 1, 1, 0.85), 2.0, true)
		c.draw_circle(ctr, 2.0, Color(1, 1, 1, 0.9)))
	layer.add_child(c)
	return c

# ---------------------------------------------------------------- demo capture

func _process(dt: float) -> void:
	if not _demo:
		return
	_demo_t += dt
	if "--side" in OS.get_cmdline_user_args() and _demo_step == 0 and _demo_t > 0.2:
		var sc := Camera3D.new()
		add_child(sc)
		sc.global_position = Vector3(5.0, 1.8, -2.0)
		sc.look_at(Vector3(-1.0, 1.0, -2.4))
		sc.fov = 62.0
		sc.current = true
		_demo_step = -1
	if "--front" in OS.get_cmdline_user_args() and _demo_t > 0.2 and _demo_step <= 0:
		var fc := Camera3D.new()
		add_child(fc)
		fc.global_position = Vector3(0.4, 1.4, -4.2)
		fc.look_at(Vector3(0.0, 1.0, -1.2))
		fc.current = true
		_demo_step = -1
	_run_demo_script()
	if "--play" in OS.get_cmdline_user_args():
		_play_capture(dt)
		return
	var rate := 20.0 if (_demo_t > 14.8 and _demo_t < 17.6) or (_demo_t > 4.0 and _demo_t < 6.0) else 5.0
	if "--mocap" in OS.get_cmdline_user_args():
		rate = 15.0 if (_demo_t > 4.4 and _demo_t < 9.0) or (_demo_t > 11.3 and _demo_t < 13.8) else 4.0
	if _demo_t >= _next_cap:
		_next_cap = _demo_t + 1.0 / rate
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/t%05d.png" % [_demo_dir, int(_demo_t * 100.0)])
		print("t=%.2f fps=%d water=%s barrel=%.1f aim=%s sign_broken=%s" % [_demo_t, Engine.get_frames_per_second(), WaterBody.S.keys()[water.state], get_tree().get_first_node_in_group("water_source").level, player.aim_point.snapped(Vector3(0.1,0.1,0.1)), _sign.broken])
	if _demo_t > (25.0 if "--anim" in OS.get_cmdline_user_args() else (17.0 if "--mocap" in OS.get_cmdline_user_args() else 22.0)):
		get_tree().quit()

var _demo_step := 0
var _next_cap := 0.0

func _at(t: float) -> bool:
	return _demo_t >= t

func _run_demo_script() -> void:
	if "--anim" in OS.get_cmdline_user_args():
		_run_anim_demo()
		return
	if "--mocap" in OS.get_cmdline_user_args():
		_run_mocap_demo()
		return
	if "--play" in OS.get_cmdline_user_args():
		_run_play_demo()
		return
	# the barrel is toward -Z and slightly left; the sign far ahead and to the right
	if _at(0.5) and (_demo_step == 0 or _demo_step == -1):
		_demo_step = 1
		Input.action_press("move_forward", 0.6)
	if _at(1.5) and _demo_step == 1:
		_demo_step = 2
		Input.action_release("move_forward")
	if _at(2.5) and _demo_step == 2:
		_demo_step = 3
		_tap("moves_up")
	if _demo_step == 3:
		# drawing needs the crosshair on the barrel
		_aim_goal = _find_target("barrel")
		_steer_cam(true)
	if _at(4.0) and _demo_step == 3:
		_demo_step = 4
		Input.action_press("draw")
	if _at(11.0) and _demo_step == 4:
		_demo_step = 5
	if _demo_step == 5:
		# turn the camera toward the sign (to the right of the barrel direction)
		var cp := player.cam.global_position
		var to := Vector3(6.5, 2.55, -13.0) - cp
		var target := atan2(-to.x, -to.z)
		player.cam_yaw = lerp_angle(player.cam_yaw, target, 0.05)
		player.cam_pitch = lerp(player.cam_pitch, atan2(to.y, Vector2(to.x, to.z).length()), 0.05)
	if _at(15.0) and _demo_step == 5:
		_demo_step = 6
		_tap("strike")


func _tap(action: String) -> void:
	Input.action_press(action)
	get_tree().create_timer(0.15).timeout.connect(func(): Input.action_release(action))

func _run_anim_demo() -> void:
	var presses := [1.0, 2.0, 7.0, 10.0, 15.0, 18.0, 23.0]
	if _at(presses[0]) and _demo_step < 1:
		_demo_step = 1
		_tap("moves_up")
	for i in [1, 3, 5]:
		if _at(presses[i]) and _demo_step == i:
			_demo_step = i + 1
			Input.action_press("draw")
	for i in [2, 4, 6]:
		if _at(presses[i]) and _demo_step == i:
			_demo_step = i + 1
			Input.action_release("draw")
			_tap("drop")

func _run_mocap_demo() -> void:
	if _at(1.0) and _demo_step <= 0:
		_demo_step = 1
		_tap("moves_up")
	if _at(4.5) and _demo_step == 1:
		_demo_step = 2
		Input.action_press("draw")
	if _at(11.5) and _demo_step == 2:
		_demo_step = 3
		_tap("strike")
	if _at(15.0) and _demo_step == 3:
		_demo_step = 4
		Input.action_release("draw")
		_tap("drop")

# ---------------------------------------------------------------- full playthrough check
# stand, ready, walk in ready, stop, draw, hold, walk holding, strike, release, stand, walk.
# A camera follows from the side; every frame the largest single-frame bone rotation is logged so pops
# show up as numbers, not only in pictures.

var _play_cam: Camera3D
var _prev_pose := {}
var _play_events := [
	[1.0, "tap", "moves_up"], [4.0, "press", "move_forward"], [5.6, "release", "move_forward"],
	[6.2, "aimat", "barrel"], [7.5, "press", "draw"], [7.6, "release", "draw"], [7.6, "cam", 0.0, -0.12],
	[11.5, "press", "move_forward"], [12.8, "release", "move_forward"],
	[14.5, "tap", "strike"], [17.0, "release", "draw"], [17.0, "tap", "drop"], [18.0, "tap", "drop"],
	[20.0, "press", "move_forward"], [21.2, "release", "move_forward"]]

var _held := {}

# precision mode check (--steer): draw, then steer the water onto the ground, along a wall, onto the
# crates, grab one, lift and carry it, drop it, then let the water fall
var _steer_events := [
	[1.0, "tap", "moves_up"], [1.5, "aimat", "barrel", 0.6], [3.0, "press", "draw"], [3.1, "release", "draw"], [3.1, "cam", 0.0, -0.12],
	[5.0, "tap", "precise"],
	[5.0, "cam", 0.0, -0.45], [5.0, "stick", -0.5], [5.35, "stick", 0.0], [6.5, "cam", 0.75, -0.1], [6.5, "stick", -0.5], [6.8, "stick", 0.0],
	[8.0, "cam", 0.45, 0.05], [9.0, "aimat", "crate"], [9.0, "stick", -0.5], [9.35, "stick", 0.0],
	[10.0, "press", "strike"], [11.0, "cam", -0.1, 0.15], [11.0, "stick", 0.5], [11.55, "stick", 0.0],
	[12.5, "cam", 0.3, 0.0], [13.8, "release", "strike"], [14.5, "cam", 0.0, -0.1],
	[15.0, "tap", "precise"], [15.8, "tap", "precise"],
	[16.0, "stick", -0.5], [16.4, "stick", 0.0], [16.8, "release", "draw"], [16.8, "tap", "drop"], [18.5, "aimat", "puddle"], [19.8, "press", "draw"], [20.0, "release", "draw"], [20.0, "cam", 0.0, -0.12]]
# fountain check (--fountain): draw from the pool, steer the water out over the basin, let it fall back in
var _fountain_events := [
	[1.0, "tap", "moves_up"], [1.5, "aimat", "fountain"], [3.0, "press", "draw"], [3.1, "release", "draw"], [3.1, "cam", 0.0, -0.15],
	[6.5, "tap", "precise"], [6.6, "aimat", "fountain"], [6.6, "stick", -0.5], [7.4, "stick", 0.0],
	[9.5, "release", "draw"], [9.5, "tap", "drop"], [9.5, "cam", 0.0, -0.2], [12.0, "tap", "drop"]]
# forms check (--forms): draw from the barrel; lash a dummy, then lash-grab and pull it; slice three
# times; pick ice spike on the wheel and throw two small and one large; draw again, pick ice wall, freeze ice
# on the ground in front
var _forms_events := [
	[1.0, "tap", "moves_up"], [1.4, "aimat", "barrel"], [2.4, "press", "draw"], [4.0, "release", "draw"], [4.0, "aimat", "dummy0"],
	[4.8, "tap", "strike"], [5.6, "press", "strike"], [6.6, "turn", 1.7], [6.85, "release", "strike"],
	[7.2, "tap", "moves_right"],
	[8.0, "aimat", "dummy1"], [9.0, "tap", "strike"], [9.5, "tap", "strike"], [10.0, "tap", "strike"],
	[10.5, "tap", "moves_down"],
	[11.6, "aimat", "dummy2"], [12.5, "tap", "strike"], [13.0, "tap", "strike"], [13.6, "press", "strike"], [14.8, "release", "strike"],
	[15.2, "release", "draw"], [15.2, "tap", "drop"], [15.5, "aimat", "barrel"], [16.3, "press", "draw"],
	[18.8, "tap", "moves_left"],
	[19.8, "release", "draw"], [19.8, "cam", 0.2, -0.45], [20.5, "press", "strike"], [22.0, "release", "strike"],
	# walk on over the ice just made (stepping up onto it)
	[22.2, "cam", 0.2, -0.1], [22.4, "press", "move_forward"], [24.6, "release", "move_forward"]]
# spike volley (--volley): on the stream's bank, draw and gather 600 L, pick ice spike, hold R2 while the
# spikes form, throw them at the boat
var _volley_events := [
	[1.0, "tap", "moves_up"], [1.4, "aimat", "pond"], [2.4, "press", "draw"], [10.5, "release", "draw"], [10.5, "aimat", "boat"],
	[11.0, "tap", "moves_down"],
	[12.2, "press", "strike"], [14.5, "release", "strike"], [16.5, "release", "draw"], [16.5, "tap", "drop"]]
# Serpent (--serpent): by the fountain, gather 600 L; Serpent (the water melds in, nothing held); draw
# 30 L more while in it; rise; glide over the fountain to the house behind it; sink onto its roof; add the
# held water to Serpent; walk on the roof; relax (L1), which drops Serpent
var _serpent_events := [
	[1.0, "tap", "moves_up"], [1.5, "aimat", "fountain"], [2.4, "press", "draw"], [8.0, "release", "draw"], [8.0, "cam", 0.0, -0.1],
	[8.50, "press", "forms"], [8.80, "press", "look_up"], [9.10, "release", "forms"], [9.15, "release", "look_up"], [9.2, "release", "draw"], [9.6, "aimat", "fountain"], [10.2, "press", "draw"],
	[11.4, "release", "draw"], [11.4, "cam", 0.0, -0.1], [11.4, "press", "jump"], [14.0, "press", "move_forward"], [17.0, "release", "move_forward"],
	[17.6, "release", "jump"], [21.00, "press", "forms"], [21.30, "press", "look_up"], [21.60, "release", "forms"], [21.65, "release", "look_up"], [22.0, "press", "move_forward"], [23.0, "release", "move_forward"],
	[24.0, "tap", "forms"]]
# ice wall (--wall): draw from the barrel; pick ice wall; tap two walls; slice the first; break the second
# with small spikes; drop the water; draw the first wall's ice back up as water
var _wall_events := [
	[1.0, "tap", "moves_up"], [1.4, "aimat", "barrel"], [2.4, "press", "draw"], [5.5, "release", "draw"], [5.5, "cam", 0.0, -0.1],
	[6.0, "tap", "moves_left"],
	[7.2, "cam", 0.0, -0.3], [7.8, "tap", "strike"], [8.6, "cam", 0.6, -0.3], [9.2, "tap", "strike"],
	[9.8, "tap", "moves_right"],
	[10.8, "aimat", "wall0"], [11.6, "tap", "strike"],
	[12.0, "tap", "moves_down"],
	[13.0, "aimat", "wall1"], [13.6, "tap", "strike"], [14.0, "tap", "strike"], [14.4, "tap", "strike"], [14.8, "tap", "strike"],
	[15.2, "tap", "strike"], [15.6, "tap", "strike"],
	[16.2, "release", "draw"], [16.2, "tap", "drop"], [17.0, "aimat", "wall0"], [18.0, "press", "draw"], [21.0, "release", "draw"], [21.0, "tap", "drop"]]
# large body (--large): on the bank by the dock: a geyser under the boat; a wave raised, swept wider,
# sent across the stream onto the far bank; then upstream, the stream parted (L2 + R2), walked into, then
# let close
var _large_events := [
	[1.0, "tap", "moves_up"], [1.5, "aimat", "boat"], [2.5, "tap", "strike"],
	[4.0, "aimat", "pond"], [4.6, "press", "strike"], [5.2, "turn", 0.9], [6.6, "release", "strike"],
	[12.0, "place", -38.0], [12.4, "aimat", "upstream"], [13.4, "press", "precise"], [13.5, "press", "strike"],
	[14.2, "press", "move_forward"], [17.0, "release", "move_forward"],
	[17.2, "release", "strike"], [17.2, "release", "precise"]]
# Octopus (--octopus): by the fountain, gather 600 L; Octopus (the water melds in); let go of R1; hold R2
# and mark two crates and the heavy one; let go (grabbed in order); pick a tentacle with the stick; strike
# with an empty one (fast); pick one holding something and strike (heavier); throw it; drop another;
# switch to Serpent and back; relax (drops it)
var _octo_events := [
	[1.0, "tap", "moves_up"], [1.5, "aimat", "fountain"], [2.4, "press", "draw"], [7.5, "release", "draw"], [7.5, "aimat", "crate0"],
	[8.00, "press", "forms"], [8.30, "press", "look_down"], [8.60, "release", "forms"], [8.65, "release", "look_down"], [8.8, "release", "draw"], [9.3, "press", "strike"], [10.0, "aimat", "crate1"],
	[10.8, "aimat", "crate3"], [11.8, "release", "strike"], [13.5, "stickv", 0.9, 0.0], [13.8, "stickv", 0.0, 0.0],
	[14.2, "octo_empty"], [14.3, "tap", "jump"], [15.5, "octo_held"], [15.6, "tap", "jump"],
	[17.0, "aimat", "dummy1"], [17.8, "tap", "strike"], [18.5, "octo_held"], [18.7, "tap", "precise"],
	[19.50, "press", "forms"], [19.80, "press", "look_up"], [20.10, "release", "forms"], [20.15, "release", "look_up"], [20.50, "press", "forms"], [20.80, "press", "look_down"], [21.10, "release", "forms"], [21.15, "release", "look_down"], [21.50, "press", "forms"], [21.80, "press", "look_down"], [22.10, "release", "forms"], [22.15, "release", "look_down"]]
# a line of people (--line): three standing one behind another; one horizontal slice at the first: only
# the first is cut, and only where the blade meets them first
var _line_events := [
	[0.3, "spawn", 0.0, -4.0], [0.3, "spawn", 0.15, -5.2], [0.3, "spawn", -0.15, -6.4],
	[1.0, "tap", "moves_up"], [1.4, "aimat", "barrel"], [2.4, "press", "draw"],
	[4.0, "release", "draw"], [4.0, "aimat", "person0"], [4.3, "tap", "moves_right"], [5.6, "tap", "strike"]]
# people (--people): draw and gather; lash the blue button twice (two people); pick slice; slice one
# across the chest, the other through the shoulder; slice the button for a third; spike them
var _people_events := [
	[1.0, "tap", "moves_up"], [1.4, "aimat", "barrel"], [2.4, "press", "draw"], [4.6, "release", "draw"], [4.6, "aimat", "button"],
	[5.8, "tap", "strike"], [6.9, "tap", "strike"],
	[7.2, "tap", "moves_right"],
	[8.0, "aimat", "person0"], [9.0, "tap", "strike"], [9.3, "aimat", "person1", 0.24], [10.0, "tap", "strike"],
	[10.6, "aimat", "button"], [11.4, "tap", "strike"],
	[11.8, "tap", "moves_down"],
	[13.0, "aimat", "person2"], [13.8, "tap", "strike"]]
# stepping (--step): two low ice blocks ahead (25 cm, then 40 cm high); walk over both
var _step_events := [
	[0.3, "iceblock", -2.0, -3.4, 0.25], [0.3, "iceblock", -3.4, -4.5, 0.40], [1.0, "cam", 0.0, -0.1],
	[1.5, "press", "move_forward"], [5.0, "release", "move_forward"]]
# upper body (--twist): ready stance standing, then walking forward; logs the shoulder line's yaw against
# the body's facing (it should be the same standing and walking)
var _twist_events := [
	[0.5, "tap", "moves_up"], [0.6, "cam", 0.0, -0.1], [3.0, "press", "move_forward"], [6.0, "release", "move_forward"]]
# amputation (--amputee): a person standing still in front; a vertical slice through their left shoulder
var _amputee_events := [
	[0.3, "spawn", 0.0, -5.0], [1.0, "tap", "moves_up"], [1.4, "aimat", "barrel"], [2.4, "press", "draw"],
	[4.0, "release", "draw"], [4.0, "aimat", "person0", 0.2], [4.3, "tap", "moves_right"], [5.6, "slice_v"], [5.6, "tap", "strike"]]
var _aim_name := ""
var _aim_off := 0.0
# pond check (--pond): at the shore, draw from the pond and keep drawing; drop it; pick ice wall and
# freeze the pond's surface; walk out onto the ice
var _pond_events := [
	[1.0, "tap", "moves_up"], [1.4, "aimat", "pond"], [2.4, "press", "draw"], [9.0, "release", "draw"], [9.0, "tap", "drop"],
	[10.0, "tap", "moves_left"],
	[11.0, "cam", 1.5708, -0.95], [11.8, "press", "strike"], [11.9, "cam", 1.5708, -0.3], [13.6, "release", "strike"],
	[13.8, "cam", 1.5708, -0.1], [15.0, "press", "move_forward"], [16.0, "release", "move_forward"]]
var _placed := false
var _on_ice := false
var _last_hint := ""
var _cam_goal := Vector2(INF, 0.0)
var _aim_goal = null
var _stick := 0.0
var _stick_x := 0.0

func _find_target(what: String):
	for n in get_tree().get_nodes_in_group("crate" if what == "crate" else "water_source"):
		if (what == "barrel" and n is WaterSource) or (what == "puddle" and n is Puddle):
			return (n as Node3D).global_position + Vector3(0, 0.5 if n is WaterSource else 0.0, 0)
		if what == "fountain" and n is Fountain:
			# the near part of the pool, between the curtain and the wall
			var fp: Vector3 = n.global_position
			var tp := Vector3(player.global_position.x - fp.x, 0, player.global_position.z - fp.z).normalized() * 1.5
			return fp + tp + Vector3(0, n.water_y(), 0)
		if what == "crate":
			return (n as Node3D).global_position
	if what.begins_with("crate"):
		var cs := get_tree().get_nodes_in_group("crate").filter(func(c): return c is RigidBody3D and not c.is_in_group("boat") and not c.is_in_group("dummy") and not c is IceBlock)
		var i := int(what.substr(5))
		return (cs[i] as Node3D).global_position if i < cs.size() else null
	if what.begins_with("dummy"):
		var ds := get_tree().get_nodes_in_group("dummy")
		var i := int(what.substr(5))
		if i < ds.size():
			return (ds[i] as Node3D).global_position + Vector3(0, 0.45, 0)
	if what == "pond":
		return Vector3(Pond.near_bank_x(POND_AT.z) - 4.0, Pond.WATER_Y, POND_AT.z)
	if what == "boatwater":
		# the water just short of the boat
		var b := get_tree().get_first_node_in_group("boat")
		return Vector3((b as Node3D).global_position.x + 0.2, Pond.WATER_Y, (b as Node3D).global_position.z + 2.2) if b else null
	if what == "upstream":
		# the stream upstream of the village, toward its far side
		return Vector3(Pond.near_bank_x(-38.0) - 7.0, Pond.WATER_Y, -43.0)
	if what == "boat":
		var b := get_tree().get_first_node_in_group("boat")
		return (b as Node3D).global_position + Vector3(0, 0.3, 0) if b else null
	if what == "button":
		var b := get_tree().get_first_node_in_group("button")
		return (b as Node3D).global_position + Vector3(0, 0, 0.2) if b else null
	if what.begins_with("wall"):
		# standing walls, oldest first: their middle
		var ws := get_tree().get_nodes_in_group("ice").filter(func(b): return b is IceBlock and b.freeze and not b.is_queued_for_deletion())
		var i := int(what.substr(4))
		if i >= ws.size():
			return null
		return (ws[i] as IceBlock).near_point(Vector3.ZERO)
	if what.begins_with("person"):
		# the people still standing, oldest first; the chest
		var ps := get_tree().get_nodes_in_group("person").filter(func(p): return not p.is_queued_for_deletion() and p.life < 0.0)
		var i := int(what.substr(6))
		if ps.is_empty():
			return null
		return (ps[mini(i, ps.size() - 1)] as Node3D).global_position + Vector3(0, 1.2, 0)
	return null

## Turns the scripted camera so the crosshair lands on _aim_goal (or toward _cam_goal).
func _steer_cam(snap := false) -> void:
	if _aim_goal != null:
		var d: Vector3 = _aim_goal - player.cam.global_position
		_cam_goal = Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	if _cam_goal.x != INF:
		var k := 1.0 if snap else 1.0 - exp(-get_process_delta_time() * 4.0)
		player.cam_yaw = lerp_angle(player.cam_yaw, _cam_goal.x, k)
		player.cam_pitch = lerpf(player.cam_pitch, _cam_goal.y, k)

func _run_play_demo() -> void:
	var ua := OS.get_cmdline_user_args()
	var events: Array = _play_events
	if "--forms" in ua:
		events = _forms_events
	elif "--pond" in ua:
		events = _pond_events
	elif "--fountain" in ua:
		events = _fountain_events
	elif "--steer" in ua:
		events = _steer_events
	elif "--volley" in ua:
		events = _volley_events
	elif "--serpent" in ua:
		events = _serpent_events
	elif "--wall" in ua:
		events = _wall_events
	elif "--line" in ua:
		events = _line_events
	elif "--large" in ua:
		events = _large_events
	elif "--octopus" in ua:
		events = _octo_events
	elif "--people" in ua:
		events = _people_events
	elif "--step" in ua:
		events = _step_events
	elif "--amputee" in ua:
		events = _amputee_events
	elif "--twist" in ua:
		events = _twist_events
		if int(_demo_t * 4.0) != int((_demo_t - get_process_delta_time()) * 4.0):
			var sk := player.skel
			var l := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("clavicle_l")).origin
			var r := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("clavicle_r")).origin
			var v := r - l
			var sy := rad_to_deg(wrapf(atan2(v.x, v.z) - player.rotation.y, -PI, PI))
			print("TWIST t=%.2f anim=%s shoulders_vs_body=%.1f body=%.1f cam=%.1f upper_influence=%.2f" % [_demo_t, player._anim_state, sy, rad_to_deg(player.rotation.y), rad_to_deg(player.cam_yaw), player._upper.weight])
	if not _placed:
		_placed = true
		if "--fountain" in ua or "--serpent" in ua:
			player.global_position = Vector3(1.0, 0.05, -11.0)
		if "--people" in ua:
			# within the lash's reach of the button, and the barrel's
			player.global_position = Vector3(3.0, 0.05, 0.5)
		if "--octopus" in ua:
			player.global_position = Vector3(1.0, 0.05, -11.0)
		if "--large" in ua:
			player.global_position = Vector3(Pond.near_bank_x(-6.0) + 1.0, 0.05, -6.0)
			player.cam_yaw = 1.5708
		if "--pond" in ua or "--volley" in ua:
			player.global_position = Vector3(Pond.near_bank_x(POND_AT.z) + 1.0, 0.05, POND_AT.z)
			player.cam_yaw = 1.5708
	while not events.is_empty() and _demo_t >= float(events[0][0]):
		var e: Array = events.pop_front()
		match e[1]:
			"tap": _tap(e[2])
			"press": _held[e[2]] = true
			"release":
				_held.erase(e[2])
				Input.action_release(e[2])
			"cam":
				_aim_goal = null
				_aim_name = ""
				_cam_goal = Vector2(e[2], e[3])
			"turn":
				# a hard turn by e[2] rad from where the camera is now
				_aim_goal = null
				_aim_name = ""
				_cam_goal = Vector2(player.cam_yaw + float(e[2]), player.cam_pitch)
			"aimat":
				_aim_goal = _find_target(e[2])
				# optional sideways miss (m), to test the aim tolerance
				_aim_off = float(e[3]) if e.size() > 3 else 0.0
				if _aim_goal != null:
					_aim_goal += player.cam.global_transform.basis.x * _aim_off
				# people walk about: the aim follows them
				_aim_name = e[2] if (e[2] as String).begins_with("person") else ""
			"stick": _stick = e[2]
			"stickv":
				_stick = e[3]
				_stick_x = e[2]
			"octo_held", "octo_empty":
				# the test picks a tentacle that holds something (or one that holds nothing)
				var o := player.octopus
				for i in o.limbs.size():
					if (o.limbs[i].phase == Octopus.P.HOLD) == (e[1] == "octo_held"):
						o.current = i
						break
			"place":
				# onto the near bank at z e[2], facing across the stream
				player.global_position = Vector3(Pond.near_bank_x(e[2]) + 0.6, 0.05, e[2])
				player.velocity = Vector3.ZERO
			"spawn":
				# a person standing still, facing the start
				var pn := Person.new()
				pn.wander = false
				pn.position = Vector3(e[2], 0.05, e[3])
				pn.rotation.y = PI
				add_child(pn)
			"slice_v":
				# the next slice vertical (second in the cycle)
				player._slice_i = 1
				player._slice_last = player._clock
			"iceblock":
				# ice from z e[2] to e[3], 1.4 m wide, e[4] high
				var z: float = e[2]
				while z > float(e[3]):
					var x := -0.7
					while x < 0.7:
						var c := IceField.cell_of(Vector3(x, 0, z))
						IceField.inst.cells[c] = {"b": -0.05, "t": float(e[4]), "src": null}
						IceField.inst._mark(c)
						x += IceField.CELL
					z -= IceField.CELL
		print("EVENT t=%.2f %s" % [_demo_t, str(e.slice(1))])
	if _aim_name != "":
		var g = _find_target(_aim_name)
		if g != null:
			_aim_goal = g + player.cam.global_transform.basis.x * _aim_off
	_steer_cam()
	if int(_demo_t * 4.0) != int((_demo_t - get_process_delta_time()) * 4.0):
		var ps := []
		for s in get_tree().get_nodes_in_group("water_source"):
			if not s is Pond:
				ps.append("%s:%.1fL" % ["P" if s is Puddle else ("F" if s is Fountain else ("I" if (s is IceBlock or s is IceField) else "B")), s.level])
		var spikes := 0
		var spike_l := 0.0
		for n in find_children("*", "IceSpike", true, false):
			spikes += 1
			spike_l += (n as IceSpike).litres
		var pieces := get_tree().get_nodes_in_group("crate").size()
		var att := []
		for d in get_tree().get_nodes_in_group("dummy"):
			att.append("%s@%s/%.1fkg/v%.1f" % ["on" if d.attached else "off", (d as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1)), d.mass, d.linear_velocity.length()])
		var ice_l := 0.0
		var ix := Vector2(INF, -INF)
		for k in IceField.inst.cells.keys():
			var c: Dictionary = IceField.inst.cells[k]
			ice_l += (c["t"] - c["b"]) * IceField.CELL * IceField.CELL * IceField.ICE_L_PER_M3
			ix = Vector2(minf(ix.x, k.x * IceField.CELL), maxf(ix.y, (k.x + 1) * IceField.CELL))
		if "--pond" in ua and ix.x < INF and _demo_t > 13.9 and not _on_ice:
			# stand the bender on the middle of the ice to check it holds them
			_on_ice = true
			var ks: Array = IceField.inst.cells.keys()
			ks.sort_custom(func(a, b): return a.x > b.x)
			var k0: Vector2i = ks[ks.size() / 2]
			var top: float = IceField.inst.cells[k0]["t"]
			player.global_position = IceField.centre(k0) + Vector3(0, top + 0.3, 0)
			print("PLACE on ice cell %s top %.2f" % [k0, top])
		if "--forms" in ua and _demo_t > 22.1 and _demo_t < 22.3:
			var cl := []
			for k in IceField.inst.cells.keys():
				var c: Dictionary = IceField.inst.cells[k]
				cl.append("%s b%.2f t%.2f" % [IceField.centre(k).snapped(Vector3(0.01, 0.01, 0.01)), c["b"], c["t"]])
			print("ICECELLS ", cl)
		if "--pond" in ua and ix.x < INF:
			var under := ""
			for i in player.get_slide_collision_count():
				under += str(player.get_slide_collision(i).get_collider()) + "@" + str(player.get_slide_collision(i).get_position().snapped(Vector3(0.01, 0.01, 0.01))) + " "
			var c := IceField.cell_of(player.global_position)
			var here: Variant = IceField.inst.cells.get(c)
			print("ICE x %.2f..%.2f floor=%s under=%s cell=%s" % [ix.x, ix.y, player.is_on_floor(), under, str(here) if here != null else "-"])
		print("S t=%.2f water=%s L=%.1f thick=%.2f form=%s pos=%s spikes=%d/%.1fL pieces=%d dummies=%s ice=%d cells/%.1fL sources=%s" % [_demo_t, WaterBody.S.keys()[water.state], water.litres(), water.thick, player.FORM_NAMES[player.form], player.global_position.snapped(Vector3(0.01, 0.01, 0.01)), spikes, spike_l, pieces, ", ".join(att), IceField.inst.cells.size(), ice_l, ", ".join(ps)])
		var boat := get_tree().get_first_node_in_group("boat") as Node3D
		var people := get_tree().get_nodes_in_group("person").size()
		var flesh := get_tree().get_nodes_in_group("flesh").size()
		if "--large" in ua:
			var pd: Pond = get_tree().get_nodes_in_group("water_source").filter(func(x): return x is Pond)[0]
			var tp := pd.part_a + Vector3(pd.part_dir.x, 0, pd.part_dir.y) * 6.0
			var wv := find_children("*", "WaterWave", true, false)
			var lt: Array = player._large_target()
			print("LT %s" % (str((lt[1] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))) if not lt.is_empty() else "-"))
			print("DRY t=%.2f me_y=%.2f water_here=%.2f in_stream=%s" % [_demo_t, player.global_position.y, pd.surface_y(player.global_position.x, player.global_position.z), pd._inside(player.global_position, Pond.shore_f())])
			print("LARGE t=%.2f part_open=%.2f trench_y=%.2f beside_y=%.2f geysers=%d waves=%s" % [_demo_t, pd.part_open, pd.surface_y(tp.x, tp.z), pd.surface_y(tp.x + pd.part_dir.y * 2.6, tp.z - pd.part_dir.x * 2.6), find_children("*", "Geyser", true, false).size(), str(wv.map(func(w): return "%s h%.2f len%.1f" % [WaterWave.S.keys()[w.state], w.height(), w.length()]))])
		if "--octopus" in ua and player.in_octopus():
			var o := player.octopus
			var ls := []
			for i in o.limbs.size():
				var l = o.limbs[i]
				ls.append("%s%s%s" % [["idle", "reach", "hold", "back"][l.phase], "*" if i == o.current else "", ("@" + str(l.body.global_position.snapped(Vector3(0.1, 0.1, 0.1))) + "/" + str(int(l.body.mass)) + "kg") if l.body != null and is_instance_valid(l.body) else ""])
			print("OCT t=%.2f L=%.0f marking=%s marked=%d ts=%.2f zoom=%.2f water=%s limbs=%s" % [_demo_t, o.litres, o.marking, o.marked.size(), Engine.time_scale, player._zoom, WaterBody.S.keys()[water.state], ", ".join(ls)])
		var sf := player.serpent_form
		print("SERP t=%.2f on=%s L=%.1f eff=%s thin=%.2f max_h=%.2f feed=%s coming=%.1f segs=%d box=%s" % [_demo_t, sf.active, sf.litres, sf.effective(), sf._thin, player.serpent_max_h(), water.feeding(), water.litres_coming(), sf._w.count, sf._w.bounds().size.snapped(Vector3(0.01, 0.01, 0.01))])
		print("X t=%.2f speed=%.2f serpent_h=%.2f ground=%.2f boat=%s people=%d flesh=%d volley=%d" % [_demo_t, Vector2(player.velocity.x, player.velocity.z).length(), player.serpent_h(), player.ground_y, boat.global_position.snapped(Vector3(0.01, 0.01, 0.01)) if boat else "-", people, flesh, player._volley.count() if player._volley != null and is_instance_valid(player._volley) else 0])
		var hk := player.mode_name() + " | " + str(player.control_hints())
		if player.wheel_open:
			var hud: Hud = find_children("*", "Hud", true, false)[0]
			print("WHEEL t=%.2f pick=%s backdrop=%s wheel=%s fade=%.2f time_scale=%.2f" % [_demo_t, (player.wheel_names()[player.wheel_pick] if player.wheel_pick >= 0 else "-"), hud._backdrop.visible, hud._wheel.visible, hud._fade, Engine.time_scale])
		if hk != _last_hint:
			_last_hint = hk
			print("HUD t=%.2f %s" % [_demo_t, hk])
	# a connected pad's centred stick would cancel a single press, so held actions are pressed every frame
	player.debug_move = Vector2(0, -0.85) if _held.has("move_forward") else Vector2(_stick_x, _stick)
	if water.state == WaterBody.S.STEER or water.state == WaterBody.S.FALL:
		print("W t=%.2f %s head=%s tgt=%s len=%.2f grab=%s yaw=%.2f pitch=%.2f aim=%s dist=%.2f hv=%s" % [_demo_t, WaterBody.S.keys()[water.state], water.head_pos().snapped(Vector3(0.01, 0.01, 0.01)), water.steer_target.snapped(Vector3(0.01, 0.01, 0.01)), water.length, water.grabbed.global_position.snapped(Vector3(0.01, 0.01, 0.01)) if water.grabbed else "-", player.cam_yaw, player.cam_pitch, player.aim_point.snapped(Vector3(0.01, 0.01, 0.01)), player._ctrl_dist, water._head_v.snapped(Vector3(0.01, 0.01, 0.01))])
	for a in _held:
		if a != "move_forward":
			Input.action_press(a)

func _play_capture(dt: float) -> void:
	if _play_cam == null:
		_demo_dir = ProjectSettings.globalize_path("user://demo/run_%d" % int(Time.get_unix_time_from_system()))
		DirAccess.make_dir_recursive_absolute(_demo_dir)
		print("RUNDIR ", _demo_dir)
		_play_cam = Camera3D.new()
		add_child(_play_cam)
		_play_cam.fov = 50.0
		_play_cam.current = "--gamecam" not in OS.get_cmdline_user_args()
	var side := "--front" not in OS.get_cmdline_user_args()
	var pp := player.global_position
	var f := player.global_transform.basis.z   # the model faces -Z of the player... use world axes instead
	var off := Vector3(4.2, 1.3, 0.0) if side else Vector3(0.0, 1.2, -2.6)
	_play_cam.global_position = pp + off
	_play_cam.look_at(pp + Vector3(0, 0.9, 0))
	# largest bone rotation change since the last frame
	var sk := player.skel
	var worst := 0.0
	var worst_b := ""
	for b in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(b)
		if _prev_pose.has(b):
			var d := rad_to_deg((_prev_pose[b] as Quaternion).angle_to(q))
			if d > worst:
				worst = d
				worst_b = sk.get_bone_name(b)
		_prev_pose[b] = q
	var pel := sk.get_bone_pose_position(sk.find_bone("pelvis"))
	print("F t=%.3f state=%s node=%s worst=%.1f %s pel=%s pos=%s spd=%.2f mv=%s vel=%s" % [_demo_t, player._anim_state, player._playback.get_current_node(), worst, worst_b, pel.snapped(Vector3(0.01, 0.01, 0.01)), player.global_position.snapped(Vector3(0.01, 0.01, 0.01)), player._speed_s, Input.get_vector("move_left", "move_right", "move_forward", "move_back"), player.velocity.snapped(Vector3(0.01,0.01,0.01))])
	if _demo_t >= _next_cap:
		_next_cap = _demo_t + 1.0 / 10.0
		if not "--nocap" in OS.get_cmdline_user_args():
			get_viewport().get_texture().get_image().save_png("%s/p%05d.png" % [_demo_dir, int(_demo_t * 100.0)])
	var end := 22.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--len="):
			end = float(a.substr(6))
	if _demo_t > (4.0 if "--short" in OS.get_cmdline_user_args() else end):
		get_tree().quit()
