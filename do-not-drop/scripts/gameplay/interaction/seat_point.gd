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
## A seat beside the cargo (the truck's fold-down seats facing the rack):
## instead of one mount of its own it looks after whichever box sits in any
## of these mounts -- the bay column right in front of it. Sitting is always
## allowed; a box in hand is shelved in the first free bay of the column.
@export var tend_mount_paths: Array[NodePath] = []
## A seat behind one of the vehicle's doors (the driver's, behind the cab
## door) can only be reached with that door open.
@export var required_door: StringName = &""

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


var _indicator_occupied: Variant = null


func _process(_delta: float) -> void:
	_update_indicator(false)


## Who sits where, worked out once per frame for every seat's marker instead of
## once per seat (N-223): seat path -> true, and the seat this client's own
## player is in (empty when none).
static var _seating_frame: int = -1
static var _seated_paths: Dictionary = {}
static var _local_seat_path: NodePath = NodePath()


func _refresh_seating(tree: SceneTree, force: bool) -> void:
	var frame: int = Engine.get_process_frames()
	if not force and frame == _seating_frame:
		return
	_seating_frame = frame
	_seated_paths.clear()
	_local_seat_path = NodePath()
	var found_local: bool = false
	for player: Node in tree.get_nodes_in_group(&"player"):
		var seat: NodePath = NodePath(player.get(&"seat_node_path"))
		_seated_paths[seat] = true
		if not found_local and player.has_method(&"is_local") and bool(player.call(&"is_local")):
			found_local = true
			_local_seat_path = seat


## `force` looks at the players again even if this frame already did.
func _update_indicator(force: bool = true) -> void:
	_refresh_seating(get_tree(), force)
	var occupied: bool = _seated_paths.has(_own_seat_path)
	# The marker is for everyone else: whoever sits here would see it glowing
	# at their shoulder whenever they turn their head (it showed up as a
	# salmon disc hanging in the side window).
	_indicator.visible = _local_seat_path != _own_seat_path
	# Rewriting the material every frame re-uploaded it for nothing; the
	# colour only changes when someone sits down or gets up.
	if occupied == _indicator_occupied:
		return
	_indicator_occupied = occupied
	var color: Color = Color("f47e6d") if occupied else Color("83e2ba")
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
	if role == &"driver":
		# Said out loud instead of the seat just not answering: with a box
		# in hand nothing showed up at the wheel, and it read as "the truck
		# won't let me in".
		var local: Node = _local_player()
		if local != null and local.get(&"carried_package") != null:
			return tr("HUD_PROMPT_DROP_TO_DRIVE")
		return tr("HUD_PROMPT_DRIVE")
	return tr("HUD_PROMPT_SIT_BY_CARGO") if not tend_mount_paths.is_empty() else tr("HUD_PROMPT_SIT")


func can_interact(player: Node) -> bool:
	if is_instance_valid(occupant) or _is_occupied():
		return false
	if required_door != &"":
		var door_vehicle: Node = get_node_or_null(vehicle_path)
		if door_vehicle != null and door_vehicle.has_method(&"is_door_open") and not bool(door_vehicle.call(&"is_door_open", required_door)):
			return false
	var carried: Node = player.get(&"carried_package")
	if role == &"driver":
		# The wheel never waits for cargo: sitting here starts the delivery
		# (level_common.gd), and a crew that leaves boxes behind pays for it
		# at the doors. A box in hand still targets the seat, so its prompt
		# can say why it won't take you (get_prompt()); interact() refuses it.
		return true
	if not tend_mount_paths.is_empty():
		return carried == null or _first_mount(false) != null
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
	if role == &"driver" and player.get(&"carried_package") != null:
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
	if role != &"driver" and not tend_mount_paths.is_empty():
		var package: Node = null
		var carried: Node = player.get(&"carried_package")
		if carried != null:
			# Boarding with a box keeps it on your lap; "drop" (Q) then shelves
			# it in this column's free bay (package_rescue.gd's lap toggle).
			package = carried
			carried.set(&"_lap_mount", _first_mount(false))
		else:
			var full_mount: Node = _first_mount(true)
			if full_mount != null:
				package = full_mount.get(&"occupied_by")
		if package != null and player.has_method(&"tend_package"):
			if package.has_method(&"set_tender"):
				package.call(&"set_tender", peer_id)
			player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())
	elif role != &"driver" and not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		var package: Node = mount.get(&"occupied_by") if mount != null else null
		if package == null:
			# Boarded with it still in hand: it stays on their lap, and "drop"
			# (Q) settles it onto this seat's mount (see can_interact() above).
			var carried: Node = player.get(&"carried_package")
			if carried != null and mount != null:
				package = carried
				carried.set(&"_lap_mount", mount)
		if package != null and player.has_method(&"tend_package"):
			if package.has_method(&"set_tender"):
				package.call(&"set_tender", peer_id)
			player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())
	interacted.emit(player)


func _local_player() -> Node:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.has_method(&"is_local") and bool(player.call(&"is_local")):
			return player
	return null


## First mount of this seat's column that is occupied (or free), in the
## order listed -- lower bay before upper.
func _first_mount(occupied: bool) -> Node:
	for path: NodePath in tend_mount_paths:
		var mount: Node = get_node_or_null(path)
		if mount != null and is_instance_valid(mount.get(&"occupied_by")) == occupied:
			return mount
	return null


## The player owns the local "leave seat" gesture, but driving state is host
## authoritative. Clearing it here prevents the same WASD input from being
## read by both the on-foot controller and the van after the driver exits.
@rpc("any_peer", "call_local", "reliable")
func release_occupant(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		return
	if is_instance_valid(occupant) and int(occupant.get_multiplayer_authority()) == peer_id:
		occupant = null
	# Whatever box they were looking after stops taking their input.
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		if int(package.get(&"tender_peer_id")) == peer_id and package.has_method(&"set_tender"):
			package.call(&"set_tender", 0)
	if role != &"driver":
		return
	var vehicle: Node = get_node_or_null(vehicle_path)
	if vehicle == null or int(vehicle.get(&"driver_peer_id")) != peer_id:
		return
	vehicle.set(&"driver_peer_id", 0)
	vehicle.set(&"controls_enabled", false)
	if vehicle.has_method(&"set_controls"):
		vehicle.call(&"set_controls", 0.0, 0.0, true)
