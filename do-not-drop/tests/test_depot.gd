extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot.gd
##
## The depot every delivery starts from (depot.gd):
##   - every package is on a dispatch shelf with its own bin code, resting on
##     the shelf, and the crew spawns inside, under the roof (no rain);
##   - the board posts one order per house, each a different kind of box, and
##     the pickup prompt names the bin so the right one can be found;
##   - the stations open their screen on the player who used them;
##   - supplies cost team money, once each, and the padding softens every
##     loaded box for the run that takes it;
##   - leaving without an ordered box is called out;
##   - the door stays open while anyone is inside on foot, and rolls down once
##     the truck is out.

var _failures: int = 0
var _opened: Array[StringName] = []
var _notices: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	crew.call(&"reset_campaign")
	# Every trap unlocked: locked ones stay off the depot's shelves
	# (depot.gd withhold_locked), and the test profile's unlocks depend on
	# whichever tests ran before this one.
	for unlock_id: StringName in (root.get_node(^"/root/UnlockManager").get(&"TRAP_UNLOCKS") as Dictionary).values():
		root.get_node(^"/root/UnlockManager").unlocked[unlock_id] = true
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	await physics_frame
	var depot: Node3D = level.get_node(^"World/Depot")
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"depot_station_opened", func(station: StringName) -> void: _opened.append(station))
	bus.connect(&"depot_notice", func(text: String) -> void: _notices.append(text))

	# Stock: every box shelved, each in its own bin, standing on the deck.
	var packages: Array = level.get(&"packages")
	_expect(packages.size() == 14, "Two boxes of every kind in the depot (got %d)" % packages.size())
	var codes: Dictionary = {}
	for package: Node3D in packages:
		var code: String = String(package.get_meta(&"dispatch_code", ""))
		_expect(not code.is_empty(), "%s has a bin code" % package.get(&"package_id"))
		codes[code] = true
		var local: Vector3 = depot.to_local(package.global_position)
		_expect(local.z > 14.0 and local.z < 24.0 and local.x < -5.0, "%s sits on the dispatch shelves (at %s)" % [package.get(&"package_id"), local])
		var content: Resource = package.call(&"content_definition")
		var bottom: float = local.y - float((content.get(&"box_size") as Vector3).y) * 0.5
		_expect(bottom > 0.3 and (absf(bottom - 0.36) < 0.03 or absf(bottom - 1.51) < 0.03), "%s rests on its deck (bottom at %.2f)" % [package.get(&"package_id"), bottom])
	_expect(codes.size() == packages.size(), "No two boxes share a bin (%d codes)" % codes.size())
	var prompt: String = packages[0].get_node(^"InteractionArea").call(&"get_prompt")
	_expect(prompt.contains(String(packages[0].get_meta(&"dispatch_code"))), "The pickup prompt names the bin (%s)" % prompt)

	# Spawn and roof.
	var player: Node3D = level.local_player
	_expect(bool(depot.call(&"covers", player.global_position)), "The crew spawns inside the depot")
	_expect(not bool(depot.call(&"covers", depot.to_global(Vector3(0.0, 1.0, -5.0)))), "The forecourt isn't under the roof")

	# Orders: one per house, all different kinds, written on the board.
	var orders: Array = depot.get(&"orders")
	var houses: Array = level.get_node(^"World/Route").get(&"houses")
	_expect(orders.size() == houses.size(), "One order per house (%d for %d)" % [orders.size(), houses.size()])
	var row: Label3D = depot.get_node(^"OrderBoard/Row0")
	_expect(row.text.contains(String(orders[0].code)), "The board shows the first order's bin (%s)" % row.text)

	# Stations: the screen opens on whoever used it.
	for station: StringName in [&"orders", &"garage", &"wardrobe", &"shop", &"records"]:
		var node: Node = depot.get_node(NodePath("Station_%s" % station))
		_expect(bool(node.call(&"can_interact", player)), "The %s station can be used before the run" % station)
		node.call(&"interact", player)
	_expect(_opened == [&"orders", &"garage", &"wardrobe", &"shop", &"records"], "Each station opens its screen (got %s)" % str(_opened))

	# Supplies: paid from team money, one of each.
	var start_money: int = int(crew.get(&"team_money"))
	depot.call(&"buy_supply", &"padding")
	depot.call(&"buy_supply", &"padding")
	var padding_cost: int = int(crew.get(&"SUPPLIES")[&"padding"]["cost"])
	_expect(int(crew.get(&"team_money")) == start_money - padding_cost, "Padding is paid once (money %d)" % int(crew.get(&"team_money")))
	_expect((depot.get(&"supplies") as Array).has(&"padding"), "The depot shows the padding waiting")
	_expect((depot.get_node(^"Supply_padding") as Node3D).visible, "The bought padding sits on the counter")

	# Leave with a box that isn't on the order: padding applies, and the
	# forgotten order is called out.
	var ordered_id: StringName = orders[0].package_id
	var other: Node = null
	for package: Node in packages:
		if package.get(&"package_id") != ordered_id:
			other = package
			break
	player.call(&"pick_up", other.get_path())
	level.vehicle.get_node(^"CargoBay/LeftSeat1PackageMount/InteractionArea").call(&"interact", player)
	_expect(bool(depot.call(&"_anyone_on_foot_inside")), "Someone on foot inside counts as inside")
	level.vehicle.call(&"set_door_open", &"cab_left", true)
	level.vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	await process_frame
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "Taking the wheel with cargo starts the run")
	_expect(is_equal_approx(float(other.get(&"impact_absorption")), 0.75), "Padding softens the loaded box")
	_expect((crew.get(&"supplies") as Dictionary).is_empty(), "The run used the supplies up")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("sin el pedido")), "Leaving without the ordered box is called out (%s)" % str(_notices))
	_expect(not bool(depot.call(&"_anyone_on_foot_inside")), "The driver is aboard, not on foot")
	for station: StringName in [&"orders", &"shop"]:
		_expect(not bool(depot.get_node(NodePath("Station_%s" % station)).call(&"can_interact", player)), "The %s station closes once the run is on" % station)

	# The door: open while the truck is inside, down once it's out.
	var door: Node = depot.get(&"door")
	await physics_frame
	_expect(bool(door.get(&"is_open")), "The door stays open while the truck is inside")
	var vehicle: RigidBody3D = level.vehicle
	vehicle.global_position = depot.to_global(Vector3(0.0, 1.2, -12.0))
	vehicle.linear_velocity = Vector3.ZERO
	for tick: int in range(4):
		await physics_frame
	_expect(not bool(door.get(&"is_open")), "The door closes behind the truck")
	_expect(_notices.any(func(text: String) -> bool: return text.contains("portón")), "The crew is told the door closed")

	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	crew.call(&"reset_campaign")
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: depot stocks every box in its bin, posts the orders, sells supplies and closes behind the truck")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
