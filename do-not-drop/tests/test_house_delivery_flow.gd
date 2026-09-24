extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_house_delivery_flow.gd
##
## The loop this project is named after, end to end: load a box in the van,
## take it back out at a stop, ring a resident's doorbell, and have that
## actually be worth something. Every one of those steps was broken or
## unscored before -- package_pickup_point.gd refused to release a loaded
## box, so no package could ever leave the van, so every house on the route
## resolved as "missed", and nothing listened to route.house_resolved
## anyway. This test exists so that can't silently come back.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var manager: Node = root.get_node("RunManager")
	var route: Node = level.get_node("World/Route")
	var player: Node = level.local_player
	var vehicle: Node = level.get_node("World/Vehicle")
	# The box the first house ordered, as the board says.
	var package: Node = _ordered_package(level)
	var pickup: Node = package.get_node("InteractionArea")
	var mount: Node = vehicle.get_node("CargoBay/LeftShelfPackageMount/InteractionArea")
	var seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	vehicle.call(&"set_door_open", &"cab_left", true)  # The seat is behind the cab door.
	var package_id: StringName = StringName(package.get(&"package_id"))

	# --- load it, start the run, then take it back out at the stop ---
	pickup.interact(player)
	mount.interact(player)
	seat.interact(player)
	_expect(manager.is_running, "The run starts once the van is loaded and crewed")
	_expect(manager.cargo.has(package_id), "The loaded box is tracked as cargo")

	pickup.interact(player)
	_expect(player.carried_package == package, "A loaded box can be taken out at a stop")
	_expect(not bool(package.get(&"is_loaded")), "Taking it out stops it counting as loaded cargo")
	_expect(mount.get(&"occupied_by") == null, "The shelf slot it came from is free again")

	# A box in someone's hands is not a box that fell off the van: the
	# lost-cargo watchdog keys off the van's own distance, and walking 12 m
	# to a front door would trip it instantly if it didn't skip held boxes.
	player.set(&"global_position", vehicle.get(&"global_position") + Vector3(0.0, 0.0, 30.0))
	level._check_lost_cargo()
	_expect(int(manager.cargo[package_id]["state"]) != ITrapBehavior.TrapState.RUINED,
		"Carrying a box away from the van doesn't count as losing it")

	# --- ring the first door with it ---
	var houses: Array = route.get(&"houses")
	_expect(houses.size() > 0, "The route built at least one house to deliver to")
	var house: Node = houses[0]
	house.get(&"doorbell").interact(player)
	await process_frame

	_expect(bool(house.get(&"delivered")), "The house registers the delivery")
	_expect(manager.deliveries.size() == 1, "RunManager recorded exactly one delivery (got %d)" % manager.deliveries.size())
	var record: Dictionary = manager.deliveries[0]
	_expect(StringName(record["outcome"]) == &"delivered_ok", "An intact box delivers as delivered_ok (got %s)" % record["outcome"])
	_expect(StringName(record["package_id"]) == package_id, "The record names the package that was handed over")
	_expect(bool(manager.cargo[package_id].get("delivered", false)),
		"A delivered box stops counting as cargo still aboard")

	# --- the photo is a bonus, and it only files against a real delivery ---
	_expect(not bool(record["photo"]), "A delivery starts with no photo filed against it")
	_expect(manager.attach_delivery_photo(0), "A photo files against the door that was just delivered to")
	_expect(bool(manager.deliveries[0]["photo"]), "The record keeps the photo")
	_expect(not manager.attach_delivery_photo(0), "The same door can't be photographed twice for double bonus")
	_expect(not manager.attach_delivery_photo(99), "Photographing a door nobody delivered to files nothing")

	# --- score it ---
	var unrung: int = houses.size() - 1
	manager.finish_run(true)
	var results: Dictionary = manager.results
	_expect(bool(results["delivered"]), "Delivering at a door counts as a successful run")
	_expect(int(results["houses_delivered"]) == 1, "Results report one door delivered (got %d)" % int(results["houses_delivered"]))
	_expect(int(results["houses_missed"]) == unrung, "Every house nobody rang is reported as missed (got %d, expected %d)" % [int(results["houses_missed"]), unrung])
	_expect(int(results["photos"]) == 1, "Results report the photo taken")
	var expected: int = manager.POINTS_DELIVERED_INTACT + manager.POINTS_PHOTO_BONUS - unrung * manager.PENALTY_MISSED_HOUSE
	_expect(int(results["delivery_points"]) == expected,
		"Door points = intact delivery + photo - missed houses (got %d, expected %d)" % [int(results["delivery_points"]), expected])
	_expect(int(results["score"]) > 0, "A delivered run scores above zero")

	level.free()
	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: a box can leave the van, reach a door, and be worth points -- photo included")
	quit(failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1


## The box the depot's board says the first house ordered (depot.gd): the
## one a crew would actually walk up to that door.
func _ordered_package(level: Node) -> Node:
	var wanted: StringName = StringName(level.get(&"depot").get(&"orders")[0]["package_id"])
	for candidate: Node in level.get(&"packages"):
		if StringName(candidate.get(&"package_id")) == wanted:
			return candidate
	return null
