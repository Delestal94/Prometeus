extends RefCounted
## Who sits where in a fleet vehicle: queries only (expansion D-0208).
##
## One per vehicle, made by the vehicle's own script with itself as `body` (any Node3D, so
## a boat, a plane or a bike can hold one too). Preloaded, not by class_name: a new global
## class isn't in the class cache until the editor imports again.
##
## The seats were already separated from vehicle.gd, so this extracts no logic and touches
## no network path. A seat is a node under `body` that answers `is_occupied()` and has a
## `role` ("driver" or "passenger"): the interaction module's SeatPoint and the game's
## CargoSeatPoint (scripts/gameplay/interaction/seat_point.gd). They seat the player, hand
## over the wheel and read who sits from the players' replicated `seat_node_path`, so
## occupancy is the same on every peer. The vehicle needs no seat list of its own.
##
## Inventory of vehicle.gd before D-0208 (line numbers of that file) -- what was seats:
## - 15-28 `driver_peer_id`, exported and replicated (vehicle.tscn's synchronizer), stays on
##   the vehicle: its setter tells the prediction and shuts/opens the cab door (host);
## - 29-33 `controls_enabled`, replicated with it, stays; SeatPoint sets both on boarding;
## - 511, 637, 679 the driver checks (_update_parking, submit_driver_input,
##   request_gear_shift), which read driver_peer_id directly and stay;
## - outside it, VehicleInputComponent, VehiclePrediction and VehicleFaults read
##   `driver_peer_id` by name from the vehicle.
## In vehicle.tscn: CabinInterior/DriverEyePoint (256-280) with its InteractionArea (266,
## role driver, required_door cab_left) and CargoBay/*EyePoint (305-465, ten passenger
## seats, some minding a mount of their own, some the bay column in front of them), each
## with a FirstPersonCamera and a SeatPoint area.
##
## What the vehicle gives: a property `driver_peer_id` (int, 0 when nobody drives). A
## vehicle without it reads as driverless.

## The seats' `role` of the one that holds the wheel.
const DRIVER_ROLE: StringName = &"driver"

var _body: Node3D
var _seats: Array[Node] = []
var _found: bool = false


func _init(body: Node3D) -> void:
	_body = body


## Every seat under the body, found once (the seats of a vehicle don't come and go).
## Call forget() after adding or removing one.
func seat_points() -> Array[Node]:
	if not _found:
		_found = true
		_seats.clear()
		_collect(_body)
	return _seats


func forget() -> void:
	_found = false


func seat_count() -> int:
	return seat_points().size()


## The seat that holds the wheel, or null when the vehicle has none.
func driver_seat() -> Node:
	for seat: Node in seat_points():
		if seat.get(&"role") == DRIVER_ROLE:
			return seat
	return null


func occupied_count() -> int:
	var count: int = 0
	for seat: Node in seat_points():
		if bool(seat.call(&"is_occupied")):
			count += 1
	return count


func free_seats() -> Array[Node]:
	var free: Array[Node] = []
	for seat: Node in seat_points():
		if not bool(seat.call(&"is_occupied")):
			free.append(seat)
	return free


func has_free_seat() -> bool:
	return occupied_count() < seat_count()


## The peer at the wheel, 0 when nobody is.
func driver_peer_id() -> int:
	var value: Variant = _body.get(&"driver_peer_id")
	return int(value) if value is int else 0


func has_driver() -> bool:
	return driver_peer_id() != 0


## Whether `peer_id` holds the wheel (never true for 0, nobody).
func is_driver(peer_id: int) -> bool:
	return peer_id != 0 and driver_peer_id() == peer_id


func _collect(node: Node) -> void:
	for child: Node in node.get_children():
		if child.has_method(&"is_occupied") and &"role" in child:
			_seats.append(child)
		_collect(child)
