class_name ReferenceTruck
extends Node3D
## Presentation adapter for the authored low-poly box truck. Gameplay stays in
## vehicle.tscn (collision, seats, mounts, door controls, wheels), laid out to
## match this model; this node only dresses it: hangs the model, makes the
## glass see-through, puts the authored wheels on the physics wheels, turns
## the steering wheel, animates the doors and ramp, and builds the cargo rack
## art from the very collision shapes the packages rest on.

const TRUCK_PATH := "res://assets/models/truck_reference_lowpoly.glb"
const MODEL_SCALE := 0.8
## Blender's +X front becomes Godot's -Z front; the offset lines the model's
## floor, axles and cab up with the collision in vehicle.tscn.
const MODEL_OFFSET := Vector3(0.0, -0.674, 0.604)
const GLASS_MATERIAL := "DT_Glass"
const DOOR_SECONDS := 0.55
const RAMP_SECONDS := 0.4
## Hinge node, opening direction and angle (radians) of every door leaf.
## Blender's vertical Z axis is Godot's Y inside the model, so each hinge
## swings on its own rotation.y; the sign sends the leaf outward.
const DOORS := {
	&"rear": [["RearDoor_Left_HINGE_Z", -1.92], ["RearDoor_Right_HINGE_Z", 1.92]],
	&"cab_left": [["CabDoor_Left_HINGE_Z", -1.1]],
	&"cab_right": [["CabDoor_Right_HINGE_Z", 1.1]],
}
const WHEELS := {
	"Wheel_Front_Left_AXLE_Y": "FrontLeftWheel",
	"Wheel_Front_Right_AXLE_Y": "FrontRightWheel",
	"Wheel_Rear_Left_AXLE_Y": "RearLeftWheel",
	"Wheel_Rear_Right_AXLE_Y": "RearRightWheel",
}
const RACK_ACCENT := Color("f0a236")

var vehicle: VehicleBody3D
var model: Node3D
var steering_wheel: Node3D
var ramp_visual: Node3D
var _hinges: Dictionary = {}
var _door_state: Dictionary = {}
var _door_tweens: Dictionary = {}
var _door_audio: Dictionary = {}
var _ramp_deployed: bool = true
var _ramp_tween: Tween
var _ramp_out_position: Vector3
var _ramp_length: float = 0.0
var _steel: Material
var _dark: Material
var _accent: StandardMaterial3D


func _ready() -> void:
	vehicle = get_parent() as VehicleBody3D
	if vehicle == null or vehicle.get_node_or_null(^"BodyVisuals/ReferenceTruckModel") != null:
		return
	model = _load_model()
	if model == null:
		push_error("No se pudo cargar el modelo de camión: " + TRUCK_PATH)
		return
	model.name = "ReferenceTruckModel"
	model.position = MODEL_OFFSET
	model.rotation.y = PI * 0.5
	model.scale = Vector3.ONE * MODEL_SCALE
	vehicle.get_node(^"BodyVisuals").add_child(model)
	_steel = _material_named("DT_Steel")
	_dark = _material_named("DT_Dark")
	_accent = StandardMaterial3D.new()
	_accent.albedo_color = RACK_ACCENT
	_accent.roughness = 0.6
	_remove_authored_shelving()
	_make_glass_transparent()
	_reshape_side_windows()
	_attach_wheel_visuals()
	_build_steering_pivot()
	_dress_cab()
	_collect_doors()
	_build_cargo_fittings()
	_build_jump_seats()
	_build_ramp()
	_bind_presentation()


func _load_model() -> Node3D:
	# The imported scene is what an exported build ships; the raw .glb is not
	# packed. GLTFDocument covers a fresh checkout whose import cache doesn't
	# exist yet (command-line tests before the editor has ever opened it).
	if ResourceLoader.exists(TRUCK_PATH, "PackedScene"):
		var packed := load(TRUCK_PATH) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_file(TRUCK_PATH, state) != OK:
		return null
	return document.generate_scene(state) as Node3D


func _meshes() -> Array[Node]:
	return model.find_children("*", "MeshInstance3D", true, false)


func _material_named(material_name: String) -> Material:
	for mesh: MeshInstance3D in _meshes():
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and material.resource_name == material_name:
				return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.55, 0.58, 0.6) if material_name == "DT_Steel" else Color(0.08, 0.09, 0.1)
	return fallback


func _uses_material(mesh: MeshInstance3D, material_name: String) -> bool:
	for surface in range(mesh.mesh.get_surface_count()):
		var material := mesh.mesh.surface_get_material(surface)
		if material != null and material.resource_name == material_name:
			return true
	return false


## The model's three-tier side shelves are 0.39 m deep with 0.54 m between
## tiers: no package in this game fits on them. The deep rack on the left
## wall (vehicle.tscn + _build_cargo_fittings) replaces them.
func _remove_authored_shelving() -> void:
	for node: Node in model.find_children("Shelf*", "", true, false):
		node.get_parent().remove_child(node)
		node.queue_free()


## Glass is chosen by material, not by node name: the windshield is called
## "FrontWindshield" (no "window"/"glass" in it), while frame pieces such as
## "CabDoorWindowHeader" are opaque paint that must stay solid.
func _make_glass_transparent() -> void:
	var glass := StandardMaterial3D.new()
	glass.resource_name = "TruckGlass"
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.82, 0.9, 0.16)
	glass.metallic_specular = 0.9
	glass.roughness = 0.06
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Shadow maps drew stair-stepped pillar shadows across every pane.
	glass.disable_receive_shadows = true
	for mesh: MeshInstance3D in _meshes():
		if _uses_material(mesh, GLASS_MATERIAL):
			mesh.material_override = glass
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Each authored wheel (tire, rim, hub, bolts) is centred on its AXLE node.
## It hangs on the physics VehicleWheel3D with no offset at all, so the
## native spin, steer and suspension move it around its own hub; the physics
## wheel sits on the same axle with the tire's real radius (vehicle.tscn).
func _attach_wheel_visuals() -> void:
	var axle_basis := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * MODEL_SCALE)
	for art_name: String in WHEELS:
		var art := model.find_child(art_name, true, false) as Node3D
		var wheel := vehicle.get_node_or_null(NodePath(WHEELS[art_name])) as VehicleWheel3D
		if art == null or wheel == null:
			continue
		art.reparent(wheel, false)
		art.transform = Transform3D(axle_basis, Vector3.ZERO)


## The authored steering wheel is twelve straight rim segments with gaps at
## every joint. It's measured (centre, column axis, radius) and rebuilt as a
## round rim with three spokes and a hub, all under one pivot whose local Y
## is the column axis pointing away from the driver -- the convention
## VehiclePresentation turns it by.
func _build_steering_pivot() -> void:
	var pieces: Array[Node3D] = []
	for node: Node in model.find_children("Steering*", "MeshInstance3D", true, false):
		if not String(node.name).begins_with("SteeringColumn"):
			pieces.append(node as Node3D)
	var rim: Array[Vector3] = []
	var center := Vector3.ZERO
	for piece: Node3D in pieces:
		if String(piece.name).begins_with("SteeringRim"):
			rim.append(piece.position)
			center += piece.position
	if rim.size() < 3:
		return
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
	steering_wheel = Node3D.new()
	steering_wheel.name = "SteeringWheel"
	steering_wheel.transform = Transform3D(Basis(side, normal, side.cross(normal)), center)
	parent.add_child(steering_wheel)
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
	steering_wheel.add_child(ring)
	# T-shaped spokes: left, right and the one toward the driver's knees.
	var down_is_plus_z: bool = steering_wheel.transform.basis.z.y < 0.0
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
		steering_wheel.add_child(spoke)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.075
	cylinder.bottom_radius = 0.085
	cylinder.height = 0.07
	cylinder.radial_segments = 16
	hub.mesh = cylinder
	hub.material_override = _dark
	steering_wheel.add_child(hub)
	var horn := MeshInstance3D.new()
	var cap := CylinderMesh.new()
	cap.top_radius = 0.055
	cap.bottom_radius = 0.06
	cap.height = 0.02
	cap.radial_segments = 16
	horn.mesh = cap
	horn.material_override = _accent
	horn.position = Vector3(0.0, -0.045, 0.0)  # Driver's side of the hub.
	steering_wheel.add_child(horn)


func _collect_doors() -> void:
	for door: StringName in DOORS:
		var leaves: Array = []
		for entry: Array in DOORS[door]:
			var hinge := model.find_child(entry[0], true, false) as Node3D
			if hinge != null:
				leaves.append([hinge, float(entry[1])])
		_hinges[door] = leaves
		var open := bool(vehicle.call(&"is_door_open", door))
		_door_state[door] = open
		_pose_door(1.0 if open else 0.0, door)
		var audio := AudioStreamPlayer3D.new()
		audio.name = "DoorAudio_" + String(door)
		audio.stream = preload("res://scripts/presentation/synth_audio.gd").impact_thud()
		audio.unit_size = 6.0
		audio.max_distance = 30.0
		if not leaves.is_empty():
			audio.position = vehicle.to_local((leaves[0][0] as Node3D).global_position)
		# Under this node (vehicle space, identity transform), not the vehicle
		# itself, so the van's own direct children stay just its gameplay parts.
		add_child(audio)
		_door_audio[door] = audio


func _pose_door(amount: float, door: StringName) -> void:
	for leaf: Array in _hinges.get(door, []):
		(leaf[0] as Node3D).rotation.y = float(leaf[1]) * amount


## Called by vehicle.gd whenever the replicated door state changes, on every
## peer. Swings open with a little overshoot, closes with a latch thud.
func set_door_open(door: StringName, open: bool) -> void:
	if not _hinges.has(door) or bool(_door_state.get(door, false)) == open:
		return
	_door_state[door] = open
	var leaves: Array = _hinges[door]
	if leaves.is_empty():
		return
	var previous: Tween = _door_tweens.get(door)
	if previous != null and previous.is_valid():
		previous.kill()
	var start: float = (leaves[0][0] as Node3D).rotation.y / float(leaves[0][1])
	var tween := create_tween()
	tween.tween_method(_pose_door.bind(door), start, 1.0 if open else 0.0, DOOR_SECONDS) \
		.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_door_tweens[door] = tween
	var audio: AudioStreamPlayer3D = _door_audio.get(door)
	if audio == null:
		return
	if open:
		_play_door_sound(audio, 1.9, -24.0)
	else:
		tween.tween_callback(_play_door_sound.bind(audio, 1.25, -12.0))


func _play_door_sound(audio: AudioStreamPlayer3D, pitch: float, volume_db: float) -> void:
	if not audio.is_inside_tree():
		return
	audio.pitch_scale = pitch
	audio.volume_db = volume_db
	audio.play()


## The authored side glass is a plain rectangle that runs forward past the
## door's slanted front pillar, so its top corner hung out over the
## windshield. Each pane is re-cut to the real opening -- back pillar to the
## slanted front pillar, sill to header -- and framed with a rubber seal.
## Coordinates are the model's (x front, y up), measured from the door frame.
const WINDOW_OPENING := [Vector2(1.53, 2.34), Vector2(3.76, 2.34), Vector2(3.15, 3.21), Vector2(1.53, 3.21)]
const WINDOW_PLANE_Z := 1.27

func _reshape_side_windows() -> void:
	var seal := _flat_material(Color("1b2025"))
	for side_name: String in ["Left", "Right"]:
		var pane := model.find_child("SideWindow_" + side_name, true, false) as MeshInstance3D
		var hinge := model.find_child("CabDoor_%s_HINGE_Z" % side_name, true, false) as Node3D
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
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
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
			strip.transform = Transform3D(Basis(along, Vector3(0.0, 0.0, 1.0).cross(along), Vector3(0.0, 0.0, 1.0)), (a + b) * 0.5)
			pane.add_child(strip)


## Life in the cab: a passenger seat, centre console with gear stick,
## handbrake and coffee, gauges, radio, rear-view mirror with an air
## freshener, sun visors, a clipboard of deliveries and floor mats. Built in
## the model's own space (x front, y up, z right), sized from its dashboard.
func _dress_cab() -> void:
	var dashboard := model.find_child("Dashboard", true, false) as MeshInstance3D
	if dashboard == null:
		return
	var cab := dashboard.get_parent() as Node3D
	var dressing := Node3D.new()
	dressing.name = "CabDressing"
	cab.add_child(dressing)
	var seat_color: Material = _material_named("DT_Seat")
	var paper := _flat_material(Color("f2eee2"))
	var cardboard := _flat_material(Color("b98a52"))
	var green := _flat_material(Color("3fae5a"))
	var screen := _flat_material(Color("1d6f78"))
	screen.emission_enabled = true
	screen.emission = Color("39c4c9")
	screen.emission_energy_multiplier = 0.6
	var dial := _flat_material(Color("f5f1e6"))
	var needle := _flat_material(Color("e2402f"))
	var cup := _flat_material(Color("f4f1ea"))
	var lid := _flat_material(Color("6b4a33"))
	# Passenger seat: a copy of the driver's, mirrored across the cab.
	for part_name: String in ["DriverSeat", "DriverBackrest", "DriverSeatBase"]:
		var part := model.find_child(part_name, true, false) as MeshInstance3D
		if part != null:
			var copy := part.duplicate() as MeshInstance3D
			copy.name = part_name.replace("Driver", "Passenger") + "_Cab"
			copy.position.z = -part.position.z
			dressing.add_child(copy)
	# Centre console between the seats, with the gear stick and handbrake.
	_prop_box(dressing, Vector3(0.72, 0.3, 0.3), Vector3(2.6, 1.33, 0.0), _dark)
	_prop_box(dressing, Vector3(0.64, 0.02, 0.24), Vector3(2.6, 1.49, 0.0), seat_color)
	_prop_cylinder(dressing, 0.018, 0.34, Vector3(2.92, 1.66, 0.0), Vector3(0.0, 0.0, deg_to_rad(12.0)), _dark)
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
	_prop_box(dressing, Vector3(0.28, 0.04, 0.05), Vector3(2.45, 1.54, 0.07), _dark, Vector3(0.0, 0.0, deg_to_rad(18.0)))
	# Coffee in the cup holder.
	_prop_cylinder(dressing, 0.04, 0.13, Vector3(2.32, 1.56, -0.06), Vector3.ZERO, cup)
	_prop_cylinder(dressing, 0.043, 0.02, Vector3(2.32, 1.63, -0.06), Vector3.ZERO, lid)
	# Two round gauges in the instrument cluster, facing the driver.
	for offset: float in [-0.1, 0.1]:
		var gauge_z: float = -0.64 + offset
		_prop_cylinder(dressing, 0.055, 0.012, Vector3(3.235, 2.255, gauge_z), Vector3(0.0, 0.0, PI * 0.5), dial)
		_prop_box(dressing, Vector3(0.006, 0.045, 0.008), Vector3(3.228, 2.27, gauge_z + 0.01), needle, Vector3(deg_to_rad(35.0), 0.0, 0.0))
	# Radio with a lit screen, centre of the dash.
	_prop_box(dressing, Vector3(0.05, 0.12, 0.3), Vector3(3.33, 2.13, 0.0), _dark)
	_prop_box(dressing, Vector3(0.01, 0.06, 0.16), Vector3(3.303, 2.15, 0.0), screen)
	# Rear-view mirror and a pine-tree air freshener hanging from it.
	_prop_box(dressing, Vector3(0.03, 0.12, 0.05), Vector3(3.22, 3.24, 0.0), _dark)
	_prop_box(dressing, Vector3(0.05, 0.11, 0.34), Vector3(3.19, 3.13, 0.0), _dark)
	_prop_box(dressing, Vector3(0.005, 0.09, 0.3), Vector3(3.164, 3.13, 0.0), _steel)
	_prop_box(dressing, Vector3(0.004, 0.14, 0.004), Vector3(3.17, 3.0, 0.1), _dark)
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
		_prop_box(dressing, Vector3(0.3, 0.025, 0.62), Vector3(3.08, 3.3, visor_z), seat_color, Vector3(0.0, 0.0, deg_to_rad(-12.0)))
	# Delivery clipboard on the passenger side of the dash.
	var clipboard := Node3D.new()
	clipboard.position = Vector3(3.5, 2.265, 0.62)
	clipboard.rotation = Vector3(0.0, deg_to_rad(14.0), 0.0)
	dressing.add_child(clipboard)
	_prop_box(clipboard, Vector3(0.3, 0.015, 0.22), Vector3.ZERO, cardboard)
	_prop_box(clipboard, Vector3(0.26, 0.006, 0.19), Vector3(-0.01, 0.01, 0.0), paper)
	_prop_box(clipboard, Vector3(0.04, 0.02, 0.1), Vector3(0.12, 0.015, 0.0), _steel)
	# A parcel riding shotgun, and rubber mats on the cab floor.
	_prop_box(dressing, Vector3(0.3, 0.22, 0.3), Vector3(2.38, 1.8, 0.62), cardboard, Vector3(0.0, deg_to_rad(-8.0), 0.0))
	for mat_z: float in [-0.62, 0.62]:
		_prop_box(dressing, Vector3(0.7, 0.012, 0.5), Vector3(3.0, 1.186, mat_z), _dark)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	return material


func _prop_box(parent: Node3D, size: Vector3, at: Vector3, material: Material, rotation_euler: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := _add_box(parent, size, at, material)
	mesh.rotation = rotation_euler
	return mesh


func _prop_cylinder(parent: Node3D, radius: float, height: float, at: Vector3, rotation_euler: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = at
	mesh.rotation = rotation_euler
	parent.add_child(mesh)
	return mesh


## Folding jump seats on the right wall, facing the rack, one per bay column
## (vehicle.tscn RackSeat*EyePoint). Folded flat against the wall while free,
## so they never narrow the aisle; they drop down when somebody sits.
const JUMP_SEAT_FOLDED := -PI * 0.5
var _jump_seats: Array = []

func _build_jump_seats() -> void:
	var seat_color: Material = _material_named("DT_Seat")
	var fittings := vehicle.get_node(^"BodyVisuals/CargoFittings") as Node3D
	for marker: Node in vehicle.get_node(^"CargoBay").get_children():
		if not String(marker.name).begins_with("RackSeat"):
			continue
		var z: float = (marker as Node3D).position.z
		var hinge := Node3D.new()
		hinge.name = String(marker.name).replace("EyePoint", "Fold")
		hinge.position = Vector3(0.985, 0.66, z)
		hinge.rotation.z = JUMP_SEAT_FOLDED
		fittings.add_child(hinge)
		# The cushion hangs off the hinge toward the aisle (-X) when down.
		_add_box(hinge, Vector3(0.36, 0.06, 0.42), Vector3(-0.18, 0.0, 0.0), seat_color)
		_add_box(hinge, Vector3(0.03, 0.04, 0.38), Vector3(-0.35, -0.03, 0.0), _dark)
		# Backrest pad and mounting plate stay on the wall.
		_add_box(fittings, Vector3(0.05, 0.42, 0.4), Vector3(0.97, 0.98, z), seat_color)
		_add_box(fittings, Vector3(0.02, 0.62, 0.46), Vector3(0.99, 0.86, z), _dark)
		_jump_seats.append([hinge, marker.get_path()])


func _process(delta: float) -> void:
	if _jump_seats.is_empty():
		return
	var occupied: Array = []
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		occupied.append(NodePath(player.get(&"seat_node_path")))
	for entry: Array in _jump_seats:
		var hinge: Node3D = entry[0]
		var target: float = 0.0 if entry[1] in occupied else JUMP_SEAT_FOLDED
		hinge.rotation.z = move_toward(hinge.rotation.z, target, delta * 6.0)


## Rack decks, end frames and wheel-well humps are drawn from the collision
## shapes themselves, so the boxes can never look like they float above or
## sink into a shelf.
func _build_cargo_fittings() -> void:
	var fittings := Node3D.new()
	fittings.name = "CargoFittings"
	# Siblings of the model inside BodyVisuals, in vehicle space.
	vehicle.get_node(^"BodyVisuals").add_child(fittings)
	for shape_name: String in ["RackLowerDeckCollision", "RackUpperDeckCollision"]:
		var deck := _box_shape(shape_name)
		if deck.is_empty():
			continue
		var size: Vector3 = deck.size
		var at: Vector3 = deck.position
		var top: float = at.y + size.y * 0.5
		var aisle_edge: float = at.x + size.x * 0.5
		# Dark deck plate: a light one showed as a bright strip under every box,
		# which read as the box hovering above the shelf.
		_add_box(fittings, Vector3(size.x, 0.03, size.z), Vector3(at.x, top - 0.015, at.z), _dark)
		# Orange load beam along the aisle edge, its top flush with the deck
		# and a centimetre proud of it, so the box visibly sits on the beam line.
		_add_box(fittings, Vector3(0.05, 0.07, size.z), Vector3(aisle_edge - 0.015, top - 0.035, at.z), _accent)
	for shape_name: String in ["RackFrontEndCollision", "RackRearEndCollision"]:
		var frame := _box_shape(shape_name)
		if frame.is_empty():
			continue
		var size: Vector3 = frame.size
		var at: Vector3 = frame.position
		_add_box(fittings, Vector3(size.x, size.y, 0.02), at, _steel)
		# Upright on the aisle corner.
		_add_box(fittings, Vector3(0.05, size.y, 0.05), Vector3(at.x + size.x * 0.5 - 0.025, at.y, at.z), _accent)
	for shape_name: String in ["LeftWheelWellCollision", "RightWheelWellCollision"]:
		var well := _box_shape(shape_name)
		if not well.is_empty():
			_add_box(fittings, well.size, well.position, _dark)
	# Logistic rails on the bare right wall: tie-down track, like a real box truck.
	for height: float in [0.95, 1.75]:
		_add_box(fittings, Vector3(0.02, 0.06, 2.7), Vector3(0.99, height, 3.05), _steel)


func _box_shape(shape_name: String) -> Dictionary:
	var node := vehicle.get_node_or_null(NodePath(shape_name)) as CollisionShape3D
	if node == null or not node.shape is BoxShape3D:
		return {}
	return {"size": (node.shape as BoxShape3D).size, "position": node.position}


func _add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


## Ramp art matches RearRamp/Shape: a steel plate with dark grip bars.
## Stowing slides it back under the cargo floor.
func _build_ramp() -> void:
	var shape_node := vehicle.get_node_or_null(^"RearRamp/Shape") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return
	var size: Vector3 = (shape_node.shape as BoxShape3D).size
	ramp_visual = Node3D.new()
	ramp_visual.name = "RampVisual"
	ramp_visual.transform = shape_node.transform
	vehicle.get_node(^"BodyVisuals").add_child(ramp_visual)
	_add_box(ramp_visual, size, Vector3.ZERO, _steel)
	var bars: int = int(size.z / 0.2)
	for index in range(bars):
		var z: float = -size.z * 0.5 + 0.1 + float(index) * size.z / float(bars)
		_add_box(ramp_visual, Vector3(size.x - 0.08, 0.02, 0.035), Vector3(0.0, size.y * 0.5 + 0.01, z), _dark)
	for side: float in [-1.0, 1.0]:
		_add_box(ramp_visual, Vector3(0.04, 0.08, size.z), Vector3(side * (size.x * 0.5 - 0.02), 0.03, 0.0), _accent)
	_ramp_out_position = ramp_visual.position
	_ramp_length = size.z
	_ramp_deployed = bool(vehicle.get(&"rear_ramp_deployed"))
	_pose_ramp(1.0 if _ramp_deployed else 0.0)


func _pose_ramp(amount: float) -> void:
	if ramp_visual == null:
		return
	# Slide along the ramp's own length, back toward (and under) the floor.
	var stowed: Vector3 = _ramp_out_position - ramp_visual.transform.basis.z.normalized() * _ramp_length
	ramp_visual.position = stowed.lerp(_ramp_out_position, amount)
	ramp_visual.visible = amount > 0.02


func set_ramp_deployed(deployed: bool) -> void:
	if ramp_visual == null or deployed == _ramp_deployed:
		return
	_ramp_deployed = deployed
	if _ramp_tween != null and _ramp_tween.is_valid():
		_ramp_tween.kill()
	_ramp_tween = create_tween()
	_ramp_tween.tween_method(_pose_ramp, 0.0 if deployed else 1.0, 1.0 if deployed else 0.0, RAMP_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _bind_presentation() -> void:
	var presentation := vehicle.get_node_or_null(^"VehiclePresentation")
	if presentation == null or not presentation.has_method(&"bind_model"):
		return
	presentation.call(&"bind_model", steering_wheel,
		model.find_children("HeadlightLens*", "MeshInstance3D", true, false),
		model.find_children("TailLight*", "MeshInstance3D", true, false))
