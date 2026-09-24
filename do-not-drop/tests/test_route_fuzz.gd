extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_fuzz.gd
## Fuzzing the procedural route (tareas de Nacho N-801), in two passes:
##
## 1. 500 seeds x 1-4 houses, from route.gd's plan (plan_spine(), what the
##    route builds) walked through the same transforms the segments chain
##    with: the road never comes back over itself -- two stretches further
##    apart than NEIGHBOUR_ALONG along the road stay a road's width apart.
## 2. BUILT_SEEDS whole routes actually built: no house or yard piece on the
##    asphalt, no solid tree within TREE_GAP of the lane, no step taller than
##    MAX_STEP in the ground under the road, and a road that reaches the goal
##    without a gap.
##
## Every failure names its seed and house count, to rebuild it with
## NetworkManager.world_seed.

const Route = preload("res://scripts/gameplay/route/route.gd")
const SEEDS: int = 500
const BUILT_SEEDS: int = 20
## Asphalt is 12 m wide.
const ROAD_HALF_WIDTH: float = 6.0
const ROAD_WIDTH: float = 12.0
## Closer than this along the road, two points are the same stretch.
const NEIGHBOUR_ALONG: float = 60.0
const STEP: float = 5.0
const TREE_GAP: float = 2.0
## A step, not a slope: the ground is sampled every STEP_SAMPLE metres, so a
## hill's steepest stretch (~0.3 m per metre) rises ~0.08 between samples.
const MAX_STEP: float = 0.3
const STEP_SAMPLE: float = 0.25
## Solid trees only: the forest group also holds bushes, rocks and grass.
const TREE_MODELS: Array[String] = ["sm_env_forest_oak.glb", "sm_env_forest_birch.glb", "sm_env_forest_pine_tall.glb",
	"sm_env_forest_maple.glb", "sm_env_forest_dead.glb", "sm_env_forest_pine_sapling.glb"]
const MAX_PATH_GAP: float = 15.0

var _failures: int = 0
var _failed_seeds: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for seed_value: int in range(1, SEEDS + 1):
		for houses: int in range(1, 5):
			_check_plan(seed_value, houses)
	for seed_value: int in range(1, BUILT_SEEDS + 1):
		await _check_built(seed_value * 7919, 1 + seed_value % 4)
	if not _failed_seeds.is_empty():
		push_error("Seeds to reproduce: %s" % ", ".join(_failed_seeds.slice(0, 30)))
	if _failures == 0:
		print("PASS: %d planned roads never cross themselves; %d built routes keep houses, yards and trees off the road, the ground smooth and the goal reachable" % [SEEDS * 4, BUILT_SEEDS])
	quit(_failures)


## Points along the planned road every ~STEP metres, [position, distance].
func _plan_points(plan: Dictionary) -> Array:
	var points: Array = []
	var cursor := Transform3D.IDENTITY
	var along: float = 0.0
	for segment: Dictionary in plan.segments:
		if segment.script == CurveSegment:
			var chords: int = roundi(CurveSegment.length_for_turn(segment.turn_deg) / CurveSegment.CHORD_LENGTH)
			var turn: float = deg_to_rad(segment.turn_deg) / float(chords)
			for chord: int in range(chords):
				for part: float in [0.0, 0.5]:
					points.append([cursor * Vector3(0.0, 0.0, -CurveSegment.CHORD_LENGTH * part), along + CurveSegment.CHORD_LENGTH * part])
				cursor = cursor * Transform3D(Basis(Vector3.UP, turn), Vector3(0.0, 0.0, -CurveSegment.CHORD_LENGTH))
				along += CurveSegment.CHORD_LENGTH
		else:
			var length: float = segment.length
			var done: float = 0.0
			while done < length:
				points.append([cursor * Vector3(0.0, 0.0, -done), along + done])
				done += STEP
			cursor = cursor * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -length))
			along += length
	points.append([cursor.origin, along])
	return points


func _check_plan(seed_value: int, houses: int) -> void:
	var points: Array = _plan_points(Route.plan_spine(seed_value, houses))
	# Bucketed by ROAD_WIDTH cells: only nearby cells can hold a crossing.
	var grid: Dictionary = {}
	for index: int in range(points.size()):
		var at: Vector3 = points[index][0]
		var cell := Vector2i(floori(at.x / ROAD_WIDTH), floori(at.z / ROAD_WIDTH))
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for other: int in grid.get(cell + Vector2i(dx, dz), []):
					var there: Vector3 = points[other][0]
					if float(points[index][1]) - float(points[other][1]) > NEIGHBOUR_ALONG and Vector2(at.x - there.x, at.z - there.z).length() < ROAD_WIDTH:
						_fail(seed_value, houses, "the road comes back over itself at %.0f m (over %.0f m)" % [points[index][1], points[other][1]])
						return
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(index)


func _check_built(seed_value: int, houses: int) -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	var terrain: Node = route.get(&"terrain")
	var road_distance := func(world_point: Vector3) -> float:
		var local: Vector3 = route.to_local(world_point)
		return float((terrain.call(&"nearest", Vector2(local.x, local.z)) as Vector3).x)

	for house: DeliveryHouse in route.get(&"houses"):
		var visual: Node = house.get_node_or_null(^"HouseVisual")
		var bounds: AABB = route.call(&"_local_bounds", house, visual) if visual != null else AABB()
		var gap: float = route.call(&"_house_road_gap", house, bounds)
		if gap < 0.0:
			_fail(seed_value, houses, "house %d stands on the asphalt (%.1f m)" % [house.house_index + 1, gap])
		var yard: Node = house.get_node_or_null(^"Yard")
		if yard != null:
			for piece: Node in yard.get_children():
				if piece is Node3D and road_distance.call((piece as Node3D).global_position) < ROAD_HALF_WIDTH:
					_fail(seed_value, houses, "a yard piece of house %d is on the asphalt (%s)" % [house.house_index + 1, piece.name])
					break

	var tree_failed: bool = false
	for group: Node in route.find_children("ForestDressing", "Node3D", true, false):
		for tree: Node in group.get_children():
			if tree_failed or not tree is Node3D or not tree.scene_file_path.get_file() in TREE_MODELS:
				continue
			var gap: float = road_distance.call((tree as Node3D).global_position)
			if gap < ROAD_HALF_WIDTH + TREE_GAP:
				_fail(seed_value, houses, "a tree (%s) stands %.1f m from the road's centre" % [tree.scene_file_path.get_file(), gap])
				tree_failed = true

	var path: Array = route.get(&"_path_points")
	for index: int in range(1, path.size()):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		if a.distance_to(b) > MAX_PATH_GAP:
			_fail(seed_value, houses, "the road has a %.0f m gap at point %d: the goal can't be reached" % [a.distance_to(b), index])
			break
		var previous: float = float(terrain.call(&"height_at", a))
		var steps: int = ceili(a.distance_to(b) / STEP_SAMPLE)
		var broken: bool = false
		for step: int in range(1, steps + 1):
			var height: float = float(terrain.call(&"height_at", a.lerp(b, float(step) / steps)))
			if absf(height - previous) > MAX_STEP:
				_fail(seed_value, houses, "a %.2f m step in the ground under the road near point %d" % [absf(height - previous), index])
				broken = true
				break
			previous = height
		if broken:
			break

	route.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame


func _fail(seed_value: int, houses: int, what: String) -> void:
	_failures += 1
	push_error("Seed %d, %d houses: %s" % [seed_value, houses, what])
	var key: String = "%d/%d" % [seed_value, houses]
	if not _failed_seeds.has(key):
		_failed_seeds.append(key)
