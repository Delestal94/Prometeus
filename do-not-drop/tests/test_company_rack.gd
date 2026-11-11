extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_rack.gd
##
## What really rides on a fleet vehicle, against what is_loaded and the mounts say (expansion D-0302.2.b.3, D-0717.b;
## DispatchRack, CompanyDispatch, CompanyTrips.left_behind, CompanyTripsView), in the solo company_root.tscn with two
## vans. test_company_departure drives the plain way; here is everything that can go wrong around it.
## - The board was opened and the world moved before "Load": of four picked boxes, one whose package went, one in hands
##   and one on the other van's rack don't go. They leave the cargo with their order, the box on the other rack stays
##   there, the board's line and confirm() say 1, and the box put down again is listed.
## - A rack that fills up while the board is open loads nothing, the van is offered again and the line says 0.
## - The board's signature changes with the vehicle's room, so an open board doesn't offer a place that is gone.
## - DispatchRack.rides() is the bay, not is_loaded: a box that fell off with is_loaded still true doesn't ride and its
##   mount counts as free, a box off its mount on the bay's floor rides, a box moved to the other van's rack doesn't
##   ride on the first. left_behind() follows that, with the vehicle it is asked about.
## - With hold_at_gate off, _on_departed() alone decides: the trip takes only what rides, a LATE order among them goes
##   OUT in the shared book with its box, and the orders of the boxes that stayed keep waiting.
## - A box lost on the way lets its mount go when the trip closes, on is_loaded too, and the order of a box that came
##   back fails. store() takes a mount from a box that fell off, and the board's read frees one that lies in the zone
##   and lists it again.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_rack"
const HEN: ProductDefinition = preload("res://data/products/hen.tres")
const VAN: StringName = &"van_classic"
const VAN_2: StringName = &"van_classic_2"
const MOUNTS: int = 7

var _failures: int = 0
var _boxes: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	for _tick: int in range(30):
		await physics_frame
	state.set(&"fleet", [{"id": VAN}, {"id": VAN}] as Array[Dictionary])
	level.fleet.build(state)
	var dispatch := level.get_node_or_null(^"Dispatch") as CompanyDispatch
	var van: Node3D = level.fleet.vehicle(String(VAN))
	var other: Node3D = level.fleet.vehicle(String(VAN_2))
	_expect(dispatch != null and van != null and other != null, "The world has its board and two vans")
	if dispatch != null and van != null and other != null:
		await physics_frame
		await _check_stale_board(level, dispatch, van, other)
		await _check_full_rack(level, dispatch, other)
		await _check_what_rides(level, dispatch, van, other)
	level.queue_free()
	current_scene = null
	await process_frame
	state.call(&"reset")
	_clean()
	if _failures == 0:
		print("PASS: what rides is what is in the bay: only that leaves, a stale board loads what it can and says so,"
			+ " and a box lost on the way gives its mount back")
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


## A sealed box lying still in the zone, with its order `order_id` in the shared book. Returns its package.
func _box(level: CompanyRoot, order_id: StringName) -> DeliveryPackage:
	var products: Dictionary = {&"hen": HEN}
	level.net.orders.book.add(Order.make(order_id, "Cliente", &"centro", &"centro_house_1",
		[{"product": &"hen", "qty": 1}], floori(level.clock.minute_now()), products))
	var box := PackedBox.new(&"M")
	box.place(HEN, Vector3i.ZERO)
	box.taped = true
	box.label_order_id = order_id
	var package: DeliveryPackage = BoxToPackage.build(box, products)
	level.packages.add_child(package)
	package.freeze = true
	var area: AABB = CompanyDispatch.area_of(level.shed)
	package.global_position = area.get_center() + Vector3(-1.0 + 0.4 * (_boxes % 6), 0.0, -1.0 + 0.4 * (_boxes / 6))
	_boxes += 1
	return package


## `orders` get their boxes, the board picks them all. The board is left open.
func _open_with(level: CompanyRoot, dispatch: CompanyDispatch, orders: Array[StringName]) -> Dictionary:
	var made: Dictionary = {}
	for order_id: StringName in orders:
		made[order_id] = _box(level, order_id)
	_expect(dispatch.open(), "The board opens")
	await process_frame
	for order_id: StringName in orders:
		var box_id: StringName = StringName("box_" + str(order_id))
		_expect(dispatch.panel.toggle(box_id)["ok"], "%s is picked" % box_id)
	return made


## Four boxes picked; three stop being loadable before "Load".
func _check_stale_board(level: CompanyRoot, dispatch: CompanyDispatch, van: Node3D, other: Node3D) -> void:
	var made: Dictionary = await _open_with(level, dispatch, [&"a1", &"a2", &"a3", &"a4"] as Array[StringName])
	var gone: DeliveryPackage = made[&"a2"]
	gone.free()
	var held: DeliveryPackage = made[&"a3"]
	PackageHandling.set_held(held, true)
	var elsewhere: DeliveryPackage = made[&"a4"]
	var mine: Array[StringName] = [&"box_a4"]
	_expect(DispatchRack.store(other, level.packages, mine) == mine, "The other van took box_a4 by hand")
	_expect(dispatch.panel.confirm() == 1, "Only one of the four went")
	_expect(dispatch.panel.status_text() == tr("UI_DISPATCH_LOADED") % 1,
		"The board's line says one (%s)" % dispatch.panel.status_text())
	dispatch.panel.close()
	var staged: Dictionary = level.trips._staged.get(VAN, {})
	_expect(staged.get("boxes", []) == [&"box_a1"] and staged.get("orders", []) == [&"a1"],
		"Only box_a1 is staged, with its order (%s)" % [staged])
	_expect((made[&"a1"] as DeliveryPackage).is_loaded and DispatchRack.free_mounts(van).size() == MOUNTS - 1,
		"box_a1 is on the van's rack")
	_expect(dispatch._loaded.keys() == [&"box_a1"], "Only box_a1 counts as loaded (%s)" % [dispatch._loaded])
	_expect(not held.is_loaded and not level.trips.book.has(&"a3") and not level.trips.book.has(&"a4"),
		"The box in hands stayed in hands, and the trip book doesn't know the orders that stayed")
	_expect(other.is_ancestor_of(elsewhere.current_mount),
		"A box already on a rack doesn't jump to the vehicle on the board")
	PackageHandling.set_held(held, false)
	held.freeze = true
	_expect(dispatch.scan().boxes().has(&"box_a3"), "Put down again, its box is listed")


## The second van's rack fills up behind the board's back.
func _check_full_rack(level: CompanyRoot, dispatch: CompanyDispatch, other: Node3D) -> void:
	_expect(dispatch.available_vehicle() == other, "With the first van loaded the board offers the second")
	var made: Dictionary = await _open_with(level, dispatch, [&"b1"] as Array[StringName])
	var before: String = dispatch._signature_of(dispatch.context())
	var fillers: Array[StringName] = []
	for index: int in range(MOUNTS - 1):
		var filler: DeliveryPackage = _box(level, StringName("fill_%d" % index))
		fillers.append(filler.package_id)
		_expect(DispatchRack.store(other, level.packages, [filler.package_id] as Array[StringName]).size() == 1,
			"%s fills a mount" % filler.package_id)
		if index == 0:
			_expect(dispatch._signature_of(dispatch.context()) != before, "The board's signature follows the room left")
	_expect(DispatchRack.free_mounts(other).is_empty(), "The second van's rack is full")
	_expect(dispatch.panel.confirm() == 0, "A full rack takes nothing")
	_expect(dispatch.panel.status_text() == tr("UI_DISPATCH_LOADED") % 0,
		"The board's line says none (%s)" % dispatch.panel.status_text())
	dispatch.panel.close()
	_expect(not level.trips.has_cargo(VAN_2) and not (made[&"b1"] as DeliveryPackage).is_loaded,
		"Nothing is staged on it, and the box stays down")
	_expect(not dispatch._loaded.has(&"box_b1"), "box_b1 doesn't count as loaded")
	_expect(dispatch.scan().boxes().has(&"box_b1"), "...and it is listed again")
	for box_id: StringName in fillers:
		var filler: DeliveryPackage = DispatchRack.package_of(level.packages, box_id)
		filler.release_mount()
		filler.free()
	_expect(DispatchRack.free_mounts(other).size() == MOUNTS - 1, "The second van has room again")


## Moves `van` to `to` (flat), as driving there would, with the boxes that ride on it.
func _carry(van: Node3D, riding: Array[DeliveryPackage], to: Vector3) -> void:
	var local: Array[Vector3] = []
	for package: DeliveryPackage in riding:
		local.append(van.to_local(package.global_position))
	van.global_position = Vector3(to.x, van.global_position.y, to.z)
	for index: int in riding.size():
		riding[index].global_position = van.to_global(local[index])
		riding[index].linear_velocity = Vector3.ZERO
		riding[index].reset_physics_interpolation()
	await physics_frame
	await physics_frame


func _check_what_rides(level: CompanyRoot, dispatch: CompanyDispatch, van: Node3D, other: Node3D) -> void:
	var order_ids: Array[StringName] = [&"c1", &"c2", &"c3", &"d1"]
	var made: Dictionary = {}
	for order_id: StringName in order_ids:
		made[order_id] = _box(level, order_id)
	var shared: OrderBook = level.net.orders.book
	var due: int = int(shared.get_order(&"d1")["due_min"])
	_expect(shared.expire_one(&"d1", due + 1) and shared.state_of(&"d1") == Order.STATE_LATE, "Setup: d1 is late")
	var boxes: Array[StringName] = [&"box_c1", &"box_c2", &"box_c3", &"box_d1"]
	dispatch.scan()
	var cargo: Array[StringName] = (level.trips._staged[VAN]["boxes"] as Array[StringName]).duplicate()
	cargo.append_array(boxes)
	var orders: Array[StringName] = (level.trips._staged[VAN]["orders"] as Array[StringName]).duplicate()
	orders.append_array(order_ids)
	level.trips.stage_cargo(VAN, orders, cargo)
	dispatch._on_loaded(VAN, boxes)
	_expect(DispatchRack.free_mounts(van).size() == MOUNTS - 5, "Five boxes are on the rack")
	for _tick: int in range(10):
		await physics_frame

	var fell: DeliveryPackage = made[&"c1"]
	fell.freeze = true
	fell.global_position = van.to_global(Vector3(0.0, 0.5, 9.0))
	_expect(fell.is_loaded and fell.is_aboard(), "A box that fell off still says it is loaded")
	_expect(not DispatchRack.rides(van, fell) and DispatchRack.free_mounts(van).size() == MOUNTS - 4,
		"...it doesn't ride and its mount counts as free")
	var floor_box: DeliveryPackage = made[&"c2"]
	floor_box.release_mount()
	floor_box.global_position = van.to_global(Vector3(0.0, 0.4, 2.0))
	_expect(not floor_box.is_aboard() and DispatchRack.rides(van, floor_box),
		"A box off its mount on the bay's floor rides")
	var moved: DeliveryPackage = made[&"c3"]
	moved.release_mount()
	_expect(DispatchRack.store(other, level.packages, [&"box_c3"] as Array[StringName]).size() == 1,
		"box_c3 goes to the other van by hand")
	_expect(moved.is_aboard() and not DispatchRack.rides(van, moved) and DispatchRack.rides(other, moved),
		"...and rides on that one")
	_expect(dispatch.left_behind(VAN, &"box_c1") and not dispatch.left_behind(VAN, &"box_c2")
		and dispatch.left_behind(VAN, &"box_c3"), "left_behind() answers for the vehicle it is asked about")
	_expect(not dispatch.left_behind(VAN, &"box_never_loaded"), "...and has no say on a box the board did not load")
	_expect(not dispatch.left_behind(VAN, &"box_a1"), "box_a1 still rides")

	# Nobody opens the board and the gate doesn't hold: _on_departed() is the only one that looks.
	level.trips.hold_at_gate = false
	var riding: Array[DeliveryPackage] = [DispatchRack.package_of(level.packages, &"box_a1"), floor_box, made[&"d1"]]
	var exit: Vector3 = CompanyFleet.gate_of(level.shed, level.net.company)
	var outward: Vector3 = -level.shed.global_basis.z
	await _carry(van, riding, exit - outward)
	await _carry(van, riding, exit + outward * 3.0)
	var trip: Trip = level.trips.trip_of(VAN)
	_expect(trip != null, "Crossing the gate started the trip")
	if trip == null:
		return
	_expect(trip.box_ids == ([&"box_a1", &"box_c2", &"box_d1"] as Array[StringName])
		and trip.order_ids == ([&"a1", &"c2", &"d1"] as Array[StringName]),
		"Only what rides left (boxes %s, orders %s)" % [trip.box_ids, trip.order_ids])
	_expect(shared.state_of(&"d1") == Order.STATE_OUT and shared.box_of(&"d1") == &"box_d1",
		"The late order is out with its box (%s)" % [shared.get_order(&"d1")])
	_expect(shared.state_of(&"c1") == Order.STATE_OPEN and shared.state_of(&"c3") == Order.STATE_OPEN,
		"The boxes that stayed keep their orders waiting (%s, %s)" % [shared.state_of(&"c1"), shared.state_of(&"c3")])

	# On the way a box falls out; back in the yard the trip closes and it gives the mount back.
	var lost: DeliveryPackage = riding.pop_back()
	lost.freeze = true
	lost.global_position = van.to_global(Vector3(0.0, 0.5, 30.0))
	var home: Vector3 = CompanyFleet.park_transform(level.shed, level.net.company, 0).origin
	await _carry(van, riding, home)
	await physics_frame
	_expect(level.trips.trip_of(VAN) == null and level.trips.trips_out() == 0, "Back in the yard the trip closed")
	_expect(not lost.is_loaded and not lost.is_aboard() and not fell.is_loaded,
		"A box that fell is not loaded any more")
	_expect(shared.state_of(&"a1") == Order.STATE_FAILED and shared.state_of(&"d1") == Order.STATE_FAILED,
		"Their orders failed in the shared book")
	var rest: Array[Node] = DispatchRack.free_mounts(van)
	var empty: bool = rest.all(func(mount: Node) -> bool: return mount.get(&"occupied_by") == null)
	_expect(rest.size() == MOUNTS - 1 and empty,
		"The mounts really are free: only box_a1 is on the rack (%d free)" % rest.size())
	_expect((riding[0] as DeliveryPackage).is_loaded, "...which still is")

	# A box that fell while the van stands, its trip long closed: store() takes the mount from it.
	var dropped: DeliveryPackage = riding[0]
	dropped.freeze = true
	dropped.global_position = van.to_global(Vector3(0.0, 0.5, 9.0))
	var next: DeliveryPackage = _box(level, &"e1")
	var taken: Node = dropped.current_mount
	_expect(DispatchRack.store(van, level.packages, [&"box_e1"] as Array[StringName]).size() == 1,
		"The next box finds room")
	_expect(not dropped.is_loaded and next.is_loaded and taken.get(&"occupied_by") != dropped,
		"...and the box that fell lets its mount go")

	# Loaded, then knocked off into the zone itself, still loaded: the board reads it as any other box.
	var knocked: DeliveryPackage = _box(level, &"f1")
	var spot: Vector3 = knocked.global_position
	dispatch.scan()
	level.trips.stage_cargo(VAN, [&"f1"] as Array[StringName], [&"box_f1"] as Array[StringName])
	dispatch._on_loaded(VAN, [&"box_f1"] as Array[StringName])
	await physics_frame
	knocked.freeze = true
	knocked.global_position = spot
	_expect(knocked.is_loaded, "Setup: the box knocked off still says it is loaded")
	_expect(dispatch.scan().boxes().has(&"box_f1"), "The board lists it again")
	_expect(not knocked.is_loaded and not dispatch._loaded.has(&"box_f1") and not level.trips.has_cargo(VAN),
		"...off its mount and off the cargo")
