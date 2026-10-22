extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_gps_link.gd
##
## Hooking the company vehicle's dashboard GPS to the road graph (expansion D-0308.1b,
## scripts/gameplay/districts/company_gps_link.gd):
## - next_stop() reads the trip's entry and the replicated OrderBook: the first order not settled, by house id;
##   delivered, failed and cancelled ones are skipped, and no trip (or an empty book) points at the shed;
## - link_vehicles() gives a fleet vehicle's DashboardGps a provider once (a second call hooks nothing);
## - the provider answers with the vehicle's trip: the next house's address and the estimate in game minutes,
##   moves on to the next house once the first order is delivered, and points at the shed when none is left;
## - the screen shows that estimate (WORLD_GPS_ETA).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map: HouseMap = HouseMap.load_default()
	var centro: Array[HouseSpot] = map.in_zone(&"centro")
	_expect(centro.size() >= 2, "The map has two Centro houses")
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	for i in 2:
		var items: Array = [{"product": &"hen", "qty": 1}]
		book.add(Order.make(StringName("o%d" % i), "Ana", &"centro", centro[i].id, items, 0, products))
	var entry: Dictionary = {
		"trip": &"trip_1", "vehicle": &"van", "orders": [&"o0", &"o1"], "boxes": [&"b0"], "minute": 480,
	}
	_test_next_stop(entry, book, centro)
	await _test_link(entry, book, centro)
	if _failures == 0:
		print("PASS: the company GPS link follows each vehicle's trip through the replicated orders")
	quit(_failures)


func _test_next_stop(entry: Dictionary, book: OrderBook, centro: Array[HouseSpot]) -> void:
	_expect(CompanyGpsLink.next_stop(entry, book) == centro[0].id, "The first order's house is the next stop")
	_expect(CompanyGpsLink.next_stop({}, book) == &"", "No trip, no stop")
	_expect(CompanyGpsLink.next_stop(entry, null) == &"", "No book, no stop")
	_expect(CompanyGpsLink.next_stop(entry, OrderBook.new()) == &"", "Unknown orders are skipped")


func _test_link(entry: Dictionary, book: OrderBook, centro: Array[HouseSpot]) -> void:
	var fleet := Node3D.new()
	root.add_child(fleet)
	var van := Node3D.new()
	van.name = "van"
	fleet.add_child(van)
	var screen := DashboardGps.new()
	screen.name = "DashboardGps"
	van.add_child(screen)
	var view := CompanyTripsView.new()
	root.add_child(view)
	var net := CompanyNet.new()
	net.orders.book = book
	root.add_child(net)
	var link := CompanyGpsLink.new()
	link.fleet = fleet
	link.view = view
	link.net = net
	link.graph = RoadGraph.load_default()
	link.houses = HouseMap.load_default()
	link.addresses = HouseAddresses.load_default()
	root.add_child(link)
	_expect(link.link_vehicles() == 1, "The vehicle's screen is hooked")
	_expect(link.link_vehicles() == 0, "Hooked once")
	_expect(screen.guidance_provider.is_valid(), "The screen has a provider")
	var home: Dictionary = screen.guidance_provider.call()
	_expect(not home.is_empty() and str(home.label) == tr("WORLD_GPS_SHED"), "With no trip it points at the shed")
	view.apply_trip(CompanyTripsView.STARTED, entry)
	van.position = Vector3(0, 0.7, 0)
	var first: Dictionary = screen.guidance_provider.call()
	_expect(int(first.get("house", -2)) == map_index(centro[0].id), "On a trip it points at the first house")
	_expect(float(first.get("game_minutes", 0.0)) > 0.0, "It carries the estimate in game minutes")
	screen.refresh()
	var eta: String = tr("WORLD_GPS_ETA") % ceili(float(first.game_minutes))
	_expect(screen.detail_label.text.contains(eta), "The screen shows the estimate")
	book.mark_packed(&"o0", &"b0")
	book.mark_out(&"o0", &"trip_1")
	book.mark_delivered(&"o0", 100, true, 480)
	var second: Dictionary = screen.guidance_provider.call()
	_expect(int(second.get("house", -2)) == map_index(centro[1].id), "Once the first is delivered it moves on")
	fleet.free()
	view.free()
	net.free()
	link.free()


func map_index(id: StringName) -> int:
	return HouseMap.load_default().index_of(id)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
