class_name SeatTending
extends RefCounted
## Who looks after a box when several seats look at its mount (host only).
##
## A passenger seat owns one mount (`required_mount_path`) and the fold-down
## seats by the rack (and LeftSeat3 / CenterSeat) look after mounts they share
## with it, so two people can sit facing the same box. The box has one tender
## (DeliveryPackage.tender_peer_id): the host only reads that peer's input.
##   - Whoever is already minding it keeps it when someone else sits down,
##     except that the mount's own seat always takes charge of its box.
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
		var mount: Node = mount_of(package)
		var holder: Node = _seat_of_peer(seat.get_tree(), current, mount, seat)
		if holder != null:
			if not seat.call(&"owns_mount", mount) or holder.call(&"owns_mount", mount):
				return false
			# The owner arrives after a neighbour took over: the neighbour's HUD
			# stops claiming a box whose input the host no longer reads.
			var displaced: Node = holder.get(&"occupant")
			if displaced.has_method(&"tend_package"):
				displaced.rpc_id(current, &"tend_package", NodePath())
	package.call(&"set_tender", peer_id)
	return true


## Host: `leaving` stopped tending `package` (got up, or dropped out). The
## best other sitter facing its mount, if any, takes it from here.
static func hand_over(package: Node, leaving: int) -> void:
	if not package.is_inside_tree() or bool(package.get(&"is_held")):
		return
	var mount: Node = mount_of(package)
	if mount == null:
		return
	var best: Node = null
	for seat: Node in package.get_tree().get_nodes_in_group(SEAT_GROUP):
		var peer: int = int(seat.call(&"seated_peer"))
		if peer <= 0 or peer == leaving or not seat.call(&"looks_at_mount", mount) \
				or _tends_something(package.get_tree(), peer):
			continue
		if best == null or (seat.call(&"owns_mount", mount) and not best.call(&"owns_mount", mount)):
			best = seat
	if best == null:
		return
	var player: Node = best.get(&"occupant")
	package.call(&"set_tender", int(best.call(&"seated_peer")))
	if player.has_method(&"tend_package"):
		player.rpc_id(int(best.call(&"seated_peer")), &"tend_package", package.get_path())


## The mount the box sits in (or, in someone's lap, the one it goes back to).
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


static func _seat_of_peer(tree: SceneTree, peer_id: int, mount: Node, except: Node) -> Node:
	for seat: Node in tree.get_nodes_in_group(SEAT_GROUP):
		if seat != except and int(seat.call(&"seated_peer")) == peer_id and seat.call(&"looks_at_mount", mount):
			return seat
	return null


## A sitter already minding another box (a rack seat facing two bays) keeps
## to that one: the player only follows one `tended_package`.
static func _tends_something(tree: SceneTree, peer_id: int) -> bool:
	for other: Node in tree.get_nodes_in_group(&"cargo"):
		if int(other.get(&"tender_peer_id")) == peer_id:
			return true
	return false
