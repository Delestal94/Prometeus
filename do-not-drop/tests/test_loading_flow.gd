extends SceneTree
## Integration regression: actual interactions, start guards, pause and debug shortcut.
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/level_base.tscn")
	var level: Node = scene.instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var manager: Node = root.get_node("RunManager")
	var player: Node = level.get_node("World/Player")
	var package: Node = level.get_node("World/Package")
	var vehicle: Node = level.get_node("World/Vehicle")
	var seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	var mount: Node = vehicle.get_node("CargoBay/LeftSeat1PackageMount/InteractionArea")
	var pickup: Node = package.get_node("InteractionArea")
	var hud: Node = level.get_node("HUD")
	_expect(not manager.is_running, "No run behind the introduction")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Intro allows clicking its button")
	hud._primary_action()
	_expect(not hud.overlay.visible and hud.dashboard.visible, "Preparation reveals the world and objective")
	level.toggle_pause()
	_expect(paused, "Preparation can pause")
	level.toggle_pause()
	_expect(not paused, "Preparation can resume")
	seat.interact(player)
	_expect(seat.occupant == null, "Cannot get stuck in driver seat before loading")
	level.start_delivery()
	_expect(not manager.is_running, "Start requires loaded cargo and driver")
	_expect(not mount.can_interact(player), "Empty-handed player cannot select mount")
	pickup.interact(player)
	_expect(player.carried_package == package, "Pickup interaction carries the crate")
	seat.interact(player)
	_expect(seat.occupant == null, "Cannot board while holding cargo")
	mount.interact(player)
	_expect(mount.occupied_by == package and package.is_loaded, "Mount records loaded crate")
	_expect(player.carried_package == null, "Mount releases player's hands")
	pickup.interact(player)
	_expect(player.carried_package == null, "Loaded crate cannot be taken and invalidate loading state")
	_expect(not manager.is_running, "Loading alone does not start the run")
	seat.interact(player)
	_expect(manager.is_running, "Boarding after loading starts delivery")
	_expect(vehicle.controls_enabled and not vehicle.freeze and not package.freeze, "Driving and cargo physics become active")
	_expect(player.collision_layer == 0, "Seated player leaves no invisible collider outside")
	_expect(vehicle.get_node("CabinInterior/DriverEyePoint/FirstPersonCamera").current, "Driver camera is active")
	level.toggle_pause()
	var elapsed: float = manager.elapsed_seconds
	await create_timer(0.05).timeout
	_expect(is_equal_approx(manager.elapsed_seconds, elapsed), "Pause freezes run timer")
	level.toggle_pause()
	manager.finish_run(true)
	await process_frame
	_expect(hud.overlay.visible and hud.overlay_mode == "results", "Result screen opens")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Results release mouse")
	level.restart_delivery()
	await process_frame
	await process_frame
	level = current_scene
	_expect(not manager.is_running and manager.results.is_empty(), "Restart resets the full run")
	level.start_debug_delivery()
	_expect(manager.is_running, "Debug shortcut starts the run")
	vehicle = level.get_node("World/Vehicle")
	package = level.get_node("World/Package")
	_expect(package.is_loaded and vehicle.controls_enabled, "Debug shortcut actually loads cargo and boards")
	_expect(package.global_position.distance_to(vehicle.global_position) < 3.0, "Debug cargo starts inside van")
	if failures == 0:
		print("PASS: preparation, guarded interactions, delivery start, pause, results, restart and debug shortcut")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
