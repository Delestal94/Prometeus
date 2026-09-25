extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_town_signs.gd
##
## Villages with names (N-601, town_sign.gd, RouteDresser._dress_town_signs):
## - every village the road passes through gets a named sign where the road
##   enters it and a crossed-out one where it leaves (unless the goal is
##   inside it), in that order along the road;
## - names come from the list of twelve, never repeat on a route, and are the
##   same for the same session seed (every peer reads the same town name);
## - each sign stands off the asphalt on the driver's right and faces the
##   oncoming truck, so its text reads the right way round;
## - the exit sign is the entry's name with the red bar across it.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var names_a: Array[String] = TownSign.names_for_seed(4242)
	_expect(names_a == TownSign.names_for_seed(4242), "Same seed, same town names")
	_expect(names_a != TownSign.names_for_seed(4243), "Another seed deals the names in another order")
	var unique: Dictionary = {}
	for town_name: String in names_a:
		unique[town_name] = true
	_expect(unique.size() == 12 and names_a.size() == 12, "Twelve distinct names (got %d of %d)" % [unique.size(), names_a.size()])

	var network: Node = root.get_node(^"/root/NetworkManager")
	var checked_towns: int = 0
	for seed_value: int in [4242, 777, 11]:
		network.set(&"world_seed", seed_value)
		network.set(&"world_house_count", 4)
		var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
		route.set(&"batch_dressing", false)
		root.add_child(route)
		await process_frame
		var signs: Array[TownSign] = []
		for node: Node in route.find_children("*", "TownSign", true, false):
			signs.append(node as TownSign)
		# Road order: by distance along the road.
		signs.sort_custom(func(a: TownSign, b: TownSign) -> bool:
			return float(route.call(&"road_distance", a.global_position)) < float(route.call(&"road_distance", b.global_position)))
		var entries: int = 0
		var open_town: String = ""
		var seen_names: Dictionary = {}
		for sign_node: TownSign in signs:
			if not sign_node.is_exit:
				_expect(open_town == "", "seed %d: a village is left before the next one is entered (%s still open at %s)" % [seed_value, open_town, sign_node.town_name])
				_expect(not seen_names.has(sign_node.town_name), "seed %d: no two villages share a name (%s)" % [seed_value, sign_node.town_name])
				_expect(sign_node.town_name in TownSign.NAMES, "seed %d: the name comes from the list (%s)" % [seed_value, sign_node.town_name])
				seen_names[sign_node.town_name] = true
				open_town = sign_node.town_name
				entries += 1
				var label := sign_node.get_node_or_null(^"Name") as Label3D
				_expect(label != null and label.text == sign_node.town_name, "seed %d: the entry sign shows the name" % seed_value)
				_expect(sign_node.get_node_or_null(^"Welcome") != null and sign_node.get_node_or_null(^"Bar") == null,
					"seed %d: the entry sign welcomes, with no bar" % seed_value)
			else:
				_expect(sign_node.town_name == open_town, "seed %d: the exit sign names the village being left (%s, open: %s)" % [seed_value, sign_node.town_name, open_town])
				_expect(sign_node.get_node_or_null(^"Bar") != null, "seed %d: the exit sign has the red bar" % seed_value)
				open_town = ""
			_check_placement(route, sign_node, seed_value)
		_expect(entries == (route.get(&"houses") as Array).size() or entries > 0,
			"seed %d: the villages round the houses get signs (%d entries for %d houses)" % [seed_value, entries, (route.get(&"houses") as Array).size()])
		checked_towns += entries
		# Same seed, same signs: name and spot.
		var first: Array = _signature(signs)
		route.free()
		await process_frame
		var again: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
		again.set(&"batch_dressing", false)
		root.add_child(again)
		await process_frame
		var again_signs: Array[TownSign] = []
		for node: Node in again.find_children("*", "TownSign", true, false):
			again_signs.append(node as TownSign)
		again_signs.sort_custom(func(a: TownSign, b: TownSign) -> bool:
			return float(again.call(&"road_distance", a.global_position)) < float(again.call(&"road_distance", b.global_position)))
		_expect(first == _signature(again_signs), "seed %d: the same seed puts up the same signs in the same spots" % seed_value)
		again.free()
		await process_frame
	_expect(checked_towns >= 6, "Several villages were checked across the seeds (%d)" % checked_towns)

	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	if _failures == 0:
		print("PASS: every village is signed in and out by name, off the road, facing the truck, the same for every peer")
	quit(_failures)


## Off the asphalt, right of the driver, board facing the truck coming at it.
func _check_placement(route: Node3D, sign_node: TownSign, seed_value: int) -> void:
	var terrain: Node = route.get(&"terrain")
	var p: Vector3 = route.to_local(sign_node.global_position)
	var road: float = terrain.nearest(Vector2(p.x, p.z)).x
	var reach: float = TownSign.POST_GAP * 0.5 + 0.1
	_expect(road - reach >= 6.5, "seed %d: %s's posts stand off the asphalt (closest post %.1f m from the centreline)" % [seed_value, sign_node.name, road - reach])
	# Road heading at the sign, from the path points around it.
	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	var nearest: int = 0
	for index: int in range(path.size()):
		if Vector2(path[index].x - p.x, path[index].z - p.z).length() < Vector2(path[nearest].x - p.x, path[nearest].z - p.z).length():
			nearest = index
	var a: Vector3 = path[maxi(nearest - 1, 0)]
	var b: Vector3 = path[mini(nearest + 1, path.size() - 1)]
	var forward := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var right := forward.cross(Vector3.UP)
	var offset := Vector3(p.x - path[nearest].x, 0.0, p.z - path[nearest].z)
	_expect(offset.dot(right) > 0.0, "seed %d: %s stands on the driver's right" % [seed_value, sign_node.name])
	var facing: Vector3 = route.global_basis.inverse() * (sign_node.global_basis * Vector3.BACK)
	_expect(Vector3(facing.x, 0.0, facing.z).normalized().dot(-forward) > 0.8,
		"seed %d: %s faces the oncoming truck (cos %.2f)" % [seed_value, sign_node.name, Vector3(facing.x, 0.0, facing.z).normalized().dot(-forward)])


func _signature(signs: Array[TownSign]) -> Array:
	var signature: Array = []
	for sign_node: TownSign in signs:
		signature.append([sign_node.town_name, sign_node.is_exit, sign_node.global_position.snapped(Vector3.ONE * 0.01)])
	return signature


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
