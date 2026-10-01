class_name ReferenceTruckCargo
extends RefCounted
## The cargo bay's art for ReferenceTruck: the rack decks, end frames, wheel-well
## humps and tie-down rails (drawn from the very collision shapes the packages
## rest on), the fold-down jump seats on the right wall and the rear ramp.
## Presentation only; the shapes and seats it follows live in vehicle.tscn.

var ramp_visual: Node3D
var _vehicle: VehicleBody3D
var _model: Node3D
var _steel: Material
var _dark: Material
var _accent: StandardMaterial3D
var _ramp_out_position: Vector3
var _ramp_length: float = 0.0


func _init(vehicle: VehicleBody3D, model: Node3D, steel: Material, dark: Material, accent: StandardMaterial3D) -> void:
	_vehicle = vehicle
	_model = model
	_steel = steel
	_dark = dark
	_accent = accent


## Rack decks, end frames and wheel-well humps are drawn from the collision
## shapes themselves, so the boxes can never look like they float above or
## sink into a shelf.
## Between the rack's two end frames, in vehicle space (RackLowerDeckCollision).
const RACK_CENTRE_Z: float = 3.11


func build_cargo_fittings() -> void:
	var fittings := Node3D.new()
	fittings.name = "CargoFittings"
	# Siblings of the model inside BodyVisuals, in vehicle space.
	_vehicle.get_node(^"BodyVisuals").add_child(fittings)
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
		ReferenceTruckProps.add_box(fittings, Vector3(size.x, 0.03, size.z), Vector3(at.x, top - 0.015, at.z), _dark)
		# Orange load beam along the aisle edge, a centimetre proud of the
		# deck: flush, the two tops shared one plane and z-fought into stripes.
		ReferenceTruckProps.add_box(
				fittings, Vector3(0.05, 0.07, size.z), Vector3(aisle_edge - 0.015, top - 0.025, at.z), _accent
			)
	for shape_name: String in ["RackFrontEndCollision", "RackRearEndCollision"]:
		var frame := _box_shape(shape_name)
		if frame.is_empty():
			continue
		var size: Vector3 = frame.size
		var at: Vector3 = frame.position
		# The collider runs well past the steel, away from the rack (see
		# vehicle.tscn): the frame is drawn on its face towards the shelves.
		var inward: float = signf(RACK_CENTRE_Z - at.z)
		var face: Vector3 = Vector3(at.x, at.y, at.z + inward * (size.z * 0.5 - 0.01))
		ReferenceTruckProps.add_box(fittings, Vector3(size.x, size.y, 0.02), face, _steel)
		# Upright on the aisle corner.
		ReferenceTruckProps.add_box(
				fittings,
				Vector3(0.05, size.y, 0.05),
				Vector3(at.x + size.x * 0.5 - 0.025, at.y, face.z - inward * 0.015),
				_accent,
			)
	for shape_name: String in ["LeftWheelWellCollision", "RightWheelWellCollision"]:
		var well := _box_shape(shape_name)
		if not well.is_empty():
			ReferenceTruckProps.add_box(fittings, well.size, well.position, _dark)
	# Logistic rails on the bare right wall: tie-down track, like a real box truck.
	for height: float in [0.95, 1.75]:
		ReferenceTruckProps.add_box(fittings, Vector3(0.02, 0.06, 2.7), Vector3(0.99, height, 3.05), _steel)


func _box_shape(shape_name: String) -> Dictionary:
	var node := _vehicle.get_node_or_null(NodePath(shape_name)) as CollisionShape3D
	if node == null or not node.shape is BoxShape3D:
		return {}
	return {"size": (node.shape as BoxShape3D).size, "position": node.position}


## Folding jump seats on the right wall, facing the rack, one per bay column
## (vehicle.tscn RackSeat*EyePoint). Folded flat against the wall while free,
## so they never narrow the aisle; they drop down when somebody sits.
const JUMP_SEAT_FOLDED := -PI * 0.5
var _jump_seats: Array = []


func build_jump_seats() -> void:
	var seat_color: Material = ReferenceTruckProps.material_named(_model, "DT_Seat")
	var fittings := _vehicle.get_node(^"BodyVisuals/CargoFittings") as Node3D
	for marker: Node in _vehicle.get_node(^"CargoBay").get_children():
		if not String(marker.name).begins_with("RackSeat"):
			continue
		var z: float = (marker as Node3D).position.z
		var hinge := Node3D.new()
		hinge.name = String(marker.name).replace("EyePoint", "Fold")
		hinge.position = Vector3(0.985, 0.66, z)
		hinge.rotation.z = JUMP_SEAT_FOLDED
		fittings.add_child(hinge)
		# The cushion hangs off the hinge toward the aisle (-X) when down.
		ReferenceTruckProps.add_box(hinge, Vector3(0.36, 0.06, 0.42), Vector3(-0.18, 0.0, 0.0), seat_color)
		ReferenceTruckProps.add_box(hinge, Vector3(0.03, 0.04, 0.38), Vector3(-0.35, -0.03, 0.0), _dark)
		# Backrest pad and mounting plate stay on the wall.
		ReferenceTruckProps.add_box(fittings, Vector3(0.05, 0.42, 0.4), Vector3(0.97, 0.98, z), seat_color)
		ReferenceTruckProps.add_box(fittings, Vector3(0.02, 0.62, 0.46), Vector3(0.99, 0.86, z), _dark)
		_jump_seats.append([hinge, marker.get_path()])


## Folds the jump seats flat while free and drops the ones somebody sits in.
func animate_jump_seats(tree: SceneTree, delta: float) -> void:
	if _jump_seats.is_empty():
		return
	var occupied: Array = []
	for player: Node in tree.get_nodes_in_group(&"player"):
		occupied.append(NodePath(player.get(&"seat_node_path")))
	for entry: Array in _jump_seats:
		var hinge: Node3D = entry[0]
		var target: float = 0.0 if entry[1] in occupied else JUMP_SEAT_FOLDED
		hinge.rotation.z = move_toward(hinge.rotation.z, target, delta * 6.0)


## Ramp art matches RearRamp/Shape: a steel plate with dark grip bars.
## Stowing slides it back under the cargo floor.
func build_ramp() -> Node3D:
	var shape_node := _vehicle.get_node_or_null(^"RearRamp/Shape") as CollisionShape3D
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return null
	var size: Vector3 = (shape_node.shape as BoxShape3D).size
	ramp_visual = Node3D.new()
	ramp_visual.name = "RampVisual"
	ramp_visual.transform = shape_node.transform
	_vehicle.get_node(^"BodyVisuals").add_child(ramp_visual)
	ReferenceTruckProps.add_box(ramp_visual, size, Vector3.ZERO, _steel)
	var bars: int = int(size.z / 0.2)
	for index in range(bars):
		var z: float = -size.z * 0.5 + 0.1 + float(index) * size.z / float(bars)
		ReferenceTruckProps.add_box(
				ramp_visual, Vector3(size.x - 0.08, 0.02, 0.035), Vector3(0.0, size.y * 0.5 + 0.01, z), _dark
			)
	for side: float in [-1.0, 1.0]:
		ReferenceTruckProps.add_box(
				ramp_visual, Vector3(0.04, 0.08, size.z), Vector3(side * (size.x * 0.5 - 0.02), 0.03, 0.0), _accent
			)
	_ramp_out_position = ramp_visual.position
	_ramp_length = size.z
	return ramp_visual


func pose_ramp(amount: float) -> void:
	if ramp_visual == null:
		return
	# Slide along the ramp's own length, back toward (and under) the floor.
	var stowed: Vector3 = _ramp_out_position - ramp_visual.transform.basis.z.normalized() * _ramp_length
	ramp_visual.position = stowed.lerp(_ramp_out_position, amount)
	ramp_visual.visible = amount > 0.02
