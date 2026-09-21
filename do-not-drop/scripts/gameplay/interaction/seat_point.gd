extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player board this seat: hides them, switches to its first-person
## camera, and -- for the driver's seat -- enables driving input. Whoever
## reaches a seat first takes that role; nothing assigns roles in advance.

@export var role: StringName = &"driver"  ## "driver" or "passenger"
@export var seat_camera_path: NodePath
@export var vehicle_path: NodePath
@export var required_mount_path: NodePath

var occupant: Node = null


func get_prompt() -> String:
	if occupant != null:
		return ""
	return "Subirse a manejar" if role == &"driver" else "Sentarse"


func can_interact(player: Node) -> bool:
	if occupant != null or player.get(&"carried_package") != null:
		return false
	if not required_mount_path.is_empty():
		var mount: Node = get_node_or_null(required_mount_path)
		return mount != null and is_instance_valid(mount.get(&"occupied_by"))
	return true


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	occupant = player
	var camera: Node = get_node_or_null(seat_camera_path)
	var vehicle: Node = get_node_or_null(vehicle_path)
	player.call(&"board_seat", camera, role == &"driver", vehicle)
	if role != &"driver" and not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		if mount != null and player.has_method(&"tend_package"):
			player.call(&"tend_package", mount.get(&"occupied_by"))
	interacted.emit(player)
