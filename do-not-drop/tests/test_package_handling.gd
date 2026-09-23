extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_handling.gd
##
## Carrying, setting down and handing over boxes: the cases that used to leave
## a box stuck (frozen on a shelf mid-run, floating after a disconnect), a
## player stuck (holding a box a resident already took), or the run stuck (a
## passenger who boarded with their box in hand never counted as cargo).

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _passenger_boarding_with_box_counts_as_cargo()
	await _remounting_mid_run_and_dropping()
	await _handing_over_at_the_door_empties_hands()
	await _carry_and_drop_respect_walls_and_floor()
	await _disconnect_mid_carry_releases_the_box()
	if failures == 0:
		print("PASS: boarding with a box, remounting mid-run, door hand-over, walls/floor and disconnects")
	quit(failures)


func _passenger_boarding_with_box_counts_as_cargo() -> void:
	var level: Node = await _load_level()
	var manager: Node = root.get_node("RunManager")
	var player: Node = level.local_player
	var package: Node = level.get_node("World/Package")
	var vehicle: Node = level.get_node("World/Vehicle")
	var seat: Node = vehicle.get_node("CargoBay/LeftSeat1EyePoint/InteractionArea")
	var mount: Node = vehicle.get_node("CargoBay/LeftSeat1PackageMount/InteractionArea")
	package.get_node("InteractionArea").interact(player)
	_expect(seat.can_interact(player), "A passenger can board their seat with the box still in hand")
	seat.interact(player)
	_expect(package.is_loaded and mount.occupied_by == package, "Boarding settles the box onto that seat's mount")
	_expect(player.carried_package == null, "Boarding empties the passenger's hands")
	_expect(package.carrier == null, "The box no longer has a carrier once mounted")
	var driver: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	driver.name = "Driver"
	level.get_node("World").add_child(driver)
	await process_frame
	level.get_node("World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea").interact(driver)
	_expect(manager.is_running, "A box loaded by boarding is enough for the driver to start the run")
	await _unload_level(level)


func _remounting_mid_run_and_dropping() -> void:
	var level: Node = await _load_level()
	var manager: Node = root.get_node("RunManager")
	var player: Node = level.local_player
	var package: Node = level.get_node("World/Package")
	var vehicle: Node = level.get_node("World/Vehicle")
	var pickup: Node = package.get_node("InteractionArea")
	var mount: Node = vehicle.get_node("CargoBay/LeftShelfPackageMount/InteractionArea")
	var seat: Node = vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea")
	pickup.interact(player)
	mount.interact(player)
	_expect(package.freeze, "A box loaded before the run waits frozen on its shelf")
	seat.interact(player)
	_expect(manager.is_running, "The run starts")
	player.leave_seat()
	pickup.interact(player)
	_expect(player.carried_package == package and package.carrier == player, "The host knows who is carrying the box")
	mount.interact(player)
	_expect(not package.freeze, "A box put back mid-run rides physically instead of staying glued to the shelf")
	_expect(package.is_loaded and mount.occupied_by == package, "Putting it back mid-run re-occupies the slot")
	pickup.interact(player)
	var integrity_before: float = package.integrity
	player._drop_carried()
	_expect(not package.is_held and package.carrier == null, "Dropping releases the box on the host")
	_expect(player.carried_package == null, "Dropping empties the player's hands")
	for i: int in 20:
		await physics_frame
	_expect(is_equal_approx(package.integrity, integrity_before),
		"Setting a box down does not register as an impact (lost %.1f)" % (integrity_before - package.integrity))
	await _unload_level(level)


func _handing_over_at_the_door_empties_hands() -> void:
	var level: Node = await _load_level()
	var player: Node = level.local_player
	var package: Node = level.get_node("World/Package")
	package.get_node("InteractionArea").interact(player)
	var houses: Array = level.get_node("World/Route").get(&"houses")
	_expect(houses.size() > 0, "The route has a house to deliver to")
	if houses.size() > 0:
		houses[0].get(&"doorbell").interact(player)
		_expect(player.carried_package == null, "Handing a box to a resident empties the carrier's hands")
		await process_frame
		_expect(not is_instance_valid(package), "The resident keeps the box")
		_expect(package_pickup_ready(level, player), "With empty hands the player can pick up another box")
	await _unload_level(level)


func package_pickup_ready(level: Node, player: Node) -> bool:
	for other: Node in get_nodes_in_group_safe(level, &"cargo"):
		if is_instance_valid(other) and not other.is_queued_for_deletion():
			return other.get_node("InteractionArea").can_interact(player)
	return false


func get_nodes_in_group_safe(_level: Node, group: StringName) -> Array[Node]:
	return root.get_tree().get_nodes_in_group(group)


## Own floor and wall far from the route, so this doesn't depend on the van
## model (which is being replaced) or on where the route's terrain lies.
func _carry_and_drop_respect_walls_and_floor() -> void:
	var level: Node = await _load_level()
	var player: Node = level.local_player
	var package: Node = level.get_node("World/Package")
	var origin := Vector3(400.0, 50.0, 0.0)
	var floor_body: StaticBody3D = _static_box(Vector3(20.0, 1.0, 20.0), origin + Vector3(0.0, -0.5, 0.0))
	var wall: StaticBody3D = _static_box(Vector3(4.0, 3.0, 0.2), origin + Vector3(0.0, 1.5, -1.1))
	level.add_child(floor_body)
	level.add_child(wall)
	player.global_position = origin
	player.rotation = Vector3.ZERO
	package.get_node("InteractionArea").interact(player)
	await physics_frame
	await physics_frame
	var wall_face_z: float = origin.z - 1.0
	var half: Vector3 = package.get_half_extents()

	var carry: Vector3 = player._carry_position()
	_expect(carry.z - half.z >= wall_face_z - 0.01,
		"A carried box stops at the wall instead of poking through it (front face at z=%.2f, wall at %.2f)" % [carry.z - half.z, wall_face_z])
	var hold: Vector3 = player._hold_point.global_position
	_expect(carry.distance_to(hold) > 0.1, "Near a wall the box is actually pulled in from the hold point")

	var against_wall: Vector3 = player._drop_position(half)
	_expect(against_wall.z - half.z >= wall_face_z - 0.01, "Dropping at a wall sets the box down in front of it, not inside it")
	_expect(absf(against_wall.y - (origin.y + half.y)) < 0.05,
		"The dropped box rests on the floor (y=%.2f, expected %.2f)" % [against_wall.y, origin.y + half.y])

	wall.queue_free()
	await physics_frame
	await physics_frame
	var open: Vector3 = player._drop_position(half)
	_expect(origin.z - open.z >= 0.35 + half.z, "In the open the box lands clear of the player's own body")

	var step: StaticBody3D = _static_box(Vector3(2.0, 0.4, 2.0), open + Vector3(0.0, -open.y + origin.y + 0.2, 0.0))
	level.add_child(step)
	await physics_frame
	await physics_frame
	var on_step: Vector3 = player._drop_position(half)
	_expect(absf(on_step.y - (origin.y + 0.4 + half.y)) < 0.05,
		"Dropping over a step lands on top of it (y=%.2f, expected %.2f)" % [on_step.y, origin.y + 0.4 + half.y])
	await _unload_level(level)


func _disconnect_mid_carry_releases_the_box() -> void:
	var level: Node = await _load_level()
	var package: Node = level.get_node("World/Package")
	var guest: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	guest.name = "Guest"
	level.get_node("World").add_child(guest)
	await process_frame
	package.get_node("InteractionArea").interact(guest)
	_expect(package.is_held, "The guest is holding the box")
	guest.free()
	_expect(not package.is_held and package.collision_layer == 4, "A carrier leaving drops their box back into the world")
	_expect(package.carrier == null, "The box forgets a carrier that is gone")
	await _unload_level(level)


func _load_level() -> Node:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	return level


func _unload_level(level: Node) -> void:
	root.get_node("RunManager").reset_run()
	level.free()
	await process_frame


func _static_box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	return body


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
