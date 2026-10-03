extends RouteDresser
## Existing route placement/catalog, with an urban zone profile and reserved
## parcels, plazas and walking paths. No linear-route hazards or delivery logic.

var _outlines: Array[PackedVector2Array] = []
var _zones: Array[int] = []


func _init(route: Node3D, terrain: Node, seed_value: int) -> void:
	super(route, terrain, seed_value)
	# Only the catalog/placement gate is used. Linear-route feature helpers
	# hold references back to the dresser; release them to avoid retaining it.
	_signage = null
	_wildlife = null
	_power_lines = null


func dress_town(
	segments: Array[RouteSegment],
	plan: Dictionary,
	districts: PackedInt32Array,
	pedestrian: Dictionary
) -> void:
	for district: Dictionary in plan.districts:
		if district.id in districts:
			_outlines.append(district.outline)
			_zones.append(
				(
					Zone.COUNTRYSIDE
					if district.id == 3
					else (Zone.FOREST if district.id == 5 else Zone.VILLAGE)
				)
			)
	for lot: Dictionary in plan.lots:
		_placement.clear_zones.append(
			Vector3(lot.position.x, lot.position.y, lot.size.length() * .5 + 2)
		)
	for green: Dictionary in plan.green_areas:
		_placement.clear_zones.append(Vector3(green.position.x, green.position.y, green.radius + 3))
	for landmark: Node3D in _route.get_node(^"DistrictLandmarks").get_children():
		if not landmark.has_meta(&"clearance_radius"):
			continue
		_placement.clear_zones.append(
			Vector3(
				landmark.position.x,
				landmark.position.z,
				float(landmark.get_meta(&"clearance_radius")) + 2
			)
		)
	for key: String in ["lot_paths", "green_paths"]:
		for path: Dictionary in pedestrian[key]:
			for i: int in range(1, path.points.size()):
				var a: Vector2 = path.points[i - 1]
				var b: Vector2 = path.points[i]
				var count: int = maxi(1, ceili(a.distance_to(b) / 3))
				for step: int in range(count + 1):
					var at: Vector2 = a.lerp(b, float(step) / count)
					_placement.clear_zones.append(Vector3(at.x, at.y, path.width * .5 + 2))
	var coast: Dictionary = _terrain.get(&"coast")
	if not coast.is_empty():
		var access: PackedVector2Array = coast.access
		for i: int in range(1, access.size()):
			var a: Vector2 = access[i - 1]
			var b: Vector2 = access[i]
			var count: int = maxi(1, ceili(a.distance_to(b) / 3))
			for step: int in range(count + 1):
				var at: Vector2 = a.lerp(b, float(step) / count)
				_placement.clear_zones.append(Vector3(at.x, at.y, 4))
	var selected: Array[StringName] = [
		&"parked_vehicle",
		&"village_furniture",
		&"bus_stop",
		&"tree",
		&"ground_plant",
		&"farm_props",
		&"tractor"
	]
	for index: int in range(_rules.size()):
		var rule: Dictionary = _rules[index]
		if rule.id not in selected:
			continue
		# Keep even small props outside the 2 m sidewalk and its outer ramp.
		rule.clearance = maxf(rule.clearance, 9.2)
		if rule.id == &"village_furniture":
			rule.lateral = Vector2(10.4, 11.5)
		if rule.id == &"ground_plant":
			rule.spacing = 3.0
		for segment_index: int in range(segments.size()):
			await _apply_rule(segments[segment_index], segment_index, index)
	progress = 1.0


func zone_at(route_point: Vector3, _distance: float) -> int:
	for i: int in range(_outlines.size()):
		if Geometry2D.is_point_in_polygon(Vector2(route_point.x, route_point.z), _outlines[i]):
			return _zones[i]
	return Zone.FOREST
