class_name CompanyDispatch
extends Node
## The dispatch board in the company's world (expansion D-0310.b, with the minimal D-0716.b): child of
## CompanyRoot, on every peer. It opens DispatchBoardPanel when a player uses the shed's DispatchStation
## (EventBus.depot_station_opened(&"dispatch") on that player's own peer) and hands it the real data.
##
## What the board shows, read from this peer's world each time it opens and twice a second while it is
## open (SCAN_SEC), nothing runs while it is closed:
## - the zone: the sealed boxes lying still inside the dispatch piece's floor (area_of()), from the
##   DeliveryPackages under World/Packages (a taped box is one, D-0715.b). A box counts when it is closed,
##   not in hands, not aboard, quiet (REST_SPEED) and its order is waiting for a box in the order book;
## - the book: a private copy of the shared one (CompanyNet.orders.book) where an order with a sealed box in
##   the zone is PACKED. The shared book is not marked PACKED by box_sealed yet (D-0715.b's order_packed is
##   open), so DispatchZone would never see a live box; when it is, nothing here changes;
## - the vehicle: the first of the fleet (CompanyFleet) that is in the yard, not out and with nothing staged
##   (CompanyTrips.has_cargo(): stage_cargo() replaces what was staged), with the numbers of its
##   VehicleDefinition (cargo_slots, cargo_kg) and its name (WORLD_VEHICLE_*);
## - the rules: DispatchRules over the catalog's zones and gates and the company's gate state.
##
## Only the host loads (S3): "Load" is DispatchBoardPanel.confirm() -> DispatchZone.load_boxes() ->
## CompanyTrips.stage_cargo(). A client sees the same list from its own copy of the packages and the book
## but with Load off and the reason. The boxes it loads are remembered here (_loaded) so they leave the list
## although they still lie in the zone; the clients don't know it (open: D-0310.c replicates the zone with
## box_dispatched / box_undispatched, row 17 of red-autoridad.md, and D-0717.b carries the boxes to the
## vehicle's PackageMountPoints, row 18). Meanwhile the host's trip book learns the loaded orders (_bridge())
## so the trip can start when the vehicle crosses the gate.
##
## While the board is open the mouse is free and the local player's input is off; closing gives both back.
## No RPC and no random roll here: nothing is placed or decided apart from the host's own loading.

## Box at rest: slower than this (m/s) and not in hands.
const REST_SPEED: float = 0.25
## Seconds between two reads of the zone while the board is open.
const SCAN_SEC: float = 0.5
## The area of the zone: its floor plus this height, and a little below the floor for a box that sank.
const AREA_HEIGHT_M: float = 2.0
const AREA_SINK_M: float = 0.2
## Families of translation keys (strings_world.csv): WORLD_ZONE_<ZONE ID> (the zones' display_key) and
## WORLD_VEHICLE_<VEHICLE ID>.
const ZONE_KEY_PREFIX: String = "WORLD_ZONE_"
const VEHICLE_KEY_PREFIX: String = "WORLD_VEHICLE_"

var net: CompanyNet
var shed: CompanyShed
## World/Packages: the DeliveryPackages of the sealed boxes.
var packages: Node
var fleet: CompanyFleet
## The host's trips (null on a client); the view is on every peer.
var trips: CompanyTrips
var trips_view: CompanyTripsView
var panel: DispatchBoardPanel
## Returns the local player (or null); its input is off while the board is open.
var player_of: Callable = Callable()
## Returns true while something else owns the screen (the build mode, the supplier board).
var busy: Callable = Callable()

var _catalog: CompanyCatalog
var _zones: Dictionary = {}
var _gates: Dictionary = {}
## This peer's copy of the order book where the boxes in the zone are PACKED.
var _view: OrderBook
## box id -> kg of the boxes in the zone at the last read, and box id -> order id of those seen in it while
## their package lives (the order of a box that was picked on a board a moment ago).
var _kg: Dictionary = {}
var _order_of: Dictionary = {}
## box id -> true: loaded by this peer (the host) although they still lie in the zone.
var _loaded: Dictionary = {}
var _signature: String = ""
var _since_scan: float = 0.0
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_off: Node = null


## The board of `root` (CompanyRoot), a child of it: its net, shed, packages, fleet, trips and player. It
## listens for the station on EventBus and, from now on, waits behind the build mode's and the supplier
## board's screens. Returns null when the root has no CompanyNet (nothing to show).
static func add_to(root: Node) -> CompanyDispatch:
	var company_net: CompanyNet = root.get(&"net") as CompanyNet
	if company_net == null:
		return null
	var dispatch := CompanyDispatch.new()
	dispatch.name = "Dispatch"
	dispatch.net = company_net
	dispatch.shed = root.get(&"shed") as CompanyShed
	dispatch.packages = root.get(&"packages") as Node
	dispatch.fleet = root.get(&"fleet") as CompanyFleet
	dispatch.trips = root.get(&"trips") as CompanyTrips
	dispatch.trips_view = root.get(&"trips_view") as CompanyTripsView
	dispatch.player_of = func() -> Node: return root.get(&"player") as Node
	var builder: ShedBuilder = root.get(&"builder") as ShedBuilder
	var supplier: SupplierBoard = root.get(&"supplier_board") as SupplierBoard
	var before: Callable = builder.busy if builder != null else Callable()
	dispatch.busy = func() -> bool:
		var building: bool = builder != null and is_instance_valid(builder) and builder.is_building()
		var ordering: bool = supplier != null and is_instance_valid(supplier) and supplier.is_open()
		return building or ordering
	if builder != null:
		# The build mode waits while this board is open, besides what it already waited for.
		builder.busy = func() -> bool:
			return dispatch.is_open() or (before.is_valid() and bool(before.call()))
	root.add_child(dispatch)
	var bus: Node = root.get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"depot_station_opened", dispatch._on_station_opened)
	return dispatch


func _init() -> void:
	_view = OrderBook.new()
	_view.name = "View"
	add_child(_view)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	var layer := CanvasLayer.new()
	layer.name = "DispatchLayer"
	add_child(layer)
	panel = DispatchBoardPanel.new()
	panel.name = "DispatchBoardPanel"
	layer.add_child(panel)
	panel.closed.connect(_on_closed)
	panel.loaded.connect(_on_loaded)


func is_open() -> bool:
	return panel != null and panel.visible


## Opens the board with what this peer sees now. False when it is already open or the screen is taken.
func open() -> bool:
	if panel == null or is_open():
		return false
	if busy.is_valid() and bool(busy.call()):
		return false
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node = player_of.call() as Node if player_of.is_valid() else null
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(false)
		_player_off = player
	var ctx: Dictionary = context()
	_signature = _signature_of(ctx)
	_since_scan = 0.0
	panel.open(ctx)
	set_process(true)
	return true


func close() -> void:
	if is_open():
		panel.close()


## True where the loading is decided: the host (solo too), which has the trips.
func can_act() -> bool:
	return trips != null and net != null and net.is_host()


## The board's data from this peer's world (see the class doc); reads the zone first.
func context() -> Dictionary:
	var zone: DispatchZone = scan()
	var body: Node3D = available_vehicle()
	var vehicle: VehicleDefinition = definition_of(body)
	var company: Object = net.company if net != null else null
	var owned: Dictionary = {}
	var opened: Array = []
	if company != null:
		if company.has_method(&"gate_owned"):
			owned = company.call(&"gate_owned")
		var opened_gates: Variant = company.get(&"opened_gates")
		if opened_gates is Array:
			opened = opened_gates
	return {
		"zone": zone, "book": _view, "trips": trips, "vehicle_id": StringName(body.name) if body != null else &"",
		"vehicle": vehicle, "vehicle_name": vehicle_name(vehicle), "box_kg": _kg.duplicate(),
		"zones": _zones_by_id(), "gates": _gates_by_id(), "owned": owned, "opened_gates": opened,
		"can_act": can_act(),
	}


## Reads the packages under World/Packages and returns the zone of the sealed boxes at rest inside the area,
## oldest first (the order they were put in the world). Fills the book copy, the weights and the orders of
## those boxes. Boxes this peer loaded are left out; ones whose package is gone are forgotten.
func scan() -> DispatchZone:
	var zone := DispatchZone.new(area_of(shed))
	_kg.clear()
	_view.from_dict(net.orders.book.to_dict() if net != null else {})
	var live: Dictionary = {}
	if zone.area.has_surface() and packages != null and is_instance_valid(packages):
		for child: Node in packages.get_children():
			var package := child as DeliveryPackage
			if package == null:
				continue
			live[package.package_id] = true
			if _loaded.has(package.package_id) or not zone.contains(package.global_position):
				continue
			_read_box(zone, package)
	for box_id: Variant in _loaded.keys():
		if not live.has(box_id):
			_loaded.erase(box_id)
	for box_id: Variant in _order_of.keys():
		if not live.has(box_id):
			_order_of.erase(box_id)
	return zone


## The vehicle the board loads: the first of the fleet in the yard that is not out and has nothing staged;
## null when none is (no fleet, all out or loaded).
func available_vehicle() -> Node3D:
	if fleet == null or not is_instance_valid(fleet):
		return null
	for body: Node3D in fleet.vehicles():
		var id := StringName(body.name)
		if trips != null:
			var inside: bool = trips.gate != null and trips.gate.side_of(body.global_position) == TripGate.INSIDE
			if trips.is_out(id) or trips.has_cargo(id) or not inside:
				continue
		elif trips_view != null and trips_view.is_out(id):
			continue
		return body
	return null


## The definition (data/vehicles/) of a fleet vehicle: its node name is the id, or "<id>_2", "<id>_3"...
## (CompanyFleet.node_names()). Null for none.
func definition_of(body: Node3D) -> VehicleDefinition:
	if body == null:
		return null
	var catalog: CompanyCatalog = _catalog_in_use()
	var named := String(body.name)
	var found: VehicleDefinition = catalog.vehicle(StringName(named))
	if found == null:
		var last: int = named.rfind("_")
		if last > 0 and named.substr(last + 1).is_valid_int():
			found = catalog.vehicle(StringName(named.substr(0, last)))
	return found


## Translated name of a vehicle ("" without a row in strings_world.csv: the board shows its capitalized id).
static func vehicle_name(vehicle: VehicleDefinition) -> String:
	if vehicle == null:
		return ""
	var key: String = vehicle_key(vehicle.id)
	var text: String = TranslationServer.translate(key)
	return "" if text == key else text


static func vehicle_key(vehicle_id: StringName) -> String:
	return VEHICLE_KEY_PREFIX + String(vehicle_id).to_upper()


static func zone_key(zone_id: StringName) -> String:
	return ZONE_KEY_PREFIX + String(zone_id).to_upper()


## The floor of the first dispatch piece of `at_shed` in world coordinates (axis aligned: the shed turns by
## quarter turns), AREA_HEIGHT_M tall; an empty AABB when it draws none.
static func area_of(at_shed: CompanyShed) -> AABB:
	if at_shed == null or not at_shed.is_inside_tree():
		return AABB()
	for piece: Dictionary in at_shed.pieces:
		if not at_shed.dispatch_stations.has(piece["uid"]):
			continue
		var rect: Rect2i = piece["rect"]
		var from: Vector3 = at_shed.to_global(at_shed.cell_to_local(Vector2(rect.position)))
		var to: Vector3 = at_shed.to_global(at_shed.cell_to_local(Vector2(rect.end)))
		var low := Vector3(minf(from.x, to.x), from.y - AREA_SINK_M, minf(from.z, to.z))
		return AABB(low, Vector3(absf(to.x - from.x), AREA_HEIGHT_M + AREA_SINK_M, absf(to.z - from.z)))
	return AABB()


func _process(delta: float) -> void:
	if not is_open():
		set_process(false)
		return
	_since_scan += delta
	if _since_scan < SCAN_SEC:
		return
	_since_scan = 0.0
	var ctx: Dictionary = context()
	var now: String = _signature_of(ctx)
	if now != _signature:
		_signature = now
		panel.refresh(ctx)


## What changes what the board draws: the boxes waiting, the vehicle and how many are out.
func _signature_of(ctx: Dictionary) -> String:
	var zone: DispatchZone = ctx["zone"]
	var out: int = trips.trips_out() if trips != null else (trips_view.trips_out() if trips_view != null else 0)
	return "%s|%s|%d|%s" % [zone.boxes(), ctx["vehicle_id"], out, ctx["can_act"]]


## One package in the area: the zone takes it when it is closed, still and its order waits for a box.
func _read_box(zone: DispatchZone, package: DeliveryPackage) -> void:
	var order_id := StringName(package.get_meta(BoxToPackage.META_ORDER_ID, &""))
	var state: StringName = _view.state_of(order_id)
	if state == Order.STATE_OPEN or state == Order.STATE_LATE:
		_view.mark_packed(order_id, package.package_id)
	var rests: bool = not package.is_held and not package.is_aboard() \
		and package.linear_velocity.length() < REST_SPEED
	var result: StringName = zone.update_box(package.package_id, order_id, package.global_position,
		not package.is_open, rests, _view)
	if result == DispatchZone.RESULT_DISPATCHED:
		_order_of[package.package_id] = order_id
		_kg[package.package_id] = _weight_of(package)


## The kg of what the box holds (BoxScale.real_kg over the box the package carries).
func _weight_of(package: DeliveryPackage) -> float:
	var saved: Variant = package.get_meta(BoxToPackage.META_PACKED_BOX, {})
	if not saved is Dictionary or (saved as Dictionary).is_empty():
		return 0.0
	var box: PackedBox = PackedBox.from_dict(saved)
	var products: Dictionary = {}
	for product_id: StringName in box.contents():
		products[product_id] = _catalog_in_use().product(product_id)
	return BoxScale.real_kg(box, products)


## The panel loaded `boxes` (the host): they leave the list although they lie in the zone, and the host's trip
## book learns their orders.
func _on_loaded(_vehicle_id: StringName, boxes: Array[StringName]) -> void:
	for box_id: StringName in boxes:
		_loaded[box_id] = true
	_bridge(boxes)


## Stop-gap until the trips share the order book (rows 17, 19 and 20 of red-autoridad.md, D-0302.2.b.3):
## CompanyTrips keeps its own book, empty in the live game, so a trip would not know the orders it carries.
## The loaded orders are copied there as PACKED with their box (the shared book is not written).
func _bridge(boxes: Array[StringName]) -> void:
	if trips == null or net == null:
		return
	for box_id: StringName in boxes:
		var order_id: StringName = _order_of.get(box_id, &"")
		if order_id == &"":
			continue
		if not trips.book.has(order_id):
			trips.book.add(net.orders.book.get_order(order_id))
		var state: StringName = trips.book.state_of(order_id)
		if state == Order.STATE_OPEN or state == Order.STATE_LATE:
			trips.book.mark_packed(order_id, box_id)


func _on_station_opened(station: StringName) -> void:
	if station == DispatchStation.ID:
		open()


func _on_closed() -> void:
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null
	set_process(false)


func _catalog_in_use() -> CompanyCatalog:
	if fleet != null and is_instance_valid(fleet) and fleet.catalog != null:
		return fleet.catalog
	if _catalog == null:
		_catalog = CompanyCatalog.load_all()
	return _catalog


func _zones_by_id() -> Dictionary:
	if _zones.is_empty():
		for zone: ZoneDefinition in _catalog_in_use().zones():
			_zones[zone.id] = zone
	return _zones


func _gates_by_id() -> Dictionary:
	if _gates.is_empty():
		for gate: Resource in _catalog_in_use().all(CompanyCatalog.GATES):
			_gates[StringName(gate.get(&"id"))] = gate
	return _gates
