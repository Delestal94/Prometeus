extends SceneTree
## Rewritten 2026-09-22: route.gd generates a random, curving path now (real
## turns, no fixed coordinates), so this can no longer assert "there's a
## chicane at exactly (2,0,-106)" -- that position doesn't necessarily exist
## on any given run. Instead it checks the invariants that still have to
## hold no matter what the RNG rolled: progress goes from 0 to 1, ground
## exists under sampled points actually pulled from the generated path, and
## the goal area still detects entry/exit at wherever the goal really ended
## up (route.goal_transform), not an assumed world position.


func _initialize() -> void:
	call_deferred("_check_route")


func _check_route() -> void:
	var scene := load("res://scenes/gameplay/route/route.tscn") as PackedScene
	var route := scene.instantiate() as Node3D
	root.add_child(route)
	await physics_frame

	var route_length: float = float(route.get(&"route_length"))
	assert(route_length > 0.0, "route_length should be positive after building")
	var goal_transform: Transform3D = route.get(&"goal_transform")

	assert(is_equal_approx(route.get_progress(route.to_global(Vector3.ZERO)), 0.0),
		"Progress at the very start of the route is 0")
	assert(is_equal_approx(route.get_progress(goal_transform.origin), 1.0),
		"Progress at the goal is 1")

	# Sample real points along the path the route actually generated (via
	# route.gd's own dense ~10m-spaced path points, the same ones
	# distance_from_path() uses) instead of assuming fixed coordinates --
	# ground/collision has to exist under every one of them, whatever shape
	# the road took. Deliberately NOT the coarser _progress_samples (segment
	# boundaries only, up to 60m apart): those sit exactly on the
	# mathematical seam between two segments' boxes, and a ray landing
	# exactly on that shared edge is a real floating-point edge case a
	# moving vehicle never actually experiences (it's always comfortably
	# inside one box or the other) -- worth not conflating with an actual
	# gap in the drivable surface.
	var path_points: Array = route.get(&"_path_points")
	assert(path_points.size() >= 20, "A route this long should have plenty of dense path points (got %d)" % path_points.size())
	var state := root.world_3d.direct_space_state
	var checked: int = 0
	for i: int in range(0, path_points.size(), maxi(1, path_points.size() / 20)):
		var local_position: Vector3 = path_points[i]
		var position: Vector3 = route.to_global(local_position)
		var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 4, position + Vector3.DOWN * 2, 1)
		var result: Dictionary = state.intersect_ray(ray)
		assert(not result.is_empty(), "Missing ground at sampled path point %s" % position)
		# Road hazards may sit above the pavement; the landscape may not fall
		# below its sampled surface. Exact mesh agreement is in test_route_terrain.
		assert(result.position.y >= position.y - 0.02, "Road collision is below terrain at %s" % position)
		checked += 1
	assert(checked >= 10, "Should have actually checked several path points (got %d)" % checked)

	var houses: Array = route.get(&"houses")
	var house_count: int = int(route.get(&"house_count"))
	assert(houses.size() == house_count, "Builds exactly house_count houses (got %d, expected %d)" % [houses.size(), house_count])

	var vehicle := CharacterBody3D.new()
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1
	vehicle.position = (goal_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 3.0))).origin
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1, 4)
	collider.shape = box
	vehicle.add_child(collider)
	root.add_child(vehicle)
	await physics_frame
	await physics_frame
	assert(route.is_vehicle_in_delivery, "Goal area did not detect layer 2 vehicle")
	vehicle.position = (goal_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 20.0))).origin
	await physics_frame
	await physics_frame
	assert(not route.is_vehicle_in_delivery, "Goal area did not clear after vehicle left")

	print("ROUTE SMOKE PASS: progress, generated-path ground collision, delivery entry/exit")
	quit(0)
