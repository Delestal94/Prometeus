extends SceneTree

var failures: int = 0

func _initialize() -> void:
	await process_frame
	for spec: Array in [
		["environment/props/sm_env_prop_street_lamp_refined.glb", 4.5, 4.8],
		["vehicles/sm_vehicle_parked_sedan_refined.glb", 1.4, 1.7],
		["vehicles/sm_vehicle_competitor_van.glb", 2.2, 2.5],
		["vehicles/sm_vehicle_tractor.glb", 2.3, 2.6],
		["props/handheld/sm_prop_phone_refined.glb", .14, .15],
	]:
		var model: Node3D = load("res://assets/models/" + spec[0]).instantiate()
		root.add_child(model)
		var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
		if bounds.size.y < spec[1] or bounds.size.y > spec[2]:
			push_error("Incorrect vertical size: %s %s" % [spec[0], bounds])
			failures += 1
		if spec[0].begins_with("vehicles/") and (absf(bounds.position.y) > .02 or bounds.size.z < 3.0):
			push_error("Vehicle must rest on its wheels and extend along Z: %s" % bounds)
			failures += 1
		model.free()
	print("Asset orientation/scale failures: ", failures)
	quit(failures)

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result := AABB()
	if node is MeshInstance3D:
		result = transform * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = _bounds(child, transform)
			if child_bounds.size != Vector3.ZERO:
				result = child_bounds if result.size == Vector3.ZERO else result.merge(child_bounds)
	return result
