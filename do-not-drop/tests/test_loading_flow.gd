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
	var player: Node = level.local_player
	var package: Node = level.get_node("World/Package")
	var vehicle: Node = level.get_node("World/Vehicle")
	var seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	# Loading a seat other than the first one must still unlock the driver's
	# seat; otherwise the loading flow depends on an arbitrary cargo slot.
	var mount: Node = vehicle.get_node("CargoBay/LeftShelfPackageMount/InteractionArea")
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
	player._drop_carried()
	_expect(player.carried_package == null and not package.is_held, "Q drop releases a mistakenly picked up crate")
	pickup.interact(player)
	_expect(player.carried_package == package, "Dropped crate can be picked up again")
	seat.interact(player)
	_expect(seat.occupant == null, "Cannot board while holding cargo")
	mount.interact(player)
	_expect(mount.occupied_by == package and package.is_loaded, "Shelf mount records loaded crate")
	_expect(package.global_position.distance_to(vehicle.get_node("CargoBay/LeftShelfPackageMount").global_position) < 0.1, "Loaded crate rests on the shelf")
	_expect(player.carried_package == null, "Mount releases player's hands")
	# Taking a loaded crate back out is the only way a package ever reaches a
	# DeliveryHouse's door, so it's allowed on purpose now -- it frees the
	# shelf slot and stops counting as loaded, and putting it back restores
	# both. Before this, every house on the route resolved as "missed"
	# because no box could ever leave the van.
	pickup.interact(player)
	_expect(player.carried_package == package, "A loaded crate can be taken back out to walk it to a door")
	_expect(mount.occupied_by == null and not package.is_loaded, "Taking a crate out frees the shelf slot it was in")
	mount.interact(player)
	_expect(mount.occupied_by == package and package.is_loaded, "Putting it back re-occupies the same slot")
	_expect(player.carried_package == null, "Mount releases the player's hands again")
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
	# restart_delivery() now fades to black before reloading (see
	# level_base.gd) -- waits out that real 0.15s delay instead of the
	# reload happening on the very next frame.
	await create_timer(0.2).timeout
	await process_frame
	level = current_scene
	_expect(not manager.is_running and manager.results.is_empty(), "Restart resets the full run")
	level.start_debug_delivery()
	_expect(manager.is_running, "Debug shortcut starts the run")
	vehicle = level.get_node("World/Vehicle")
	package = level.get_node("World/Package")
	_expect(package.is_loaded and vehicle.controls_enabled, "Debug shortcut actually loads cargo and boards")
	_expect(package.global_position.distance_to(vehicle.global_position) < 4.0, "Debug cargo starts inside van")
	if failures == 0:
		print("PASS: preparation, guarded interactions, delivery start, pause, results, restart and debug shortcut")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
