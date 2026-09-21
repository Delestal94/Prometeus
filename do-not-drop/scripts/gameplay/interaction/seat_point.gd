extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player board this seat: hides them, switches to its first-person
## camera, and -- for the driver's seat -- enables driving input. Whoever
## reaches a seat first takes that role; nothing assigns roles in advance.

@export var role: StringName = &"driver"  ## "driver" or "passenger"
@export var seat_camera_path: NodePath
@export var vehicle_path: NodePath

var occupant: Node = null


func get_prompt() -> String:
	if occupant != null:
		return ""
	return "Subirse a manejar" if role == &"driver" else "Sentarse"


func interact(player: Node) -> void:
	if occupant != null:
		return
	occupant = player
	var camera: Node = get_node_or_null(seat_camera_path)
	var vehicle: Node = get_node_or_null(vehicle_path)
	player.call(&"board_seat", camera, role == &"driver", vehicle)
	interacted.emit(player)
