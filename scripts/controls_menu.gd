class_name ControlsPage
extends VBoxContainer
## Options > Controls. It lists every action with its pad button and key; choosing one waits for the next
## press and binds it. A press already bound to another action swaps the two. Bindings are saved at once.

signal back

var _rows := {}                  # action -> [pad Button, key Button]
var first: Button
var _listen := []                # [action, kind] while waiting for a press, else []
var _listen_from := 0            # ms: presses before this are ignored (the one that chose the button)
var _status: Label
var _scroll: ScrollContainer

const STICK_SCROLL := 900.0      # px/s the right stick scrolls the list at full tilt

## True while waiting for a press (the menu then leaves Esc and the pad alone).
func listening() -> bool:
	return not _listen.is_empty()

## The right stick scrolls the list (any pad), in real time.
func _process(dt: float) -> void:
	if not is_visible_in_tree() or not _listen.is_empty():
		return
	var y := 0.0
	for pad in Input.get_connected_joypads():
		var v := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if absf(v) > absf(y):
			y = v
	if absf(y) < 0.25:
		return
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	_scroll.scroll_vertical += int(signf(y) * (absf(y) - 0.25) / 0.75 * STICK_SCROLL * rdt)

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(OptionsMenu.title("Controls"))
	var note := Label.new()
	note.text = "The game keeps running. Choose a binding, then press the new button or key."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.8, 0.88, 0.95, 0.8))
	add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# moving the focus (d-pad, left stick) past the bottom or top scrolls the list with it
	scroll.follow_focus = true
	add_child(scroll)
	_scroll = scroll
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for h in ["Action", "Controller", "Keyboard"]:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0, 0.7))
		grid.add_child(l)
	for a in Controls.ACTIONS:
		var name_l := Label.new()
		name_l.text = a[1]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 16)
		grid.add_child(name_l)
		var pair := []
		for kind in ["pad", "key"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 30)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(_choose.bind(a[0], kind))
			grid.add_child(b)
			pair.append(b)
			if first == null:
				first = b
		_rows[a[0]] = pair

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	add_child(_status)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	var reset := Button.new()
	reset.text = "Reset to Default"
	reset.pressed.connect(_reset)
	bar.add_child(reset)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func(): back.emit())
	bar.add_child(close)
	_refresh()

## Shown: fresh labels, focus on the first binding.
func shown() -> void:
	_listen = []
	_status.text = ""
	_refresh()
	first.grab_focus()

func _refresh() -> void:
	for a in _rows:
		var pair: Array = _rows[a]
		(pair[0] as Button).text = Controls.event_name(Controls.binding(a, "pad"))
		(pair[1] as Button).text = Controls.event_name(Controls.binding(a, "key"))

func _choose(action: String, kind: String) -> void:
	_listen = [action, kind]
	_listen_from = Time.get_ticks_msec() + 200
	var b: Button = _rows[action][0 if kind == "pad" else 1]
	b.text = "Press…"
	_status.text = "Press a %s for “%s” (Esc to cancel)." % ["controller button, trigger or stick" if kind == "pad" else "key or mouse button", _label(action)]

func _label(action: String) -> String:
	for a in Controls.ACTIONS:
		if a[0] == action:
			return a[1]
	return action

func _reset() -> void:
	Controls.reset_defaults()
	Controls.clear_saved()
	_status.text = "Back to the default controls."
	_refresh()

func _input(e: InputEvent) -> void:
	if _listen.is_empty():
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() < _listen_from:
		return
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		_listen = []
		_status.text = ""
		_refresh()
		return
	var kind: String = _listen[1]
	if not Controls.is_kind(e, kind):
		return
	if e is InputEventJoypadMotion:
		if absf((e as InputEventJoypadMotion).axis_value) < 0.6:
			return
	elif not e.is_pressed() or e.is_echo():
		return
	_bind(_listen[0], kind, Controls.clean(e))
	_listen = []

## Binds e; if another action had it, that action takes this one's old binding (a swap).
func _bind(action: String, kind: String, e: InputEvent) -> void:
	if e == null:
		return
	var old := Controls.binding(action, kind)
	var swapped := ""
	for a in Controls.ACTIONS:
		if a[0] == action:
			continue
		var other := Controls.binding(a[0], kind)
		if other != null and _same(other, e):
			Controls.set_binding(a[0], kind, old)
			swapped = a[1]
	Controls.set_binding(action, kind, e)
	Controls.save()
	_status.text = "“%s” is now %s." % [_label(action), Controls.event_name(e)]
	if swapped != "":
		_status.text += " “%s” took %s." % [swapped, Controls.event_name(old)]
	_refresh()
	(_rows[action][0 if kind == "pad" else 1] as Button).grab_focus()

func _same(a: InputEvent, b: InputEvent) -> bool:
	return Controls._to_data(a) == Controls._to_data(b)
