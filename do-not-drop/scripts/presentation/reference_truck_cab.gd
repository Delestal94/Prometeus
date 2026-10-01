class_name ReferenceTruckCab
extends RefCounted
## The inside of the reference truck's cab, built by ReferenceTruck on top of the
## authored model: the re-cut side windows, the round steering wheel, the cab
## dressing (seat, console, gauges, GPS, mirror, visors, clipboard, mats), the
## panels that close the interior and the pedals that dip with the truck's
## driving. Everything is presentation, in the model's own space.

## Clutch, brake and accelerator under the dash (docs/tareas-nacho.md #9).
## Brake and accelerator dip with what the truck is actually doing, so a
## passenger glancing down sees the driver's feet at work.
var brake_pedal: Node3D
var gas_pedal: Node3D
const PEDAL_REST: float = deg_to_rad(-28.0)
const PEDAL_PRESSED: float = deg_to_rad(-8.0)

var _model: Node3D
var _steel: Material
var _dark: Material
var _accent: StandardMaterial3D


func _init(model: Node3D, steel: Material, dark: Material, accent: StandardMaterial3D) -> void:
	_model = model
	_steel = steel
	_dark = dark
	_accent = accent


## The authored side glass is a plain rectangle that runs forward past the
## door's slanted front pillar, so its top corner hung out over the
## windshield. Each pane is re-cut to the real opening -- back pillar to the
## slanted front pillar, sill to header -- and framed with a rubber seal.
## Coordinates are the model's (x front, y up), measured from the door frame.
const WINDOW_OPENING := [Vector2(1.53, 2.34), Vector2(3.76, 2.34), Vector2(3.15, 3.21), Vector2(1.53, 3.21)]
const WINDOW_PLANE_Z := 1.27


func reshape_side_windows() -> void:
	var seal := ReferenceTruckProps.flat_material(Color("1b2025"))
	for side_name: String in ["Left", "Right"]:
		var pane := _model.find_child("SideWindow_" + side_name, true, false) as MeshInstance3D
		var hinge := _model.find_child("CabDoor_%s_HINGE_Z" % side_name, true, false) as Node3D
		if pane == null or hinge == null:
			continue
		var outward: float = -1.0 if side_name == "Left" else 1.0
		var z: float = WINDOW_PLANE_Z * outward - hinge.position.z
		var corners: Array[Vector3] = []
		for corner: Vector2 in WINDOW_OPENING:
			corners.append(Vector3(corner.x - hinge.position.x, corner.y - hinge.position.y, z) - pane.position)
		var normals := PackedVector3Array()
		for index in range(6):
			normals.append(Vector3(0.0, 0.0, outward))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
				[corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]
			)
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		pane.mesh = mesh
		for index in range(4):
			var a: Vector3 = corners[index]
			var b: Vector3 = corners[(index + 1) % 4]
			var strip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(a.distance_to(b) + 0.035, 0.035, 0.05)
			strip.mesh = box
			strip.material_override = seal
			var along := (b - a).normalized()
			strip.transform = Transform3D(
					Basis(along, Vector3(0.0, 0.0, 1.0).cross(along), Vector3(0.0, 0.0, 1.0)), (a + b) * 0.5
				)
			pane.add_child(strip)


## The authored steering wheel is twelve straight rim segments with gaps at
## every joint. It's measured (centre, column axis, radius) and rebuilt as a
## round rim with three spokes and a hub, all under one pivot whose local Y
## is the column axis pointing away from the driver -- the convention
## VehiclePresentation turns it by.
func build_steering_pivot() -> Node3D:
	var pieces: Array[Node3D] = []
	for node: Node in _model.find_children("Steering*", "MeshInstance3D", true, false):
		if not String(node.name).begins_with("SteeringColumn"):
			pieces.append(node as Node3D)
	var rim: Array[Vector3] = []
	var center := Vector3.ZERO
	for piece: Node3D in pieces:
		if String(piece.name).begins_with("SteeringRim"):
			rim.append(piece.position)
			center += piece.position
	if rim.size() < 3:
		return null
	var parent := pieces[0].get_parent() as Node3D
	center /= float(rim.size())
	var first := rim[0] - center
	var normal := Vector3.ZERO
	var radius := 0.0
	for point: Vector3 in rim:
		radius += point.distance_to(center) / float(rim.size())
		var candidate := first.cross(point - center)
		if candidate.length() > normal.length():
			normal = candidate
	normal = normal.normalized()
	# Away from the driver means toward the truck's front, model +X.
	if normal.x < 0.0:
		normal = -normal
	var side := Vector3(0.0, 0.0, 1.0)
	side = (side - normal * side.dot(normal)).normalized()
	for piece: Node3D in pieces:
		piece.get_parent().remove_child(piece)
		piece.queue_free()
	var wheel := Node3D.new()
	wheel.name = "SteeringWheel"
	wheel.transform = Transform3D(Basis(side, normal, side.cross(normal)), center)
	parent.add_child(wheel)
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color("20262c")
	grip.roughness = 0.55
	var ring := MeshInstance3D.new()
	ring.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.03
	torus.outer_radius = radius + 0.03
	torus.rings = 32
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = grip
	wheel.add_child(ring)
	# T-shaped spokes: left, right and the one toward the driver's knees.
	var down_is_plus_z: bool = wheel.transform.basis.z.y < 0.0
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK if down_is_plus_z else Vector3.FORWARD]:
		var spoke := MeshInstance3D.new()
		var bar := CylinderMesh.new()
		bar.top_radius = 0.02
		bar.bottom_radius = 0.026
		bar.height = radius
		bar.radial_segments = 8
		spoke.mesh = bar
		spoke.material_override = _dark
		var along := direction.normalized()
		var across := Vector3.UP.cross(along).normalized()
		spoke.transform = Transform3D(Basis(across, along, across.cross(along)), along * radius * 0.5)
		wheel.add_child(spoke)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.075
	cylinder.bottom_radius = 0.085
	cylinder.height = 0.07
	cylinder.radial_segments = 16
	hub.mesh = cylinder
	hub.material_override = _dark
	wheel.add_child(hub)
	var horn := MeshInstance3D.new()
	var cap := CylinderMesh.new()
	cap.top_radius = 0.055
	cap.bottom_radius = 0.06
	cap.height = 0.02
	cap.radial_segments = 16
	horn.mesh = cap
	horn.material_override = _accent
	horn.position = Vector3(0.0, -0.045, 0.0)  # Driver's side of the hub.
	wheel.add_child(horn)
	return wheel


## Life in the cab: a passenger seat, centre console with gear stick,
## handbrake and coffee, gauges, radio, rear-view mirror with an air
## freshener, sun visors, a clipboard of deliveries and floor mats. Built in
## the model's own space (x front, y up, z right), sized from its dashboard.
func dress_cab() -> void:
	var dashboard := _model.find_child("Dashboard", true, false) as MeshInstance3D
	if dashboard == null:
		return
	var cab := dashboard.get_parent() as Node3D
	var dressing := Node3D.new()
	dressing.name = "CabDressing"
	cab.add_child(dressing)
	var seat_color: Material = ReferenceTruckProps.material_named(_model, "DT_Seat")
	var paper := ReferenceTruckProps.flat_material(Color("f2eee2"))
	var cardboard := ReferenceTruckProps.flat_material(Color("b98a52"))
	var green := ReferenceTruckProps.flat_material(Color("3fae5a"))
	var dial := ReferenceTruckProps.flat_material(Color("f5f1e6"))
	var needle := ReferenceTruckProps.flat_material(Color("e2402f"))
	var cup := ReferenceTruckProps.flat_material(Color("f4f1ea"))
	var lid := ReferenceTruckProps.flat_material(Color("6b4a33"))
	# Passenger seat: a copy of the driver's, mirrored across the cab.
	for part_name: String in ["DriverSeat", "DriverBackrest", "DriverSeatBase"]:
		var part := _model.find_child(part_name, true, false) as MeshInstance3D
		if part != null:
			var copy := part.duplicate() as MeshInstance3D
			copy.name = part_name.replace("Driver", "Passenger") + "_Cab"
			copy.position.z = -part.position.z
			dressing.add_child(copy)
	# Centre console between the seats, with the gear stick and handbrake.
	ReferenceTruckProps.prop_box(dressing, Vector3(0.72, 0.3, 0.3), Vector3(2.6, 1.33, 0.0), _dark)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.64, 0.02, 0.24), Vector3(2.6, 1.49, 0.0), seat_color)
	ReferenceTruckProps.prop_cylinder(
			dressing, 0.018, 0.34, Vector3(2.92, 1.66, 0.0), Vector3(0.0, 0.0, deg_to_rad(12.0)), _dark
		)
	var knob := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	ball.radial_segments = 12
	ball.rings = 6
	knob.mesh = ball
	knob.material_override = _accent
	knob.position = Vector3(2.885, 1.83, 0.0)
	dressing.add_child(knob)
	build_pedals(dressing)
	ReferenceTruckProps.prop_box(
			dressing, Vector3(0.28, 0.04, 0.05), Vector3(2.45, 1.54, 0.07), _dark, Vector3(0.0, 0.0, deg_to_rad(18.0))
		)
	# Coffee in the cup holder.
	ReferenceTruckProps.prop_cylinder(dressing, 0.04, 0.13, Vector3(2.32, 1.56, -0.06), Vector3.ZERO, cup)
	ReferenceTruckProps.prop_cylinder(dressing, 0.043, 0.02, Vector3(2.32, 1.63, -0.06), Vector3.ZERO, lid)
	# Two round gauges in the instrument cluster, facing the driver.
	for offset: float in [-0.1, 0.1]:
		var gauge_z: float = -0.64 + offset
		ReferenceTruckProps.prop_cylinder(
				dressing, 0.055, 0.012, Vector3(3.235, 2.255, gauge_z), Vector3(0.0, 0.0, PI * 0.5), dial
			)
		ReferenceTruckProps.prop_box(
				dressing,
				Vector3(0.006, 0.045, 0.008),
				Vector3(3.228, 2.27, gauge_z + 0.01),
				needle,
				Vector3(deg_to_rad(35.0), 0.0, 0.0),
			)
	# The GPS, centre of the dash where the radio was (dashboard_gps.gd):
	# its screen faces the cab, model -X, turned a little toward the driver's
	# eye and tilted up so it reads from the seat.
	var gps := DashboardGps.new()
	gps.name = "DashboardGps"
	gps.position = Vector3(3.3, 2.16, 0.0)
	gps.rotation = Vector3(deg_to_rad(12.0), PI * 0.5 - deg_to_rad(15.0), 0.0)
	dressing.add_child(gps)
	# Rear-view mirror and a pine-tree air freshener hanging from it.
	ReferenceTruckProps.prop_box(dressing, Vector3(0.03, 0.12, 0.05), Vector3(3.22, 3.24, 0.0), _dark)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.05, 0.11, 0.34), Vector3(3.19, 3.13, 0.0), _dark)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.005, 0.09, 0.3), Vector3(3.164, 3.13, 0.0), _steel)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.004, 0.14, 0.004), Vector3(3.17, 3.0, 0.1), _dark)
	var tree := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.08, 0.12, 0.01)
	tree.mesh = prism
	tree.material_override = green
	tree.position = Vector3(3.17, 2.87, 0.1)
	tree.rotation.y = PI * 0.5
	dressing.add_child(tree)
	# Sun visors folded up against the headliner.
	for visor_z: float in [-0.6, 0.6]:
		ReferenceTruckProps.prop_box(
				dressing,
				Vector3(0.3, 0.025, 0.62),
				Vector3(3.08, 3.3, visor_z),
				seat_color,
				Vector3(0.0, 0.0, deg_to_rad(-12.0)),
			)
	# Delivery clipboard on the passenger side of the dash.
	var clipboard := Node3D.new()
	clipboard.position = Vector3(3.5, 2.265, 0.62)
	clipboard.rotation = Vector3(0.0, deg_to_rad(14.0), 0.0)
	dressing.add_child(clipboard)
	ReferenceTruckProps.prop_box(clipboard, Vector3(0.3, 0.015, 0.22), Vector3.ZERO, cardboard)
	ReferenceTruckProps.prop_box(clipboard, Vector3(0.26, 0.006, 0.19), Vector3(-0.01, 0.01, 0.0), paper)
	ReferenceTruckProps.prop_box(clipboard, Vector3(0.04, 0.02, 0.1), Vector3(0.12, 0.015, 0.0), _steel)
	# A parcel riding shotgun, and rubber mats on the cab floor.
	ReferenceTruckProps.prop_box(
			dressing, Vector3(0.3, 0.22, 0.3), Vector3(2.38, 1.8, 0.62), cardboard, Vector3(0.0, deg_to_rad(-8.0), 0.0)
		)
	for mat_z: float in [-0.62, 0.62]:
		ReferenceTruckProps.prop_box(dressing, Vector3(0.7, 0.012, 0.5), Vector3(3.0, 1.186, mat_z), _dark)
	_close_cab(dressing, seat_color)
	_add_cab_details(dressing)


## The authored cab is a shell of separate plates: from the seat you could
## see grass under the dashboard, the white hood behind it, the painted
## fenders poking up through the floor and bare white door skins. These
## panels close it into one interior.
func _close_cab(dressing: Node3D, trim: Material) -> void:
	var liner := ReferenceTruckProps.flat_material(Color("2b353c"))
	# Firewall under the dashboard, floor to dash, wall to wall.
	ReferenceTruckProps.prop_box(dressing, Vector3(0.1, 0.92, 2.42), Vector3(3.67, 1.64, 0.0), liner)
	# Dash top: covers the white hood seen through the windshield base.
	ReferenceTruckProps.prop_box(dressing, Vector3(0.36, 0.05, 2.3), Vector3(3.66, 2.275, 0.0), _dark)
	# Wheel-well humps over the front fenders, which rise above the floor.
	for side: float in [-1.0, 1.0]:
		ReferenceTruckProps.prop_box(dressing, Vector3(1.8, 0.42, 0.2), Vector3(2.63, 1.39, side * 1.15), liner)
	# Inner door trims ride on the door hinges, so they swing with the door.
	for side_name: String in ["Left", "Right"]:
		var hinge := _model.find_child("CabDoor_%s_HINGE_Z" % side_name, true, false) as Node3D
		if hinge == null:
			continue
		var inward: float = 1.0 if side_name == "Left" else -1.0
		var trims := Node3D.new()
		trims.name = "DoorTrim_" + side_name
		trims.position = -hinge.position
		hinge.add_child(trims)
		var z: float = -1.215 if side_name == "Left" else 1.215
		ReferenceTruckProps.prop_box(trims, Vector3(2.3, 0.72, 0.02), Vector3(2.5, 1.96, z), trim)
		ReferenceTruckProps.prop_box(
				trims, Vector3(0.9, 0.06, 0.1), Vector3(2.4, 2.02, z + 0.05 * inward), liner
			)  # Armrest.
		ReferenceTruckProps.prop_box(
				trims, Vector3(0.12, 0.05, 0.04), Vector3(1.75, 2.12, z + 0.03 * inward), _steel
			)  # Handle.



## Pedals, a fire extinguisher and a first-aid kit on the bulkhead.
func _add_cab_details(dressing: Node3D) -> void:
	var rubber := ReferenceTruckProps.flat_material(Color("1b1f23"))
	var pedals: Array = [
		[-0.44, Vector3(0.05, 0.16, 0.08)],
		[-0.66, Vector3(0.05, 0.12, 0.12)],
		[-0.86, Vector3(0.05, 0.12, 0.12)],
	]
	for pedal: Array in pedals:
		var z: float = pedal[0]
		ReferenceTruckProps.prop_box(
				dressing, Vector3(0.03, 0.5, 0.03), Vector3(3.5, 1.62, z), _dark, Vector3(0.0, 0.0, deg_to_rad(-20.0))
			)
		ReferenceTruckProps.prop_box(
				dressing, pedal[1], Vector3(3.42, 1.36, z), rubber, Vector3(0.0, 0.0, deg_to_rad(-35.0))
			)
	var red := ReferenceTruckProps.flat_material(Color("c8302b"))
	ReferenceTruckProps.prop_cylinder(dressing, 0.06, 0.34, Vector3(1.32, 1.4, 0.95), Vector3.ZERO, red)
	ReferenceTruckProps.prop_cylinder(dressing, 0.025, 0.06, Vector3(1.32, 1.6, 0.95), Vector3.ZERO, _dark)
	var first_aid := ReferenceTruckProps.flat_material(Color("f2f0ea"))
	ReferenceTruckProps.prop_box(dressing, Vector3(0.06, 0.2, 0.28), Vector3(1.29, 2.5, 0.8), first_aid)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.065, 0.04, 0.12), Vector3(1.29, 2.5, 0.8), red)
	ReferenceTruckProps.prop_box(dressing, Vector3(0.065, 0.12, 0.04), Vector3(1.29, 2.5, 0.8), red)


## Each pedal hangs from a pivot at its top, in the model's space (x front,
## y up, z right): the driver sits at z -0.62, the cab floor is at y 1.18.
func build_pedals(parent: Node3D) -> void:
	var rubber := ReferenceTruckProps.flat_material(Color("2a2d2e"))
	for entry: Array in [["Clutch", -0.8], ["Brake", -0.63], ["Gas", -0.45]]:
		var pivot := Node3D.new()
		pivot.name = "Pedal%s" % entry[0]
		pivot.position = Vector3(3.36, 1.52, float(entry[1]))
		pivot.rotation.z = PEDAL_REST
		parent.add_child(pivot)
		ReferenceTruckProps.add_box(pivot, Vector3(0.025, 0.26, 0.025), Vector3(0.0, -0.13, 0.0), _steel)
		var pad_size := Vector3(0.03, 0.1, 0.07) if entry[0] != "Gas" else Vector3(0.03, 0.16, 0.06)
		ReferenceTruckProps.add_box(pivot, pad_size, Vector3(-0.02, -0.26, 0.0), rubber)
		if entry[0] == "Brake":
			brake_pedal = pivot
		elif entry[0] == "Gas":
			gas_pedal = pivot


## Brake and accelerator dip with what the truck is actually doing.
func animate_pedals(vehicle: VehicleBody3D, delta: float) -> void:
	if brake_pedal == null or vehicle == null:
		return
	var braking: bool = bool(vehicle.get(&"presentation_braking"))
	var accelerating: bool = absf(vehicle.engine_force) > 1.0
	brake_pedal.rotation.z = move_toward(brake_pedal.rotation.z, PEDAL_PRESSED if braking else PEDAL_REST, delta * 3.0)
	gas_pedal.rotation.z = move_toward(gas_pedal.rotation.z, PEDAL_PRESSED if accelerating else PEDAL_REST, delta * 3.0)
