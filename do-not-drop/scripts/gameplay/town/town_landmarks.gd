extends RefCounted
## Authored landmarks occupy spare plots, leaving every address/green access clear.
const ART := preload("res://scripts/gameplay/town/town_art.gd")
const PLAN := preload("res://modules/town_gen/town_plan.gd")
const SOURCES: Dictionary = {
	2: "res://assets/models/environment/landmarks/sm_env_landmark_water_tower.glb",
	3: "res://assets/models/environment/landmarks/sm_env_landmark_windmill.glb",
}


static func build(
	town: Node3D, plan: Dictionary, districts: PackedInt32Array, pedestrian: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = "DistrictLandmarks"
	town.add_child(holder)
	var plots: Array = town.get_meta(&"landmark_plots", [])
	if not town.has_meta(&"landmark_plots"):
		plots = prepare(town, plan, districts, pedestrian)
	for plot: Dictionary in plots:
		var landmark: Node3D = ART.model(
			holder,
			"District_%d" % plot.id,
			plot.model,
			Vector3(plot.position.x, .08, plot.position.y),
			0,
			true
		)
		landmark.set_meta(&"district", plot.id)
		landmark.set_meta(&"clearance_radius", plot.radius)


## Reserve a small foundation before terrain sampling so native models keep
## all their feet supported when the surrounding ground has natural relief.
static func prepare(
	town: Node3D, plan: Dictionary, districts: PackedInt32Array, pedestrian: Dictionary
) -> Array[Dictionary]:
	var plots: Array[Dictionary] = []
	var kit := ART.KIT.new(town)
	for id: int in SOURCES:
		if id not in districts:
			continue
		var path: String = SOURCES[id]
		var bounds: AABB = kit.model_bounds(path)
		var radius: float = 0
		for x: float in [bounds.position.x, bounds.end.x]:
			for z: float in [bounds.position.z, bounds.end.z]:
				radius = maxf(radius, Vector2(x, z).length())
		var plot: Variant = _find_plot(plan, pedestrian, id, radius)
		if plot == null:
			continue
		plots.append({"id": id, "model": path, "position": plot, "radius": radius})
	return plots


static func _find_plot(plan: Dictionary, pedestrian: Dictionary, id: int, radius: float) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, &"town_landmark", id])
	for attempt: int in range(600):
		var at: Vector2 = (
			plan.districts[id].center
			+ Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(25, 110)
		)
		if PLAN.road_clearance(plan, at) < radius + 4:
			continue
		var free: bool = true
		for i: int in range(12):
			free = (
				free
				and Geometry2D.is_point_in_polygon(
					at + Vector2.from_angle(TAU * i / 12.0) * radius, plan.districts[id].outline
				)
			)
		for lot: Dictionary in plan.lots:
			free = free and at.distance_to(lot.position) > radius + lot.size.length() * .5 + 2
		for green: Dictionary in plan.green_areas:
			free = free and at.distance_to(green.position) > radius + green.radius + 2
		for key: String in ["lot_paths", "green_paths"]:
			for path: Dictionary in pedestrian[key]:
				for i: int in range(1, path.points.size()):
					var near: Vector2 = Geometry2D.get_closest_point_to_segment(
						at, path.points[i - 1], path.points[i]
					)
					free = free and at.distance_to(near) > radius + path.width * .5 + 2
		if free:
			return at
	return null
