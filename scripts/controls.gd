class_name Controls
extends RefCounted
## The control scheme: every action, its default pad and keyboard bindings, the player's own bindings
## (saved to user://controls.cfg, loaded over the defaults at start), and button names for the HUD.
## The menu (OptionsMenu > Controls, Esc / Options) changes them. While it is open the game keeps running but the
## bender takes no input (blocked()).

const SAVE_PATH := "user://controls.cfg"

## [action, name in the menu, deadzone, default pad binding, default key]. A pad binding is
## ["btn", JoyButton] or ["axis", JoyAxis, -1 or 1]. Actions listed here can be rebound.
const ACTIONS := [
	["move_forward", "Move forward", 0.2, ["axis", JOY_AXIS_LEFT_Y, -1], KEY_W],
	["move_back", "Move back", 0.2, ["axis", JOY_AXIS_LEFT_Y, 1], KEY_S],
	["move_left", "Move left", 0.2, ["axis", JOY_AXIS_LEFT_X, -1], KEY_A],
	["move_right", "Move right", 0.2, ["axis", JOY_AXIS_LEFT_X, 1], KEY_D],
	["look_up", "Look up", 0.2, ["axis", JOY_AXIS_RIGHT_Y, -1], KEY_UP],
	["look_down", "Look down", 0.2, ["axis", JOY_AXIS_RIGHT_Y, 1], KEY_DOWN],
	["look_left", "Look left", 0.2, ["axis", JOY_AXIS_RIGHT_X, -1], KEY_LEFT],
	["look_right", "Look right", 0.2, ["axis", JOY_AXIS_RIGHT_X, 1], KEY_RIGHT],
	["draw", "Draw water (tap: 30 L, hold: keep drawing)", 0.5, ["btn", JOY_BUTTON_RIGHT_SHOULDER], KEY_E],
	["drop", "Drop held water (nothing held: relax)", 0.5, ["btn", JOY_BUTTON_B], KEY_C],
	["strike", "Use the move", 0.5, ["axis", JOY_AXIS_TRIGGER_RIGHT, 1], KEY_F],
	["precise", "Precision bending", 0.5, ["axis", JOY_AXIS_TRIGGER_LEFT, 1], KEY_R],
	["jump", "Jump / rise", 0.5, ["btn", JOY_BUTTON_X], KEY_SPACE],
	["forms", "Forms (tap: last form, hold: wheel)", 0.5, ["btn", JOY_BUTTON_LEFT_SHOULDER], KEY_Q],
	["moves_up", "Moves: up", 0.5, ["btn", JOY_BUTTON_DPAD_UP], KEY_1],
	["moves_right", "Moves: right", 0.5, ["btn", JOY_BUTTON_DPAD_RIGHT], KEY_2],
	["moves_down", "Moves: down", 0.5, ["btn", JOY_BUTTON_DPAD_DOWN], KEY_3],
	["moves_left", "Moves: left", 0.5, ["btn", JOY_BUTTON_DPAD_LEFT], KEY_4],
]

static var menu_open := false
static var _block_until := 0     # ms: input stays blocked for a moment after the menu closes

## The bender takes no input: the menu is open (or has only just closed, so the press that closed it
## does nothing in the game).
static func blocked() -> bool:
	return menu_open or Time.get_ticks_msec() < _block_until

static func block_briefly() -> void:
	_block_until = Time.get_ticks_msec() + 150

## Sets up every action with its defaults, then the saved bindings over them. Also the menu's own action
## (Esc / Options), which is not rebound.
static func setup() -> void:
	for a in ACTIONS:
		var n: String = a[0]
		if not InputMap.has_action(n):
			InputMap.add_action(n, a[2])
	if not InputMap.has_action("menu"):
		InputMap.add_action("menu")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("menu", k)
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTON_START
		InputMap.action_add_event("menu", b)
	# menus on the pad: Cross chooses, Circle goes back (Godot's defaults have no pad buttons for these)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var has := false
		for e in InputMap.action_get_events(pair[0]):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == pair[1]:
				has = true
		if not has:
			var pb := InputEventJoypadButton.new()
			pb.button_index = pair[1]
			InputMap.action_add_event(pair[0], pb)
	reset_defaults()
	load_saved()

static func reset_defaults() -> void:
	for a in ACTIONS:
		set_binding(a[0], "pad", _pad_event(a[3]))
		var k := InputEventKey.new()
		k.physical_keycode = a[4]
		set_binding(a[0], "key", k)

static func _pad_event(d: Array) -> InputEvent:
	if d[0] == "btn":
		var b := InputEventJoypadButton.new()
		b.button_index = d[1]
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = d[1]
	m.axis_value = float(d[2])
	return m

## kind "pad" (joypad buttons and axes) or "key" (keyboard and mouse buttons).
static func is_kind(e: InputEvent, kind: String) -> bool:
	if kind == "pad":
		return e is InputEventJoypadButton or e is InputEventJoypadMotion
	return e is InputEventKey or e is InputEventMouseButton

## The action's binding of that kind, or null.
static func binding(action: String, kind: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if is_kind(e, kind):
			return e
	return null

## Replaces the action's binding of that kind with e (null clears it).
static func set_binding(action: String, kind: String, e: InputEvent) -> void:
	for old in InputMap.action_get_events(action):
		if is_kind(old, kind):
			InputMap.action_erase_event(action, old)
	if e != null:
		InputMap.action_add_event(action, e)

## Saves every action's bindings.
static func save() -> void:
	var cf := ConfigFile.new()
	for a in ACTIONS:
		for kind in ["pad", "key"]:
			var e := binding(a[0], kind)
			cf.set_value(a[0], kind, _to_data(e) if e != null else [])
	cf.save(SAVE_PATH)

static func load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for a in ACTIONS:
		for kind in ["pad", "key"]:
			if cf.has_section_key(a[0], kind):
				var d: Array = cf.get_value(a[0], kind, [])
				set_binding(a[0], kind, _from_data(d) if not d.is_empty() else null)

static func clear_saved() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

static func _to_data(e: InputEvent) -> Array:
	if e is InputEventJoypadButton:
		return ["btn", (e as InputEventJoypadButton).button_index]
	if e is InputEventJoypadMotion:
		return ["axis", (e as InputEventJoypadMotion).axis, signf((e as InputEventJoypadMotion).axis_value)]
	if e is InputEventKey:
		var k := e as InputEventKey
		return ["key", k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode]
	if e is InputEventMouseButton:
		return ["mouse", (e as InputEventMouseButton).button_index]
	return []

static func _from_data(d: Array) -> InputEvent:
	match d[0]:
		"btn", "axis":
			return _pad_event(d)
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d[1])
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d[1])
			return m
	return null

## A captured press as a binding: only its button, key or axis direction (not its strength or modifiers).
static func clean(e: InputEvent) -> InputEvent:
	var d := _to_data(e)
	return _from_data(d) if not d.is_empty() else null

# ---------------------------------------------------------------- names

const PAD_BUTTONS := {
	JOY_BUTTON_A: "×", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△",
	JOY_BUTTON_BACK: "Share", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}

static func event_name(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventJoypadButton:
		var i := (e as InputEventJoypadButton).button_index
		return PAD_BUTTONS.get(i, "Button %d" % i)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		var s := m.axis_value > 0.0
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT: return "L2"
			JOY_AXIS_TRIGGER_RIGHT: return "R2"
			JOY_AXIS_LEFT_X: return "L stick right" if s else "L stick left"
			JOY_AXIS_LEFT_Y: return "L stick down" if s else "L stick up"
			JOY_AXIS_RIGHT_X: return "R stick right" if s else "R stick left"
			JOY_AXIS_RIGHT_Y: return "R stick down" if s else "R stick up"
		return "Axis %d%s" % [m.axis, "+" if s else "-"]
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	return "?"

## The pad button an action is on now, by name (for the HUD).
static func pad_name(action: String) -> String:
	return event_name(binding(action, "pad"))

## The HUD's hints are written with the default pad buttons; this puts in the buttons actually bound now.
static func relabel(hints: Array) -> Array:
	var names := {"R1": pad_name("draw"), "R2": pad_name("strike"), "L1": pad_name("forms"),
			"L2": pad_name("precise"), "□": pad_name("jump"), "○": pad_name("drop")}
	var re := RegEx.new()
	re.compile("(?<![A-Za-z0-9])(R1|R2|L1|L2|□|○)(?![A-Za-z0-9])")
	var out := []
	for h in hints:
		var s: String = h[0]
		var res := ""
		var at := 0
		for m in re.search_all(s):
			res += s.substr(at, m.get_start() - at) + str(names[m.get_string(1)])
			at = m.get_end()
		res += s.substr(at)
		out.append([res, h[1]])
	return out
