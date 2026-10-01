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
## box out of their bay and shelved it elsewhere -- stops tending it, and a
## sitter facing the new mount takes over. The lap toggle and boarding store
## into a mount the tender looks at, so nothing changes for them. Not done when
## the box is taken out (take_by), or putting it back in the same mount would
## lose its tender.
static func on_stored(package: Node, mount: Node) -> void:
	var tender: int = int(package.get(&"tender_peer_id"))
	if tender <= 0 or not package.is_inside_tree():
		return
	var tree: SceneTree = package.get_tree()
	if _seat_of_peer(tree, tender, mount, null) != null:
		return
	package.call(&"set_tender", 0)
	var seat: Node = _seat_of_peer(tree, tender, null, null, true)
	if seat != null:
		var displaced: Node = seat.get(&"occupant")
		if displaced.has_method(&"tend_package"):
			displaced.rpc_id(tender, &"tend_package", NodePath())
	hand_over(package, tender)


## The mount the box sits in or, in a seated passenger's lap, the one it goes
## back to.
static func mount_of(package: Node) -> Node:
	var mount: Variant = package.get(&"current_mount")
	if is_instance_valid(mount):
		return mount as Node
	var lap: Variant = package.get(&"_lap_mount")
	return lap as Node if is_instance_valid(lap) else null


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
