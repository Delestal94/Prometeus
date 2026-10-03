extends "res://scripts/gameplay/route/route_terrain.gd"
## Urban profile of the original terrain: keep district interiors level,
## blend into its natural landscape outside the irregular city boundaries.

var city_outlines: Array[PackedVector2Array] = []
var _platform_index: Dictionary = {}
var _profile_indexed: bool = false


## Prepare once after adding all platforms, before synchronous/worker sampling.
func index_profile() -> void:
	_platform_index.clear()
	for platform: Dictionary in platforms:
		var along: Vector2 = platform.along
		var across := Vector2(-along.y, along.x)
		var half: Vector2 = platform.half
		var extent: Vector2 = (
			along.abs() * half.y + across.abs() * half.x + Vector2.ONE * PLATFORM_BLEND
		)
		var low: Vector2 = platform.centre - extent
		var high: Vector2 = platform.centre + extent
		for x: int in range(floori(low.x / TILE), floori(high.x / TILE) + 1):
			for z: int in range(floori(low.y / TILE), floori(high.y / TILE) + 1):
				var key := Vector2i(x, z)
				if not _platform_index.has(key):
					_platform_index[key] = [] as Array[Dictionary]
				_platform_index[key].append(platform)
	_profile_indexed = true


func _platform_candidates(p: Vector2) -> Array[Dictionary]:
	if not _profile_indexed:
		return platforms
	var key := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	var empty: Array[Dictionary] = []
	return _platform_index.get(key, empty)


## Fill the irregular city envelope as well as the original road halos.
func complete_surface() -> void:
	var points := PackedVector2Array()
	for outline: PackedVector2Array in city_outlines:
		points.append_array(outline)
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	var expanded: Array[PackedVector2Array] = Geometry2D.offset_polygon(hull, HALO)
	if expanded.is_empty():
		return
	var boundary: PackedVector2Array = expanded[0]
	var bounds := Rect2(boundary[0], Vector2.ZERO)
	for point: Vector2 in boundary:
		bounds = bounds.expand(point)
	for x: int in range(floori(bounds.position.x / TILE), floori(bounds.end.x / TILE) + 1):
		for z: int in range(floori(bounds.position.y / TILE), floori(bounds.end.y / TILE) + 1):
			var origin := Vector2(x, z) * TILE
			var tile := PackedVector2Array(
				[
					origin,
					origin + Vector2(TILE, 0),
					origin + Vector2.ONE * TILE,
					origin + Vector2(0, TILE)
				]
			)
			if not Geometry2D.intersect_polygons(tile, boundary).is_empty():
				_tiles[Vector2i(x, z)] = true


func _natural_height_from(p: Vector2, road: Vector3, with_ridge: bool = true) -> float:
	# Interiors are exactly zero. Avoid evaluating every inherited platform
	# and then discarding the result for each terrain vertex in the city.
	for outline: PackedVector2Array in city_outlines:
		if Geometry2D.is_point_in_polygon(p, outline):
			return 0.0
	var original: float = super(p, road, with_ridge)
	var distance: float = INF
	for outline: PackedVector2Array in city_outlines:
		for i: int in range(outline.size()):
			distance = minf(
				distance,
				p.distance_to(
					Geometry2D.get_closest_point_to_segment(
						p, outline[i], outline[(i + 1) % outline.size()]
					)
				)
			)
	return original * smoothstep(0, 24, distance)
