class_name CompanyUnitsNet
extends RefCounted
## The units of CompanyNet's stream (D-2003, D-2006; out of company_net.gd in D-0254): the three requests that move
## units between a station, a player's hands and the floor (rows 5 to 7 of
## docs/expansion-distritos/diseno/red-autoridad.md), their one event, and the reach every request at a station is
## measured with (rule 4), here and for the packing tables, the carts and the pallets.
##
##   units_take   {station, product, qty, rid}       ->  units_moved {product, qty, from, to}
##   units_store  {station, product, qty, rid}       ->  units_moved {product, qty, from, to}
##   units_drop   {product, qty, pos: Vector3, rid}  ->  units_moved {product, qty, from, to: floor:<n>, pos}
##
## CompanyNet holds one (CompanyNet.units) and passes itself with every call: the stock, the floor bundles, the
## `stations` lookup and `player_origin` are read from it when used, since its owner sets them after the node is
## made. Nothing here publishes: on_request() gives the refusal or the one event and CompanyNet publishes it, as
## for every other domain. The only state is where each peer stood at its last units request.

const TAKE: StringName = &"units_take"
const STORE: StringName = &"units_store"
## Units from the sender's hands onto the floor: {product, qty, pos: Vector3, rid} (row 7, D-2006).
const DROP: StringName = &"units_drop"
const MOVED: StringName = &"units_moved"
const REQUEST_KINDS: Array[StringName] = [TAKE, STORE, DROP]
## Letting go is critical (rule 8): losing it leaves a player stuck with what it holds.
const CRITICAL_KINDS: Array[StringName] = [DROP]
## Never one of CompanyNet.HOST_EVENT_KINDS: units only move because somebody asked, or left.
const EVENT_KINDS: Array[StringName] = [MOVED]
const HOST_EVENT_KINDS: Array[StringName] = []
## units_drop: a `pos` farther than this (meters) from where the host sees the player lands at
## its feet instead. Never a refusal: letting go always empties the hand (row 7).
const DROP_REACH: float = 2.0

## Host: {peer: Vector3}, where each peer stood at its last units request (take, store, drop).
## What a leaver held is dropped there when its player node is already gone
## (last_known_position(), D-2006); forgotten once it left (forget()).
var _last_origin: Dictionary = {}


## Host: a units request of `peer` (one of REQUEST_KINDS) checked with what only the host knows: {reason} when
## it is refused, else {reason: &"", kind: units_moved, data}, the one event CompanyNet publishes.
func on_request(net: CompanyNet, peer: int, kind: StringName, data: Dictionary) -> Dictionary:
	match kind:
		TAKE:
			return _check_take(net, peer, data)
		STORE:
			return _check_store(net, peer, data)
		DROP:
			return _check_drop(net, peer, data)
	return {"reason": CompanyNet.REASON_BAD_DATA}


## Every peer: a units_moved in place, the stock and, for a floor bundle, where it lies
## (FloorBundles.apply_move()). False, changing nothing, when the data doesn't fit.
static func apply(stock: Inventory, bundles: FloorBundles, data: Dictionary) -> bool:
	return bundles.apply_move(stock, CompanyAsk.as_id(data.get("product")),
		CompanyAsk.as_int(data.get("qty")), CompanyAsk.as_id(data.get("from")),
		CompanyAsk.as_id(data.get("to")), data.get("pos"))


## Host: the event that puts `qty` of `product` from `peer`'s hands into a new floor bundle at `pos` (one
## units_moved with its `pos`), as on_request() gives it. The bundle is the next free one when this is called, so
## each event is published before the next is asked for.
func dropped(net: CompanyNet, peer: int, product: StringName, qty: int, pos: Vector3) -> Dictionary:
	var moved: Dictionary = {
		"product": product, "qty": qty, "from": CompanyNet.hands_location(peer),
		"to": net.floor_bundles.next_free(net.inventory), "pos": pos,
	}
	return {"reason": &"", "kind": MOVED, "data": moved}


## Rule 4's shared check: a spot (a pallet, a shelf slot, a grid cell) is within reach of
## `origin` (the player's reach origin) up to Interactable.REMOTE_REACH plus `slack`.
static func within_reach(origin: Vector3, spot: Vector3, slack: float = 0.0) -> bool:
	return origin.distance_to(spot) <= Interactable.REMOTE_REACH + slack


## Host: where `peer` stood at its last units request, null if it never made one or it left
## (D-2006: what a leaver held is dropped there when its player is already gone).
func last_known_position(peer: int) -> Variant:
	return _last_origin.get(peer)


## Host: `peer` left; where it stood is forgotten.
func forget(peer: int) -> void:
	_last_origin.erase(peer)


## Host: the station `ask` names when `peer` may act at it, as {reason: &"", station}; {reason} when the data is
## bad, the station unknown or out of the sender's reach (station_of(), then station_problem()). Every request
## at a station goes through here before its own checks: the units, the packing tables, the carts, the pallets.
func reach(net: CompanyNet, peer: int, ask: Dictionary) -> Dictionary:
	var station: Dictionary = station_of(net, ask)
	var problem: StringName = station_problem(net, peer, ask, station)
	return {"reason": problem} if problem != &"" else {"reason": &"", "station": station}


## The station a checked request names, or {} (CompanyAsk.station_of(): `stations` and the floor bundles).
func station_of(net: CompanyNet, ask: Dictionary) -> Dictionary:
	return CompanyAsk.station_of(ask, net.floor_bundles, net.stations)


## Why a units request can't be done at that station: bad data, an unknown station or one out
## of the sender's reach (rule 4, measured to the station's spot). &"" when it can.
func station_problem(net: CompanyNet, peer: int, ask: Dictionary, station: Dictionary) -> StringName:
	if ask.is_empty():
		return CompanyNet.REASON_BAD_DATA
	if station.is_empty():
		return CompanyNet.REASON_NO_STATION
	var origin: Variant = _origin_of(net, peer)
	if not (origin is Vector3 and RpcGuard.finite_vec3(origin)):
		return CompanyNet.REASON_OUT_OF_REACH
	_last_origin[peer] = origin
	var slack: float = NetStats.reach_slack(net.multiplayer.multiplayer_peer, peer)
	if not within_reach(origin, station["spot"], slack):
		return CompanyNet.REASON_OUT_OF_REACH
	return &""


## Host: where `peer`'s player stands, its body (not its reach origin) or player_origin's value,
## if known and finite; else where it stood at its last units request; else null.
func feet_of(net: CompanyNet, peer: int) -> Variant:
	var body: Variant = _origin_of(net, peer, false)
	if body is Vector3 and RpcGuard.finite_vec3(body):
		return body
	return _last_origin.get(peer)


## Host, section 2 row 5: units from a station (pallet, shelf slot, floor bundle) into the
## sender's hands, free or empty hands holding only that product, up to the hand's limit.
## Reserved units may be taken too: a reservation is per product and stays where it is (who
## may put a reserved unit in which box is checked at box_place, D-0807 / D-0703).
func _check_take(net: CompanyNet, peer: int, data: Dictionary) -> Dictionary:
	var ask: Dictionary = CompanyAsk.at_station(data)
	var gate: Dictionary = _units_gate(net, peer, ask)
	if gate["reason"] != &"":
		return gate
	return CompanyAsk.take(net.inventory, ask, gate["station"], CompanyNet.hands_location(peer))


## Host, section 2 row 6: units from the sender's hands into a station that takes them (a
## shelf slot labeled for that product, with room, D-0608). A floor bundle is no such station
## (no_station): letting go on the floor is units_drop, a bundle of its own.
func _check_store(net: CompanyNet, peer: int, data: Dictionary) -> Dictionary:
	var ask: Dictionary = CompanyAsk.at_station(data)
	var gate: Dictionary = _units_gate(net, peer, ask)
	if gate["reason"] != &"":
		return gate
	return CompanyAsk.store(net.inventory, ask, gate["station"], CompanyNet.hands_location(peer))


## reach() for units_take / units_store: a packing table (table:<uid>) is a station of the box_* requests only
## (CompanyTableNet: units go into its box with box_place, out with box_take_out), never one units lie at, so
## it is no_station here. Without this a table, having no `accepts` and no `capacity`, would take any units into
## a location nothing draws, saves back or returns (D-2016.4 review).
func _units_gate(net: CompanyNet, peer: int, ask: Dictionary) -> Dictionary:
	var gate: Dictionary = reach(net, peer, ask)
	if gate["reason"] != &"":
		return gate
	if CompanyTableNet.table_of((gate["station"] as Dictionary).get("location")) != &"":
		return {"reason": CompanyNet.REASON_NO_STATION}
	return gate


## Host, section 2 row 7 (D-2006): units from the sender's hands into a new floor bundle at
## `pos`, or at its feet (feet_of()) when `pos` is over DROP_REACH plus the reach slack from them
## (never refused for distance). Refused for bad data, units not in the hand (not_enough, also
## for another product) or no idea where the player is (out_of_reach, as at a station).
func _check_drop(net: CompanyNet, peer: int, data: Dictionary) -> Dictionary:
	var ask: Dictionary = CompanyAsk.drop(data)
	if ask.is_empty():
		return {"reason": CompanyNet.REASON_BAD_DATA}
	var feet: Variant = feet_of(net, peer)
	if feet == null:
		return {"reason": CompanyNet.REASON_OUT_OF_REACH}
	_last_origin[peer] = feet
	var product: StringName = ask["product"]
	var qty: int = ask["qty"]
	if net.inventory.count(product, CompanyNet.hands_location(peer)) < qty:
		return {"reason": CompanyNet.REASON_NOT_ENOUGH}
	var pos: Vector3 = ask["pos"]
	if pos.distance_to(feet) > DROP_REACH + NetStats.reach_slack(net.multiplayer.multiplayer_peer, peer):
		pos = feet
	return dropped(net, peer, product, qty, pos)


## Where `peer`'s player is: its reach_origin() when `reach`, else its body's position;
## player_origin's value when set. Null when that peer has no player.
func _origin_of(net: CompanyNet, peer: int, reach: bool = true) -> Variant:
	if net.player_origin.is_valid():
		return net.player_origin.call(peer)
	for player: Node in net.get_tree().get_nodes_in_group(Interactable.player_group):
		if player.get_multiplayer_authority() == peer and player is Node3D:
			if reach and player.has_method(&"reach_origin"):
				return player.call(&"reach_origin")
			return (player as Node3D).global_position
	return null
