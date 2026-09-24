extends SceneTree
## The seated driver's visible arms must reach the real wheel targets.

var _failures := 0

func _initialize() -> void:
	var vehicle: Node3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(vehicle)
	root.add_child(player)
	await process_frame
	var seat: Node3D = vehicle.get_node(^"CabinInterior/DriverEyePoint")
	var camera: Node = seat.get_node(^"FirstPersonCamera")
	player.call(&"board_seat", camera.get_path(), seat.get_path())
	for _i: int in range(20):
		await physics_frame
	var body: Node = player.get_node(^"BodyVisual")
	var skeleton := _find_skeleton(body)
	_expect(skeleton != null, "Driver has a skeleton")
	_expect(skeleton.get_children().filter(func(node: Node) -> bool: return node is SkeletonIK3D).size() == 2,
		"Both driver arms are solved by SkeletonIK3D")
	_expect(vehicle.find_child("DriverHandTargetLeft", true, false) != null
		and vehicle.find_child("DriverHandTargetRight", true, false) != null,
		"Both hand targets are attached to the steering wheel")
	# The character's own arms reach the wheel now (no stand-in cylinders):
	# each solved wrist lands on its target.
	_expect(vehicle.find_child("DriverArmVisualLeft", true, false) == null,
		"No stand-in arm cylinders: the skinned arms do the reaching")
	# SkeletonIK3D is a SkeletonModifier3D: its result only exists between the
	# modifier pass and the skin update, so the wrists are read in there.
	var wrists: Dictionary = {}
	var shoulders: Dictionary = {}
	var capture := func() -> void:
		for bone_name: StringName in [&"hand.L", &"hand.R"]:
			var bone: int = skeleton.find_bone(bone_name)
			if bone >= 0:
				wrists[bone_name] = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
				var shoulder: int = skeleton.get_bone_parent(skeleton.get_bone_parent(bone))
				shoulders[bone_name] = skeleton.to_global(skeleton.get_bone_global_pose(shoulder).origin)
	skeleton.skeleton_updated.connect(capture)
	for _i: int in range(3):
		await process_frame
	skeleton.skeleton_updated.disconnect(capture)
	for pair: Array in [[&"hand.L", "DriverHandTargetLeft"], [&"hand.R", "DriverHandTargetRight"]]:
		var target := vehicle.find_child(pair[1], true, false) as Node3D
		_expect(wrists.has(pair[0]), "Skeleton has bone %s" % pair[0])
		if wrists.has(pair[0]) and target != null:
			var gap: float = (wrists[pair[0]] as Vector3).distance_to(target.global_position)
			print("driver %s wrist-to-wheel gap: %.3f m, shoulder-to-wheel %.3f m" % [pair[0], gap,
				(shoulders[pair[0]] as Vector3).distance_to(target.global_position)])
			_expect(gap < 0.08, "%s reaches its wheel target (gap %.3f m)" % [pair[0], gap])
	# The horn takes the character's own right hand to the hub, and nothing
	# else on the wheel is a hand.
	_expect(vehicle.find_child("DriverHands", true, false) == null and vehicle.find_child("DriverGlove*", true, false) == null,
		"No stand-in gloves hang on the steering wheel")
	var right_target := vehicle.find_child("DriverHandTargetRight", true, false) as Node3D
	var rim: Vector3 = right_target.position
	vehicle.get_node(^"VehiclePresentation").set(&"_horn_press", 0.45)
	for _i: int in range(2):
		await process_frame
	_expect(right_target.position.distance_to(rim) > 0.1, "Honking moves the driver's own right hand off the rim")
	await create_timer(0.6).timeout  # past HORN_PRESS_SECONDS
	await process_frame
	_expect(right_target.position.distance_to(rim) < 0.01, "The hand goes back to the rim after honking")
	# Standing up frees the solvers and the wheel targets, so boarding again
	# doesn't stack a second pair.
	player.call(&"leave_seat")
	for _i: int in range(5):
		await physics_frame
	_expect(skeleton.get_children().filter(func(node: Node) -> bool: return node is SkeletonIK3D).is_empty(),
		"Leaving the seat frees the driver IK solvers")
	_expect(vehicle.find_child("DriverHandTargetLeft", true, false) == null,
		"Leaving the seat frees the wheel targets")
	player.free()
	vehicle.free()
	if _failures == 0:
		print("PASS: driver arms reach the steering wheel visually")
	quit(_failures)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1
