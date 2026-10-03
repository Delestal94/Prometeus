extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_delivery.gd
## town_delivery.gd: seeded offline district uses the real truck, packages,
## player and houses. Load, board, choose a different customer, reject a wrong
## package, hand over in arbitrary order, reboard and return to the depot.
## DashboardGps follows street waypoints; completion does not save a campaign.
## Authored client houses vary, keep their frontage and use the depot's rack.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/town/town_delivery.tscn")
	var level: Node3D = scene.instantiate()
	level.set(&"world_seed", 4242)
	root.add_child(level)
	current_scene = level
	await process_frame
	for frame: int in range(10):
		await physics_frame
	var manager: Node = root.get_node(^"RunManager")
	var vehicle: Node3D = level.get(&"vehicle")
	var player: Node3D = level.get(&"local_player")
	var houses: Array = level.get(&"houses")
	var packages: Array = level.get(&"packages")
	_expect(
		houses.size() == 3 and packages.size() == 3,
		"There are three real customers and packages (got %d/%d)" % [houses.size(), packages.size()]
	)
	_expect(not bool(manager.get(&"is_running")), "Preparation waits for the driver to board")
	var mounts: Array[String] = ["LeftShelf", "RightShelf", "LeftSeat1"]
	var variants: Dictionary = {}
	for house: Node3D in houses:
		variants[int(house.get(&"visual_variant"))] = true
	_expect(
		variants.size() == 3,
		"Each starting client uses a different authored house (got %s)" % variants
	)
	var depot: Node3D = level.get(&"town").get_node(^"depot_1")
	_expect(
		depot.get_node(^"LoadingRack").get_meta(&"model_sources").size() == 2,
		"Packages load from the original depot shelf pieces"
	)
	_expect(
		absf(vehicle.global_position.y - .866) < .03,
		"The frozen truck rests on asphalt before loading (got %f)" % vehicle.global_position.y
	)
	for index: int in range(packages.size()):
		var package: Node = packages[index]
		package.get_node(^"InteractionArea").call(&"interact", player)
		_expect(
			player.get(&"carried_package") == package,
			"An order can be picked up from its rack (got %s)" % player.get(&"carried_package")
		)
		var mount: Node = vehicle.get_node(
			"CargoBay/%sPackageMount/InteractionArea" % mounts[index]
		)
		mount.call(&"interact", player)
		_expect(
			bool(package.call(&"is_aboard")),
			"The real truck stores the order (got %s)" % package.get(&"current_mount_path")
		)
	var seat: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	seat.call(&"interact", player)
	_expect(bool(manager.get(&"is_running")), "Boarding starts the town delivery")
	_expect(
		not NodePath(player.get(&"seat_node_path")).is_empty(),
		"The player sits in the real driver seat"
	)
	_expect(
		manager.get(&"cargo").size() == 3,
		"All loaded packages are registered (got %s)" % manager.get(&"cargo")
	)
	var parked: Vector3 = vehicle.global_position
	Input.action_press(&"drive_accelerate")
	for frame: int in range(120):
		await physics_frame
	Input.action_release(&"drive_accelerate")
	_expect(
		vehicle.global_position.distance_to(parked) > 2,
		(
			"The boarded truck actually drives on the generated asphalt (got %s)"
			% vehicle.global_position
		)
	)
	vehicle.set(&"linear_velocity", Vector3.ZERO)
	vehicle.set(&"angular_velocity", Vector3.ZERO)
	level.call(&"select_house", 2)
	var guide: Dictionary = level.call(&"guidance")
	_expect(
		guide.house == 2 and guide.distance > 0,
		"Any pending customer can be selected (got %s)" % guide
	)
	var gps: Node = level.get(&"gps")
	_expect(gps != null, "The truck contains its actual dashboard GPS")
	if gps != null:
		gps.call(&"refresh")
		_expect(
			gps.get(&"target_house") == 2,
			"The physical GPS follows the chosen customer (got %s)" % gps.get(&"target_house")
		)
		gps.set(&"guidance_provider", func() -> Dictionary: return {})
		gps.call(&"refresh")
		_expect(
			not bool(gps.get(&"arrow").get(&"visible")),
			"An unreachable street route hides the guidance arrow"
		)
		gps.set(&"guidance_provider", Callable(level, &"guidance"))
		gps.call(&"refresh")
	player.call(&"leave_seat")
	packages[2].get_node(^"InteractionArea").call(&"interact", player)
	houses[0].get(&"doorbell").call(&"interact", player)
	_expect(
		not bool(houses[0].get(&"delivered")) and player.get(&"carried_package") == packages[2],
		"A wrong package leaves the customer's order open and stays in hand"
	)
	for index: int in [2, 0, 1]:
		if player.get(&"carried_package") != packages[index]:
			packages[index].get_node(^"InteractionArea").call(&"interact", player)
		houses[index].get(&"doorbell").call(&"interact", player)
		_expect(
			bool(houses[index].get(&"delivered")),
			"An arbitrary-order handover resolves its real customer (got %d)" % index
		)
		_expect(player.get(&"carried_package") == null, "The resident takes the physical package")
		_expect(
			bool(seat.call(&"can_interact", player)),
			"The driver may reboard after each town delivery"
		)
	_expect(
		manager.get(&"deliveries").size() == 3,
		"Three outcomes are recorded once (got %s)" % [manager.get(&"deliveries")]
	)
	_expect(level.get(&"selected_house") == -1, "GPS returns to the depot after all orders resolve")
	_expect(
		not bool(level.get(&"finished")), "Delivering all orders still requires the return trip"
	)
	var frontage: Vector2 = level.get(&"depot_frontage")
	vehicle.set(&"freeze", true)
	vehicle.set(&"linear_velocity", Vector3.ZERO)
	vehicle.global_position = Vector3(frontage.x, 1.5, frontage.y)
	level.call(&"_process", .2)
	_expect(
		bool(level.get(&"finished")) and not bool(manager.get(&"is_running")),
		"A stopped truck back at the depot completes the playtest"
	)
	_expect(
		manager.get(&"results").is_empty(), "The prototype never writes scored campaign results"
	)
	level.queue_free()
	await process_frame
	_expect(
		manager.get(&"deliveries").is_empty(), "Leaving the playtest clears its temporary run state"
	)
	if _failures == 0:
		print("PASS: real town cargo, chosen customers, street GPS, handovers and depot return")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
