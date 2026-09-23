extends "res://scripts/gameplay/interaction/interactable.gd"
## One openable door of the van: the pair of rear cargo leaves, or either cab
## door. The host owns the open/closed state on the vehicle (vehicle.gd) and
## its MultiplayerSynchronizer mirrors it, so every peer sees the same door.

@export var door: StringName = &"rear"

const OPEN_PROMPTS := {
	&"rear": "Cerrar puertas traseras",
	&"cab_left": "Cerrar puerta del conductor",
	&"cab_right": "Cerrar puerta del acompañante",
}
const CLOSED_PROMPTS := {
	&"rear": "Abrir puertas traseras",
	&"cab_left": "Abrir puerta del conductor",
	&"cab_right": "Abrir puerta del acompañante",
}


## A door only answers a player actually looking at it. Its reach overlaps
## the rack bays, seats and driver's seat, and without this it would steal
## the E meant for a package or a seat (and close the rear doors on people).
const AIM_ALIGNMENT: float = 0.55
const AIM_DISTANCE: float = 2.6


func can_interact(player: Node) -> bool:
	if get_prompt().is_empty():
		return false
	var camera := player.get_node_or_null(^"Head/Camera3D") as Node3D if player != null else null
	if camera == null:
		return true
	var to_door: Vector3 = global_position - camera.global_position
	if to_door.length() > AIM_DISTANCE:
		return false
	return (-camera.global_basis.z).dot(to_door.normalized()) >= AIM_ALIGNMENT


func get_prompt() -> String:
	var vehicle := _vehicle()
	if vehicle == null:
		return ""
	var open: bool = bool(vehicle.call(&"is_door_open", door))
	return String((OPEN_PROMPTS if open else CLOSED_PROMPTS).get(door, prompt))


func interact(player: Node) -> void:
	var vehicle := _vehicle()
	if vehicle == null or (player != null and not can_interact(player)):
		return
	vehicle.call(&"set_door_open", door, not bool(vehicle.call(&"is_door_open", door)))
	interacted.emit(player)


func _vehicle() -> VehicleBody3D:
	var node: Node = get_parent()
	while node != null and not node is VehicleBody3D:
		node = node.get_parent()
	return node as VehicleBody3D
