extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_dispatch_station.gd
##
## The dispatch board in the company's world (expansion D-0310.b, with the minimal D-0716.b;
## DispatchStation, CompanyDispatch, DispatchBoardPanel), in the solo company_root.tscn:
## - the shed has one DispatchStation per dispatch zone, a DepotStation with station_id &"dispatch"
##   standing in the middle of the zone on the interaction layer, with a shape and the prompt "Usar
##   despacho"; the zone has that and no ShedPiecePoint; a redraw of the shed keeps exactly one; its
##   prompt stays when a delivery run left results behind (a DepotStation would hide it);
## - the translations the board needs exist in both languages: WORLD_ZONE_<id> for every data/zones/,
##   WORLD_VEHICLE_<id> for every data/vehicles/ (the zones' display_key is that key);
## - using the station (interact() with the local player, as the host does) opens the board
##   (CompanyDispatch, child "Dispatch" of the root): the sealed boxes lying inside the zone's area are
##   its rows, oldest first, with their kg (BoxScale), and a box outside the area, or one for Islas
##   (DispatchRules: the van does not go there, the row says why), is not pickable; the vehicle is the
##   fleet's real van, by name, with the slots and kg of its VehicleDefinition; the local player's input is
##   off while it is open and back on when it closes;
## - on the host two boxes picked and "Load" stage them on the van in CompanyTrips (their orders too), the
##   host's trip book learns those orders as PACKED with their box, the shared book is left alone; the
##   third waits; opening it again does not list the loaded boxes although they still lie in the zone, and
##   with the van loaded there is no vehicle at the yard and Load is off; a box carried out of the area
##   leaves the list and one whose package is gone is forgotten;
## - a peer that doesn't decide (no CompanyTrips, as a client) sees the list from its own copy but Load
##   is off with the reason and loads nothing.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_dispatch_station"
const CSV: String = "res://translations/strings_world.csv"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const VAN: StringName = &"van_classic"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	_check_translations()
	await _check_world()
	state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: the shed's dispatch station opens the board with the zone's sealed boxes and the real van;"
			+ " the host loads two, a client cannot")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1


func _es(key: String) -> String:
	return TranslationServer.translate(key)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _check_translations() -> void:
	TranslationServer.set_locale("es")
	var rows: Dictionary = {}
	var file := FileAccess.open(CSV, FileAccess.READ)
	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.size() >= 3:
			rows[cols[0]] = cols
	var catalog := CompanyCatalog.load_all()
	_expect(not catalog.zones().is_empty(), "the catalog has zones")
	for zone: ZoneDefinition in catalog.zones():
		var key: String = CompanyDispatch.zone_key(zone.id)
		_expect(zone.display_key == key, "%s: display_key is %s (got %s)" % [zone.id, key, zone.display_key])
		_expect(rows.has(key) and rows[key][1] != "" and rows[key][2] != "", "%s has both languages" % key)
	_expect(not catalog.all(CompanyCatalog.VEHICLES).is_empty(), "the catalog has vehicles")
	for vehicle: Resource in catalog.all(CompanyCatalog.VEHICLES):
		var key: String = CompanyDispatch.vehicle_key(vehicle.get(&"id"))
		_expect(rows.has(key) and rows[key][1] != "" and rows[key][2] != "", "%s has both languages" % key)
		_expect(CompanyDispatch.vehicle_name(vehicle as VehicleDefinition) != "", "%s is translated" % key)


func _check_world() -> void:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	var shed: CompanyShed = level.shed
	var dispatch := level.get_node_or_null(^"Dispatch") as CompanyDispatch
	_expect(dispatch != null and dispatch.panel != null and not dispatch.panel.visible,
		"the root has its dispatch board, closed")
	_expect(level.player != null, "the local player is up")
	if dispatch == null or level.player == null or level.trips == null:
		_free_level(level)
		return
	var station := _check_station(level, shed)
	if station == null:
		_free_level(level)
		return
	_put_boxes(level, shed)
	var panel: DispatchBoardPanel = dispatch.panel
	var player: Node = level.player
	station.interact(player)
	await process_frame
	await process_frame
	_check_open(level, dispatch, panel)
	_check_load(level, panel)
	panel.close()
	_expect(player.is_processing_unhandled_input(), "closing the board gives the player's input back")
	await _check_reopen(level, dispatch, station)
	await _check_client(level, dispatch)
	_free_level(level)
	await process_frame


## The station of the dispatch zone: a DepotStation `dispatch` in the middle of the zone.
func _check_station(level: CompanyRoot, shed: CompanyShed) -> DispatchStation:
	_expect(shed.dispatch_stations.size() == 1, "one dispatch station for the one dispatch zone (%d)"
		% shed.dispatch_stations.size())
	var uid: StringName = shed.dispatch_stations.keys()[0] if not shed.dispatch_stations.is_empty() else &""
	var station := shed.dispatch_stations.get(uid) as DispatchStation
	if station == null:
		_expect(false, "the dispatch station exists")
		return null
	_expect(station is DepotStation and station.station_id == &"dispatch", "it is a DepotStation `dispatch`")
	_expect(station.collision_layer == Interactable.interaction_layer and station.get_child_count() >= 1
		and station.get_child(0) is CollisionShape3D, "...on the interaction layer, with its shape")
	var prompt: String = _es("WORLD_SHED_USE_DISPATCH")
	_expect(station.get_prompt() == prompt and prompt != "WORLD_SHED_USE_DISPATCH",
		"...with the translated prompt (%s)" % station.get_prompt())
	var area: AABB = CompanyDispatch.area_of(shed)
	_expect(area.has_surface() and area.has_point(station.global_position),
		"...standing in the middle of the zone's area (%s, %s)" % [area, station.global_position])
	_expect(not shed.use_points.has(uid), "the zone has the station and no use point")
	var run: Node = root.get_node(^"/root/RunManager")
	var before: Variant = run.get(&"results")
	run.set(&"results", {"left_by": "a delivery run"})
	_expect(station.get_prompt() != "", "a run's results left behind don't hide the prompt")
	run.set(&"results", before)
	shed.rebuild(level.net.company, level.net.inventory)
	var stations: int = 0
	for child: Node in shed.get_children():
		if child is DispatchStation:
			stations += 1
	_expect(stations == 1 and shed.dispatch_stations.size() == 1,
		"a redraw of the shed keeps one station (%d)" % stations)
	return shed.dispatch_stations.get(uid) as DispatchStation


## Orders o1..o3 (Centro) and o4 (Islas) with their sealed boxes inside the zone's area, o5 (Centro) outside.
func _put_boxes(level: CompanyRoot, shed: CompanyShed) -> void:
	var area: AABB = CompanyDispatch.area_of(shed)
	var book: OrderBook = level.net.orders.book
	var products: Dictionary = {&"hen": HEN}
	var spots: Dictionary = {
		&"o1": [&"centro", area.get_center() + Vector3(-0.8, 0.0, 0.0)],
		&"o2": [&"centro", area.get_center() + Vector3(-0.2, 0.0, 0.0)],
		&"o3": [&"centro", area.get_center() + Vector3(0.4, 0.0, 0.0)],
		&"o4": [&"islas", area.get_center() + Vector3(0.9, 0.0, 0.0)],
		&"o5": [&"centro", area.get_center() + Vector3(area.size.x + 3.0, 0.0, 0.0)],
	}
	for order_id: StringName in spots:
		var zone_id: StringName = spots[order_id][0]
		book.add(Order.make(order_id, "Cliente " + str(order_id), zone_id, &"house_1",
			[{"product": &"hen", "qty": 1}], 0, products))
		var box := PackedBox.new(&"M")
		box.place(HEN, Vector3i.ZERO)
		box.taped = true
		box.label_order_id = order_id
		var package: DeliveryPackage = BoxToPackage.build(box, products)
		level.packages.add_child(package)
		package.freeze = true
		package.global_position = spots[order_id][1]


func _check_open(level: CompanyRoot, dispatch: CompanyDispatch, panel: DispatchBoardPanel) -> void:
	_expect(panel.visible and dispatch.is_open(), "using the station opens the board")
	_expect(not level.player.is_processing_unhandled_input(), "...with the local player's input off")
	for box_id: StringName in [&"box_o1", &"box_o2", &"box_o3", &"box_o4"]:
		_expect(panel.row_button(box_id) != null, "the sealed box %s inside the zone is a row" % box_id)
	_expect(panel.row_button(&"box_o5") == null, "the box outside the area is not")
	var zone: DispatchZone = dispatch.scan()
	_expect(zone.boxes() == ([&"box_o1", &"box_o2", &"box_o3", &"box_o4"] as Array[StringName]),
		"the zone lists them oldest first (got %s)" % [zone.boxes()])
	var first: String = panel.row_button(&"box_o1").text
	var zone_name: String = _es("WORLD_ZONE_CENTRO")
	_expect(first.begins_with(DispatchBoardPanel.FREE) and first.contains("3.0 kg") and first.contains(zone_name),
		"a row says customer, zone (translated) and kg (got %s)" % first)
	var islas: String = panel.row_button(&"box_o4").text
	var why: String = _es("WORLD_DISPATCH_NEEDS_VEHICLE").split("%")[0]
	_expect(islas.begins_with(DispatchBoardPanel.BLOCKED) and islas.contains(why),
		"the Islas box is crossed out with its reason (got %s)" % islas)
	_expect(not panel.toggle(&"box_o4")["ok"], "...and cannot be picked")
	var van_line: String = (panel.find_child("Vehicle", true, false) as Label).text
	_expect(van_line.contains(_es("WORLD_VEHICLE_VAN_CLASSIC")),
		"the vehicle is the fleet's van, by name (got %s)" % van_line)
	var definition: VehicleDefinition = CompanyCatalog.load_all().vehicle(VAN)
	var capacity: String = (panel.find_child("Capacity", true, false) as Label).text
	_expect(capacity.contains("0 de %d" % definition.cargo_slots)
		and capacity.contains("%.0f kg" % definition.cargo_kg),
		"...with its slots and kg (got %s)" % capacity)
	_expect(dispatch.can_act(), "the host can load")


func _check_load(level: CompanyRoot, panel: DispatchBoardPanel) -> void:
	var trips: CompanyTrips = level.trips
	var shared: OrderBook = level.net.orders.book
	_expect(panel.toggle(&"box_o1")["ok"] and panel.toggle(&"box_o2")["ok"], "two boxes are picked")
	_expect(not panel.load_button().disabled, "Load is on for the host")
	_expect(panel.confirm() == 2, "Load takes the two picked boxes")
	var staged: Dictionary = trips._staged.get(VAN, {})
	_expect(staged.get("boxes", []) == [&"box_o1", &"box_o2"] and staged.get("orders", []) == [&"o1", &"o2"],
		"the van has those boxes and orders staged (got %s)" % [staged])
	_expect(trips.has_cargo(VAN), "CompanyTrips says the van has cargo")
	for order_id: StringName in [&"o1", &"o2"]:
		var box_id := StringName("box_" + str(order_id))
		_expect(trips.book.state_of(order_id) == Order.STATE_PACKED and trips.book.box_of(order_id) == box_id,
			"the host's trip book knows %s as PACKED with its box" % order_id)
		_expect(shared.state_of(order_id) == Order.STATE_OPEN,
			"the shared book is left alone (%s)" % shared.state_of(order_id))
	_expect(panel.row_button(&"box_o3") != null and panel.row_button(&"box_o1") == null, "the third box keeps waiting")


## Opened again: the loaded boxes still lie in the zone but are not listed, the van is loaded so none is at the
## yard; a box carried out of the area leaves the list, a freed package is forgotten.
func _check_reopen(level: CompanyRoot, dispatch: CompanyDispatch, station: DispatchStation) -> void:
	station.interact(level.player)
	await process_frame
	var panel: DispatchBoardPanel = dispatch.panel
	_expect(panel.visible, "the board opens again")
	_expect(panel.row_button(&"box_o1") == null and panel.row_button(&"box_o2") == null
		and panel.row_button(&"box_o3") != null, "the loaded boxes are not listed again")
	_expect(dispatch.available_vehicle() == null, "a van with cargo staged is not the vehicle to load")
	_expect(panel.load_button().disabled, "...and Load is off")
	_expect((panel.find_child("Vehicle", true, false) as Label).text == _es("UI_DISPATCH_NO_VEHICLE"),
		"...the board says there is no vehicle at the yard")
	var third := level.packages.get_node_or_null(^"Package_box_o3") as Node3D
	third.global_position += Vector3(CompanyDispatch.area_of(level.shed).size.x + 4.0, 0.0, 0.0)
	_expect(dispatch.scan().boxes() == ([&"box_o4"] as Array[StringName]),
		"a box carried out of the area leaves the list")
	panel.close()
	var gone := level.packages.get_node_or_null(^"Package_box_o1")
	level.packages.remove_child(gone)
	gone.free()
	dispatch.scan()
	_expect(not dispatch._loaded.has(&"box_o1") and dispatch._loaded.has(&"box_o2"),
		"a loaded box whose package is gone is forgotten (loaded %s)" % [dispatch._loaded.keys()])


## A peer with no CompanyTrips (a client): same list from its own copy, Load off with the reason.
func _check_client(level: CompanyRoot, host: CompanyDispatch) -> void:
	var third := level.packages.get_node_or_null(^"Package_box_o3") as Node3D
	third.global_position -= Vector3(CompanyDispatch.area_of(level.shed).size.x + 4.0, 0.0, 0.0)
	var client := CompanyDispatch.new()
	client.name = "ClientDispatch"
	client.net = level.net
	client.shed = level.shed
	client.packages = level.packages
	client.fleet = level.fleet
	client.trips_view = level.trips_view
	level.add_child(client)
	_expect(not client.can_act(), "without CompanyTrips a peer does not decide")
	var staged_before: Dictionary = level.trips._staged.duplicate(true)
	_expect(client.open(), "the client's board opens")
	await process_frame
	var panel: DispatchBoardPanel = client.panel
	_expect(panel.row_button(&"box_o3") != null, "it lists the boxes in the zone from its own copy")
	panel.toggle(&"box_o3")
	_expect(panel.load_button().disabled and panel.load_button().visible, "Load is disabled, not hidden")
	_expect(panel.status_text() == _es("UI_DISPATCH_HOST_ONLY"), "...with the reason (got %s)" % panel.status_text())
	_expect(panel.confirm() == 0 and level.trips._staged == staged_before, "and loads nothing")
	panel.close()
	_expect(host.panel.visible == false, "the host's board stayed closed")
	client.queue_free()


func _free_level(level: Node) -> void:
	level.queue_free()
	current_scene = null
