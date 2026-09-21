extends SceneTree


func _initialize() -> void:
	call_deferred("_check_route")


func _check_route() -> void:
	var scene := load("res://scenes/gameplay/route/route.tscn") as PackedScene
	var route := scene.instantiate() as Node3D
	root.add_child(route)
	await physics_frame
	assert(is_equal_approx(route.get_progress(Vector3(0, 0, -110)), 0.5))
	assert(is_equal_approx(route.get_progress(Vector3(0, 0, -240)), 1.0))
	var state := root.world_3d.direct_space_state
	for position: Vector3 in [Vector3(0, 0, 0), Vector3(0, 0, -52), Vector3(2, 0, -106), Vector3(-2, 0, -126), Vector3(0, 0, -162), Vector3(0, 0, -220), Vector3(20, 0, -162)]:
		var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 4, position + Vector3.DOWN * 2, 1)
		var result: Dictionary = state.intersect_ray(ray)
		assert(not result.is_empty(), "Missing ground at %s" % position)
		assert(result.position.y > -0.5, "Unsafe road/shoulder drop at %s" % position)
	var vehicle := CharacterBody3D.new()
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1
	vehicle.position = Vector3(0, 1, -220)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1, 4)
	collider.shape = box
	vehicle.add_child(collider)
	root.add_child(vehicle)
	await physics_frame
	await physics_frame
	assert(route.is_vehicle_in_delivery, "Delivery did not detect layer 2 vehicle")
	vehicle.position.z = -200
	await physics_frame
	await physics_frame
	assert(not route.is_vehicle_in_delivery, "Delivery did not clear after vehicle left")
	print("ROUTE SMOKE PASS: progress, road/bump/bridge/ground collision, delivery entry/exit")
	quit(0)
