p = 'scripts/world.gd'
s = open(p).read()
for a, b in [
 ("var _anim_label: Label\n", ""),
 ("\tplayer.anim_label = _anim_label\n\tplayer.refresh_label()\n", ""),
 ("\t\tplayer.draw_variant = 1\n\t\tplayer.refresh_label()\n", "\t\tplayer.draw_variant = 1\n"),
 ('''	_anim_label = Label.new()
	_anim_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_anim_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_anim_label.offset_right = -36.0
	_anim_label.offset_top = 8.0
	_anim_label.add_theme_font_size_override("font_size", 180)
	_anim_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_anim_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.35))
	_anim_label.add_theme_constant_override("outline_size", 16)
	layer.add_child(_anim_label)
''', "")]:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
print("ok")
