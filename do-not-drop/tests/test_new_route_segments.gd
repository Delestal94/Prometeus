extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_new_route_segments.gd
## Covers docs/tareas-nacho.md #57, #61, #64: the three newest RouteSegment
## types. SCurveSegment and ConstructionZoneSegment are geometry-only checks;
## GravelSegment gets real physics frames since what matters there is that
## wheel_friction_slip actually changes and actually restores, not just that
## an Area3D exists.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_check_s_curve()
	_check_construction_zone()
	await _check_gravel()

	if _failures == 0:
		print("PASS: S-curve, gravel grip zone and construction zone all behave as designed")
	quit(_failures)


func _check_s_curve() -> void:
	var segment := SCurveSegment.new()
	root.add_child(segment)
	var blocks: Array[Node] = []
	for index: int in range(4):
		var block: Node = segment.get_node_or_null(NodePath("SCurveBlock" + str(index)))
		_expect(block != null, "SCurveBlock%d exists" % index)
		if block != null:
			blocks.append(block)
	if blocks.size() == 4:
		var sides: Array[float] = []
		for block: Node in blocks:
			sides.append(signf((block as Node3D).position.x))
		_expect(sides == [-1.0, 1.0, -1.0, 1.0],
			"Blocks alternate sides in order, doubling the single chicane's one weave into two (got %s)" % [sides])
		# N-803: solid well above what's drawn, so a truck can't end up on top.
		for block: Node in blocks:
			var height: float = 0.0
			for shape: Node in block.get_children():
				if shape is CollisionShape3D and (shape as CollisionShape3D).shape is BoxShape3D:
					height = ((shape as CollisionShape3D).shape as BoxShape3D).size.y
			_expect(height >= 1.5, "%s is too tall to end up sitting on (%.2f m)" % [block.name, height])
		_expect(segment.get_node_or_null(^"SCurveBlock0Visual") != null, "Each block is still drawn at its own size")
	segment.free()


func _check_construction_zone() -> void:
	var segment := ConstructionZoneSegment.new()
	root.add_child(segment)
	# The solid wall; the imported barrier models along it are ConstructionBarrier0..N.
	var barrier: Node = segment.get_node_or_null(^"ConstructionBarrierCollision")
	_expect(barrier != null, "ConstructionBarrierCollision exists")
	_expect(segment.get_node_or_null(^"ConstructionBarrier0") != null, "Barrier models line the wall")
	if barrier != null:
		_expect((barrier as Node3D).position.x > 0.0,
			"Barrier sits off-center, narrowing one side of the lane rather than blocking it entirely")
	var first_cone: Node = segment.get_node_or_null(^"ConstructionCone0")
	_expect(first_cone != null, "Cones mark the narrowed edge for visibility")
	# N-803: a truck that clipped a static 0.65 m cone could land on it, or
	# on the 0.9 m wall, with its wheels in the air and no way off. Cones are
	# light bodies it bats aside, and the wall is too tall to be climbed.
	_expect(first_cone is RigidBody3D and (first_cone as RigidBody3D).mass <= 10.0,
		"Cones are light bodies the truck knocks over, not posts (got %s)" % [first_cone])
	if barrier != null:
		var wall_height: float = 0.0
		for shape: Node in barrier.get_children():
			if shape is CollisionShape3D and (shape as CollisionShape3D).shape is BoxShape3D:
				wall_height = ((shape as CollisionShape3D).shape as BoxShape3D).size.y
		_expect(wall_height >= 1.5, "The barrier's wall is too tall for the truck to end up sitting on (%.2f m)" % wall_height)
	segment.free()


func _check_gravel() -> void:
	var segment := GravelSegment.new()
	root.add_child(segment)
	await process_frame  # let the Area3D's shape register with the physics server

	var vehicle := VehicleBody3D.new()
	vehicle.add_to_group(&"vehicle")
	vehicle.collision_layer = 2
	vehicle.collision_mask = 5
	var chassis_collider := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(2.0, 1.0, 4.0)
	chassis_collider.shape = chassis_shape
	vehicle.add_child(chassis_collider)
	var wheels: Array[VehicleWheel3D] = []
	for _i: int in range(4):
		var wheel := VehicleWheel3D.new()
		wheel.wheel_friction_slip = 3.5
		vehicle.add_child(wheel)
		wheels.append(wheel)
	root.add_child(vehicle)

	# Start well outside the trigger (segment's road runs z in [0, -30]).
	vehicle.global_position = Vector3(0.0, 0.0, 50.0)
	for _i: int in range(3):
		await physics_frame
	for wheel: VehicleWheel3D in wheels:
		_expect(wheel.wheel_friction_slip == 3.5, "Grip untouched before entering the gravel zone")

	# Move it into the trigger zone (centred at z=-15) and let overlap resolve.
	vehicle.global_position = Vector3(0.0, 0.0, -15.0)
	for _i: int in range(5):
		await physics_frame
	for wheel: VehicleWheel3D in wheels:
		_expect(is_equal_approx(wheel.wheel_friction_slip, segment.reduced_friction_slip),
			"Grip actually drops while inside the gravel zone (got %.2f)" % wheel.wheel_friction_slip)

	# Move it back out and confirm the restore, not just that it changed once.
	vehicle.global_position = Vector3(0.0, 0.0, 50.0)
	for _i: int in range(5):
		await physics_frame
	for wheel: VehicleWheel3D in wheels:
		_expect(wheel.wheel_friction_slip == 3.5, "Grip restores to its original value after leaving the gravel zone")

	vehicle.free()
	segment.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
