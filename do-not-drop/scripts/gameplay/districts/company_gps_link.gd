class_name CompanyGpsLink
extends Node
## Hooks each company vehicle's dashboard GPS to the road graph (expansion D-0308.1b), on every peer.
##
## The dashboard screen (DashboardGps) asks its guidance_provider for {distance, label, waypoint, house}; here
## it is answered by a CompanyGps per vehicle (each keeps its own planned path), fed with the vehicle's x, z, the
## stop its trip has next and the gates the company opened. Presentation only: the stop is read from what every
## peer holds, the trip's entry in the CompanyTripsView and the replicated OrderBook (next_stop()), not from the
## host's Trip, so a client's driver sees the same screen as the host's. Vehicles come and go (bought, recovered):
## the fleet is looked at every CHECK_SECONDS and a vehicle whose screen has no provider yet gets one.
## No autoload is named here (lesson N-919); the caller hands the pieces.

const CHECK_SECONDS: float = 1.0
const SCREEN_NAME: String = "DashboardGps"
## Orders that no longer wait at a door.
const SETTLED: Array[StringName] = [Order.STATE_DELIVERED, Order.STATE_FAILED, Order.STATE_CANCELLED]

var fleet: Node
var view: CompanyTripsView
var net: CompanyNet
var graph: RoadGraph
var houses: HouseMap
var addresses: HouseAddresses

var _timer: float = 0.0
var _linked: Dictionary = {}


static func add_to(
	parent: Node, company_fleet: Node, trips_view: CompanyTripsView, company_net: CompanyNet
) -> CompanyGpsLink:
	var link := CompanyGpsLink.new()
	link.name = "GpsLink"
	link.fleet = company_fleet
	link.view = trips_view
	link.net = company_net
	link.graph = RoadGraph.load_default()
	link.houses = HouseMap.load_default()
	link.addresses = HouseAddresses.load_default()
	parent.add_child(link)
	return link


## The next house a trip still has to visit: the first order of `entry` (CompanyTripsView.trip_of(), its "orders"
## in the order they were loaded) that has not been settled in `book`, by its house id. Empty when the vehicle is
## on no trip or nothing is left to deliver (the screen then points at the shed).
static func next_stop(entry: Dictionary, book: OrderBook) -> StringName:
	if entry.is_empty() or book == null:
		return &""
	for order_id: StringName in entry.get("orders", []):
		var order: Dictionary = book.get_order(order_id)
		if order.is_empty() or StringName(order.get("state", "")) in SETTLED:
			continue
		return StringName(order.get("house_id", ""))
	return &""


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_SECONDS
	link_vehicles()


## Gives every vehicle of the fleet whose screen has no provider the CompanyGps one. Returns how many it hooked.
func link_vehicles() -> int:
	if fleet == null or graph == null or houses == null:
		return 0
	var hooked: int = 0
	for vehicle: Node in fleet.get_children():
		var screen: Node = vehicle.find_child(SCREEN_NAME, true, false)
		if screen == null or _linked.get(vehicle.get_instance_id(), null) == screen.get_instance_id():
			continue
		var gps := CompanyGps.build(graph, houses, addresses)
		screen.set(&"guidance_provider", _guidance_of.bind(vehicle as Node3D, gps))
		_linked[vehicle.get_instance_id()] = screen.get_instance_id()
		hooked += 1
	return hooked


func _guidance_of(vehicle: Node3D, gps: CompanyGps) -> Dictionary:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return {}
	var gates: Array = []
	if net != null and net.company != null:
		gates = net.company.get(&"opened_gates")
	gps.open_locks = gates
	var book: OrderBook = net.book if net != null else null
	var stop: StringName = next_stop(view.trip_of(StringName(vehicle.name)) if view != null else {}, book)
	return gps.guidance_to(Vector2(vehicle.global_position.x, vehicle.global_position.z), stop)
