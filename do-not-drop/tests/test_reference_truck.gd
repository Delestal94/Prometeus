extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_reference_truck.gd
## The authored box truck, end to end: its art is hung and see-through where
## it should be, its parts move (doors, ramp, wheels, steering wheel), and its
## physics matches what is drawn -- tires on the road, every package shape
## fits every rack bay, and the crew can walk from the ramp to the seats.

const FLAT := Vector3(0.95, 0.42, 0.95)
const TALL := Vector3(0.42, 0.98, 0.42)
const CUBE := Vector3(0.65, 0.65, 0.65)
const MOUNTS := ["LeftSeat1PackageMount", "LeftSeat2PackageMount", "RightSeat1PackageMount",
	"RightSeat2PackageMount", "LeftShelfPackageMount", "RightShelfPackageMount"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80.0, 1.0, 80.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	ground.add_child(ground_shape)
	world.add_child(ground)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.position.y = 1.5
	world.add_child(van)
	await process_frame

	var adapter: Node = van.get_node_or_null(^"ReferenceTruck")
	var model: Node3D = van.get_node_or_null(^"BodyVisuals/ReferenceTruckModel")
	_expect(adapter != null and model != null, "The authored truck model is installed")
	if model == null:
		quit(1)
		return

	_test_glass(model)
	_test_side_windows_fit_frame(model)
	_expect(model.find_child("CabDressing", true, false) != null and model.find_child("CabDressing", true, false).get_child_count() > 20,
		"The cab is dressed (console, gear stick, gauges, mirror, visors, clipboard...)")
	_test_wheel_art(van)
	_test_steering(van)
	_test_rack_fits_every_shape(van)
	_test_aisle_is_walkable(van)
	_test_seats_match_model(van, model)
	await _test_doors(van, adapter)
	await _test_door_needs_aim(van)
	await _test_boarding_swings_driver_door(van, model)
	await _test_tires_on_ground(van)
	await _test_ramp(van)

	world.free()
	await _test_packages_rest_on_deck()
	await _test_sit_with_the_cargo()
	await _test_getting_up_lands_somewhere_clear()
	await _test_only_what_is_in_reach()
	await _test_parked_truck_stays_put()
	if _failures == 0:
		print("PASS: truck art, glass, doors, ramp, wheels, steering, rack fit, aisle and seats all line up")
	quit(_failures)


func _test_glass(model: Node3D) -> void:
	var glass_names := ["FrontWindshield", "SideWindow_Left", "SideWindow_Right", "CommunicationGlassFixed", "CommunicationGlassMoving"]
	for glass_name: String in glass_names:
		var mesh := model.find_child(glass_name, true, false) as MeshInstance3D
		var material := mesh.material_override as BaseMaterial3D if mesh != null else null
		_expect(material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
			"%s is see-through" % glass_name)
	for frame_name: String in ["CabDoorWindowHeader_Left", "CommunicationWindowJamb", "WindowGrip"]:
		var frame := model.find_child(frame_name, true, false) as MeshInstance3D
		_expect(frame != null and frame.material_override == null, "%s (frame, not glass) stays opaque" % frame_name)


## The re-cut side glass stays inside the door opening: behind the slanted
## front pillar at the top, instead of hanging out over the windshield.
func _test_side_windows_fit_frame(model: Node3D) -> void:
	for side_name: String in ["Left", "Right"]:
		var pane := model.find_child("SideWindow_" + side_name, true, false) as MeshInstance3D
		var pillar := model.find_child("CabDoorFrontPillar_" + side_name, true, false) as MeshInstance3D
		var pane_box: AABB = pane.global_transform * pane.get_aabb()
		var pillar_box: AABB = pillar.global_transform * pillar.get_aabb()
		# Front = -Z in the vehicle. The pane's front edge may reach the
		# pillar's bottom but never past its front face.
		_expect(pane_box.position.z >= pillar_box.position.z - 0.01, "%s side glass ends at its front pillar" % side_name)
		_expect(pane.get_child_count() == 4, "%s side glass has a rubber seal all around" % side_name)


func _test_wheel_art(van: VehicleBody3D) -> void:
	for wheel_name: String in ["FrontLeftWheel", "FrontRightWheel", "RearLeftWheel", "RearRightWheel"]:
		var wheel := van.get_node(NodePath(wheel_name)) as VehicleWheel3D
		var tire: MeshInstance3D = null
		for mesh: Node in wheel.find_children("Tire_*", "MeshInstance3D", true, false):
			tire = mesh
		_expect(tire != null, "%s carries the authored tire" % wheel_name)
		if tire == null:
			continue
		var center: Vector3 = (tire.global_transform * tire.get_aabb()).get_center()
		_expect(center.distance_to(wheel.global_position) < 0.03,
			"%s tire is centred on its physics wheel, so it spins around its own hub" % wheel_name)


func _test_steering(van: VehicleBody3D) -> void:
	var presentation: Node = van.get_node(^"VehiclePresentation")
	var wheel := presentation.get(&"steering_wheel") as Node3D
	_expect(wheel != null and wheel.is_inside_tree() and wheel.has_node(^"Hub"), "Presentation drives the model's steering wheel")
	if wheel == null:
		return
	var rim := wheel.get_node_or_null(^"Rim") as MeshInstance3D
	_expect(rim != null and rim.mesh is TorusMesh, "Steering wheel has a round, gapless rim")
	_expect(van.find_children("SteeringRim*", "MeshInstance3D", true, false).is_empty(), "The segmented authored rim is gone")
	var eye := van.get_node(^"CabinInterior/DriverEyePoint") as Node3D
	var axis: Vector3 = wheel.global_basis.y.normalized()
	_expect(axis.dot((wheel.global_position - eye.global_position).normalized()) > 0.5,
		"Steering column axis points from the driver toward the dashboard")
	var rest: Basis = wheel.basis
	van.steering = 0.3
	presentation.call(&"update_presentation", 0.0)
	_expect(not wheel.basis.is_equal_approx(rest), "Steering wheel turns with the road wheels")
	van.steering = 0.0
	presentation.call(&"update_presentation", 0.0)


## Each bay must hold every package shape resting on its deck without the
## box touching a wall, the roof, the rack ends, another tier or the aisle
## side of the truck. Boxes are shrunk by a hair so resting contact with the
## deck itself doesn't count.
func _test_rack_fits_every_shape(van: VehicleBody3D) -> void:
	var space := van.get_world_3d().direct_space_state
	for mount_name: String in MOUNTS:
		var marker := van.get_node(NodePath("CargoBay/" + mount_name)) as Node3D
		var ray := PhysicsRayQueryParameters3D.create(marker.global_position, marker.global_position + Vector3.DOWN * 1.5, 2)
		var hit := space.intersect_ray(ray)
		_expect(not hit.is_empty() and hit.collider == van, "%s has a deck under it" % mount_name)
		if hit.is_empty():
			continue
		var deck_top: float = (hit.position as Vector3).y
		_expect(absf(marker.global_position.y - 0.325 - deck_top) < 0.01, "%s marker sits a standard box above its deck" % mount_name)
		for size: Vector3 in [FLAT, TALL, CUBE]:
			var box := BoxShape3D.new()
			box.size = size - Vector3.ONE * 0.02
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = box
			query.collision_mask = 2
			query.transform = Transform3D(marker.global_basis, Vector3(marker.global_position.x, deck_top + size.y * 0.5 + 0.005, marker.global_position.z))
			var overlaps := space.intersect_shape(query, 4)
			_expect(overlaps.is_empty(), "A %s box fits in bay %s" % [str(size), mount_name])


## A crew member (the player's 0.35 m capsule) fits all the way from the rear
## doorway to the front seats, even with the widest box in every bay.
func _test_aisle_is_walkable(van: VehicleBody3D) -> void:
	var space := van.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var floor_y: float = van.to_global(Vector3(0.0, 0.255, 0.0)).y
	var widest_box_edge: float = -0.52 + FLAT.x * 0.5
	# Down the aisle right of the rack, diagonally past the rack's front corner
	# and the end of the right seat row, then down the middle between seats.
	var waypoints: Array[Vector2] = [Vector2(0.36, 4.3), Vector2(0.36, 1.95), Vector2(0.17, 1.55), Vector2(0.0, 1.2), Vector2(0.0, 0.1)]
	for leg in range(waypoints.size() - 1):
		var steps: int = maxi(1, int(waypoints[leg].distance_to(waypoints[leg + 1]) / 0.1))
		for step in range(steps):
			var point: Vector2 = waypoints[leg].lerp(waypoints[leg + 1], float(step) / float(steps))
			var local := Vector3(point.x, 0.255 + 0.85 + 0.02, point.y)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 2
			query.transform = Transform3D(Basis.IDENTITY, van.to_global(local))
			_expect(space.intersect_shape(query, 1).is_empty(), "Aisle is clear for a player at x=%.2f z=%.2f" % [point.x, point.y])
			if point.y > 1.8:
				_expect(point.x - capsule.radius > widest_box_edge, "Even a flat box in the rack leaves the aisle open at z=%.2f" % point.y)
	_expect(floor_y < van.to_global(Vector3(0.0, 0.3, 0.0)).y, "Cargo floor is where the model's floor is")


func _test_seats_match_model(van: VehicleBody3D, model: Node3D) -> void:
	var cushions: Array[Vector3] = []
	for cushion: Node in model.find_children("PassengerCushion*", "MeshInstance3D", true, false):
		var mesh := cushion as MeshInstance3D
		cushions.append((mesh.global_transform * mesh.get_aabb()).get_center())
	_expect(cushions.size() == 7, "The model has seven passenger seats (got %d)" % cushions.size())
	var used: Array[int] = []
	for seat: Node in van.get_node(^"CargoBay").find_children("*EyePoint", "Marker3D", false, false):
		if String(seat.name).begins_with("RackSeat"):
			continue  # Fold-down seats by the rack, not the model's benches.
		var eye := (seat as Node3D).global_position
		var best := -1
		for index in range(cushions.size()):
			var flat := Vector2(cushions[index].x - eye.x, cushions[index].z - eye.z)
			if flat.length() < 0.2 and cushions[index].y < eye.y:
				best = index
		_expect(best >= 0 and not best in used, "%s sits on its own model seat" % seat.name)
		used.append(best)


func _test_doors(van: VehicleBody3D, adapter: Node) -> void:
	var hinges := {
		&"rear": "RearDoor_Left_HINGE_Z",
		&"cab_left": "CabDoor_Left_HINGE_Z",
		&"cab_right": "CabDoor_Right_HINGE_Z",
	}
	var model: Node3D = van.get_node(^"BodyVisuals/ReferenceTruckModel")
	var blocker := van.get_node(^"RearDoorCollision") as CollisionShape3D
	_expect(blocker.disabled, "Rear doors start open for loading, nothing blocks the doorway")
	for door: StringName in hinges:
		var hinge := model.find_child(hinges[door], true, false) as Node3D
		var control: Node = van.find_child(("RearDoorControl" if door == &"rear" else ("CabLeftDoorControl" if door == &"cab_left" else "CabRightDoorControl")), true, false)
		_expect(control != null and control.has_method(&"interact"), "%s door has an interaction" % door)
		var was_open: bool = van.is_door_open(door)
		control.call(&"interact", null)
		_expect(van.is_door_open(door) != was_open, "Interacting toggles the %s door" % door)
		await create_timer(0.8).timeout
		var expected_open: bool = not was_open
		_expect(absf(hinge.rotation.y) > 1.0 if expected_open else absf(hinge.rotation.y) < 0.01,
			"%s door leaf swings %s" % [door, "open" if expected_open else "shut"])
		if door == &"rear":
			_expect(blocker.disabled == expected_open, "Closed rear doors block the doorway, open ones don't")
		control.call(&"interact", null)
		await create_timer(0.8).timeout
		_expect(absf(hinge.rotation.y) > 1.0 if was_open else absf(hinge.rotation.y) < 0.01, "%s door returns" % door)
	_expect(control_prompt(van, "RearDoorControl") == "Cerrar puertas traseras", "Door prompt reflects its state")
	# Open leaves are solid where they are drawn: the right rear leaf swung
	# out behind the truck stops a ray (and so a player or a carried box).
	var space := van.get_world_3d().direct_space_state
	var right_leaf := model.find_child("RearDoor_Right", true, false) as MeshInstance3D
	var leaf_center: Vector3 = (right_leaf.global_transform * right_leaf.get_aabb()).get_center()
	var probe := PhysicsRayQueryParameters3D.create(leaf_center + Vector3(0.0, 0.0, 3.0), leaf_center - Vector3(0.0, 0.0, 3.0), 2)
	var through := space.intersect_ray(probe)
	var probe_x := PhysicsRayQueryParameters3D.create(leaf_center + van.global_basis.x * 3.0, leaf_center - van.global_basis.x * 3.0, 2)
	var across := space.intersect_ray(probe_x)
	_expect((not through.is_empty() and through.collider != van) or (not across.is_empty() and across.collider != van),
		"An open rear door leaf has collision where it is drawn")


## A door ignores a player who isn't looking at it, so it can't swallow the
## E meant for a package or seat right next to it.
func _test_door_needs_aim(van: VehicleBody3D) -> void:
	var player := (load("res://scenes/gameplay/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	# Only its view matters here: no body to shove the truck around.
	player.collision_layer = 0
	player.collision_mask = 0
	player.position = van.to_global(Vector3(0.3, 0.26, 3.4))
	van.get_parent().add_child(player)
	await process_frame
	var control: Node3D = van.find_child("RearDoorControl", true, false)
	var camera := player.get_node(^"Head/Camera3D") as Node3D
	player.set_physics_process(false)
	player.look_at(van.to_global(Vector3(-0.5, 0.26, 3.4)))  # Facing the rack.
	await process_frame
	_expect(not bool(control.call(&"can_interact", player)), "Facing the rack, the rear door doesn't answer E")
	player.look_at(control.global_position * Vector3(1, 0, 1) + Vector3(0, player.global_position.y, 0))
	camera.look_at(control.global_position)
	await process_frame
	_expect(bool(control.call(&"can_interact", player)), "Looking at the rear doors, they do")
	player.free()


func _test_boarding_swings_driver_door(van: VehicleBody3D, model: Node3D) -> void:
	var hinge := model.find_child("CabDoor_Left_HINGE_Z", true, false) as Node3D
	var seat: Node = van.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	van.set_door_open(&"cab_left", false)
	await create_timer(0.8).timeout
	_expect(not bool(seat.call(&"can_interact", Node.new())), "With the cab door shut the driver's seat is out of reach")
	van.set_door_open(&"cab_left", true)
	await create_timer(0.8).timeout
	_expect(absf(hinge.rotation.y) > 0.9, "The driver's door swings open")
	van.driver_peer_id = 1
	await create_timer(0.8).timeout
	_expect(not van.is_door_open(&"cab_left") and absf(hinge.rotation.y) < 0.01, "Taking the wheel shuts the door behind the driver")
	van.driver_peer_id = 0
	await create_timer(0.8).timeout
	_expect(van.is_door_open(&"cab_left") and absf(hinge.rotation.y) > 0.9, "Getting out opens it again")
	van.set_door_open(&"cab_left", false)
	await create_timer(0.8).timeout


## Getting up from any seat lands the player on a floor they can stand on,
## never inside the truck's collision (that used to launch the truck).
func _test_getting_up_lands_somewhere_clear() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var van: VehicleBody3D = level.vehicle
	var player: CharacterBody3D = level.local_player
	var space := van.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.65
	for seat: Node in van.find_children("*EyePoint", "Marker3D", true, false):
		var exit: Vector3 = player.call(&"_seat_exit_position", seat)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1 | 2
		query.transform = Transform3D(Basis.IDENTITY, exit + Vector3.UP * (0.85 + 0.03))
		_expect(space.intersect_shape(query, 1).is_empty(), "Getting up from %s leaves the player standing clear" % seat.name)
		var standing_inside: bool = absf(van.to_local(exit).x) < 1.0 and van.to_local(exit).z > -0.3
		if seat.name == "DriverEyePoint":
			_expect(van.to_local(exit).x < -1.1, "The driver climbs out beside the cab, not into it")
		else:
			_expect(standing_inside, "%s: getting up leaves the passenger in the cargo aisle" % seat.name)
	level.free()


func control_prompt(van: VehicleBody3D, control_name: String) -> String:
	return String(van.find_child(control_name, true, false).call(&"get_prompt"))


func _test_tires_on_ground(van: VehicleBody3D) -> void:
	for tick in range(300):
		await physics_frame
	var space := van.get_world_3d().direct_space_state
	for wheel_name: String in ["FrontLeftWheel", "FrontRightWheel", "RearLeftWheel", "RearRightWheel"]:
		var wheel := van.get_node(NodePath(wheel_name)) as VehicleWheel3D
		var ray := PhysicsRayQueryParameters3D.create(wheel.global_position, wheel.global_position + Vector3.DOWN * 2.0, 1)
		var hit := space.intersect_ray(ray)
		var gap: float = wheel.global_position.y - (hit.position as Vector3).y - van.get_script().TIRE_RADIUS if not hit.is_empty() else 9.0
		_expect(absf(gap) < 0.015, "%s tire rests on the road (gap %.3f m)" % [wheel_name, gap])
	_expect(absf(van.global_position.y - van.get_script().RIDE_HEIGHT) < 0.02, "Truck settles at its ride height (%.3f)" % van.global_position.y)
	_expect(absf(van.rotation_degrees.x) < 0.3, "Truck sits level (pitch %.2f°)" % van.rotation_degrees.x)


func _test_ramp(van: VehicleBody3D) -> void:
	var ramp := van.get_node(^"RearRamp/Shape") as CollisionShape3D
	var visual := van.get_node(^"BodyVisuals/RampVisual") as Node3D
	await physics_frame
	_expect(van.rear_ramp_deployed and not ramp.disabled and visual.visible, "Parked with the doors open, the ramp is out")
	var tip: Vector3 = ramp.global_transform * Vector3(0.0, 0.03, (ramp.shape as BoxShape3D).size.z * 0.5)
	_expect(tip.y > 0.0 and tip.y < 0.12, "Ramp foot nearly touches the road without scraping it (%.3f)" % tip.y)
	van.set_door_open(&"rear", false)
	await physics_frame
	await physics_frame
	await create_timer(0.5).timeout
	_expect(not van.rear_ramp_deployed and ramp.disabled and not visual.visible, "Closing the doors stows the ramp")
	van.set_door_open(&"rear", true)
	await physics_frame
	await physics_frame
	_expect(van.rear_ramp_deployed and not ramp.disabled, "Opening them while parked puts it back out")


## In the real level: whatever its shape, a box put in a rack bay rests on
## that bay's deck.
func _test_packages_rest_on_deck() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var player: Node = level.local_player
	var van: VehicleBody3D = level.vehicle
	var packages: Array[Node] = []
	packages.assign(root.get_tree().get_nodes_in_group(&"cargo"))
	var index := 0
	# More trap types (7) than rack bays (6): every bay gets a box.
	for package: Node in packages.slice(0, MOUNTS.size()):
		var mount_name: String = MOUNTS[index]
		index += 1
		var marker := van.get_node(NodePath("CargoBay/" + mount_name)) as Node3D
		player.call(&"pick_up", package.get_path())
		marker.get_node(^"InteractionArea").call(&"interact", player)
		await process_frame
		var half: Vector3 = package.call(&"get_half_extents")
		var deck_top: float = marker.global_position.y - 0.325
		var bottom: float = (package as Node3D).global_position.y - half.y
		_expect(absf(bottom - deck_top) < 0.01,
			"%s (%s) rests on the %s deck (off by %.3f)" % [package.name, str(half * 2.0), mount_name, bottom - deck_top])
	level.free()


## The fold-down seats face the rack: sitting in one tends a box in its bay
## column, and boarding with a box in hand shelves it there first.
func _test_sit_with_the_cargo() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var player: Node = level.local_player
	var van: VehicleBody3D = level.vehicle
	var package: Node = root.get_tree().get_nodes_in_group(&"cargo")[0]
	var seat: Node = van.get_node(^"CargoBay/RackSeat2EyePoint/InteractionArea")
	var lower: Node = van.get_node(^"CargoBay/RightSeat1PackageMount/InteractionArea")
	_expect(String(seat.call(&"get_prompt")) == "Sentarse junto a la carga", "Fold-down seat offers to sit with the cargo")
	player.call(&"pick_up", package.get_path())
	_expect(bool(seat.call(&"can_interact", player)), "Can board it holding a box")
	seat.call(&"interact", player)
	await process_frame
	_expect(lower.get(&"occupied_by") == package, "Boarding shelves the box in the column's lower bay")
	_expect(player.get(&"tended_package") == package, "...and the passenger now looks after it")
	for tick in range(40):
		await process_frame
	var fold := van.get_node(^"BodyVisuals/CargoFittings/RackSeat2Fold") as Node3D
	_expect(absf(fold.rotation.z) < 0.05, "The occupied fold-down seat is down")
	var free_fold := van.get_node(^"BodyVisuals/CargoFittings/RackSeat1Fold") as Node3D
	_expect(absf(free_fold.rotation.z) > 1.4, "Free fold-down seats stay folded against the wall")
	level.free()


## Interactions need a clear line from the eyes: nothing through the truck's
## walls, the driver's seat only through its open door.
func _test_only_what_is_in_reach() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var van: VehicleBody3D = level.vehicle
	var player: CharacterBody3D = level.local_player
	var package: Node = root.get_tree().get_nodes_in_group(&"cargo")[0]
	player.call(&"pick_up", package.get_path())
	var shelf: Node3D = van.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea")
	var head := player.get_node(^"Head") as Node3D
	var camera := head.get_node(^"Camera3D") as Node3D
	# Outside, level with the shelf, facing the left wall right behind it.
	player.global_position = van.to_global(Vector3(-1.55, -0.62, 3.9))
	await physics_frame
	camera.look_at(shelf.global_position)
	_expect(not bool(player.call(&"_within_reach", shelf)), "A shelf can't be reached through the truck's wall")
	player.global_position = van.to_global(Vector3(0.36, 0.26, 3.9))
	await physics_frame
	camera.look_at(shelf.global_position)
	_expect(bool(player.call(&"_within_reach", shelf)), "From the aisle it can")
	var seat: Node3D = van.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	player.global_position = van.to_global(Vector3(-1.7, -0.62, -1.0))
	await physics_frame
	camera.look_at(seat.global_position)
	_expect(bool(player.call(&"_within_reach", seat)), "Through the open door the driver's seat is in reach")
	level.free()


## A delivery in progress, nobody at the wheel: the truck holds still like a
## parked heavy vehicle, and drives off again once somebody takes the wheel.
func _test_parked_truck_stays_put() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	for tick in range(10):
		await physics_frame
	var van: VehicleBody3D = level.vehicle
	var player: Node = level.local_player
	var package: Node = root.get_tree().get_nodes_in_group(&"cargo")[0]
	player.call(&"pick_up", package.get_path())
	van.get_node(^"CargoBay/LeftShelfPackageMount/InteractionArea").call(&"interact", player)
	van.set_door_open(&"cab_left", true)
	var seat: Node = van.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	seat.call(&"interact", player)
	for tick in range(90):
		await physics_frame
	player.call(&"leave_seat")
	for tick in range(30):
		await physics_frame
	var parked_at: Vector3 = van.global_position
	for tick in range(180):
		await physics_frame
	_expect(van.freeze and van.global_position.distance_to(parked_at) < 0.005, "Driverless mid-delivery, the truck stays exactly where it was left")
	seat.call(&"interact", player)
	van.controls_enabled = false  # Scripted throttle instead of the keyboard.
	van.set_controls(0.7, 0.0, false)
	for tick in range(90):
		await physics_frame
	_expect(not van.freeze and van.speed_kmh > 5.0, "Back at the wheel, it drives off again")
	level.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
