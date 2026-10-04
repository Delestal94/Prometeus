class_name WorldGate
extends Node3D
## A gate of the continuous map: a closed way that a milestone, a vehicle, a piece
## of equipment or money opens for good (expansion D-0306).
##
## Barrier, roadblock and equipment gates are a StaticBody3D that stops whoever
## hits it, plus a sign that says what is missing. Water and altitude gates have
## no collision: they are the edge of the map for the vehicles that cannot cross
## (see passable_for). The open/closed state lives in the company state, not here:
## it is handed in by setup() as a plain object so this script names no autoload
## (lesson N-919). What you see is a GLB per kind (MODELS, built by
## assets/tools/build_world_gates.py): a boom, two barricades or a ranger post that
## move out of the way when the gate opens, or a coast / mountain sign. The closed
## pose of every moving part is saved at build time and the open pose is "closed +
## delta", so refresh() can run any number of times. Without the asset (a test scene)
## the old grey box stands in.

signal gate_opened(gate_id: StringName)

const SIZE: Vector3 = Vector3(8.0, 3.0, 0.6)
const SIGN_HEIGHT: float = 3.6
const SIGN_ON_BOARD_FONT: int = 26
const SIGN_ON_BOARD_WIDTH: float = 184.0
const BOARD_LIFT: float = 0.02
const ROADBLOCK_SLIDE: float = 5.5
const MODEL_DIR: String = "res://assets/models/environment/gates/"
const MODELS: Dictionary = {
	GateRequirement.Kind.BARRIER: MODEL_DIR + "sm_env_gate_barrier.glb",
	GateRequirement.Kind.ROADBLOCK: MODEL_DIR + "sm_env_gate_roadblock.glb",
	GateRequirement.Kind.EQUIPMENT: MODEL_DIR + "sm_env_gate_checkpoint.glb",
	GateRequirement.Kind.WATER: MODEL_DIR + "sm_env_gate_sign_coast.glb",
	GateRequirement.Kind.ALTITUDE: MODEL_DIR + "sm_env_gate_sign_mountain.glb",
}

var requirement: GateRequirement
var body: StaticBody3D
var sign_label: Label3D

var _state: Object
var _mesh: MeshInstance3D  ## the grey fallback box, null when the GLB loaded
var _model: Node3D  ## the GLB instance (named "Model"), null on the fallback
var _board: Node3D  ## the blank plate a Label3D sits on, if the model has one
## Moving parts by name: {node, position, rotation} as they stand closed.
var _parts: Dictionary = {}


## `state` is a CompanyState (or anything with is_gate_open, open_gate, gate_owned
## and money). Call it before adding the gate to the tree, or right after.
func setup(gate_requirement: GateRequirement, state: Object) -> void:
	requirement = gate_requirement
	_state = state
	name = String(requirement.id)
	position = Vector3(requirement.position_xz.x, 0.0, requirement.position_xz.y)
	_build()
	refresh()


func is_open() -> bool:
	return _state != null and _state.call("is_gate_open", requirement.id)


## Can this vehicle cross right now? An open gate lets everyone through. A closed
## water or altitude gate lets through only the vehicle it names (the boat sails,
## the plane flies over); a closed barrier, roadblock or equipment gate lets no one.
func passable_for(vehicle_key: StringName) -> bool:
	if is_open():
		return true
	return not requirement.has_collision() and vehicle_key == requirement.vehicle_key


## Opens the gate if the company meets the requirement, or, with `pay`, if paying
## the cost does. Returns true when it is open afterwards. Never closes it.
func try_open(pay: bool = false) -> bool:
	if is_open():
		return true
	var owned: Dictionary = _state.call("gate_owned")
	if requirement.is_met(owned):
		_open()
		return true
	var money: int = _state.get("money")
	if pay and requirement.can_buy_open(owned, money):
		_state.set("money", money - requirement.cost)
		_open()
		return true
	refresh()
	return false


## Syncs collision, model and sign with the company state (also after a load).
func refresh() -> void:
	if requirement == null or body == null:
		return
	var open: bool = is_open()
	body.process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
	for shape: Node in body.get_children():
		if shape is CollisionShape3D:
			(shape as CollisionShape3D).set_deferred("disabled", open or not requirement.has_collision())
	if _mesh != null:
		_mesh.position.y = (SIZE.y * 1.5) if open else (SIZE.y * 0.5)
	else:
		_pose_parts(open)
	if open:
		sign_label.text = tr("WORLD_GATE_OPEN")
	else:
		sign_label.text = _closed_text()


func _open() -> void:
	if _state.call("open_gate", requirement.id):
		gate_opened.emit(requirement.id)
	refresh()


func _closed_text() -> String:
	var args: Array = []
	var key: String = requirement.missing_key(_state.call("gate_owned"), args)
	if key.is_empty():
		return tr("WORLD_GATE_CLOSED")
	return tr(key) % args


func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	body = StaticBody3D.new()
	body.name = "Body"
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y * 0.5
	body.add_child(shape)
	_mesh = null
	_model = null
	_board = null
	_parts.clear()
	var packed: PackedScene = _load_model(requirement.kind)
	if packed != null:
		_model = packed.instantiate() as Node3D
	if _model != null:
		_model.name = "Model"
		add_child(_model)
		_grab_parts()
	else:
		_build_fallback_box()
	sign_label = Label3D.new()
	sign_label.name = "Sign"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	add_child(sign_label)
	if _board != null and not requirement.has_collision():
		# Coast / mountain sign: the text sits on the plate, flat, readable from the road.
		sign_label.position = _pose_in_model(_board).origin + Vector3(0.0, 0.0, BOARD_LIFT)
		sign_label.font_size = SIGN_ON_BOARD_FONT
		sign_label.width = SIGN_ON_BOARD_WIDTH
		sign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sign_label.modulate = Color(0.12, 0.13, 0.2)
		sign_label.outline_size = 0
	else:
		# The middle of the road stays free: the text floats above it.
		sign_label.position.y = SIGN_HEIGHT
		sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _load_model(kind: GateRequirement.Kind) -> PackedScene:
	var path: String = MODELS.get(kind, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func _build_fallback_box() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Model"
	var visual := BoxMesh.new()
	visual.size = SIZE
	_mesh.mesh = visual
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.55, 0.58)
	_mesh.material_override = grey
	_mesh.visible = requirement.has_collision()
	add_child(_mesh)


## Finds the moving parts of this kind (the importer may nest them) and saves their
## closed pose.
func _grab_parts() -> void:
	var names: Array[String] = []
	match requirement.kind:
		GateRequirement.Kind.BARRIER:
			names = ["Boom"]
		GateRequirement.Kind.ROADBLOCK:
			names = ["BarricadeLeft", "BarricadeRight"]
		GateRequirement.Kind.EQUIPMENT:
			names = ["Boom", "Door"]
	for part_name: String in names:
		var node := _model.find_child(part_name, true, false) as Node3D
		if node != null:
			_parts[part_name] = {"node": node, "position": node.position, "rotation": node.rotation}
	_board = _model.find_child("Board", true, false) as Node3D


## Closed pose plus the open delta of each part. Always computed from the saved
## closed pose, never from the current one.
func _pose_parts(open: bool) -> void:
	for part_name: String in _parts:
		var part: Dictionary = _parts[part_name]
		var node: Node3D = part["node"]
		var pos: Vector3 = part["position"]
		var rot: Vector3 = part["rotation"]
		if open:
			match [requirement.kind, part_name]:
				[GateRequirement.Kind.BARRIER, "Boom"]:
					rot.z -= PI * 0.5
				[GateRequirement.Kind.EQUIPMENT, "Boom"]:
					rot.z += PI * 0.5
				[GateRequirement.Kind.EQUIPMENT, "Door"]:
					rot.y += PI * 0.5
				[GateRequirement.Kind.ROADBLOCK, "BarricadeLeft"]:
					pos.x -= ROADBLOCK_SLIDE
				[GateRequirement.Kind.ROADBLOCK, "BarricadeRight"]:
					pos.x += ROADBLOCK_SLIDE
		node.position = pos
		node.rotation = rot


## Transform of a node relative to the model root (works before entering the tree).
func _pose_in_model(node: Node3D) -> Transform3D:
	var pose: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != _model:
		pose = (current as Node3D).transform * pose
		current = current.get_parent()
	return pose
