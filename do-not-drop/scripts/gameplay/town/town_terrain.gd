extends "res://scripts/gameplay/route/route_terrain.gd"
## Urban profile of the original terrain: keep district interiors level,
## blend into its natural landscape outside the irregular city boundaries.

var city_outlines: Array[PackedVector2Array] = []


func _natural_height_from(p: Vector2, road: Vector3, with_ridge: bool = true) -> float:
	var original: float = super(p, road, with_ridge)
	var distance: float = INF
	for outline: PackedVector2Array in city_outlines:
		if Geometry2D.is_point_in_polygon(p, outline):
			return 0.0
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
