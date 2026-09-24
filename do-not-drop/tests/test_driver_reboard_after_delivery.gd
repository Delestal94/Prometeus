extends SceneTree
## Delivering a box removes it from its mount. During an active route that
## must not make the driver seat unavailable: the crew still has more houses.

func _initialize() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var player: Node = level.get(&"local_player")
	var vehicle: Node = level.get_node("World/Vehicle")
	vehicle.call(&"set_door_open", &"cab_left", true)
	var seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	var run_manager: Node = root.get_node("RunManager")
	run_manager.set(&"is_running", true)
	if not seat.can_interact(player):
		push_error("Driver must be able to reboard after a delivered package leaves its mount")
		quit(1)
		return
	run_manager.call(&"reset_run")
	print("PASS: delivery does not block reboarding the driver seat")
	quit()
