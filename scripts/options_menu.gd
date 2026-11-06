class_name OptionsMenu
extends CanvasLayer
## The Options menu (Esc on the keyboard, Options on the pad). The game is not paused: the world carries
## on, only the bender stops taking input (Controls.blocked()).
## Pages: Options (Resume, Audio, Visual, Controls, Quit) > Visual (Graphics, Edit Water Shapes) > a list
## of the water things > one water thing's shape: the lines of its code that set its shape, each number in
## a box (WaterShapes). An empty box uses the default, shown grey in it; type a number to change it (it
## shows at once). Reset to Default, Save (named; also kept for the next start), Load (a named save).
## Esc / Options / Circle: back a page (out of the menu from the first page).

var _root: Control
var _panel: PanelContainer
var _pages := {}                 # name -> Control
var _page := ""
var _history: Array[String] = []
var _controls: ControlsPage
var _shapes_list: VBoxContainer
var _editor: VBoxContainer       # the shape page's contents (rebuilt for each water thing)
var _group := ""
var _boxes := {}                 # name -> LineEdit, on the shape page
var _status: Label
var _save_row: HBoxContainer
var _save_name: LineEdit
var _load_list: VBoxContainer

static var _mono: SystemFont
static var _italic: FontVariation

const PANEL_W := 1100.0
const PANEL_H := 660.0

# ---------------------------------------------------------------- shared looks

static func title(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0))
	return t

static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return _mono

static func italic() -> FontVariation:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = ThemeDB.fallback_font
		# slanted
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	return _italic

## A choice in a box. With sub, a second line in italics under it (e.g. "Coming soon!"); off: greyed out.
func _choice(parent: Control, text: String, on_press: Callable, enabled := true, sub := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(420, 58 if sub == "" else 72)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if enabled:
		b.pressed.connect(on_press)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	b.add_child(col)
	var grey := Color(0.55, 0.6, 0.65)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0) if enabled else grey)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_override("font", italic())
		s.add_theme_font_size_override("font_size", 15)
		s.add_theme_color_override("font_color", grey)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(s)
	parent.add_child(b)
	return b

func _page_box(name_: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.visible = false
	_panel.add_child(v)
	_pages[name_] = v
	return v

func _list_page(name_: String, heading: String) -> VBoxContainer:
	var v := _page_box(name_)
	var t := title(heading)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	v.add_child(gap)
	return v

# ---------------------------------------------------------------- building

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.03, 0.06, 0.55)
	_root.add_child(shade)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.18, 0.94)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.offset_left = -PANEL_W * 0.5
	_panel.offset_right = PANEL_W * 0.5
	_panel.offset_top = -PANEL_H * 0.5
	_panel.offset_bottom = PANEL_H * 0.5
	_root.add_child(_panel)

	var main := _list_page("main", "Options")
	_choice(main, "Resume", close_menu)
	_choice(main, "Audio", Callable(), false, "Coming soon!")
	_choice(main, "Visual", _go.bind("visual"))
	_choice(main, "Controls", _go.bind("controls"))
	_choice(main, "Quit", func(): get_tree().quit())

	var visual := _list_page("visual", "Visual")
	_choice(visual, "Graphics", Callable(), false, "Coming soon!")
	_choice(visual, "Edit Water Shapes", _go.bind("shapes"))
	_choice(visual, "Back", _back)

	_shapes_list = _list_page("shapes", "Edit Water Shapes")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	_shapes_list.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	sc.add_child(inner)
	for g in WaterShapes.GROUPS:
		_choice(inner, g[1], _open_group.bind(g[0]))
	_choice(inner, "Back", _back)

	_editor = _page_box("shape")
	_load_list = _list_page("load", "Load")

	_controls = ControlsPage.new()
	_controls.visible = false
	_controls.back.connect(_back)
	_panel.add_child(_controls)
	_pages["controls"] = _controls

# ---------------------------------------------------------------- pages

func open_menu() -> void:
	Controls.menu_open = true
	_root.visible = true
	_history.clear()
	_show("main")

func close_menu() -> void:
	Controls.menu_open = false
	Controls.block_briefly()
	_root.visible = false
	var f := _root.get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()

func _go(p: String) -> void:
	_history.append(_page)
	_show(p)

func _back() -> void:
	if _history.is_empty():
		close_menu()
		return
	_show(_history.pop_back())

func _show(p: String) -> void:
	_page = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if p == "controls":
		_controls.shown()
		return
	_focus_first(_pages[p])

func _focus_first(n: Node) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).visible \
				and not (c is Button and (c as Button).disabled):
			(c as Control).grab_focus()
			return
		if c is Control and (c as Control).visible:
			var before := _root.get_viewport().gui_get_focus_owner()
			_focus_first(c)
			var after := _root.get_viewport().gui_get_focus_owner()
			if after != before and after != null and n.is_ancestor_of(after):
				return

# ---------------------------------------------------------------- one water thing's shape

func _open_group(id: String) -> void:
	_group = id
	_build_editor()
	_go("shape")

func _fmt(v: float) -> String:
	var s := "%.4f" % v
	s = s.rstrip("0")
	if s.ends_with("."):
		s += "0"
	return s

func _build_editor() -> void:
	for c in _editor.get_children():
		c.queue_free()
	_boxes.clear()
	var g := WaterShapes.group(_group)
	_editor.add_child(title(g[1]))
	var where := Label.new()
	where.text = "%s · numbers in boxes set the shape (grey: the default; empty a box to go back to it)" % g[2]
	where.add_theme_font_size_override("font_size", 14)
	where.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.7))
	_editor.add_child(where)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	_editor.add_child(sc)
	var code := VBoxContainer.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_constant_override("separation", 4)
	sc.add_child(code)
	var code_bg := StyleBoxFlat.new()
	code_bg.bg_color = Color(0.02, 0.06, 0.09, 0.9)
	code_bg.set_corner_radius_all(4)
	code_bg.content_margin_left = 10
	code_bg.content_margin_right = 10
	code_bg.content_margin_top = 6
	code_bg.content_margin_bottom = 6
	var block: VBoxContainer = null
	for line in g[3]:
		var ln: String = line
		if ln.begins_with("#"):
			# a comment: starts a new block of code under it
			var cm := Label.new()
			cm.text = ln
			cm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cm.add_theme_font_override("font", mono())
			cm.add_theme_font_size_override("font_size", 15)
			cm.add_theme_color_override("font_color", Color(0.5, 0.75, 0.55))
			code.add_child(cm)
			block = null
			continue
		if block == null:
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", code_bg)
			code.add_child(pc)
			block = VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			pc.add_child(block)
		block.add_child(_code_line(ln))

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_editor.add_child(_status)
	# naming a save
	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 10)
	_save_row.visible = false
	_editor.add_child(_save_row)
	var nl := Label.new()
	nl.text = "Name this save:"
	_save_row.add_child(nl)
	_save_name = LineEdit.new()
	_save_name.custom_minimum_size = Vector2(320, 0)
	_save_name.placeholder_text = "e.g. thick tail"
	_save_name.text_submitted.connect(func(_t): _do_save())
	_save_row.add_child(_save_name)
	var ok := Button.new()
	ok.text = "Save"
	ok.pressed.connect(_do_save)
	_save_row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): _save_row.visible = false)
	_save_row.add_child(cancel)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_editor.add_child(bar)
	for b in [["Reset to Default", _reset_group], ["Save", _ask_save], ["Load", _open_load], ["Back", _back]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(170, 40)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(b[1])
		bar.add_child(btn)

## One line of code, its numbers as boxes. Words wrap onto the next row if the line is long.
func _code_line(line: String) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 0)
	row.add_theme_constant_override("v_separation", 2)
	var indent := 0
	while indent < line.length() and line[indent] == "\t":
		indent += 1
	if indent > 0:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(28 * indent, 0)
		row.add_child(sp)
	for piece in WaterShapes.pieces(line.substr(indent)):
		if piece is String:
			# split at spaces so a long line wraps between words
			var words := (piece as String).split(" ")
			for i in words.size():
				var w: String = words[i] + (" " if i < words.size() - 1 else "")
				if w == "":
					continue
				var l := Label.new()
				l.text = w
				l.add_theme_font_override("font", mono())
				l.add_theme_font_size_override("font_size", 15)
				l.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
				row.add_child(l)
		else:
			row.add_child(_number_box(piece[0], piece[1]))
	return row

func _number_box(n: String, dflt: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = _fmt(dflt)
	var cur = WaterShapes.changed(_group, n)
	e.text = _fmt(cur) if cur != null else ""
	e.tooltip_text = "k(\"%s\")  default %s" % [n, _fmt(dflt)]
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size = Vector2(maxf(64.0, 10.0 * maxi(e.placeholder_text.length(), 4) + 18.0), 0)
	e.add_theme_font_override("font", mono())
	e.add_theme_font_size_override("font_size", 15)
	e.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	e.add_theme_color_override("font_placeholder_color", Color(0.6, 0.65, 0.7, 0.75))
	e.select_all_on_focus = true
	e.text_changed.connect(_typed.bind(n, e))
	e.text_submitted.connect(func(_t): e.release_focus())
	if not _boxes.has(n):
		_boxes[n] = []
	(_boxes[n] as Array).append(e)
	return e

func _typed(text: String, n: String, e: LineEdit) -> void:
	var t := text.strip_edges()
	if t == "":
		WaterShapes.set_value(_group, n, null)
		e.remove_theme_color_override("font_color")
		e.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		_status.text = "%s back to its default, %s." % [n, _fmt(WaterShapes.default_of(_group, n))]
	elif t.is_valid_float():
		WaterShapes.set_value(_group, n, t.to_float())
		e.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		_status.text = "%s = %s (not saved yet)" % [n, t]
	else:
		e.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_status.text = "“%s” is not a number." % t
		return
	# the same number may appear in more than one place
	for other in _boxes.get(n, []):
		if other != e:
			(other as LineEdit).text = t

func _refresh_boxes() -> void:
	for n in _boxes:
		var cur = WaterShapes.changed(_group, n)
		for e in _boxes[n]:
			(e as LineEdit).text = _fmt(cur) if cur != null else ""

func _reset_group() -> void:
	WaterShapes.reset(_group)
	_refresh_boxes()
	_status.text = "Back to the defaults (Save to keep them for the next start)."

func _ask_save() -> void:
	_save_row.visible = true
	_save_name.text = ""
	_save_name.grab_focus()

func _do_save() -> void:
	var nm := _save_name.text.strip_edges().replace("/", "-")
	if nm == "":
		_status.text = "Give the save a name first."
		return
	WaterShapes.save(_group, nm)
	_save_row.visible = false
	_status.text = "Saved as “%s”; these are now used every time the game starts." % nm

func _open_load() -> void:
	_fill_load()
	_go("load")

## The saved names, each to load (or delete).
func _fill_load() -> void:
	for c in _load_list.get_children():
		if c is Button or c is HBoxContainer or c.has_meta("empty"):
			c.queue_free()
	var names := WaterShapes.saves(_group)
	if names.is_empty():
		var l := Label.new()
		l.text = "No saves for %s yet." % WaterShapes.group(_group)[1]
		l.set_meta("empty", true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_list.add_child(l)
	for nm in names:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		_load_list.add_child(row)
		var b := _choice(row, nm, _do_load.bind(nm))
		b.custom_minimum_size = Vector2(420, 50)
		var del := Button.new()
		del.text = "Delete"
		del.custom_minimum_size = Vector2(100, 50)
		del.pressed.connect(func():
			WaterShapes.delete_save(_group, nm)
			_fill_load()
			_focus_first.call_deferred(_load_list))
		row.add_child(del)
	_choice(_load_list, "Back", _back)

func _do_load(nm: String) -> void:
	if WaterShapes.load_save(_group, nm):
		_back()
		_refresh_boxes()
		_status.text = "Loaded “%s”." % nm

# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if _controls != null and _controls.listening():
		return
	if e.is_action_pressed("menu") and not e.is_echo():
		get_viewport().set_input_as_handled()
		if not _root.visible:
			open_menu()
		elif _save_row != null and _save_row.visible and _page == "shape":
			_save_row.visible = false
		else:
			_back()
	elif _root.visible and e.is_action_pressed("ui_cancel") and not e.is_echo():
		var f := _root.get_viewport().gui_get_focus_owner()
		if f is LineEdit:
			# leaves the box first
			f.release_focus()
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		_back()
