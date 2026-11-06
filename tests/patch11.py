p = 'scripts/player.gd'
s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)

rep('''const STATES := ["loco", "stand", "ready_in", "ready", "draw1", "draw2", "draw3", "hold", "strike"]''',
'''const STATES := ["loco", "loco_ready", "loco_hold", "stand", "ready_in", "ready", "draw1", "draw2", "draw3", "hold", "strike"]
const LOCO_SPACES := ["parameters/loco/blend_position", "parameters/loco_ready/bs/blend_position",
		"parameters/loco_hold/bs/blend_position"]''')
rep('''var draw_variant := 0
var anim_label: Label
''', '''var draw_variant := 0
''')

rep('''	_tree = AnimationTree.new()
	add_child(_tree)
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 4.0
	for e in [["Idle", 0.0], ["Walk", 1.5], ["Jog_Fwd", 3.6]]:
		var an := AnimationNodeAnimation.new()
		an.animation = "loco/" + e[0]
		bs.add_blend_point(an, e[1])
	var sm := AnimationNodeStateMachine.new()
	sm.add_node("loco", bs)
	for n in STATES:
		if n == "loco":
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = "mocap/" + n
		sm.add_node(n, node)''', '''	_tree = AnimationTree.new()
	add_child(_tree)
	var arms := _bone_tracks(["clavicle_l", "clavicle_r"])
	var upper := _bone_tracks(["spine_01"])
	var sm := AnimationNodeStateMachine.new()
	sm.add_node("loco", _loco_space())
	# standing: the recorded body, with relaxed hanging arms (the tracker's arms clip the thighs here)
	sm.add_node("stand", _layered(_anim("mocap/stand"), _anim("loco/Idle"), arms))
	# walking in the ready stance or holding water: walking legs under the recorded upper body
	sm.add_node("loco_ready", _layered(_loco_space(), _anim("mocap/ready"), upper))
	sm.add_node("loco_hold", _layered(_loco_space(), _anim("mocap/hold"), upper))
	for n in STATES:
		if not sm.has_node(n):
			sm.add_node(n, _anim("mocap/" + n))''')

rep('''	_playback = _tree.get("parameters/playback")
	_playback.start("stand")''', '''	_playback = _tree.get("parameters/playback")
	for n in ["stand", "loco_ready", "loco_hold"]:
		_tree.set("parameters/%s/blend/blend_amount" % n, 1.0)
	_playback.start("stand")''')

rep('''# ---------------------------------------------------------------- per-frame
''', '''func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a

func _loco_space() -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 4.0
	for e in [["Idle", 0.0], ["Walk", 1.5], ["Jog_Fwd", 3.6]]:
		bs.add_blend_point(_anim("loco/" + e[0]), e[1])
	return bs

## Track paths of the given bones and everything below them.
func _bone_tracks(roots: Array) -> Array:
	var out := []
	var stack := []
	for r in roots:
		stack.append(skel.find_bone(r))
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(NodePath("Armature/Skeleton3D:" + skel.get_bone_name(b)))
		for c in skel.get_bone_children(b):
			stack.append(c)
	return out

## base, with the listed tracks taken from over instead.
func _layered(base: AnimationRootNode, over: AnimationRootNode, tracks: Array) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var bl := AnimationNodeBlend2.new()
	bl.filter_enabled = true
	for t in tracks:
		bl.set_filter_path(t, true)
	bt.add_node("base", base)
	bt.add_node("over", over)
	bt.add_node("blend", bl)
	bt.connect_node("blend", 0, "base")
	bt.connect_node("blend", 1, "over")
	bt.connect_node("output", 0, "blend")
	if base is AnimationNodeBlendSpace1D:
		bt.rename_node("base", "bs")
	return bt

# ---------------------------------------------------------------- per-frame
''')

rep('''	_tree.set("parameters/loco/blend_position", _speed_s)''', '''	for pth in LOCO_SPACES:
		_tree.set(pth, _speed_s)''')

rep('''	if _prev_state == WaterBody.S.DRAW and st == WaterBody.S.HOLD:
		draw_variant = (draw_variant + 1) % 3
		refresh_label()
		_go("hold")
	_prev_state = st''', '''	if _prev_state == WaterBody.S.DRAW and st == WaterBody.S.HOLD:
		draw_variant = (draw_variant + 1) % 3
	_prev_state = st''')

rep('''	if not busy:
		if _speed_s > 0.4:
			_go("loco")
		elif ready_mode:
			if _anim_state == "ready_in":
				if _playback.get_current_node() == "ready_in" and _playback.get_current_play_position() >= _clip_len("ready_in") - 0.05:
					_go("ready")
			elif _anim_state != "ready":
				_go("ready_in")
		else:
			_go("stand")''', '''	var moving := _speed_s > 0.4
	if _strike_t < 0.0 and (st == WaterBody.S.HOLD or st == WaterBody.S.GATHER):
		_go("loco_hold" if moving else "hold")
	elif not busy:
		if moving:
			_go("loco_ready" if ready_mode else "loco")
		elif ready_mode:
			if _anim_state == "ready_in":
				if _playback.get_current_node() == "ready_in" and _playback.get_current_play_position() >= _clip_len("ready_in") - 0.05:
					_go("ready")
			elif _anim_state == "stand" or _anim_state == "loco":
				_go("ready_in")
			else:
				_go("ready")
		else:
			_go("stand")''')

rep('''
func refresh_label() -> void:
	if anim_label:
		anim_label.text = str(draw_variant + 1)
''', '')
open(p, 'w').write(s)
print("ok")
