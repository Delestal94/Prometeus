extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_road_hazards.gd
## Where the new roadside hazards go (tareas de Nacho N-106), on real routes:
##   - storm debris only when it rains, solid, and always leaving a lane
##     free to drive round it;
##   - flocks only in open country, the dog only in a village;
##   - all of it from the session seed: the same seed places the same.

const SEEDS: Array[int] = [11, 222, 3333, 4444, 55555, 666666, 7777777, 88888888]
const MIN_FREE_WIDTH: float = 5.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var debris_seen: int = 0
	var flocks_seen: int = 0
	var dogs_seen: int = 0
	for seed_value: int in SEEDS:
		network.set(&"world_seed", seed_value)
		network.set(&"world_house_count", 3)
		var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
		route.set(&"batch_dressing", false)
		root.add_child(route)
		var dresser: RouteDresser = route.get(&"dresser")
		var raining: bool = (route.get(&"mood") as WorldMood).is_raining()
		var debris: Array = _find(route, "StormDebris")
		_expect(raining or debris.is_empty(), "Seed %d: no storm debris without rain" % seed_value)
		if not raining:
			# Rain it on this route to see where the debris would go.
			dresser.raining = true
			dresser.call(&"_dress_storm_debris", route.get(&"_segments"))
			debris = _find(route, "StormDebris")
		debris_seen += debris.size()
		for piece: StaticBody3D in debris:
			_expect(piece.collision_layer & 1 != 0, "Seed %d: debris is solid" % seed_value)
			var free: float = _free_width(piece)
			_expect(free >= MIN_FREE_WIDTH, "Seed %d: debris leaves %.1f m of road free (at least %.0f)" % [seed_value, free, MIN_FREE_WIDTH])
		for flock: Node3D in _find(route, "FlockCrossing"):
			flocks_seen += 1
			var segment: RouteSegment = flock.get_parent()
			var zone: int = dresser.zone_at(segment.transform * flock.position, float(segment.get_meta(&"route_distance", 0.0)))
			_expect(zone == RouteDresser.Zone.COUNTRYSIDE, "Seed %d: the flock is in open country" % seed_value)
		for dog: Node3D in _find(route, "ChasingDog"):
			dogs_seen += 1
			var segment: RouteSegment = dog.get_parent()
			var zone: int = dresser.zone_at(segment.transform * Vector3.ZERO, float(segment.get_meta(&"route_distance", 0.0)))
			_expect(zone == RouteDresser.Zone.VILLAGE, "Seed %d: the dog is in a village" % seed_value)
		route.free()
		await process_frame
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	_expect(debris_seen > 0, "Some routes do get storm debris in the rain (%d pieces)" % debris_seen)
	_expect(flocks_seen > 0, "Some routes get a flock (%d)" % flocks_seen)
	_expect(dogs_seen > 0, "Some routes get a dog (%d)" % dogs_seen)
	print("HAZARDS over %d seeds: %d debris, %d flocks, %d dogs" % [SEEDS.size(), debris_seen, flocks_seen, dogs_seen])
	if _failures == 0:
		print("PASS: storm debris only in the rain and never blocking the road, flocks in the country, dogs in villages")
	quit(_failures)


func _find(route: Node, node_name: String) -> Array:
	return route.find_children(node_name + "*", "", true, false)


## Road width (of 12 m) left uncovered by the debris' collider, measured
## across the road in its segment's space.
func _free_width(piece: StaticBody3D) -> float:
	var shape := piece.get_child(piece.get_child_count() - 1) as CollisionShape3D
	var box: Vector3 = (shape.shape as BoxShape3D).size
	var low: float = INF
	var high: float = -INF
	for corner: int in range(8):
		var local := Vector3((corner & 1) * 2 - 1, ((corner >> 1) & 1) * 2 - 1, ((corner >> 2) & 1) * 2 - 1) * box * 0.5
		var x: float = (piece.transform * (shape.transform * local)).x
		low = minf(low, x)
		high = maxf(high, x)
	var covered: float = maxf(0.0, minf(high, 6.0) - maxf(low, -6.0))
	return 12.0 - covered


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
