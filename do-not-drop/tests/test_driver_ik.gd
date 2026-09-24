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
	_expect(vehicle.find_child("DriverArmVisualLeft", true, false) != null
		and vehicle.find_child("DriverArmVisualRight", true, false) != null,
		"Visible driver arms connect the shoulders to both steering-wheel targets")
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
