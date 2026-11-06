class_name MocapLibrary
extends RefCounted
## Builds animations for the placeholder mannequin from the performer's tracked video
## (mocap/clips/full_right__full.json, made by tools/pose/retarget.py). Each clip is a slice of that
## recording, in seconds; looping slices play back and forth so the join is never visible.

const SOURCE := "res://mocap/clips/full_right__full.json"
const PATH := "Armature/Skeleton3D"

## The tracker's sense of "forward" is off. The bending clips are turned by this much (negative = to the
## character's right) so the ready stance faces the crosshair: chest side-on toward it, back leg behind.
## -50 was matched by the owner's screenshot from the gameplay camera (-15 still faced too far left).
const AIM_YAW := -50.0

## name: [start, end, loop, yaw]   (times in the source video; yaw: 1 = turned by AIM_YAW, "ramp" = turns
## from 0 to AIM_YAW over the clip)
const SLICES := {
	"stand": [19.6, 21.6, true, 0],
	"ready_in": [22.85, 25.5, false, "ramp"],
	"ready": [25.5, 29.5, true, 1],
	"draw1": [11.0, 13.0, false, 1],
	"draw2": [31.0, 33.5, false, 1],
	"draw3": [42.0, 44.0, false, 1],
	"hold": [47.0, 61.0, true, 1],
	"strike": [64.2, 65.6, false, 1],
}

static func build(skel: Skeleton3D) -> AnimationLibrary:
	var f := FileAccess.open(SOURCE, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var fps: float = data["fps"]
	var t0: float = data["range"][0]
	var pel := skel.find_bone("pelvis")
	var root_rest := skel.get_bone_global_rest(skel.get_bone_parent(pel)).basis
	var root_basis := root_rest.inverse()
	var pel_rest := skel.get_bone_rest(pel).origin
	var pel_global := skel.get_bone_global_rest(pel).origin
	var aim := AIM_YAW
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aimyaw="):
			aim = float(arg.substr(9))          # test runs only
	var lib := AnimationLibrary.new()
	var hang := {}
	for sd in ["l", "r"]:
		hang.merge(_hanging_arm(skel, sd))
	for name in SLICES:
		var s: Array = SLICES[name]
		var i0 := int(round((float(s[0]) - t0) * fps))
		var i1 := int(round((float(s[1]) - t0) * fps))
		var a := Animation.new()
		a.length = float(i1 - i0 - 1) / fps
		a.loop_mode = Animation.LOOP_PINGPONG if s[2] else Animation.LOOP_NONE
		var yaws := PackedFloat32Array()
		for i in range(i0, i1):
			var u := float(i - i0) / float(maxi(i1 - i0 - 1, 1))
			var w := 0.0
			if typeof(s[3]) == TYPE_STRING:
				w = smoothstep(0.15, 0.85, u)
			else:
				w = float(s[3])
			yaws.append(deg_to_rad(aim) * w)
		for bn in data["bones"]:
			var tr := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(tr, NodePath("%s:%s" % [PATH, bn]))
			var rows: Array = data["bones"][bn]
			if name == "stand" and hang.has(bn):
				# the tracker's standing arms cross the body and clip the thighs; the standing arms hang relaxed
				a.rotation_track_insert_key(tr, 0.0, hang[bn])
				continue
			for i in range(i0, i1):
				var q: Array = rows[i]
				var lq := Quaternion(q[0], q[1], q[2], q[3]).normalized()
				if bn == "pelvis":
					# turn the whole body about the vertical (in skeleton space), expressed in the root's frame
					var yq := Quaternion(root_basis * Basis(Vector3.UP, yaws[i - i0]) * root_rest)
					lq = (yq * lq).normalized()
				a.rotation_track_insert_key(tr, float(i - i0) / fps, lq)
		# height goes on the pelvis; travel across the floor goes on the root bone, which the player takes as
		# root motion, so a step stays taken when the next clip starts
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath("%s:pelvis" % PATH))
		var tr_root := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tr_root, NodePath("%s:root" % PATH))
		var offs: Array = data["pelvis_offset"]
		var o0: Array = offs[i0]
		for i in range(i0, i1):
			var o: Array = offs[i]
			var p := pel_global + Vector3(o[0] - o0[0], o[1], o[2] - o0[2])
			p = Basis(Vector3.UP, yaws[i - i0]) * p
			var d := p - pel_global
			var kt := float(i - i0) / fps
			a.position_track_insert_key(tp, kt, pel_rest + root_basis * Vector3(0.0, d.y, 0.0))
			a.position_track_insert_key(tr_root, kt, Vector3(d.x, 0.0, d.z))
		lib.add_animation(name, a)
	return lib

## Local rotations for an arm hanging relaxed at the side: upper arm nearly straight down and slightly out
## from the body, elbow bent a little, wrist in line with the forearm, palm toward the thigh.
static func _hanging_arm(skel: Skeleton3D, sd: String) -> Dictionary:
	var cl := skel.find_bone("clavicle_" + sd)
	var up := skel.find_bone("upperarm_" + sd)
	var lo := skel.find_bone("lowerarm_" + sd)
	var hd := skel.find_bone("hand_" + sd)
	var gc := skel.get_bone_global_rest(cl)
	var gu := skel.get_bone_global_rest(up)
	var gl := skel.get_bone_global_rest(lo)
	var gh := skel.get_bone_global_rest(hd)
	var out := Vector3(1.0 if sd == "l" else -1.0, 0.0, 0.0)   # skeleton X is the character's left
	var fwd := Vector3(0.0, 0.0, 1.0)
	var d_up := (Vector3.DOWN + out * 0.13 + fwd * 0.03).normalized()
	var r1 := Basis(Quaternion((gl.origin - gu.origin).normalized(), d_up))
	var cur_lo := (r1 * (gh.origin - gl.origin)).normalized()
	var d_lo := (Vector3.DOWN + out * 0.06 + fwd * 0.26).normalized()
	var r2 := Basis(Quaternion(cur_lo, d_lo))
	var bu := r1 * gu.basis
	var bl := r2 * r1 * gl.basis
	var bh := r2 * r1 * gh.basis
	return {
		"clavicle_" + sd: skel.get_bone_rest(cl).basis.get_rotation_quaternion(),
		"upperarm_" + sd: (gc.basis.inverse() * bu).get_rotation_quaternion(),
		"lowerarm_" + sd: (bu.inverse() * bl).get_rotation_quaternion(),
		"hand_" + sd: (bl.inverse() * bh).get_rotation_quaternion(),
	}
