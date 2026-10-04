class_name LateJoinSeating
extends Node
## Whoever joins while the truck is already on the road (N-228.7) used to be
## spawned in the depot, which by then is empty and behind the crew. Here they
## appear in the truck instead: sitting in a free passenger seat, or standing
## in the cargo bay if no seat will have them. Host only; a level builds one
## (level_common.gd) and asks it where the next player goes.
##
## The seat is chosen before the player exists, with this node standing in for
## a player who carries nothing (a newcomer has empty hands). Preference: the
## seat facing the most boxes nobody minds yet; then one whose boarding takes
## no box off a neighbour who is already minding it (a seat claims the box of
## its own mount, seat_tending.gd); then any free one. Seating goes through the
## seat's own interact(), so the boarding, the tending claim and the RPCs are
## exactly those of a player who walked up and sat down.
##
## No retry and no timeout: spawn() sends the player's spawn packet before it
## returns, on the reliable channel 0, and board_seat / tend_package go out on
## that same ordered channel (the player's RPCs are only visible to a peer that
## has the node), so they reach the client after its player exists. A newcomer
## who drops, or who stands up, frees the seat on their own (player.gd's
## _exit_tree and leave_seat). Releasing a seat on a deadline would hand its
## box to a neighbour and take it back while the client believed it was sitting.

## Where a newcomer stands in the truck's own space when no seat takes them:
## the aisle between the front seats and the rack, clear of the cushions and
## of the boxes in every bay (tests/test_late_join_seating.gd checks it).
const BAY_SPOT: Vector3 = Vector3(0.0, 0.285, 0.9)
## Where the cargo floor is in the truck's space when a ray can't find it (the
## truck's model has it at 0.255), plus a hair: a standing player's feet.
const FLOOR_Y: float = 0.285
## A hair above the floor the ray finds.
const FLOOR_CLEARANCE: float = 0.03
## What the floor ray hits: the truck's body and its cargo shell (vehicle.gd).
const FLOOR_MASK: int = 1 | 2 | 64
## How far from the seat toward the aisle a standing newcomer is put when
## the seat has no ExitPoint of its own (player.gd SEAT_EXIT_STEP).
const EXIT_STEP: float = 0.55

var vehicle: Node3D


## The truck is out on the road, or about to be: a run is on and not over.
## Before that the depot is where everybody starts, as ever.
func underway() -> bool:
	return is_instance_valid(vehicle) and RunManager.is_running and RunManager.results.is_empty()


## The seat a newcomer boards and where they spawn, in the truck's own space
## ("local", what the spawn data carries) and in the world ("position"). The
## seat is null when none will have them: they stand in the bay instead.
func place() -> Dictionary:
	var seat: Node = pick_seat()
	var local: Vector3 = floor_at(BAY_SPOT if seat == null else standing_spot(seat))
	return {"seat": seat, "local": local, "position": vehicle.to_global(local)}


## Where a newcomer stands for a moment at `seat`, in the truck's space: the
## seat's exit toward the aisle, as when someone gets up from it.
func standing_spot(seat: Node) -> Vector3:
	var eye := seat.get_parent() as Node3D
	var exit_point := eye.get_node_or_null(^"ExitPoint") as Node3D
	var world: Vector3 = exit_point.global_position if exit_point != null \
			else eye.global_position - eye.global_basis.z * EXIT_STEP
	return floor_at(vehicle.to_local(world))


## `spot` (truck space) with its height put on the cargo floor below it, found
## with a ray as player_seat_pose.gd's seat_exit_position() does.
func floor_at(spot: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(vehicle.to_global(spot + Vector3.UP * 1.0),
			vehicle.to_global(spot + Vector3.DOWN * 1.0), FLOOR_MASK)
	var hit: Dictionary = vehicle.get_world_3d().direct_space_state.intersect_ray(query)
	spot.y = vehicle.to_local(hit.position as Vector3).y + FLOOR_CLEARANCE if not hit.is_empty() else FLOOR_Y
	return spot


## A free passenger seat of this truck that takes someone with empty hands:
## the one facing the most unminded boxes, else one that displaces nobody,
## else the first free one.
func pick_seat() -> CargoSeatPoint:
	var best: CargoSeatPoint = null
	var best_score: int = -1
	for node: Node in get_tree().get_nodes_in_group(SeatTending.SEAT_GROUP):
		var seat := node as CargoSeatPoint
		if seat == null or not vehicle.is_ancestor_of(seat) or not seat.can_interact(self):
			continue
		var score: int = seat.unminded_cargo() * 2 + (0 if seat.would_displace() else 1)
		if score > best_score:
			best = seat
			best_score = score
	return best


## Sits `player` (just spawned) at `seat`, once; if the seat refuses, they
## stay where they spawned, standing at its exit inside the truck. The host's
## copy is marked as seated at once: the owner writes seat_node_path itself
## when board_seat reaches it, a round trip later, and until then the copy
## would stand solid in the road while the truck drives on (player.gd turns
## its collision off and poses it at the seat as soon as the path is set).
func seat_player(player: Node, seat: SeatPoint) -> void:
	seat.interact(player)
	if seat.occupant == player:
		player.set(&"seat_node_path", seat.get_parent().get_path())
