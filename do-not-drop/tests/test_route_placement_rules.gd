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
##   - the same seed dresses the same world, down to every position;
##   - the depot's other vehicles turn up on the road (N-306): a tractor out in
##     the countryside, well back from the asphalt, and the competition's van
##     parked in a village, lined up with the road like the other parked cars.

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
			&"farm_props", &"tractor":
				_expect(zone == "countryside", "%s only in the countryside (found in %s)" % [node.scene_file_path.get_file(), zone])
			&"competitor_van":
				_expect(zone == "village", "%s only in the village (found in %s)" % [node.scene_file_path.get_file(), zone])
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

	# 6. The tractor and the competition's van (N-306): rare, so look over a
	# few seeds until both have shown up.
	var seen: Dictionary = {&"tractor": 0, &"competitor_van": 0}
	for seed_value: int in [777, 11, 4242, 90210, 31337, 2024, 5, 606]:
		if seen[&"tractor"] > 0 and seen[&"competitor_van"] > 0:
			break
		network.world_seed = seed_value
		var dressed: Node3D = await _build()
		var dressed_terrain: Node = dressed.get(&"terrain")
		for node: Node3D in _placed(dressed):
			var rule: StringName = node.get_meta(&"rule", &"")
			if not seen.has(rule):
				continue
			seen[rule] += 1
			var p: Vector3 = dressed.to_local(node.global_position)
			var edge: float = dressed_terrain.nearest(Vector2(p.x, p.z)).x - float(node.get_meta(&"reach", 0.0))
			if rule == &"tractor":
				_expect(edge >= 12.0, "seed %d: the tractor stays well back from the asphalt (edge %.1f m from the centreline)" % [seed_value, edge])
			else:
				var along_road: float = absf(_long_axis(node).dot(_road_direction(dressed, p)))
				_expect(along_road > 0.9, "seed %d: the van is parked along the road like the other cars (|cos| %.2f)" % [seed_value, along_road])
		dressed.free()
		await process_frame
	_expect(seen[&"tractor"] > 0, "A tractor shows up in the countryside on some route (%s)" % seen)
	_expect(seen[&"competitor_van"] > 0, "The competition's van shows up parked in a village on some route (%s)" % seen)

	network.world_seed = original_seed
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: dressing stays off the road, never overlaps, respects its zones, and is the same for every peer")
	quit(_failures)


func _build() -> Node3D:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate() as Node3D
	route.set(&"house_count", 5)
	# These are the dresser's own promises, piece by piece: keep them nodes.
	route.set(&"batch_dressing", false)
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


## The model's longest horizontal axis, in world space.
func _long_axis(node: Node3D) -> Vector3:
	var bounds := AABB()
	var first: bool = true
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var local: AABB = (node.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
		bounds = local if first else bounds.merge(local)
		first = false
	var axis: Vector3 = Vector3.RIGHT if bounds.size.x >= bounds.size.z else Vector3.BACK
	var world: Vector3 = node.global_basis * axis
	return Vector3(world.x, 0.0, world.z).normalized()


## The road's heading next to a point (route-local), from the path points.
func _road_direction(route: Node3D, local_point: Vector3) -> Vector3:
	var path: Array[Vector3] = []
	path.assign(route.get(&"_path_points"))
	var nearest: int = 0
	for index: int in range(path.size()):
		if Vector2(path[index].x - local_point.x, path[index].z - local_point.z).length() < Vector2(path[nearest].x - local_point.x, path[nearest].z - local_point.z).length():
			nearest = index
	var a: Vector3 = path[maxi(nearest - 1, 0)]
	var b: Vector3 = path[mini(nearest + 1, path.size() - 1)]
	var local_dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var world: Vector3 = route.global_basis * local_dir
	return Vector3(world.x, 0.0, world.z).normalized()


func _signature(route: Node3D) -> Array:
	var signature: Array = []
	for node: Node3D in _placed(route):
		signature.append([node.scene_file_path, route.to_local(node.global_position).snapped(Vector3.ONE * 0.01)])
	return signature


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
