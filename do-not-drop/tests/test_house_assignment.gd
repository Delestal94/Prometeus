extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_house_assignment.gd
##
## docs/tareas-nacho.md #104/#105/#107/#121: one house per passenger, and each
## house waits for one specific box.
##   - the house count follows the crew: players minus the driver, at least one;
##   - online, the host decides that number once per session and every joiner
##     builds the host's number, not one from its own roster (a client's roster
##     starts as just [host, itself]);
##   - the depot's order board hands each house one specific box from the
##     start (depot.gd), and its sign says which box and which shelf;
##   - ringing with somebody else's box gets it handed back (the house stays
##     open, and every HUD hears why), while the right box is delivered.

var _failures: int = 0
var _refusals: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var route_script: Script = load("res://scripts/gameplay/route/route.gd")
	_expect(route_script.crew_house_count(1) == 1, "Playing alone still gets one house")
	_expect(route_script.crew_house_count(2) == 1, "Two players: the passenger's house")
	_expect(route_script.crew_house_count(4) == 3, "Four players: three passengers, three houses")
	await _check_session_house_count()

	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var route: Node = level.get_node(^"World/Route")
	var houses: Array = route.get(&"houses")
	_expect(houses.size() == 1, "Solo (one peer), the route builds a single house (got %d)" % houses.size())

	# The depot posts the orders the moment the level loads: the house waits
	# for that specific box from the start, and its sign says which.
	var depot: Node = level.get_node(^"World/Depot")
	var orders: Array = depot.get(&"orders")
	_expect(orders.size() == 1, "One order per house on the depot's board (got %d)" % orders.size())
	var house: DeliveryHouse = houses[0]
	var packages: Array = level.get(&"packages")
	var first: Node = null
	var second: Node = null
	for package: Node in packages:
		if package.get(&"package_id") == orders[0].package_id:
			first = package
		elif second == null:
			second = package
	_expect(first != null, "The ordered box is on the depot's shelves")
	_expect(house.assigned_package_id == first.get(&"package_id"), "The house waits for the ordered box (got %s)" % house.assigned_package_id)
	var sign_text: String = (route.get_node(^"HouseNumber0") as Label3D).text
	_expect(sign_text.contains(String(first.trap_definition.get(&"display_name")).to_upper()) and sign_text.contains(String(orders[0].code)), "The house sign names the box and its shelf (%s)" % sign_text.replace("\n", " / "))

	# Load it plus one more, then take the wheel: the run starts, and the
	# orders are handed out again (relayed) without changing.
	var player: Node = level.local_player
	var van: Node = level.vehicle
	var bays: Array[String] = ["LeftSeat1PackageMount", "LeftSeat2PackageMount"]
	for index: int in range(2):
		player.call(&"pick_up", [first, second][index].get_path())
		van.get_node(NodePath("CargoBay/%s/InteractionArea" % bays[index])).call(&"interact", player)
	van.call(&"set_door_open", &"cab_left", true)
	van.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	await process_frame
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "The run started")
	_expect(house.assigned_package_id == first.get(&"package_id"), "Starting the run keeps the posted order")

	# Wrong box: handed back, house still open, everyone told.
	root.get_node(^"/root/EventBus").connect(&"house_refused_package", func(index: int, expected: String) -> void: _refusals.append([index, expected]))
	house.call(&"_on_doorbell_rung", second)
	await process_frame
	_expect(not house.delivered, "Somebody else's box doesn't settle the house")
	_expect(is_instance_valid(second) and not second.is_queued_for_deletion(), "The wrong box is handed back, not consumed")
	_expect(_refusals.size() == 1 and int(_refusals[0][0]) == 0, "The refusal reaches the HUD (got %s)" % str(_refusals))

	# Right box: delivered (and consumed, so read its id first).
	var first_id: StringName = first.get(&"package_id")
	house.call(&"_on_doorbell_rung", first)
	await process_frame
	_expect(house.delivered and house.delivered_package_id == first_id, "The ordered box is delivered")

	level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: one house per passenger, each waiting for its own box, and a wrong box is handed back")
	quit(_failures)


func _check_session_house_count() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_roster: Array[int] = network.peer_ids.duplicate()
	var original_seed: int = int(network.world_seed)
	# The host's route, with a crew of four in an online session: three
	# houses, and that becomes the session's number.
	network.world_seed = 4242
	network.world_house_count = 0
	network.peer_ids = [1, 2, 3, 4] as Array[int]
	_expect(await _built_house_count() == 3, "The host builds one house per passenger")
	_expect(int(network.world_house_count) == 3, "The host records it as the session's house count (got %d)" % int(network.world_house_count))
	# A fifth player joins and the host restarts: clients don't reload their
	# world, so the host keeps the number it already handed out.
	network.peer_ids = [1, 2, 3, 4, 5] as Array[int]
	_expect(await _built_house_count() == 3, "A host restart keeps the session's house count")
	# A joiner: its own roster says [host, itself] (one house), but it builds
	# the number the handshake brought.
	network.world_house_count = 0
	network.peer_ids = [1, 7] as Array[int]
	network.set(&"_awaiting_handshake", true)
	network.call(&"_accept_joiner", 4242, 3, [])
	_expect(await _built_house_count() == 3, "A joiner builds the host's house count, not its own roster's")
	# Solo play never records one: every run counts the crew afresh.
	network.world_seed = 0
	network.world_house_count = 0
	network.peer_ids = [1] as Array[int]
	_expect(await _built_house_count() == 1 and int(network.world_house_count) == 0, "Solo play counts the crew and records nothing")
	network.world_seed = original_seed
	network.world_house_count = 0
	network.peer_ids = original_roster


func _built_house_count() -> int:
	var route: Node = load("res://scenes/gameplay/route/route.tscn").instantiate()
	root.add_child(route)
	await process_frame
	var count: int = (route.get(&"houses") as Array).size()
	route.free()
	await process_frame
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
