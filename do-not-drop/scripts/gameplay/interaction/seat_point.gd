extends SeatPoint
## Take My Package's seats on the interaction module's SeatPoint
## (docs/modulos.md): the module seats the player and hands the driver the
## wheel; this file is what a seat in the van means for the cargo -- the
## passenger's own package at their seat, or the bay column a fold-down seat
## looks after -- and the prompts that say it.

## A passenger seat with one mount of its own: the box on it (or the box in
## the player's hands, settled there as they sit) is theirs to look after.
@export var required_mount_path: NodePath
## A seat beside the cargo (the truck's fold-down seats facing the rack):
## instead of one mount of its own it looks after whichever box sits in any
## of these mounts -- the bay column right in front of it. Sitting is always
## allowed; a box in hand is shelved in the first free bay of the column.
@export var tend_mount_paths: Array[NodePath] = []


func _ready() -> void:
	super._ready()
	add_to_group(SeatTending.SEAT_GROUP)


func _free_prompt() -> String:
	if role == &"driver":
		# Said out loud instead of the seat just not answering: with a box
		# in hand nothing showed up at the wheel, and it read as "the truck
		# won't let me in".
		var local: Node = local_player()
		if local != null and local.get(&"carried_package") != null:
			return tr("HUD_PROMPT_DROP_TO_DRIVE")
		return tr("HUD_PROMPT_DRIVE")
	return tr("HUD_PROMPT_SIT_BY_CARGO") if not tend_mount_paths.is_empty() else tr("HUD_PROMPT_SIT")


func _can_board(player: Node) -> bool:
	var carried: Node = player.get(&"carried_package")
	if role == &"driver":
		# The wheel never waits for cargo: sitting here starts the delivery
		# (level_common.gd), and a crew that leaves boxes behind pays for it
		# at the doors. A box in hand still targets the seat, so its prompt
		# can say why it won't take you (_free_prompt()); _accept_boarding
		# refuses it.
		return true
	if not tend_mount_paths.is_empty():
		return carried == null or _first_mount(false) != null
	if not required_mount_path.is_empty():
		# A passenger's tending mount can be filled two ways: someone already
		# left the package there, or this player is still holding it and
		# boards with it in hand -- _on_boarded settles it onto the mount as
		# part of sitting down, so there's never a bare "put it down first"
		# step where it could be dropped and broken.
		var mount: Node = get_node_or_null(required_mount_path)
		if mount == null:
			return false
		if is_instance_valid(mount.get(&"occupied_by")):
			return carried == null
		return carried != null
	return carried == null


func _accept_boarding(player: Node) -> bool:
	return not (role == &"driver" and player.get(&"carried_package") != null)


func _on_boarded(player: Node, peer_id: int) -> void:
	if role == &"driver":
		return
	var package: Node = null
	var carried: Node = player.get(&"carried_package")
	if not tend_mount_paths.is_empty():
		if carried != null:
			# Boarding with a box keeps it on your lap; "drop" (Q) then shelves
			# it in this column's free bay (package_rescue.gd's lap toggle).
			package = carried
			carried.set(&"_lap_mount", _first_mount(false))
		else:
			var full_mount: Node = _first_mount(true)
			if full_mount != null:
				package = full_mount.get(&"occupied_by")
	elif not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		package = mount.get(&"occupied_by") if mount != null else null
		if package == null and carried != null and mount != null:
			# Boarded with it still in hand: it stays on their lap, and "drop"
			# (Q) settles it onto this seat's mount (see _can_board() above).
			package = carried
			carried.set(&"_lap_mount", mount)
	if package != null and player.has_method(&"tend_package"):
		# Several seats can look at the same mount: someone already minding the
		# box keeps it (seat_tending.gd), the newcomer just sits.
		if package.has_method(&"set_tender") and not SeatTending.claim(self, package, peer_id):
			return
		player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())


## Whatever box they were looking after stops taking their input -- unless
## another seat looks at the same mount, which then takes it over.
func _on_released(peer_id: int) -> void:
	for package: Node in get_tree().get_nodes_in_group(&"cargo"):
		if int(package.get(&"tender_peer_id")) == peer_id and package.has_method(&"set_tender"):
			package.call(&"set_tender", 0)
			SeatTending.hand_over(package, peer_id)


## Who sits here (host; 0 when the seat is free).
func seated_peer() -> int:
	return int(occupant.get_multiplayer_authority()) if is_instance_valid(occupant) else 0


## This seat's own mount: the one it is `required_mount_path` for.
func owns_mount(mount: Node) -> bool:
	return mount != null and not required_mount_path.is_empty() and get_node_or_null(required_mount_path) == mount


## Whether this seat looks after the box in `mount`, its own or by the column.
func looks_at_mount(mount: Node) -> bool:
	if mount == null:
		return false
	if owns_mount(mount):
		return true
	for path: NodePath in tend_mount_paths:
		if get_node_or_null(path) == mount:
			return true
	return false


## First mount of this seat's column that is occupied (or free), in the
## order listed -- lower bay before upper.
func _first_mount(occupied: bool) -> Node:
	for path: NodePath in tend_mount_paths:
		var mount: Node = get_node_or_null(path)
		if mount != null and is_instance_valid(mount.get(&"occupied_by")) == occupied:
			return mount
	return null
