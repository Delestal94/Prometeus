extends RefCounted
## Adapt the existing route terrain and straight segments to a branched city.
## The town keeps its graph/addresses; route_gen supplies textured ground and art.

const TERRAIN := preload("res://scripts/gameplay/town/town_terrain.gd")
const STRAIGHT := preload("res://modules/route_gen/straight_segment.gd")
const NAV := preload("res://modules/town_gen/town_navigation.gd")
const BIOMES := preload("res://scripts/gameplay/town/town_biomes.gd")
const LANDMARKS := preload("res://scripts/gameplay/town/town_landmarks.gd")


static func build_ground(
	town: Node3D, plan: Dictionary, districts: PackedInt32Array, pedestrian: Dictionary
) -> TerrainField:
	var terrain: TERRAIN = TERRAIN.new()
	terrain.name = "ContinuousTerrain"
	town.add_child(terrain)
	for district: Dictionary in plan.districts:
		if district.id in districts:
			terrain.city_outlines.append(district.outline)
	for edge: Dictionary in NAV.accessible_edges(plan, districts):
		_register_road(terrain, plan.nodes[edge.a], plan.nodes[edge.b], edge.width * .5)
	for gate: Dictionary in plan.gates:
		var first: bool = gate.districts.x in districts
		if first == (gate.districts.y in districts):
			continue
		var a: Vector2 = plan.nodes[gate.a if first else gate.b]
		var b: Vector2 = plan.nodes[gate.b if first else gate.a]
		_register_road(terrain, a, a.move_toward(b, minf(35, a.distance_to(b) * .5)))
	for lot: Dictionary in plan.lots:
		if lot.district in districts:
			terrain.platforms.append(
				{
					"centre": lot.position,
					"along": Vector2.from_angle(lot.angle + PI * .5),
					"half": lot.size * .5 + Vector2.ONE * 2,
					"height": 0.0
				}
			)
	for green: Dictionary in plan.green_areas:
		if green.district in districts:
			terrain.platforms.append(
				{
					"centre": green.position,
					"along": Vector2.DOWN,
					"half": Vector2.ONE * (green.radius + 2),
					"height": 0.0
				}
			)
	for key: String in ["lot_paths", "green_paths", "corner_paths"]:
		for path: Dictionary in pedestrian[key]:
			for i: int in range(1, path.points.size()):
				_level_strip(terrain, path.points[i - 1], path.points[i], path.width * .5 + 2)
	var plots: Array[Dictionary] = LANDMARKS.prepare(town, plan, districts, pedestrian)
	town.set_meta(&"landmark_plots", plots)
	for plot: Dictionary in plots:
		terrain.platforms.append(
			{
				"centre": plot.position,
				"along": Vector2.DOWN,
				"half": Vector2.ONE * (plot.radius + 2),
				"height": 0.0
			}
		)
	BIOMES.configure(terrain, plan, districts)
	terrain.index_profile()
	if districts.size() == 6:
		terrain.complete_surface()
	terrain.build()
	return terrain


static func _register_road(terrain: TerrainField, a: Vector2, b: Vector2, half: float = 6) -> void:
	terrain.add_span(Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), false, half)
	_level_strip(terrain, a, b, half + 5)


static func _level_strip(terrain: TerrainField, a: Vector2, b: Vector2, width: float) -> void:
	if a.distance_squared_to(b) < .000001:
		return
	terrain.platforms.append(
		{
			"centre": (a + b) * .5,
			"along": (b - a).normalized(),
			"half": Vector2(width, a.distance_to(b) * .5 + 2),
			"height": 0.0
		}
	)


static func build_segments(
	town: Node3D, plan: Dictionary, districts: PackedInt32Array
) -> Array[RouteSegment]:
	var segments: Array[RouteSegment] = []
	var edges: Array[Dictionary] = NAV.accessible_edges(plan, districts)
	var spans: Array[Dictionary] = (town.get(&"terrain") as TerrainField).spans
	var holder := Node3D.new()
	holder.name = "RouteStreets"
	town.add_child(holder)
	for index: int in range(edges.size()):
		var edge: Dictionary = edges[index]
		var a: Vector2 = plan.nodes[edge.a]
		var b: Vector2 = plan.nodes[edge.b]
		var direction: Vector2 = (b - a).normalized()
		if a.distance_to(b) <= 20:
			continue
		var segment: RouteSegment = STRAIGHT.new()
		segment.length = a.distance_to(b) - 20
		segment.continuous_terrain = true
		segment.scale.x = edge.width / 12.0
		segment.position = Vector3(a.x + direction.x * 10, .20, a.y + direction.y * 10)
		segment.rotation.y = atan2(-direction.x, -direction.y)
		segment.set_meta(&"district", edge.district)
		segment.set_meta(&"block_street", edge.get("block_street", false))
		holder.add_child(segment)
		# Original paint must end where any other branch crosses this street.
		for marking: Node3D in segment.get_children():
			var mesh := marking.get_child(0) as MeshInstance3D
			var box: AABB = mesh.get_aabb()
			var clear: bool = true
			for x: float in [box.position.x, box.end.x]:
				for z: float in [box.position.z, box.end.z]:
					var world: Vector3 = town.to_local(mesh.to_global(Vector3(x, 0, z)))
					var point := Vector2(world.x, world.z)
					for other: int in range(spans.size()):
						if other == index:
							continue
						var branch: Dictionary = spans[other]
						var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
							point, branch.a, branch.b
						)
						clear = clear and point.distance_to(closest) > float(branch.width) + .3
			if not clear:
				marking.free()
		segments.append(segment)
	return segments
