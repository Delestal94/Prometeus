class_name CompanyGps
extends RefCounted
## What the company vehicle's dashboard GPS shows (expansion D-0308.1, D-0308.2).
##
## guidance() answers the DashboardGps.guidance_provider contract ({distance, label, waypoint, house})
## and adds {seconds, game_minutes, polyline}. It points at the house of the trip's next stop
## (Trip.next_stop(), a HouseMap spot) and, once no stop is left, at the shed. The path comes from
## RoadNavigator over the road graph, avoiding the gates that are not open; it is kept and only
## planned again when the target or the open gates change or the vehicle leaves it by more than
## OFF_ROUTE meters. A target no open way reaches gives {} (the screen shows "—").
## No node, no autoload: the caller feeds the vehicle position, the trip and the open gates.

## Meters from the planned path at which the vehicle counts as off it.
const OFF_ROUTE: float = 25.0
const HOME_KEY: String = "WORLD_GPS_SHED"
const HOME_NODE: StringName = &"shed"

var net: RoadNetwork
var houses: HouseMap
var addresses: HouseAddresses
## Open gate locks (CompanyState.opened_gates).
var open_locks: Array = []
## The trip the vehicle is on; null (or closed) points home.
var trip: Trip

var _plan: Dictionary = {}
var _plan_target: Vector2 = Vector2.INF
var _plan_locks: int = -1
## How many times the path was planned (tests read it to see it is kept).
var plans_made: int = 0


static func build(road_net: RoadNetwork, map: HouseMap, address_book: HouseAddresses) -> CompanyGps:
	var gps := CompanyGps.new()
	gps.net = road_net
	gps.houses = map
	gps.addresses = address_book
	return gps


## Where the screen points now, for a vehicle at `position` (x, z of the map).
func guidance(position: Vector2) -> Dictionary:
	return guidance_to(position, trip.next_stop() if trip != null else &"")


## The same for a vehicle whose next stop is already known (a peer that holds the trip's entry and the order
## book, not the host's Trip): `stop` is a HouseMap id, or empty to point at the shed.
func guidance_to(position: Vector2, stop: StringName) -> Dictionary:
	var spot: HouseSpot = houses.spot(stop) if stop != &"" and houses != null else null
	var target: Vector2
	if spot != null:
		target = spot.position
	else:
		var home: RoadNode = net.node_by_id(HOME_NODE)
		if home == null:
			return {}
		target = home.position
	var planned: Dictionary = _planned(position, target)
	if not planned.get("ok", false):
		return {}
	var ahead: Dictionary = RoadNavigator.guidance(planned, position, CompanyTuning.GPS_LOOKAHEAD)
	var seconds: float = float(ahead.seconds)
	return {
		"distance": float(ahead.distance),
		"waypoint": ahead.waypoint,
		"house": houses.index_of(stop) if spot != null else -1,
		"label": _label(spot),
		"seconds": seconds,
		"game_minutes": seconds * 60.0 / CompanyTuning.SECONDS_PER_GAME_HOUR,
		"polyline": planned.polyline,
	}


func _planned(position: Vector2, target: Vector2) -> Dictionary:
	if _plan.get("ok", false) and target == _plan_target and open_locks.size() == _plan_locks \
			and _distance_to_plan(position) <= OFF_ROUTE:
		return _plan
	_plan = RoadNavigator.route(net, position, target, open_locks)
	_plan_target = target
	_plan_locks = open_locks.size()
	plans_made += 1
	return _plan


func _distance_to_plan(position: Vector2) -> float:
	var line: PackedVector2Array = _plan.polyline
	var best: float = INF
	for i in line.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, line[i], line[i + 1])
		best = minf(best, position.distance_to(closest))
	return best


func _label(spot: HouseSpot) -> String:
	if spot == null:
		return TranslationServer.translate(HOME_KEY)
	var address: Dictionary = addresses.of_house(spot.id) if addresses != null else {}
	if address.is_empty():
		return String(spot.id)
	return "%s %d" % [TranslationServer.translate(address.street_key), address.number]
