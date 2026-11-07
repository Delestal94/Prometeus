extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_departure.gd
##
## The shed's gate as the start of a trip, end to end (expansion D-0302, D-0302.2.b.3 with D-0717.b;
## CompanyDispatch, DispatchRack, CompanyTrips, CompanyTripsView), in the solo company_root.tscn, with nobody
## handing the gate a position: sealed boxes lie in the dispatch zone, the board loads them and the van, driven by
## the player, leaves with them.
## - "Load" puts the boxes on the van's rack: on the van's PackageMountPoints (occupied by them), aboard, not frozen
##   (nothing starts a run here to thaw them), inside its bay and out of the zone, where the rest keep waiting;
## - a loaded box taken back down leaves the cargo: when the board reads it, or at the gate when nobody opened the
##   board; the trip doesn't take it and its order stays OPEN in the shared book, so it can be listed again;
## - the van really carries what stays: driven across the gate the trip starts with that box and its order, the box
##   is still in the bay, and the shared book (CompanyNet.orders.book) has the order OUT with its box and trip;
## - the district loads around the loaded van (the host's cells follow it): a Campo cell, not pinned and not loaded
##   while the van was in the yard, is built once the van is there, with the box still aboard;
## - back in the yard the trip closes, the order fails in the shared book (no door yet) and the box is still on the
##   rack, taking up a slot: the board offers the van again with one slot fewer, the definition untouched;
## - a rack on a vehicle that doesn't drive outside a run keeps a box frozen until the run starts (the delivery run).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_departure"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const DRIVER := preload("res://tests/bot_company_van.gd")
const VAN: StringName = &"van_classic"
const ORDERS: Array[StringName] = [&"o1", &"o2", &"o3", &"o4"]
## Frames the cells may take to build one around the van.
const CELL_FRAMES: int = 900

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	_check_rack_rule()
	await _check_world()
	state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: the board puts the boxes on the van, the van leaves with them, the district loads around it"
			+ " and the shared book follows the trip")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


## PackageHandling.rack_drives(): only a mount owned by a vehicle of the fleet, which drives outside a run.
func _check_rack_rule() -> void:
	var owner_node := Node3D.new()
	var marker := Marker3D.new()
	owner_node.add_child(marker)
	marker.owner = owner_node
	_expect(not PackageHandling.rack_drives(marker), "A shelf that drives nowhere keeps its box frozen until the run")
	owner_node.add_to_group(CompanyTrips.VEHICLE_GROUP)
	_expect(PackageHandling.rack_drives(marker), "A rack on a fleet vehicle does not")
	var lone := Marker3D.new()
	_expect(not PackageHandling.rack_drives(lone), "...and so does a mount with no owner")
	lone.free()
	owner_node.free()


func _check_world() -> void:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	var dispatch := level.get_node_or_null(^"Dispatch") as CompanyDispatch
	var van: VehicleBody3D = DRIVER.van_of(level, VAN)
	_expect(dispatch != null and van != null and level.trips != null, "The world has its board, van and gate")
	if dispatch == null or van == null or level.trips == null:
		_free_level(level)
		return
	_put_boxes(level)
	await _check_load(level, dispatch, van)
	await _check_taken_down(level, dispatch)
	await _check_leaves(level, van)
	await _check_district(level, van)
	await _check_back(level, dispatch, van)
	_free_level(level)
	await process_frame


## Orders in the shared book, each with its sealed box lying in the zone (as a taped box is, a DeliveryPackage).
func _put_boxes(level: CompanyRoot) -> void:
	var area: AABB = CompanyDispatch.area_of(level.shed)
	var products: Dictionary = {&"hen": HEN}
	for index: int in ORDERS.size():
		var order_id: StringName = ORDERS[index]
		level.net.orders.book.add(Order.make(order_id, "Cliente", &"centro", &"centro_house_1",
			[{"product": &"hen", "qty": 1}], floori(level.clock.minute_now()), products))
		var box := PackedBox.new(&"M")
		box.place(HEN, Vector3i.ZERO)
		box.taped = true
		box.label_order_id = order_id
		var package: DeliveryPackage = BoxToPackage.build(box, products)
		level.packages.add_child(package)
		package.freeze = true
		package.global_position = area.get_center() + Vector3(-1.0 + 0.5 * index, 0.0, 0.0)


func _package(level: CompanyRoot, order_id: StringName) -> DeliveryPackage:
	return DispatchRack.package_of(level.packages, StringName("box_" + str(order_id)))


## The first three go on the rack, the fourth is not picked.
func _check_load(level: CompanyRoot, dispatch: CompanyDispatch, van: VehicleBody3D) -> void:
	_expect(DispatchRack.free_mounts(van).size() == 7, "The empty van has 7 free mounts")
	_expect(dispatch.open(), "The board opens")
	await process_frame
	var panel: DispatchBoardPanel = dispatch.panel
	for box_id: StringName in [&"box_o1", &"box_o2", &"box_o3"]:
		_expect(panel.toggle(box_id)["ok"], "%s is picked" % box_id)
	_expect(panel.confirm() == 3, "Load takes the three")
	panel.close()
	for order_id: StringName in [&"o1", &"o2", &"o3"]:
		var package: DeliveryPackage = _package(level, order_id)
		_expect(package.is_loaded and package.is_aboard() and package.current_mount != null
			and van.is_ancestor_of(package.current_mount) and package.current_mount.get(&"occupied_by") == package,
			"%s is on a mount of the van" % package.package_id)
		_expect(not package.freeze, "%s is not frozen: it has to ride" % package.package_id)
	_expect(DispatchRack.free_mounts(van).size() == 4, "Three mounts are taken")
	for _tick: int in range(30):
		await physics_frame
	for order_id: StringName in [&"o1", &"o2", &"o3"]:
		_expect(van.call(&"carries", _package(level, order_id).global_position),
			"%s rests in the bay (at %s)" % [order_id, _package(level, order_id).global_position])
	_expect(dispatch.scan().boxes() == ([&"box_o4"] as Array[StringName]), "Only the fourth is left in the zone")
	var staged: Dictionary = level.trips._staged.get(VAN, {})
	_expect(staged.get("boxes", []) == [&"box_o1", &"box_o2", &"box_o3"], "The three are staged (got %s)" % [staged])
	_expect(level.net.orders.book.state_of(&"o1") == Order.STATE_OPEN, "The shared book moves only when it leaves")


## A hand takes one down and sets it in the zone, with the board open or not.
func _check_taken_down(level: CompanyRoot, dispatch: CompanyDispatch) -> void:
	var area: AABB = CompanyDispatch.area_of(level.shed)
	var seen: DeliveryPackage = _package(level, &"o2")
	seen.release_mount()
	seen.freeze = true
	seen.global_position = area.get_center() + Vector3(0.6, 0.0, 0.3)
	var unseen: DeliveryPackage = _package(level, &"o3")
	unseen.release_mount()
	unseen.freeze = true
	unseen.global_position = area.get_center() + Vector3(0.0, 0.0, 0.3)
	await physics_frame
	var listed: Array[StringName] = dispatch.scan().boxes()
	_expect(listed.has(&"box_o2") and listed.has(&"box_o3"),
		"Read by the board, a box taken down is listed (got %s)" % [listed])
	var staged: Dictionary = level.trips._staged.get(VAN, {})
	_expect(staged.get("boxes", []) == [&"box_o1"] and staged.get("orders", []) == [&"o1"],
		"...and left the cargo with its order (got %s)" % [staged])
	# Staged again and not aboard, with nobody reading the board: the gate is what leaves it out.
	level.trips.stage_cargo(VAN, [&"o1", &"o3"] as Array[StringName], [&"box_o1", &"box_o3"] as Array[StringName])
	dispatch._loaded[&"box_o3"] = VAN
	_expect(dispatch.left_behind(VAN, &"box_o3") and not dispatch.left_behind(VAN, &"box_o1"),
		"left_behind() names the staged box that is not in the bay")


func _check_leaves(level: CompanyRoot, van: VehicleBody3D) -> void:
	var left: Dictionary = await DRIVER.drive_out(self, level, VAN)
	_expect(str(left.get("reason")) == "", "The player drives the van out (got %s)" % [left])
	var trip: Trip = level.trips.trip_of(VAN)
	_expect(trip != null, "Crossing the gate started the trip")
	if trip == null:
		return
	_expect(trip.order_ids == ([&"o1"] as Array[StringName]) and trip.box_ids == ([&"box_o1"] as Array[StringName]),
		"The gate let only what rides go (orders %s, boxes %s)" % [trip.order_ids, trip.box_ids])
	var package: DeliveryPackage = _package(level, &"o1")
	_expect(package.is_aboard() and van.call(&"carries", package.global_position),
		"The box left with the van (box %s, van %s)" % [package.global_position, van.global_position])
	var shared: OrderBook = level.net.orders.book
	_expect(shared.state_of(&"o1") == Order.STATE_OUT and shared.box_of(&"o1") == &"box_o1"
		and StringName(shared.get_order(&"o1").get("trip_id", "")) == trip.id,
		"The shared book has the order out with its box and trip (%s)" % [shared.get_order(&"o1")])
	_expect(shared.state_of(&"o3") == Order.STATE_OPEN and level.trips.book.state_of(&"o3") == Order.STATE_PACKED,
		"The box left behind keeps its order waiting (%s)" % shared.state_of(&"o3"))
	_expect(level.trips_view.is_out(VAN) and level.trips_view.trip_of(VAN).get("orders") == [&"o1"],
		"The view shows the van out with its order")


## The cell of Campo nearest its middle that is neither pinned nor built, or a cell out of the map (Vector2i.MAX).
func _far_cell(cells: CompanyCells) -> Vector2i:
	var campo: ZoneDefinition = CompanyCatalog.load_all().zone(&"campo")
	var from: Vector2i = cells.grid.cell_of(Vector3(campo.bounds.get_center().x, 0.0, campo.bounds.get_center().y))
	for ring: int in range(6):
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				var cell: Vector2i = from + Vector2i(dx, dz)
				if not cells.grid.is_pinned(cell) and not cells.is_loaded(cell):
					return cell
	return Vector2i.MAX


## The loaded van stands in Campo, its box with it: the host's cells build the district around it.
func _check_district(level: CompanyRoot, van: VehicleBody3D) -> void:
	var cells: CompanyCells = level.cells
	var cell: Vector2i = _far_cell(cells)
	_expect(cell != Vector2i.MAX, "Campo has a cell that isn't built while the van is in the yard")
	if cell == Vector2i.MAX or level.trips.trip_of(VAN) == null:
		return
	var size: float = cells.grid.cell_size
	var at := Vector3((cell.x + 0.5) * size, van.global_position.y + 0.5, (cell.y + 0.5) * size)
	var package: DeliveryPackage = _package(level, &"o1")
	var aboard: Vector3 = van.to_local(package.global_position)
	van.global_position = at
	package.global_position = van.to_global(aboard)
	package.reset_physics_interpolation()
	var built: bool = false
	for _frame: int in range(CELL_FRAMES):
		await process_frame
		built = cells.is_loaded(cell)
		if built:
			break
	_expect(built, "The district loaded around the van (cell %s)" % cell)
	_expect(package.is_aboard(), "...with the box still aboard")


func _check_back(level: CompanyRoot, dispatch: CompanyDispatch, van: VehicleBody3D) -> void:
	if level.trips.trip_of(VAN) == null:
		return
	var home: Vector3 = CompanyFleet.park_transform(level.shed, level.net.company, 0).origin
	var package: DeliveryPackage = _package(level, &"o1")
	var aboard: Vector3 = van.to_local(package.global_position)
	van.global_position = Vector3(home.x, van.global_position.y, home.z)
	package.global_position = van.to_global(aboard)
	for _tick: int in range(4):
		await physics_frame
	_expect(level.trips.trips_out() == 0 and not level.trips_view.is_out(VAN), "Back in the yard the trip closes")
	_expect(level.net.orders.book.state_of(&"o1") == Order.STATE_FAILED,
		"The undelivered order failed in the shared book too (%s)" % level.net.orders.book.state_of(&"o1"))
	await process_frame
	_expect(package.is_aboard(), "Nobody took the box: it is still on the rack")
	_expect(dispatch.available_vehicle() == van, "The van is offered again")
	var offered: VehicleDefinition = dispatch.context()["vehicle"]
	var defined: VehicleDefinition = CompanyCatalog.load_all().vehicle(VAN)
	_expect(offered.cargo_slots == defined.cargo_slots - 1 and defined.cargo_slots == 7,
		"...with one slot fewer, the definition untouched (offered %d, defined %d)"
		% [offered.cargo_slots, defined.cargo_slots])


func _free_level(level: Node) -> void:
	level.queue_free()
	current_scene = null
