class_name LateJoinSeating
extends Node
## Whoever joins while the truck is already on the road (N-228.7) used to be
## spawned in the depot, which by then is empty and behind the crew. Here they
## appear in the truck instead: sitting in a free passenger seat, or standing
## in the cargo bay if no seat will have them. Host only; a level builds one
## (level_common.gd) and asks it where the next player goes.
##
## The seat is chosen before the player exists, with a stand-in that carries
## nothing (a newcomer has empty hands), preferring a seat that looks after a
## box nobody minds yet. Seating goes through the seat's own interact(), so the
## boarding, the tending claim and the RPCs are exactly those of a player who
## walked up and sat down. The newcomer's client builds its player from the
## spawner's packet, and the board_seat RPC follows it on the same reliable
## channel; should it still get lost, the host notices that the player never
## sat (seat_node_path is replicated back from its owner) and boards them again.

## Where a standing newcomer lands in the truck's own space when no seat takes
## them: the middle of the aisle, a little above the floor.
const BAY_SPOT: Vector3 = Vector3(0.0, 0.2, 2.1)
## Height above the truck's floor of a standing player at a seat's x and z.
const SEAT_FLOOR: float = 0.2
## How many times the host seats a newcomer before leaving them standing in
## the bay, and how long it waits for the owner's seat to come back each time.
const ATTEMPTS: int = 3
var retry_seconds: float = 1.0

var vehicle: Node3D
## Times seat_player() asked a seat to board someone (for tests).
var boarding_attempts: int = 0
var _stand_in: Node = Node.new()


func _exit_tree() -> void:
	_stand_in.free()


## The truck is out on the road, or about to be: a run is on and not over.
## Before that the depot is where everybody starts, as ever.
func underway() -> bool:
	return is_instance_valid(vehicle) and RunManager.is_running and RunManager.results.is_empty()


## The seat a newcomer boards and the world position they spawn at. The seat
## is null when none will have them: they stand in the bay instead.
func place() -> Dictionary:
	var seat: Node = pick_seat()
	if seat == null:
		return {"seat": null, "position": vehicle.to_global(BAY_SPOT)}
	var eye := seat.get_parent() as Node3D
	var spot: Vector3 = vehicle.to_local(eye.global_position)
	return {"seat": seat, "position": vehicle.to_global(Vector3(spot.x, SEAT_FLOOR, spot.z))}


## A free passenger seat of this truck that takes someone with empty hands;
## the one facing the most unminded boxes first, else the first free one.
func pick_seat() -> Node:
	var best: Node = null
	var best_boxes: int = -1
	for seat: Node in get_tree().get_nodes_in_group(SeatTending.SEAT_GROUP):
		if not vehicle.is_ancestor_of(seat) or not seat.has_method(&"unminded_cargo") \
				or not bool(seat.call(&"can_interact", _stand_in)):
			continue
		var boxes: int = int(seat.call(&"unminded_cargo"))
		if boxes > best_boxes:
			best = seat
			best_boxes = boxes
	return best


## Sits `player` (just spawned) at `seat`. Boards again if the owner never
## reports sitting; after ATTEMPTS they are left standing in the bay.
func seat_player(player: Node, seat: Node) -> void:
	var peer_id: int = int(player.get_multiplayer_authority())
	for attempt: int in range(ATTEMPTS):
		boarding_attempts += 1
		seat.call(&"interact", player)
		if seat.get(&"occupant") != player:
			return
		await get_tree().create_timer(retry_seconds).timeout
		# Gone, or stood up already (which clears the seat's occupant).
		if not is_instance_valid(player) or not player.is_inside_tree() or seat.get(&"occupant") != player:
			return
		if not String(NodePath(player.get(&"seat_node_path"))).is_empty():
			return
		seat.call(&"release_occupant", peer_id)
