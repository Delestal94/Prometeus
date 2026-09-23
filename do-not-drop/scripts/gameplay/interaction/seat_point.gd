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

## Host-only: interact() (and so this) only ever runs on the host, so other
## clients' copies of this same node never see it change. Fine for the
## can_interact()/interact() logic below (host-authoritative anyway), but
## no use for a visual indicator everyone needs to see -- see _is_occupied().
var occupant: Node = null
var _own_seat_path: NodePath = NodePath()
var _indicator: MeshInstance3D
var _indicator_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_own_seat_path = get_parent().get_path()
	_build_indicator()


## A small glowing marker (item #94) instead of only the prompt text: green
## while free, red once someone's seated -- readable from across the cabin,
## not just when close enough to trigger the interact prompt. Derived from
## every Player's own replicated seat_node_path (see player.gd's #81 work)
## rather than `occupant`, so it updates correctly on every client, not just
## the host's.
func _build_indicator() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 1.4
	_indicator = MeshInstance3D.new()
	_indicator.mesh = sphere
	_indicator.material_override = _indicator_material
	_indicator.position = Vector3(0.0, 0.3, 0.0)
	add_child(_indicator)
	_update_indicator()


func _process(_delta: float) -> void:
	_update_indicator()


func _update_indicator() -> void:
	var color: Color = Color("f47e6d") if _is_occupied() else Color("83e2ba")
	_indicator_material.albedo_color = color
	_indicator_material.emission = color


func _is_occupied() -> bool:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if NodePath(player.get(&"seat_node_path")) == _own_seat_path:
			return true
	return false


func get_prompt() -> String:
	if _is_occupied():
		return ""
	return "Subirse a manejar" if role == &"driver" else "Sentarse"


func can_interact(player: Node) -> bool:
	if _is_occupied():
		return false
	var carried: Node = player.get(&"carried_package")
	if role == &"driver":
		# Any loaded passenger position makes the van ready. Requiring the
		# first seat's mount made a valid package on the other three seats
		# leave the driver prompt unavailable.
		var has_loaded_cargo: bool = false
		for mount: Node in get_tree().get_nodes_in_group(&"package_mount"):
			if is_instance_valid(mount.get(&"occupied_by")):
				has_loaded_cargo = true
				break
		if not has_loaded_cargo:
			return false
		return carried == null
	if not required_mount_path.is_empty():
		# A passenger's tending mount can be filled two ways: someone already
		# left the package there, or this player is still holding it and
		# boards with it in hand -- interact() settles it onto the mount as
		# part of sitting down, so there's never a bare "put it down first"
		# step where it could be dropped and broken.
		var mount: Node = get_node_or_null(required_mount_path)
		if mount == null:
			return false
		if is_instance_valid(mount.get(&"occupied_by")):
			return carried == null
		return carried != null
	return carried == null


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
		# The seat anchor itself (this Area3D's parent, e.g. DriverEyePoint) --
		# an absolute path so it resolves the same way from the player's own
		# position in the tree, which is a sibling of the vehicle, not a child.
		var seat_path: NodePath = get_parent().get_path()
		player.rpc_id(peer_id, &"board_seat", camera_path, seat_path)
	if role != &"driver" and not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		var package: Node = mount.get(&"occupied_by") if mount != null else null
		if package == null:
			# Boarded with it still in hand: settle it onto the mount now,
			# right as they sit, instead of requiring them to put it down
			# unattended first (see can_interact() above).
			var carried: Node = player.get(&"carried_package")
			if carried != null and mount != null and mount.has_method(&"store"):
				mount.call(&"store", carried)
				package = carried
				if player.get(&"carried_package") == carried:
					player.rpc(&"drop_carried")
				# Same signal a hand-placed box sends, so the level counts it
				# as loaded cargo and the driver can actually start the run.
				mount.emit_signal(&"interacted", player)
		if package != null and player.has_method(&"tend_package"):
			player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())
	interacted.emit(player)


## The player owns the local "leave seat" gesture, but driving state is host
## authoritative. Clearing it here prevents the same WASD input from being
## read by both the on-foot controller and the van after the driver exits.
@rpc("any_peer", "call_local", "reliable")
func release_occupant(peer_id: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		return
	if occupant != null and int(occupant.get_multiplayer_authority()) == peer_id:
		occupant = null
	if role != &"driver":
		return
	var vehicle: Node = get_node_or_null(vehicle_path)
	if vehicle == null or int(vehicle.get(&"driver_peer_id")) != peer_id:
		return
	vehicle.set(&"driver_peer_id", 0)
	vehicle.set(&"controls_enabled", false)
	if vehicle.has_method(&"set_controls"):
		vehicle.call(&"set_controls", 0.0, 0.0, true)
