extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_multi_cargo.gd
## The Fase 2 question: does the van actually carry several traps at once,
## and does losing one stop being everybody's game over?

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame

	var packages: Array[Node] = []
	packages.assign(root.get_tree().get_nodes_in_group(&"cargo"))
	var mounts: Array[Node] = []
	mounts.assign(root.get_tree().get_nodes_in_group(&"package_mount"))
	# The level declares one box per trap; the depot (depot.gd) stocks a
	# second of each on its shelves.
	_expect(packages.size() == 14, "The depot holds two packages of every trap (got %d)" % packages.size())
	_expect(mounts.size() == 6, "Four seat mounts plus two shelf mounts are available (got %d)" % mounts.size())
	var seat_mounts: Array[Node] = []
	for mount: Node in mounts:
		if String(mount.get_parent().name).contains("Seat"):
			seat_mounts.append(mount)
	_expect(seat_mounts.size() == 4, "Every cargo-tending seat keeps its own mount")

	var trap_ids: Array = []
	for package: Node in packages:
		trap_ids.append(String(package.get(&"trap_definition").get(&"id")))
	var kinds: Array = []
	for trap_id: String in trap_ids:
		if not kinds.has(trap_id):
			kinds.append(trap_id)
	kinds.sort()
	_expect(kinds == ["balance", "explosive", "fragile", "growing_weight", "hostile", "liquid", "noisy"] and trap_ids.size() == 14,
		"All seven trap types are represented (got %s)" % str(trap_ids))

	# Seven passenger places fit behind the driver; the four outer seats own
	# cargo mounts while the remaining three are free crew seats.
	var seats: Array[Node] = []
	for node: Node in _all_nodes(level):
		if node.get(&"role") == &"passenger":
			seats.append(node)
	_expect(seats.size() == 10, "Seven passenger seats plus three fold-down seats by the rack (got %d)" % seats.size())

	var player: Node = level.local_player
	var manager: Node = root.get_node(^"/root/RunManager")

	# Load two different traps, leaving the other two behind on the rack.
	# pick_up is an @rpc now (called with rpc_id() from package_pickup_point.gd
	# normally); calling it directly here, with no RPC in flight, is what a
	# host's own local interaction looks like -- _from_host() allows it.
	player.call(&"pick_up", packages[0].get_path())
	seat_mounts[0].call(&"interact", player)
	player.call(&"pick_up", packages[1].get_path())
	seat_mounts[1].call(&"interact", player)
	_expect(bool(packages[0].get(&"is_loaded")) and bool(packages[1].get(&"is_loaded")), "Both boxes report loaded")
	_expect(not bool(packages[2].get(&"is_loaded")), "The box left on the rack stays unloaded")

	# Taking the wheel with cargo aboard starts the delivery.
	var driver_seat: Node = level.get_node(^"World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea")
	driver_seat.get_parent().get_parent().get_parent().call(&"set_door_open", &"cab_left", true)  # Seat is behind the cab door.
	driver_seat.call(&"interact", player)
	_expect(bool(manager.get(&"is_running")), "Delivery starts once a driver sits with cargo aboard")
	_expect((manager.get(&"cargo") as Dictionary).size() == 2,
		"Only the two boxes actually aboard count toward the run")

	# Losing one box is not everyone's game over.
	packages[0].call(&"mark_lost", "Prueba")
	_expect(int(packages[0].get(&"trap_state")) == 2, "A lost box counts as ruined")
	_expect(bool(manager.get(&"is_running")), "The delivery survives losing a single box")

	# A passenger seat hands its package to whoever sits there.
	var second_player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(second_player)
	await process_frame
	var seat_for_mount_two: Node = null
	for seat: Node in seats:
		var required: NodePath = seat.get(&"required_mount_path")
		if not required.is_empty() and seat.get_node_or_null(required) == seat_mounts[1]:
			seat_for_mount_two = seat
			break
	_expect(seat_for_mount_two != null, "The seat tied to the second mount can be found")
	if seat_for_mount_two != null:
		seat_for_mount_two.call(&"interact", second_player)
		_expect(second_player.get(&"tended_package") == packages[1],
			"Sitting down puts that seat's package in the passenger's care")

	# Arriving scores what survived rather than all-or-nothing.
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	_expect(bool(results.get("delivered")), "Arriving with something still counts as delivered")
	_expect(int(results.get("cargo_ruined")) == 1, "The lost box is reported ruined")
	_expect(int(results.get("cargo_points")) > 0, "Surviving cargo still scores")

	level.free()
	second_player.free()
	if _failures == 0:
		print("PASS: seven traps ride together, one loss doesn't end the run, seats hand over their package")
	quit(_failures)


func _all_nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_all_nodes(child))
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
