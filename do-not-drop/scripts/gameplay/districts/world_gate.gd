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
## (lesson N-919). Placeholder grey geometry; the real model is asked in
## docs/expansion-distritos/arte-pendiente/D-0306.md.

signal gate_opened(gate_id: StringName)

const SIZE: Vector3 = Vector3(8.0, 3.0, 0.6)
const SIGN_HEIGHT: float = 3.6

var requirement: GateRequirement
var body: StaticBody3D
var sign_label: Label3D

var _state: Object
var _mesh: MeshInstance3D


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
	_mesh.position.y = (SIZE.y * 1.5) if open else (SIZE.y * 0.5)
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
	sign_label = Label3D.new()
	sign_label.name = "Sign"
	sign_label.position.y = SIGN_HEIGHT
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	add_child(sign_label)
