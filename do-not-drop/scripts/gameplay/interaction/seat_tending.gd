class_name SeatTending
extends RefCounted
## Who looks after a box when several seats look at its mount (host only).
##
## A passenger seat owns one mount (`required_mount_path`) and the fold-down
## seats by the rack (and LeftSeat3 / CenterSeat) look after mounts they share
## with it, so two people can sit facing the same box. The box has one tender
## (DeliveryPackage.tender_peer_id): the host only reads that peer's input.
##   - Whoever is already minding it keeps it when someone else sits down,
##     except that the mount's own seat takes charge of its box when it sits
##     down (an owner already seated while a neighbour shelves it waits its turn).
##   - When the tender gets up or drops out, another sitter facing that mount
##     takes over (the owner first), so a box never stays unattended with
##     someone seated right beside it.
## No RPC of its own: the new tender is told with the player's `tend_package`,
## as when sitting down, and a displaced one with an empty path.

const SEAT_GROUP: StringName = &"cargo_seat"


## Host: `seat` (just boarded by `peer_id`) wants to look after `package`.
## True when it becomes the tender (then the caller tells the player); false
## when someone sitting at another seat facing the same mount keeps it.
static func claim(seat: Node, package: Node, peer_id: int) -> bool:
	var current: int = int(package.get(&"tender_peer_id"))
	if current > 0 and current != peer_id:
		var tree: SceneTree = seat.get_tree()
		var in_hands: bool = _carried_by(package, peer_id)
		# A box the newcomer sits down with is theirs whoever minded it before.
		var mount: Node = null if in_hands else mount_of(package)
		var holder: Node = _seat_of_peer(tree, current, mount, seat, in_hands)
		if holder != null:
			if not in_hands and (not seat.call(&"owns_mount", mount) or holder.call(&"owns_mount", mount)):
				return false
			# The owner arrives after a neighbour took over (or the box came
			# in someone's hands): the neighbour's HUD stops claiming a box
			# whose input the host no longer reads.
			var displaced: Node = holder.get(&"occupant")
			if displaced.has_method(&"tend_package"):
				displaced.rpc_id(current, &"tend_package", NodePath())
	package.call(&"set_tender", peer_id)
	return true


## Host: `leaving` stopped tending `package` (got up, or dropped out). The
## best other sitter facing its mount, if any, takes it from here. Only a box
## still in its bay is handed over: not one in someone's hands or on the floor.
static func hand_over(package: Node, leaving: int) -> void:
	if not package.is_inside_tree() or bool(package.get(&"is_held")) or not bool(package.get(&"is_loaded")):
		return
	var current: Variant = package.get(&"current_mount")
	var mount: Node = current as Node if is_instance_valid(current) else null
	if mount == null:
		return
	var tree: SceneTree = package.get_tree()
	var best: Node = null
	for seat: Node in tree.get_nodes_in_group(SEAT_GROUP):
		var peer: int = int(seat.call(&"seated_peer"))
		if peer <= 0 or peer == leaving or not seat.call(&"looks_at_mount", mount) \
				or _tends_something(tree, peer):
			continue
		if best == null or (seat.call(&"owns_mount", mount) and not best.call(&"owns_mount", mount)):
			best = seat
	if best == null:
		return
	var heir: int = int(best.call(&"seated_peer"))
	var player: Node = best.get(&"occupant")
	package.call(&"set_tender", heir)
	if player.has_method(&"tend_package"):
		player.rpc_id(heir, &"tend_package", package.get_path())


## Host: `package` was just placed in `mount` (package_mount_point.gd's store()).
## A tender whose seat does not look at that mount -- someone standing took the
## box out of their bay and shelved it elsewhere -- stops tending it. Then, with
## or without a tender before, a sitter facing the mount takes over (a box
## shelved by someone who just got up from its lap, or by a standing player,
## would otherwise stay unminded beside a sitter). The lap toggle and boarding
## store into a mount the tender looks at, so nothing changes for them. Not
## done when the box is taken out (take_by), or putting it back in the same
## mount would lose its tender.
static func on_stored(package: Node, mount: Node) -> void:
	if not package.is_multiplayer_authority() or not package.is_inside_tree():
		return
	var tender: int = int(package.get(&"tender_peer_id"))
	var tree: SceneTree = package.get_tree()
	if tender > 0:
		if _seat_of_peer(tree, tender, mount, null) != null:
			return
		package.call(&"set_tender", 0)
		var seat: Node = _seat_of_peer(tree, tender, null, null, true)
		if seat != null:
			var displaced: Node = seat.get(&"occupant")
			if displaced.has_method(&"tend_package"):
				displaced.rpc_id(tender, &"tend_package", NodePath())
	hand_over(package, tender)


## Whether `player` sits in a seat. The host knows it from the seats' own
## `occupant`: the player's replicated seat_node_path lags a sitting down or
## getting up (and stays empty for a crewmate whose RPC never arrived). A
## client has no occupants, only the replicated path.
static func is_seated(tree: SceneTree, player: Node, is_server: bool) -> bool:
	if not is_server:
		return not NodePath(player.get(&"seat_node_path")).is_empty()
	for seat: Node in tree.get_nodes_in_group(SEAT_GROUP):
		if int(seat.call(&"seated_peer")) > 0 and seat.get(&"occupant") == player:
			return true
	return false


## Whether a box riding on a seated passenger's lap will be shelved in `mount`
## (`except` is the box about to be shelved there: its own reservation does not
## count). Works on every peer from replicated state: the box's lap_mount_path,
## its holder -- `carrier` on the host, otherwise the player whose
## `carried_package` it is -- and whether that player sits (is_seated()).
static func lap_reserves(tree: SceneTree, mount: Node, except: Node, is_server: bool) -> bool:
	for package: Node in tree.get_nodes_in_group(&"cargo"):
		if package == except or not bool(package.get(&"is_held")) or lap_mount_of(package) != mount:
			continue
		var carrier: Node = _holder_of(tree, package)
		if carrier != null and is_seated(tree, carrier, is_server):
			return true
	return false


## The mount the box sits in or, in a seated passenger's lap, the one it goes
## back to.
static func mount_of(package: Node) -> Node:
	var mount: Variant = package.get(&"current_mount")
	if is_instance_valid(mount):
		return mount as Node
	return lap_mount_of(package)


## The mount a box on a seated tender's lap goes back to, from its replicated
## lap_mount_path (so on every peer); null when it is on no lap.
static func lap_mount_of(package: Node) -> Node:
	var path: NodePath = NodePath(package.get(&"lap_mount_path"))
	return package.get_node_or_null(path) if not path.is_empty() and package.is_inside_tree() else null


## Host: `package` is on its holder's lap, bound for `mount` (null: for none).
static func bind_lap(package: Node, mount: Node) -> void:
	var bound: bool = is_instance_valid(mount) and mount.is_inside_tree()
	package.set(&"lap_mount_path", mount.get_path() if bound else NodePath())


## Whether some seat owns `mount` (`required_mount_path`). The parasite event
## pairs only such boxes: two shelf bays share their one fold-down seat, so a
## shelf pair could never be tended by two people and would just expire.
static func is_owned_mount(tree: SceneTree, mount: Node) -> bool:
	if mount == null:
		return false
	for seat: Node in tree.get_nodes_in_group(SEAT_GROUP):
		if seat.call(&"owns_mount", mount):
			return true
	return false


## The seat `peer_id` sits in, other than `except`, that looks at `mount`
## (`any_mount`: whichever it is).
static func _seat_of_peer(tree: SceneTree, peer_id: int, mount: Node, except: Node, any_mount: bool = false) -> Node:
	for seat: Node in tree.get_nodes_in_group(SEAT_GROUP):
		if seat != except and int(seat.call(&"seated_peer")) == peer_id \
				and (any_mount or seat.call(&"looks_at_mount", mount)):
			return seat
	return null


## Who holds `package`: `carrier` (host only) or, on a client, the player whose
## hands it is in (broadcast by the player's pick_up).
static func _holder_of(tree: SceneTree, package: Node) -> Node:
	var carrier: Variant = package.get(&"carrier")
	if is_instance_valid(carrier):
		return carrier as Node
	for player: Node in tree.get_nodes_in_group(&"player"):
		if player.get(&"carried_package") == package:
			return player
	return null


static func _carried_by(package: Node, peer_id: int) -> bool:
	var carrier: Variant = package.get(&"carrier")
	return bool(package.get(&"is_held")) and is_instance_valid(carrier) \
			and int((carrier as Node).get_multiplayer_authority()) == peer_id


## A sitter already minding another box (a rack seat facing two bays) keeps
## to that one: the player only follows one `tended_package`.
static func _tends_something(tree: SceneTree, peer_id: int) -> bool:
	for other: Node in tree.get_nodes_in_group(&"cargo"):
		if int(other.get(&"tender_peer_id")) == peer_id:
			return true
	return false
