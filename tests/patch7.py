p = 'tools/pose/compare.gd'
s = open(p).read()
s = s.replace('''	var side := -1.0 if view == "right" else 1.0
	var cpos := Vector3(side * 4.2, 1.0, 0.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - cpos, Vector3.UP), cpos)''', '''	var side := -1.0 if view == "right" else 1.0
	var cpos := Vector3(side * 4.2, 1.0, 0.0)
	if view.begins_with("cam:"):
		# cam:<x>,<y>,<z> camera position in skeleton space (X = character's left, Z = its front)
		var c := view.substr(4).split(",")
		cpos = Vector3(float(c[0]), float(c[1]), float(c[2]))
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - cpos, Vector3.UP), cpos)''')
open(p, 'w').write(s)
