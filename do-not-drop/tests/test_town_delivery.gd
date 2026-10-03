extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_delivery.gd
## town_delivery.gd: seeded offline district uses the real truck, packages,
## player and houses. Load, board, choose a different customer, reject a wrong
## package, hand over in arbitrary order, reboard and return to the depot.
## DashboardGps follows street waypoints; completion does not save a campaign.
## Authored client houses vary, keep their frontage and use the depot's rack.
## Six coded orders cover both districts; the seed fixes their addresses.
## Native boxes fit and can be aimed at on both rack levels. F1-F6 selects
## customers; F7 explores the center. Completing only one district stays open.
## The real on-foot controller walks from asphalt over the sidewalk and
## reaches a front path using collision surfaces, without jumping.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_manifests()
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
		houses.size() == 6 and packages.size() == 6,
		"There are six real customers and packages (got %d/%d)" % [houses.size(), packages.size()]
	)
	if houses.size() != 6 or packages.size() != 6:
		level.queue_free()
		await process_frame
		quit(_failures)
		return
	_expect(int(manager.get(&"expected_houses")) == 6, "Run expects orders from both districts")
	_expect(not bool(manager.get(&"is_running")), "Preparation waits for the driver to board")
	var mounts: Array[String] = [
		"LeftShelf", "RightShelf", "LeftSeat1", "LeftSeat2", "RightSeat1", "RightSeat2"
	]
	var variants: Dictionary = {}
	for index: int in range(3):
		variants[int(houses[index].get(&"visual_variant"))] = true
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
	var player_start: Transform3D = player.global_transform
	var parcel_path: Dictionary = level.get(&"town").get(&"pedestrian_plan").lot_paths[1]
	var first: Vector2 = parcel_path.points[0]
	var last: Vector2 = parcel_path.points[-1]
	var direction: Vector2 = (last - first).normalized()
	player.global_position = Vector3(first.x - direction.x * 1.0, .21, first.y - direction.y * 1.0)
	player.rotation.y = atan2(-direction.x, -direction.y)
	player.set(&"_pitch", 0.0)
	var walking_start: Vector3 = player.global_position
	var previous_mouse_mode: Input.MouseMode = Input.mouse_mode
	var manual_step: bool = DisplayServer.get_name() == "headless"
	var movement: Script = load("res://scripts/gameplay/player/player_movement.gd")
	# The dummy display cannot capture a mouse. Exercise the same movement
	# component against real physics instead of Player's menu/input gate.
	if manual_step:
		player.set_physics_process(false)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press(&"walk_forward")
	for frame: int in range(120):
		await physics_frame
		if manual_step:
			movement.on_foot_step(player, 1.0 / Engine.physics_ticks_per_second)
	Input.action_release(&"walk_forward")
	Input.mouse_mode = previous_mouse_mode
	player.set_physics_process(true)
	var progress: float = (
		Vector2(
			player.global_position.x - walking_start.x, player.global_position.z - walking_start.z
		)
		. dot(direction)
	)
	_expect(
		progress > 5.0 and player.global_position.y >= .06 and player.global_position.y <= .25,
		(
			"The actual player walks from road to its front path without a curb blocking it (got %f m, y %f)"
			% [progress, player.global_position.y]
		)
	)
	player.global_transform = player_start
	player.set(&"velocity", Vector3.ZERO)
	var front: Vector2 = (
		(depot.get_meta(&"lot").frontage - depot.get_meta(&"lot").position)
		. rotated(-float(depot.get_meta(&"lot").angle))
	)
	var rack: Node3D = depot.get_node(^"LoadingRack")
	for index: int in range(packages.size()):
		var package: Node3D = packages[index]
		_expect(
			package.get(&"package_id") == houses[index].get(&"assigned_package_id"),
			"Each code belongs to exactly its real customer (got %d)" % index
		)
		_expect(
			int(package.get_meta(&"district")) == (0 if index < 3 else 1),
			"Rack codes identify the correct destination district (got %d)" % index
		)
		var shape: CollisionShape3D = package.get_node(^"CollisionShape3D")
		var box: BoxShape3D = shape.shape
		var box_bounds: AABB = shape.global_transform * AABB(-box.size * .5, box.size)
		for collider: CollisionShape3D in rack.find_children("*", "CollisionShape3D", true, false):
			if collider.shape is BoxShape3D:
				var rack_box: BoxShape3D = collider.shape
				var rack_bounds: AABB = (
					collider.global_transform * AABB(-rack_box.size * .5, rack_box.size)
				)
				_expect(
					not box_bounds.intersects(rack_bounds),
					"Native package clears shelf decks and uprights (order %d)" % index
				)
		var mount: Node3D = depot.get_node("OrderMount_%d" % index)
		player.global_position = depot.to_global(
			mount.position + Vector3(0, -mount.position.y + .2, signf(front.y) * 1.3)
		)
		player.look_at(
			Vector3(package.global_position.x, player.global_position.y, package.global_position.z)
		)
		var head: Node3D = player.get(&"_head")
		head.look_at(package.global_position)
		player.set(&"_pitch", head.rotation.x)
		var eye: Camera3D = player.get(&"_camera")
		eye.rotation = Vector3.ZERO
		for frame: int in range(3):
			await physics_frame
		var pickup: Node = package.get_node(^"InteractionArea")
		_expect(
			bool(player.call(&"_within_reach", pickup)),
			"Both rack levels can be reached from the front (order %d)" % index
		)
		var aimed: Node = player.call(&"_closest_interactable")
		_expect(
			aimed == pickup,
			(
				"Aiming at each rack box selects its own pickup (order %d, got %s)"
				% [index, aimed.get_path() if aimed != null else "none"]
			)
		)
		for other: int in range(index + 1, packages.size()):
			_expect(
				package.global_position.distance_to(packages[other].global_position) > box.size.y,
				"Rack packages do not overlap (orders %d/%d)" % [index, other]
			)
	player.global_transform = player_start
	player.set(&"_pitch", 0.0)
	player.get(&"_head").rotation = Vector3.ZERO
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
		manager.get(&"cargo").size() == 6,
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
	var explore := InputEventKey.new()
	explore.physical_keycode = KEY_F7
	explore.pressed = true
	level.call(&"_unhandled_input", explore)
	var center_guide: Dictionary = level.call(&"guidance")
	_expect(
		(
			center_guide.get("label") == tr("WORLD_TOWN_DISTRICT_CENTER")
			and center_guide.get("house") == -1
			and center_guide.get("distance", 0) > 100
		),
		"Center exploration provides a real cross-district GPS destination (got %s)" % center_guide
	)
	var center: Vector2 = level.get(&"center_frontage")
	var before: Vector3 = vehicle.global_position
	vehicle.global_position = Vector3(center.x, before.y, center.y)
	_expect(
		float(level.call(&"guidance").get("distance", -1)) < .01,
		"Center GPS arrives at a point on asphalt"
	)
	vehicle.global_position = before
	var select := InputEventKey.new()
	select.physical_keycode = KEY_F4
	select.pressed = true
	level.call(&"_unhandled_input", select)
	var center_order: Dictionary = level.call(&"guidance")
	_expect(
		center_order.get("house") == 3 and center_order.get("distance", 0) > 100,
		"F4 selects package D's center customer across the open corridor (got %s)" % center_order
	)
	level.call(&"select_house", 2)
	_expect(
		not bool(level.get(&"exploring_center")), "Choosing a customer exits center exploration"
	)
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
	for index: int in [2, 0, 1, 5, 3, 4]:
		if player.get(&"carried_package") != packages[index]:
			packages[index].get_node(^"InteractionArea").call(&"interact", player)
		houses[index].get(&"doorbell").call(&"interact", player)
		if index == 1:
			vehicle.set(&"freeze", true)
			vehicle.set(&"linear_velocity", Vector3.ZERO)
			var depot_stop: Vector2 = level.get(&"depot_frontage")
			vehicle.global_position = Vector3(depot_stop.x, .866, depot_stop.y)
			level.call(&"_process", .2)
			_expect(
				not bool(level.get(&"finished")) and bool(manager.get(&"is_running")),
				"Returning after only the starting orders cannot finish the center's pending orders"
			)
			_expect(
				int(level.get(&"selected_house")) == 3,
				"Resolving the original orders automatically guides to the first center customer"
			)
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
		manager.get(&"deliveries").size() == 6,
		"Six outcomes are recorded once (got %s)" % [manager.get(&"deliveries")]
	)
	houses[4].get(&"doorbell").call(&"interact", player)
	_expect(
		manager.get(&"deliveries").size() == 6,
		"A resolved doorbell cannot record a duplicate order"
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


func _check_manifests() -> void:
	var adapter: Script = load("res://scripts/gameplay/town/town_delivery.gd")
	var planner: Script = load("res://modules/town_gen/town_plan.gd")
	var navigation: Script = load("res://modules/town_gen/town_navigation.gd")
	for seed_value: int in range(1, 101):
		var plan: Dictionary = planner.call(&"generate", seed_value)
		var original: Dictionary = plan.duplicate(true)
		var orders: Array = adapter.call(&"delivery_lots", plan)
		var legacy: Dictionary = planner.call(&"generate", seed_value, 1)
		_expect(
			orders == adapter.call(&"delivery_lots", legacy),
			"Urban infill preserves all six original delivery destinations"
		)
		_expect(
			orders.size() == 6,
			(
				"Each seeded manifest has six destinations (seed %d, got %d)"
				% [seed_value, orders.size()]
			)
		)
		var shuffled: Dictionary = plan.duplicate(true)
		shuffled.lots.reverse()
		_expect(
			adapter.call(&"delivery_lots", shuffled) == orders,
			(
				"Seeded order identities do not depend on scene construction order (seed %d)"
				% seed_value
			)
		)
		_expect(plan == original, "Activating deliveries preserves the city's streets and lots")
		var depot: Vector2
		for lot: Dictionary in plan.lots:
			if lot.role == &"depot":
				depot = lot.frontage
		var addresses: Dictionary = {}
		for index: int in range(orders.size()):
			var lot: Dictionary = orders[index]
			_expect(
				lot.district == (0 if index < 3 else 1),
				"The manifest assigns three orders to each district"
			)
			_expect(not addresses.has(lot.address), "Each seeded order has a distinct address")
			addresses[lot.address] = true
			if index < 3:
				_expect(
					lot.role == &"house" and lot.address.y == index + 2,
					"The original customer addresses stay stable"
				)
			else:
				_expect(
					lot.role == &"residential",
					"Center orders preserve existing shops and green spaces"
				)
			var route: Dictionary = navigation.call(
				&"route", plan, depot, lot.frontage, PackedInt32Array([0, 1])
			)
			_expect(
				not route.is_empty(),
				(
					"All seeded center orders have accessible street routes (seed %d, order %d)"
					% [seed_value, index]
				)
			)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
