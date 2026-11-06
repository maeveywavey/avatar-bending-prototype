class_name Hud
extends CanvasLayer
## On-screen help: the current bending mode in the top right, and the controls available right now in
## the bottom right (each a button and what it does), both read from the player every frame.

var player: Player
var _mode: PanelContainer
var _mode_label: Label
var _list: GridContainer
var _last := ""
var _backdrop: ColorRect
var _wheel: WheelView
var _fade := 0.0                 # 0..1: how far the wheel and its backdrop are in

## The forms wheel: one sector per slot (up first, then clockwise, as Player picks them), the one under
## the stick lit, the form the bender is in marked. Empty slots (for later forms) are drawn dim, unlabelled.
class WheelView extends Control:
	var names: Array = []
	var pick := -1
	var current := -1
	var fade := 0.0
	const R_IN := 70.0
	const R_OUT := 190.0

	func _draw() -> void:
		var c := size * 0.5
		var n := names.size()
		if n == 0:
			return
		var font := ThemeDB.fallback_font
		var span := TAU / n
		for i in n:
			var a0 := i * span - span * 0.5 + 0.03
			var a1 := i * span + span * 0.5 - 0.03
			var pts := PackedVector2Array()
			var steps := 16
			for s in steps + 1:
				var a := lerpf(a0, a1, float(s) / steps)
				pts.append(c + Vector2(sin(a), -cos(a)) * R_OUT)
			for s in range(steps, -1, -1):
				var a := lerpf(a0, a1, float(s) / steps)
				pts.append(c + Vector2(sin(a), -cos(a)) * R_IN)
			var empty: bool = names[i] == ""
			var col := Color(0.06, 0.14, 0.2, 0.5 if empty else 0.82)
			if i == pick and not empty:
				col = Color(0.25, 0.62, 0.85, 0.92)
			elif i == pick:
				col = Color(0.12, 0.24, 0.32, 0.7)
			col.a *= fade
			draw_colored_polygon(pts, col)
			var edge := Color(0.75, 0.93, 1.0, (0.9 if i == pick else 0.35) * fade)
			pts.append(pts[0])
			draw_polyline(pts, edge, 2.0 if i == pick else 1.0, true)
			# the label in the middle of the sector
			var am := i * span
			var lp := c + Vector2(sin(am), -cos(am)) * (R_IN + R_OUT) * 0.5
			var fs := 22 if i == pick else 19
			var txt: String = names[i]
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tc := Color(1, 1, 1, fade) if i == pick else Color(0.8, 0.92, 1.0, 0.85 * fade)
			draw_string(font, lp + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
			if i == current:
				var mp := c + Vector2(sin(am), -cos(am)) * (R_OUT - 14.0)
				draw_circle(mp, 4.0, Color(0.75, 0.93, 1.0, fade))
		draw_arc(c, R_IN - 8.0, 0.0, TAU, 48, Color(0.75, 0.93, 1.0, 0.3 * fade), 1.5, true)

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# under everything else on the HUD: the world blurred and darkened while the wheel is open
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/wheel_backdrop.gdshader")
	_backdrop.material = bm
	_backdrop.visible = false
	root.add_child(_backdrop)

	_mode = PanelContainer.new()
	_mode.add_theme_stylebox_override("panel", _box(Color(0.05, 0.12, 0.18, 0.72), 10))
	_mode.anchor_left = 1.0
	_mode.anchor_right = 1.0
	_mode.offset_right = -24
	_mode.offset_top = 22
	_mode.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 22)
	_mode_label.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0))
	_mode.add_child(_mode_label)
	root.add_child(_mode)

	# two columns: the button, then what it does
	_list = GridContainer.new()
	_list.columns = 2
	_list.add_theme_constant_override("h_separation", 10)
	_list.add_theme_constant_override("v_separation", 6)
	_list.anchor_left = 1.0
	_list.anchor_right = 1.0
	_list.anchor_top = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_right = -24
	_list.offset_bottom = -22
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_list)

	_wheel = WheelView.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.visible = false
	root.add_child(_wheel)

func _box(c: Color, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(6)
	b.content_margin_left = pad + 4
	b.content_margin_right = pad + 4
	b.content_margin_top = pad * 0.5
	b.content_margin_bottom = pad * 0.5
	return b

func _process(dt: float) -> void:
	if player == null or player.water == null:
		return
	# the wheel fades in and out in real time (the world is slowed while it is open)
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	_fade = move_toward(_fade, 1.0 if player.wheel_open else 0.0, rdt / 0.12)
	_backdrop.visible = _fade > 0.0
	_wheel.visible = _fade > 0.0
	if _fade > 0.0:
		(_backdrop.material as ShaderMaterial).set_shader_parameter("amount", _fade)
		_wheel.names = player.wheel_names()
		_wheel.pick = player.wheel_pick
		_wheel.current = player.wheel_current()
		_wheel.fade = _fade
		_wheel.queue_redraw()
	var m := player.mode_name()
	_mode.visible = m != ""
	_mode_label.text = m
	var hints: Array = player.control_hints()
	var key := str(hints)
	if key == _last:
		return
	_last = key
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for h in hints:
		var act := Label.new()
		act.text = h[1]
		act.add_theme_font_size_override("font_size", 17)
		act.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		act.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		act.add_theme_constant_override("outline_size", 4)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _box(Color(0.05, 0.12, 0.18, 0.78), 6))
		var k := Label.new()
		k.text = h[0]
		k.add_theme_font_size_override("font_size", 16)
		k.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0))
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(k)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
		_list.add_child(chip)
		_list.add_child(act)
