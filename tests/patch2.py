p = 'scripts/player.gd'
s = open(p).read()
s = s.replace("var _turn_hold := false\n", "var _turn_hold := false\nvar draw_variant := 0\nvar anim_label: Label\nvar _draw_t := 0.0\nvar _prev_state := WaterBody.S.NONE\n")
s = s.replace("""			_draw_src = src
			water.begin_draw(src)""", """			_draw_src = src
			_draw_t = 0.0
			pose.draw_variant = draw_variant
			water.begin_draw(src)""")
s = s.replace("	pose.draw_u = water.draw_u if st == WaterBody.S.DRAW else 0.0\n", """	if st == WaterBody.S.DRAW:
		_draw_t += dt
		var v: Dictionary = BendPose.VARIANTS[draw_variant]
		var ru := clampf(_draw_t / v["reach_t"], 0.0, 1.0)
		var pu := clampf((_draw_t - v["reach_t"] - v["hold_t"]) / v["pull_t"], 0.0, 1.0)
		water.reach_u = ru
		water.pull_u = pu
		pose.reach_u = ru
		pose.pull_u = pu
		pose.src_local = global_transform.affine_inverse() * _draw_src.surface_point()
	elif pose.w_draw < 0.01:
		pose.reach_u = 0.0
		pose.pull_u = 0.0
	# the next completed draw uses the next animation
	if _prev_state == WaterBody.S.DRAW and st == WaterBody.S.HOLD:
		draw_variant = (draw_variant + 1) % BendPose.VARIANTS.size()
		refresh_label()
	_prev_state = st
""")
s += """
func refresh_label() -> void:
	if anim_label:
		anim_label.text = str(draw_variant + 1)
"""
open(p, 'w').write(s)

p = 'scripts/world.gd'
s = open(p).read()
s = s.replace("""	var barrel := WaterSource.new()
	barrel.position = Vector3(-1.6, 0, -4.2)
	add_child(barrel)
""", """	var barrel := WaterSource.new()
	barrel.position = Vector3(-1.6, 0, -4.2)
	add_child(barrel)
	var barrel2 := WaterSource.new()
	barrel2.position = Vector3(6.5, 0, -5.0)
	add_child(barrel2)
""")
s = s.replace("	player.reticle = _make_hud()\n", "	player.reticle = _make_hud()\n	player.anim_label = _anim_label\n	player.refresh_label()\n")
s = s.replace("var _sign: SignBoard\n", "var _sign: SignBoard\nvar _anim_label: Label\n")
s = s.replace("""	layer.add_child(c)
	return c""", """	layer.add_child(c)
	_anim_label = Label.new()
	_anim_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_anim_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_anim_label.offset_right = -36.0
	_anim_label.offset_top = 8.0
	_anim_label.add_theme_font_size_override("font_size", 180)
	_anim_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_anim_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.35))
	_anim_label.add_theme_constant_override("outline_size", 16)
	layer.add_child(_anim_label)
	return c""")
open(p, 'w').write(s)
print("patched")
