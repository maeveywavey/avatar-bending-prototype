class_name Boat
extends RigidBody3D
## A small flat-bottomed fishing boat (a jon boat: square bow and stern) of 4 cm planks, 3 m long and
## 1.2 m across. It floats on the stream (Pond's buoyancy, by the volume its open hull displaces), collides
## with ice and everything else, and can be dragged by the lash or shoved by water, but at about 180 kg it
## is too heavy for the water to lift or throw (WaterBody.LIFT_MAX_N, GRAB_MAX_F). It is built from convex
## parts, so slices cut it like a crate.

const WOOD_KG_M3 := 600.0
const L := 1.5                  # half length
const B := 0.6                  # half beam
const H := 0.45                 # depth of the hull
const T := 0.02                 # half plank thickness

func _init() -> void:
	var wood := Color(0.50, 0.36, 0.22)
	var cut := Color(0.78, 0.64, 0.45)
	var parts := []
	var boxes := [
		[Vector3(B, T, L), Vector3(0, T, 0)],                                  # bottom
		[Vector3(T, H * 0.5, L), Vector3(B - T, H * 0.5, 0)],                  # sides
		[Vector3(T, H * 0.5, L), Vector3(-(B - T), H * 0.5, 0)],
		[Vector3(B - 2.0 * T, H * 0.5, T), Vector3(0, H * 0.5, L - T)],        # stern
		[Vector3(B - 2.0 * T, H * 0.42, T), Vector3(0, H * 0.58, -(L - T))],  # bow, a little higher off the water
		[Vector3(B - 2.0 * T, T, 0.16), Vector3(0, H * 0.66, 0.15)],           # middle bench
		[Vector3(B - 2.0 * T, T, 0.2), Vector3(0, H * 0.66, L - 0.25)],        # stern seat
	]
	var vol := 0.0
	for bx in boxes:
		var f := Slicer.box_faces(bx[0], bx[1])
		parts.append(Slicer.part(f, wood, cut))
		vol += Slicer.volume(f)
	set_meta("parts", parts)
	set_meta("stuff", "wood")
	# the open hull keeps the water out of all of its inside
	set_meta("disp_vol", 2.0 * B * 2.0 * L * H)
	mass = vol * WOOD_KG_M3
	angular_damp = 0.8
	linear_damp = 0.1
	continuous_cd = true
	add_to_group("crate")
	add_to_group("boat")

func _ready() -> void:
	Slicer.build(self)

## Where the lash's aim assist aims: the middle of the hull.
func lash_point() -> Vector3:
	return global_transform * Vector3(0, H * 0.4, 0)
