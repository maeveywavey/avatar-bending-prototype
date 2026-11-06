p = 'scripts/player.gd'
s = open(p).read()
a = '''	bt.add_node("base", base)
	bt.add_node("over", over)
	bt.add_node("blend", bl)
	bt.connect_node("blend", 0, "base")
	bt.connect_node("blend", 1, "over")
	bt.connect_node("output", 0, "blend")
	if base is AnimationNodeBlendSpace1D:
		bt.rename_node("base", "bs")
	return bt'''
b = '''	var bn := "bs" if base is AnimationNodeBlendSpace1D else "base"
	bt.add_node(bn, base)
	bt.add_node("over", over)
	bt.add_node("blend", bl)
	bt.connect_node("blend", 0, bn)
	bt.connect_node("blend", 1, "over")
	bt.connect_node("output", 0, "blend")
	return bt'''
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)
