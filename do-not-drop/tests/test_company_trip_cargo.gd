extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trip_cargo.gd
##
## The traps run on the company's trips (expansion D-0710.d, trip_cargo.gd, PackageHandling.on_trip(),
## CompanyTrips.broken_boxes(), Trip.broken_ids), with no delivery run going (RunManager.is_running false):
## - in a real CompanyRoot (solo = host) CompanyDispatch adds TripCargo, which answers CompanyTrips.box_broken;
## - a box on the shelf, before its trip leaves, is a box on a shelf: a hit, a running step and the ticks do
##   nothing to it (DeliveryPackage._is_run_active() false);
## - once its vehicle crosses the gate outward its boxes carry ON_TRIP_META and live as cargo in a run: the same
##   hit takes more off a box packed at the high level (bare glass) than off one packed low (padded), a running
##   step (PackageRunShake.jolt) wears it and the cargo tick (_simulate_cargo) runs on it; a milestone earned on it
##   pays no classic campaign merit (PackageTending.award_milestone refuses a trip box with no delivery run);
## - the box that broke on the road is in Trip.broken_ids when the trip comes back through the gate (and the sound
##   one is not), its trip_closed listeners read it there, and the boxes are off the trip again (a hit does nothing);
## - a trip closed by a tow (CompanyTrips.tow()) or by its vehicle leaving the world (forget()) also tells its
##   broken boxes; with nobody answering box_broken a trip closes with none;
## - a client (no CompanyTrips, only a CompanyTripsView) marks its copies from the view: a box of a trip that started
##   is on it, a box sealed after the view changed is marked when it comes in, and both come off when the trip
##   closes; PlayerCargoCare.cared_for() lets the card and the care input live for a box on a trip with no run.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const CARGO_CARE := preload("res://scripts/gameplay/player/player_cargo_care.gd")
const RUN_SHAKE := preload("res://scripts/gameplay/package/package_run_shake.gd")
const HIT: float = 8.0
const SAVE_DIR: String = "user://test_company_trip_cargo"

var _failures: int = 0


class Wallet:
	extends RefCounted
	func can_afford(_cost: int) -> bool:
		return true

	func spend(_cost: int, _reason: StringName) -> bool:
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run_manager: Node = root.get_node(^"/root/RunManager")
	_expect(run_manager != null and not bool(run_manager.get(&"is_running")), "No delivery run is going")
	await _test_root()
	await _test_other_closes()
	await _test_client()
	if _failures == 0:
		print("PASS: a badly packed box suffers on a company trip, and the broken one reaches the trip's close")
	quit(_failures)


func _test_root() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level: CompanyRoot = (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate()
	level.save_dir = SAVE_DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var trips: CompanyTrips = level.get(&"trips")
	var cargo: TripCargo = level.get_node_or_null(^"TripCargo") as TripCargo
	_expect(trips != null and cargo != null and cargo.trips == trips and trips.box_broken.is_valid(),
		"The host root has a TripCargo answering its CompanyTrips' box_broken (got %s)" % cargo)
	if trips == null or cargo == null:
		level.queue_free()
		await process_frame
		return
	var packages: Node = level.get(&"packages")
	var bare: DeliveryPackage = _package(packages, &"t1", 0)
	var padded: DeliveryPackage = _package(packages, &"t2", 19)
	await physics_frame
	var high: float = BoxTrap.severity(BoxTrap.LEVEL_HIGH)
	_expect(is_equal_approx(bare.trap_behavior.severity, high) and is_equal_approx(padded.trap_behavior.severity, 1.0),
		"Bare glass is packed high, padded glass low (got %.2f and %.2f)"
		% [bare.trap_behavior.severity, padded.trap_behavior.severity])
	# On the shelf, before the trip: nothing wears it.
	bare.apply_impact(HIT)
	RUN_SHAKE.jolt(bare, 1.0)
	for _tick: int in range(5):
		await physics_frame
	_expect(not bare._is_run_active() and is_equal_approx(bare.integrity, 100.0) and is_zero_approx(bare.care.elapsed),
		"Before its trip a box is not cargo: a hit, a step and the ticks leave it whole (got %.1f, %.2f s)"
		% [bare.integrity, bare.care.elapsed])
	var closed: Array = []
	trips.trip_closed.connect(func(t: Trip, _f: Array[StringName]) -> void: closed.append(t.broken_ids.duplicate()))
	_packed(trips, [&"t1", &"t2"])
	trips.stage_cargo(&"test_van", [&"t1", &"t2"], [&"box_t1", &"box_t2"])
	var half_depth: float = CompanyRoot.SHED_SIZE.y * 0.5
	var edge: float = half_depth + CompanyShed.WALL_THICKNESS + CompanyFleet.PLAYON_DEPTH_M
	var inside := Vector3(0, 0, -edge + 1.0)
	var outside := Vector3(0, 0, -edge - 2.0)
	trips.track(&"test_van", inside)
	_expect(trips.track(&"test_van", outside) == &"departed" and trips.trip_of(&"test_van") != null,
		"The van crosses the gate outward and its trip starts")
	_expect(PackageHandling.on_trip(bare) and PackageHandling.on_trip(padded) and bare._is_run_active()
		and bare._registered_for_run(), "Its boxes are out on the trip and live as cargo")
	# The same hit.
	var bare_before: float = bare.integrity
	var padded_before: float = padded.integrity
	bare.apply_impact(HIT)
	padded.apply_impact(HIT)
	var bare_lost: float = bare_before - bare.integrity
	var padded_lost: float = padded_before - padded.integrity
	_expect(bare_lost > 0.0 and bare_lost > padded_lost,
		"The same hit takes more off the box packed high than off the one packed low (got %.1f vs %.1f)"
		% [bare_lost, padded_lost])
	var stepped: float = padded.integrity
	RUN_SHAKE.jolt(padded, 1.0)
	_expect(padded.integrity < stepped, "A running step wears a box on a trip (got %.2f -> %.2f)"
		% [stepped, padded.integrity])
	# A save on a trip is not the classic campaign's merit (no delivery run).
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var merit_before: Dictionary = (crew.get(&"merit") as Dictionary).duplicate()
	_expect(not padded._award_milestone(1, &"rescued") and (crew.get(&"merit") as Dictionary) == merit_before,
		"A milestone on a trip box pays no campaign merit (got %s)" % [crew.get(&"merit")])
	# The road keeps hitting the bare box before any tick (a solo crew's rack assistant steadies the boxes from
	# the first tick on, which softens hits as it does in a run).
	for _hit: int in range(60):
		if TripCargo.is_broken(bare):
			break
		bare.apply_impact(9.0)
	_expect(TripCargo.is_broken(bare) and not TripCargo.is_broken(padded),
		"Hit again and again the bare box breaks, the padded one did not (state %d, %d)"
		% [bare.trap_state, padded.trap_state])
	for _tick: int in range(5):
		await physics_frame
	_expect(padded.care.elapsed > 0.0, "The cargo tick runs on a box on a trip (care %.2f s)" % padded.care.elapsed)
	trips.track(&"test_van", inside)
	_expect(closed.size() == 1 and (closed[0] as Array[StringName]) == _ids([&"box_t1"]),
		"The broken box reaches the trip's close through the gate, the sound one does not (got %s)" % [closed])
	_expect(not PackageHandling.on_trip(bare) and not PackageHandling.on_trip(padded),
		"Back in, its boxes are off the trip")
	var resting: float = padded.integrity
	padded.apply_impact(HIT)
	_expect(is_equal_approx(padded.integrity, resting), "Back on the shelf a hit does nothing (got %.2f -> %.2f)"
		% [resting, padded.integrity])
	# Off the trip the same call reaches CrewProgression (so the refusal above was the trip's, not a dead path).
	_expect(padded._award_milestone(1, &"rescued"), "Off the trip the milestone call still reaches CrewProgression")
	crew.call(&"reset_campaign", false)
	level.queue_free()
	await process_frame
	state.call(&"reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


## A tow and a vehicle that leaves the world close with the broken boxes too; nobody asked, none.
func _test_other_closes() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var packages := Node3D.new()
	holder.add_child(packages)
	var broken: DeliveryPackage = _package(packages, &"b1", 0)
	var whole: DeliveryPackage = _package(packages, &"b2", 19)
	await physics_frame
	broken.mark_lost("HUD_PACKAGE_RUINED_RUNNING")
	var trips := CompanyTrips.new()
	trips.setup(Vector3(0, 0, -4), 2.0)
	holder.add_child(trips)
	TripCargo.add_to(holder, packages, trips, null)
	_packed(trips, [&"b1", &"b2", &"b3", &"b4", &"b5", &"b6"])
	var trip: Trip = _depart(trips, &"tow_van", [&"b1", &"b2"])
	_expect(PackageHandling.on_trip(broken) and PackageHandling.on_trip(whole), "Both boxes go out with the tow van")
	var towed: Dictionary = trips.tow(&"tow_van", TripTow.VEHICLE_STUCK, Wallet.new())
	_expect(bool(towed.get("ok", false)) and trip != null and trip.broken_ids == _ids([&"box_b1"]),
		"A tow closes the trip with its broken box (got %s)" % [trip.broken_ids if trip != null else null])
	_expect(not PackageHandling.on_trip(broken) and not PackageHandling.on_trip(whole),
		"A towed trip's boxes are off it")
	var gone: Trip = _depart(trips, &"gone_van", [&"b3", &"b4"], [&"box_b1", &"box_b2"])
	_expect(PackageHandling.on_trip(broken), "A box out again is on the trip again")
	trips.forget(&"gone_van")
	_expect(gone != null and gone.broken_ids == _ids([&"box_b1"]),
		"A trip whose vehicle left the world closes with its broken box (got %s)"
		% [gone.broken_ids if gone != null else null])
	trips.box_broken = Callable()
	var unasked: Trip = _depart(trips, &"plain_van", [&"b5", &"b6"])
	trips.track(&"plain_van", Vector3(0, 0, -2))
	_expect(unasked != null and unasked.broken_ids.is_empty(),
		"With nobody answering box_broken a trip closes with none broken")
	holder.queue_free()
	await process_frame


## A client follows its CompanyTripsView: no CompanyTrips, no RPC of its own.
func _test_client() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var packages := Node3D.new()
	holder.add_child(packages)
	var first: DeliveryPackage = _package(packages, &"c1", 0)
	var view := CompanyTripsView.new()
	holder.add_child(view)
	TripCargo.add_to(holder, packages, null, view)
	await physics_frame
	_expect(not CARGO_CARE.cared_for(false, first), "With no run and no trip the card leaves a box alone")
	var started: bool = view.apply_trip(CompanyTripsView.STARTED, {"trip": "trip_1", "vehicle": "van",
		"orders": ["c1", "c2"], "boxes": ["box_c1", "box_c2"], "minute": 480})
	_expect(started and PackageHandling.on_trip(first), "A client's box is on the trip its view shows out")
	_expect(CARGO_CARE.cared_for(false, first), "The card and the care input live for a box on a trip, with no run")
	var late: DeliveryPackage = _package(packages, &"c2", 0)
	await process_frame
	_expect(PackageHandling.on_trip(late), "A box sealed after the view changed is marked when it comes in")
	var back: bool = view.apply_trip(CompanyTripsView.CLOSED, {"trip": "trip_1", "vehicle": "van", "failed": [],
		"minute": 540})
	_expect(back and not PackageHandling.on_trip(first) and not PackageHandling.on_trip(late),
		"The trip closed in the view: the client's boxes are off it")
	holder.queue_free()
	await process_frame


## `van` leaves with `orders` in `box_ids` (by default box_<order> each).
func _depart(trips: CompanyTrips, van: StringName, orders: Array[StringName], box_ids: Array[StringName] = []) -> Trip:
	var boxes: Array[StringName] = box_ids.duplicate()
	if boxes.is_empty():
		for order_id: StringName in orders:
			boxes.append(StringName("box_%s" % order_id))
	trips.stage_cargo(van, orders, boxes)
	trips.track(van, Vector3(0, 0, -2))
	trips.track(van, Vector3(0, 0, -6))
	return trips.trip_of(van)


## A taped glass box for order `order_id` (package box_<order_id>), frozen under `packages`: `padding` cells of
## padding (0: bare glass, packed high).
func _package(packages: Node, order_id: StringName, padding: int) -> DeliveryPackage:
	var box := PackedBox.new(&"M")
	box.place(VASE, Vector3i.ZERO)
	box.fill_free_cells(padding)
	box.taped = true
	box.label_order_id = order_id
	var order: Dictionary = {"id": order_id, "items": [{"product": &"porcelain_vase", "qty": 1}], "requirements": []}
	var package: DeliveryPackage = BoxToPackage.build(box, {&"porcelain_vase": VASE}, order)
	package.freeze = true
	packages.add_child(package)
	package.global_position = Vector3(40.0 + packages.get_child_count() * 2.0, 30.0, 40.0)
	return package


func _packed(trips: CompanyTrips, ids: Array[StringName]) -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in ids:
		trips.book.add(Order.make(id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
		trips.book.mark_packed(id, StringName("box_" + str(id)))


func _ids(ids: Array) -> Array[StringName]:
	var typed: Array[StringName] = []
	typed.assign(ids)
	return typed


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
