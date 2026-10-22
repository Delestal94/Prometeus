extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_gps.gd
##
## The company vehicle's GPS (expansion D-0308.1 and D-0308.2, scripts/gameplay/districts/company_gps.gd)
## on the real map (data/world/road_graph.tres, data/world/houses.tres):
## - on a trip it points at the house of the next stop, labelled with its street and number
##   (the same address as the order label), and the arrow's waypoint is ahead of the vehicle;
## - once that stop is delivered it moves on to the next one; with none left it points at the shed;
## - a stop behind a closed gate gives {} (nothing to follow) and, with its lock open, a guidance;
## - the path is kept while the vehicle follows it (no new plan per call) and planned again when
##   the vehicle leaves it by more than OFF_ROUTE;
## - the estimate in game minutes is the seconds left x 60 / SECONDS_PER_GAME_HOUR (D-0308.2).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var graph: RoadGraph = RoadGraph.load_default()
	var map: HouseMap = HouseMap.load_default()
	var addresses: HouseAddresses = HouseAddresses.build(map, graph)
	var gps: CompanyGps = CompanyGps.build(graph, map, addresses)
	var centro: Array[HouseSpot] = map.in_zone(&"centro")
	var campo: Array[HouseSpot] = map.in_zone(&"campo")
	_expect(centro.size() >= 2 and not campo.is_empty(), "The map has Centro and Campo houses")
	var shed := Vector2.ZERO
	_test_next_stop(gps, shed, centro, addresses)
	_test_home(gps, shed)
	_test_closed_gate(gps, shed, campo)
	_test_kept_and_rerouted(gps, shed, centro)
	if _failures == 0:
		print("PASS: the company GPS follows the trip's next stop, goes home and keeps its path")
	quit(_failures)


func _trip_to(houses: Array[StringName]) -> Trip:
	var trip := Trip.new()
	for house_id: StringName in houses:
		trip.stops.append({"house_id": house_id, "order_ids": [StringName("o_" + String(house_id))] as Array[StringName]})
	return trip


func _test_next_stop(gps: CompanyGps, shed: Vector2, centro: Array[HouseSpot], addresses: HouseAddresses) -> void:
	gps.trip = _trip_to([centro[0].id, centro[1].id])
	var first: Dictionary = gps.guidance(shed)
	_expect(not first.is_empty(), "A Centro stop is reachable from the shed")
	var address: Dictionary = addresses.of_house(centro[0].id)
	_expect(String(first.label) == "%s %d" % [tr(address.street_key), address.number], "The label is the house's address: %s" % [first.get("label")])
	_expect(int(first.house) == gps.houses.index_of(centro[0].id), "It names the next stop's house index")
	var ahead := Vector2(first.waypoint.x, first.waypoint.z)
	_expect(ahead.distance_to(shed) > 1.0, "The arrow's waypoint is ahead of the vehicle")
	_expect(float(first.distance) >= shed.distance_to(centro[0].position) * 0.9, "The distance is no shorter than the straight line")
	_expect(is_equal_approx(float(first.game_minutes), float(first.seconds) * 60.0 / CompanyTuning.SECONDS_PER_GAME_HOUR), "Game minutes = seconds x 60 / seconds per game hour")
	_expect(float(first.game_minutes) > 0.0, "The arrival estimate is above zero")
	_expect((first.polyline as PackedVector2Array).size() >= 2, "It carries the path to draw")
	# The first stop is delivered: the screen moves on to the second one.
	gps.trip.delivered_ids.append(StringName("o_" + String(centro[0].id)))
	var second: Dictionary = gps.guidance(shed)
	_expect(int(second.house) == gps.houses.index_of(centro[1].id), "Delivered stop: it points at the next one")


func _test_home(gps: CompanyGps, shed: Vector2) -> void:
	gps.trip = _trip_to([])
	var home: Dictionary = gps.guidance(Vector2(40, 0))
	_expect(not home.is_empty(), "With no stop left the way home exists")
	_expect(int(home.house) == -1, "Home has no house index")
	_expect(String(home.label) == tr("WORLD_GPS_SHED"), "Home is labelled as the shed")
	_expect(float(home.distance) <= 80.0, "Home is near from 40 m of the shed: %s" % [home.distance])
	gps.trip = null
	_expect(not gps.guidance(Vector2(40, 0)).is_empty(), "Without a trip it points home too")
	var arrived: Dictionary = gps.guidance(shed)
	_expect(not arrived.is_empty() and float(arrived.distance) <= 1.0, "At the shed the distance is nil")


func _test_closed_gate(gps: CompanyGps, shed: Vector2, campo: Array[HouseSpot]) -> void:
	gps.trip = _trip_to([campo[0].id])
	gps.open_locks = []
	_expect(gps.guidance(shed).is_empty(), "A Campo stop behind a closed gate gives no guidance")
	gps.open_locks = [&"gate_campo_obra"]
	var open: Dictionary = gps.guidance(shed)
	_expect(not open.is_empty(), "With the lock open the Campo stop is guided")
	gps.open_locks = []


func _test_kept_and_rerouted(gps: CompanyGps, shed: Vector2, centro: Array[HouseSpot]) -> void:
	gps.trip = _trip_to([centro[0].id])
	gps.guidance(shed)
	var made: int = gps.plans_made
	var line: PackedVector2Array = gps.guidance(shed).polyline
	_expect(gps.plans_made == made, "Asking again from the same spot keeps the path")
	gps.guidance(line[line.size() / 3])
	_expect(gps.plans_made == made, "Following the path keeps it")
	var off: Vector2 = line[line.size() / 2] + Vector2(0, CompanyGps.OFF_ROUTE * 3.0)
	gps.guidance(off)
	_expect(gps.plans_made == made + 1, "Leaving the path plans it again")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
