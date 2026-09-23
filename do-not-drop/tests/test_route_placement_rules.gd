extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_placement_rules.gd
##
## RouteDresser's promises (scripts/gameplay/route/route_dresser.gd), checked
## on a real five-house route:
##   - nothing but the roadworks cones stands on or at the edge of the
##     asphalt -- a house's side fence once did, before yards were validated;
##   - no two solid things share ground (a tree through a parked car, a bus
##     stop inside a bench);
##   - each kind of thing only appears in its zone: street furniture in the
##     village, hay bales and crates in the countryside;
##   - the route passes through more than one kind of place;
##   - everything rests on the ground by all of its feet (root tips, both
##     ends of a log), not just its centre;
##   - the same seed dresses the same world, down to every position.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var original_seed: int = int(network.world_seed)
	network.world_seed = 777
	var route: Node3D = await _build()
	var terrain: Node = route.get(&"terrain")
	var placed: Array[Node3D] = _placed(route)
	_expect(placed.size() > 500, "The route actually got dressed (%d pieces)" % placed.size())

	# 1. Off the road.
	var worst_road: float = INF
	var worst_name: String = ""
	for node: Node3D in placed:
		if node.get_meta(&"rule", &"") == &"roadworks":
			continue
		var p: Vector3 = route.to_local(node.global_position)
		var edge: float = terrain.nearest(Vector2(p.x, p.z)).x - float(node.get_meta(&"reach", 0.0))
		if edge < worst_road:
			worst_road = edge
			worst_name = node.scene_file_path.get_file()
	_expect(worst_road >= 5.9, "Nothing encroaches on the road (closest edge %.2f m: %s)" % [worst_road, worst_name])

	# 2. No overlapping solids.
	var solids: Array[Vector3] = []
	var names: Array[String] = []
	for node: Node3D in placed:
		if node.get_meta(&"solid", false):
			var p: Vector3 = route.to_local(node.global_position)
			solids.append(Vector3(p.x, p.z, float(node.get_meta(&"footprint", 0.0))))
			names.append(node.scene_file_path.get_file())
	var overlaps: int = 0
	var cells: Dictionary = {}
	for index: int in range(solids.size()):
		var c: Vector3 = solids[index]
		var key := Vector2i(floori(c.x / 16.0), floori(c.y / 16.0))
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for other_index: int in cells.get(key + Vector2i(dx, dz), []):
					var o: Vector3 = solids[other_index]
					if Vector2(c.x - o.x, c.y - o.y).length() < c.z + o.z - 0.01:
						overlaps += 1
						if overlaps <= 5:
							print("overlap: ", names[index], " / ", names[other_index])
		if not cells.has(key):
			cells[key] = []
		cells[key].append(index)
	_expect(overlaps == 0, "No two solid pieces share ground (%d overlaps among %d)" % [overlaps, solids.size()])

	# 3. Zones.
	var zones_seen: Dictionary = {}
	for node: Node3D in placed:
		var zone: String = node.get_meta(&"zone", "")
		if zone != "":
			zones_seen[zone] = true
		match node.get_meta(&"rule", &""):
			&"village_furniture", &"bus_stop":
				_expect(zone == "village", "%s only in the village (found in %s)" % [node.scene_file_path.get_file(), zone])
			&"farm_props":
				_expect(zone == "countryside", "%s only in the countryside (found in %s)" % [node.scene_file_path.get_file(), zone])
	_expect(zones_seen.size() >= 2, "The road passes through more than one kind of place (%s)" % str(zones_seen.keys()))

	# 4. On the ground, by every foot: no root tip or log end in the air, and
	# nothing buried deeper than the deliberate sink.
	var floating: int = 0
	var buried: int = 0
	for node: Node3D in placed:
		var gap: float = RouteDresser.ground_gap(node, route, terrain)
		if gap > 0.005:
			floating += 1
			if floating <= 5:
				print("floating: %s %.3f m" % [node.scene_file_path.get_file(), gap])
		elif gap < -RouteDresser.SINK_RANGE.y - 0.005:
			buried += 1
			if buried <= 5:
				print("buried: %s %.3f m" % [node.scene_file_path.get_file(), gap])
	_expect(floating == 0, "No piece has a foot in the air (%d of %d)" % [floating, placed.size()])
	_expect(buried == 0, "No piece sinks past its intended depth (%d of %d)" % [buried, placed.size()])

	# 5. Same seed, same world.
	var first: Array = _signature(route)
	route.free()
	await process_frame
	var again: Node3D = await _build()
	_expect(first == _signature(again), "The same seed places every piece in the same spot")
	again.free()

	network.world_seed = original_seed
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: dressing stays off the road, never overlaps, respects its zones, and is the same for every peer")
	quit(_failures)


func _build() -> Node3D:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate() as Node3D
	route.set(&"house_count", 5)
	root.add_child(route)
	await process_frame
	return route


## Everything RouteDresser spawned or validated: segment dressing groups plus
## the lot pieces of each yard (porch pieces belong to the house itself).
func _placed(route: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in route.find_children("*", "Node3D", true, false):
		if node.has_meta(&"rule") and not node.get_meta(&"on_porch", false):
			found.append(node as Node3D)
	return found


func _signature(route: Node3D) -> Array:
	var signature: Array = []
	for node: Node3D in _placed(route):
		signature.append([node.scene_file_path, route.to_local(node.global_position).snapped(Vector3.ONE * 0.01)])
	return signature


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
