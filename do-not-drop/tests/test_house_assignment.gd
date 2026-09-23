extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_house_assignment.gd
##
## docs/tareas-nacho.md #104/#105/#107/#121: one house per passenger, and each
## house waits for one specific box.
##   - the house count follows the crew: players minus the driver, at least one;
##   - starting the run hands each house one of the loaded boxes, in rack
##     order, and its sign says which;
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

	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var route: Node = level.get_node(^"World/Route")
	var houses: Array = route.get(&"houses")
	_expect(houses.size() == 1, "Solo (one peer), the route builds a single house (got %d)" % houses.size())

	# Load two boxes, then take the wheel: the run starts and houses get assigned.
	var player: Node = level.local_player
	var van: Node = level.vehicle
	var packages: Array = level.get(&"packages")
	var bays: Array[String] = ["LeftSeat1PackageMount", "LeftSeat2PackageMount"]
	for index: int in range(2):
		player.call(&"pick_up", packages[index].get_path())
		van.get_node(NodePath("CargoBay/%s/InteractionArea" % bays[index])).call(&"interact", player)
	van.call(&"set_door_open", &"cab_left", true)
	van.get_node(^"CabinInterior/DriverEyePoint/InteractionArea").call(&"interact", player)
	await process_frame
	_expect(bool(root.get_node(^"/root/RunManager").get(&"is_running")), "The run started")
	var house: DeliveryHouse = houses[0]
	var first: Node = packages[0]
	var second: Node = packages[1]
	_expect(house.assigned_package_id == first.get(&"package_id"), "The first bay's box goes to the first house (got %s)" % house.assigned_package_id)
	var sign_text: String = (route.get_node(^"HouseNumber0") as Label3D).text
	_expect(sign_text.contains(String(first.trap_definition.get(&"display_name")).to_upper()), "The house sign says which box it's waiting for (%s)" % sign_text.replace("\n", " / "))

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


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
