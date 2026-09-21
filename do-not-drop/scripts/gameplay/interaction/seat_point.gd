extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player board this seat: hides them, switches to its first-person
## camera, and -- for the driver's seat -- enables driving input. Whoever
## reaches a seat first takes that role; nothing assigns roles in advance.
##
## interact() only ever runs on the host (see interactable.gd), so it's the
## right place to touch the vehicle directly. The camera swap and the
## passenger's own package assignment are someone else's local, visual
## state, though, so those go out as an RPC targeted at that specific peer.

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
	var peer_id: int = int(player.get_multiplayer_authority())
	var camera: Node = get_node_or_null(seat_camera_path)
	var vehicle: Node = get_node_or_null(vehicle_path)
	if role == &"driver" and vehicle != null:
		# The vehicle is host-authoritative, and interact() only ever runs on
		# the host -- this is the real state, not a copy.
		vehicle.set(&"controls_enabled", true)
		vehicle.set(&"driver_peer_id", peer_id)
	if player.has_method(&"board_seat"):
		var camera_path: NodePath = camera.get_path() if camera != null else NodePath()
		player.rpc_id(peer_id, &"board_seat", camera_path)
	if role != &"driver" and not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		var package: Node = mount.get(&"occupied_by") if mount != null else null
		if package != null and player.has_method(&"tend_package"):
			player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())
	interacted.emit(player)
