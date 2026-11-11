class_name TripCargo
extends Node
## The boxes of a company trip as the packages they are (expansion D-0710.d).
##
## CompanyTrips knows a box only as an id and the company's world starts no delivery run, so a box out on a trip
## was a box on a shelf: its trap never ran and nothing wore it, however it was packed. This node ties the two,
## over the packages under World/Packages (a taped box is a DeliveryPackage named by its box id, D-0715.b). Child
## "TripCargo" of CompanyRoot on every peer (CompanyDispatch.add_to() adds it: it holds the packages, the trips
## and the view). No RPC and no event: each peer marks its own copies from what it already knows.
## - While a trip is out its boxes carry PackageHandling.ON_TRIP_META, so they live as in a delivery run
##   (DeliveryPackage._is_run_active()). The host marks them as its CompanyTrips starts and closes the trip (the
##   authority: the trap, the hits and the care are simulated there, and the integrity travels in the package's
##   own synchronizer). A client marks them from its CompanyTripsView (trip_started carries the boxes, and so does
##   a snapshot), so its copy shows what the box asks for and its player's hands reach it (PlayerCargoCare).
## - When a trip closes the host's CompanyTrips asks which of its boxes are broken (box_broken): is_broken().
##
## A box whose package is gone (handed over at a door) is neither marked nor broken.

## World/Packages: the DeliveryPackages of the sealed boxes.
var packages: Node
## The host's trips (null on a client), and the view every peer has.
var trips: CompanyTrips
var view: CompanyTripsView


## The trip cargo of a world, a child of `parent`: on the host it follows `company_trips` and answers its
## box_broken; with none (a client) it follows `trips_view`.
static func add_to(parent: Node, cargo: Node, company_trips: CompanyTrips, trips_view: CompanyTripsView) -> TripCargo:
	var made := TripCargo.new()
	made.name = "TripCargo"
	made.packages = cargo
	made.trips = company_trips
	made.view = trips_view
	parent.add_child(made)
	if company_trips != null:
		company_trips.box_broken = made.box_broken
		company_trips.trip_started.connect(made._on_trip_started)
		company_trips.trip_closed.connect(made._on_trip_closed)
	elif trips_view != null:
		trips_view.changed.connect(made.follow_view)
		# A box sealed or restored after the view last changed (a snapshot can bring the packages after the trips).
		if cargo != null:
			cargo.child_entered_tree.connect(made._on_package_added)
	return made


func _exit_tree() -> void:
	if trips != null and is_instance_valid(trips) and trips.box_broken == box_broken:
		trips.box_broken = Callable()


## A box that lost what it carried: its package is ruined (lost for good), or its contents are out and nobody put
## them back (a rescue still pending). False for no package.
static func is_broken(package: DeliveryPackage) -> bool:
	if package == null or not is_instance_valid(package):
		return false
	return package.trap_state == ITrapBehavior.TrapState.RUINED or package.care.needs_restore


## Marks the packages of `box_ids` under `cargo` as out on a trip, or back (PackageHandling.set_on_trip()).
static func mark(cargo: Node, box_ids: Array[StringName], on: bool) -> void:
	for box_id: StringName in box_ids:
		var package: DeliveryPackage = DispatchRack.package_of(cargo, box_id)
		if package != null:
			PackageHandling.set_on_trip(package, on)


## Host, CompanyTrips.box_broken: whether the package of `box_id` is broken now.
func box_broken(box_id: StringName) -> bool:
	return is_broken(DispatchRack.package_of(packages, box_id))


## A client, after every trip event and after a snapshot: its packages are out on a trip exactly when a vehicle
## its view shows out carries them.
func follow_view() -> void:
	if view == null or packages == null or not is_instance_valid(packages):
		return
	var out: Dictionary = {}
	for vehicle_id: StringName in view.vehicles_out():
		for box_id: Variant in view.trip_of(vehicle_id).get("boxes", []):
			out[StringName(box_id)] = true
	for child: Node in packages.get_children():
		var package := child as DeliveryPackage
		if package != null:
			PackageHandling.set_on_trip(package, out.has(package.package_id))


## A client: a package that came in is marked once its id is set (deferred: the maker names it before or right
## after add_child).
func _on_package_added(node: Node) -> void:
	if node is DeliveryPackage:
		follow_view.call_deferred()


func _on_trip_started(trip: Trip) -> void:
	mark(packages, trip.box_ids, true)


func _on_trip_closed(trip: Trip, _failed: Array[StringName]) -> void:
	mark(packages, trip.box_ids, false)
