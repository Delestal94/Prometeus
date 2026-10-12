extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_box_package_flow.gd
##
## A packed box that BoxToPackage turned into a DeliveryPackage (expansion
## D-0711, box_to_package.gd) goes through the real delivery flow like any box:
## - the player lifts it through its InteractionArea and settles it on a truck
##   mount, and it joins the run's cargo once the run starts;
## - looking after it (tending, impact damage, the rescue crisis) behaves the
##   same as with an ordinary fragile package of the same absorption;
## - handing it over at the door of the house that ordered it (assigned_package_id
##   = the box's id) empties the carrier's hands and takes the box out of play,
##   while a different house refuses it;
## - its box metadata (META_PACKED_BOX, META_ORDER_ID) survives all of that.
## What it prevents: a box package that works in isolation (test_box_to_package.gd)
## but gets stuck, uncared for or undeliverable once it is in a level.

const VASE: ProductDefinition = preload("res://data/products/porcelain_vase.tres")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const FRAGILE: TrapDefinition = preload("res://data/traps/fragile.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame

	var player: Node = level.local_player
	var world: Node = level.get_node("World")
	var vehicle: Node = level.get_node("World/Vehicle")

	var packed := PackedBox.new(&"M")
	packed.place(VASE, Vector3i.ZERO)
	packed.taped = true
	packed.label_order_id = &"o7"
	var box: DeliveryPackage = BoxToPackage.build(packed)
	_expect(box != null, "The packed vase gives a package")
	if box == null:
		quit(_failures)
		return
	var saved: Dictionary = box.get_meta(BoxToPackage.META_PACKED_BOX)
	world.add_child(box)
	box.global_position = player.global_position + Vector3(0.0, 1.0, -1.0)
	level.packages.append(box)
	await physics_frame
	_expect(box.is_in_group(&"cargo"), "A box package is cargo like any other")

	# (1) Pick up through the InteractionArea and settle on a mount.
	var pickup: Node = box.get_node("InteractionArea")
	var mount: Node = vehicle.get_node("CargoBay/LeftShelfPackageMount/InteractionArea")
	_expect(pickup.can_interact(player), "The player can lift the box package")
	pickup.interact(player)
	_expect(player.carried_package == box and box.is_held, "Lifting it puts it in the player's hands")
	_expect(box.carrier == player, "The host knows who carries it")
	mount.interact(player)
	_expect(box.is_loaded and mount.occupied_by == box, "It settles on the truck mount")
	_expect(player.carried_package == null, "...and the hands are empty again")
	pickup.interact(player)
	_expect(player.carried_package == box, "It can be lifted off the mount again")

	# (2) Care: boarding with it in hand makes the passenger tend it; once the
	# run starts it reacts to hits like an ordinary fragile package.
	var seat: Node = vehicle.get_node("CargoBay/LeftSeat1EyePoint/InteractionArea")
	seat.interact(player)
	_expect(player.tended_package == box, "The passenger tends the box package on their lap")
	_expect(box.is_aboard(), "A box package on a lap counts as aboard")
	box.request_lap_toggle()
	_expect(box.is_loaded and player.carried_package == null, "Drop (Q) settles the lap box on the seat mount")
	box.request_lap_toggle()
	_expect(player.carried_package == box, "...and Q again brings it back to the lap")
	var driver: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	driver.name = "Driver"
	world.add_child(driver)
	await process_frame
	vehicle.call(&"set_door_open", &"cab_left", true)
	vehicle.get_node("CabinInterior/DriverEyePoint/InteractionArea").interact(driver)
	var manager: Node = root.get_node("RunManager")
	_expect(manager.is_running, "The run starts with the box package aboard")
	_expect(manager.cargo_names.has(box.package_id), "The box package counts as this run's cargo")
	var plain: DeliveryPackage = PACKAGE_SCENE.instantiate()
	plain.trap_definition = FRAGILE
	plain.impact_absorption = box.impact_absorption
	world.add_child(plain)
	await physics_frame
	box.apply_impact(7.0)
	plain.apply_impact(7.0)
	_expect(is_equal_approx(box.integrity, plain.integrity) and box.integrity < box.integrity_max,
		"A hit damages the box package as it does a common one (box %.1f, common %.1f)" % [box.integrity, plain.integrity])
	_expect(box.run_state() == plain.run_state(), "Same trap state after the hit")
	for _i: int in 4:
		box.apply_impact(7.0)
		plain.apply_impact(7.0)
	_expect(box.care.phase == plain.care.phase and box.care.phase == &"crisis",
		"Breaking it opens the same rescue crisis (box %s, common %s)" % [box.care.phase, plain.care.phase])
	plain.free()
	player.leave_seat()
	player._drop_carried()

	# (3) Hand-over at the door of the house that ordered it.
	var fresh: DeliveryPackage = BoxToPackage.build(packed)
	world.add_child(fresh)
	level.packages.append(fresh)
	await physics_frame
	var houses: Array = level.get_node("World/Route").get(&"houses")
	_expect(houses.size() > 1, "The route has two houses")
	if houses.size() > 1:
		houses[0].assigned_package_id = &"someone_elses"
		houses[1].assigned_package_id = fresh.package_id
		fresh.get_node("InteractionArea").interact(player)
		houses[0].get(&"doorbell").interact(player)
		_expect(player.carried_package == fresh, "A house that did not order it refuses the box")
		houses[1].get(&"doorbell").interact(player)
		_expect(player.carried_package == null, "Handing it to its house empties the hands")
		await process_frame
		_expect(not is_instance_valid(fresh) or (not fresh.is_in_group(&"cargo") and fresh.collision_layer == 0),
			"The delivered box leaves play")
		await create_timer(1.1).timeout
		_expect(not is_instance_valid(fresh), "The resident keeps the box package")
		_expect(houses[1].delivered, "The house counts as delivered")

	# Metadata survived everything above.
	_expect(box.get_meta(BoxToPackage.META_PACKED_BOX) == saved, "META_PACKED_BOX survives the flow")
	_expect(box.get_meta(BoxToPackage.META_ORDER_ID) == &"o7", "META_ORDER_ID survives the flow")

	root.get_node("RunManager").reset_run()
	level.free()
	await process_frame
	if _failures == 0:
		print("PASS: a packed box is lifted, mounted, tended and delivered as a common package")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
