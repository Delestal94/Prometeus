extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_interaction_highlight.gd
## Covers items #98 (highlight the interactable you're looking at) and #94
## (seat occupied/free indicator) of docs/especificaciones-visuales.md.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_package_highlight()
	await _test_seat_indicator()
	if _failures == 0:
		print("PASS: interactables glow when targeted, seats show occupied/free")
	quit(_failures)


func _test_package_highlight() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	await process_frame
	var pickup: Node = package.get_node(^"InteractionArea")
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var material: StandardMaterial3D = feedback.get(&"_material")

	_expect(not material.emission_enabled, "No glow before anyone looks at it")
	pickup.call(&"highlight", true)
	_expect(material.emission_enabled and material.emission_energy_multiplier > 0.0,
		"Highlighting the pickup point actually glows the package's own material")
	pickup.call(&"highlight", false)
	_expect(is_equal_approx(material.emission_energy_multiplier, 0.0), "Turns back off when no longer the target")
	package.free()


func _test_seat_indicator() -> void:
	var vehicle: Node = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(vehicle)
	root.add_child(player)
	await process_frame

	var seat: Node = vehicle.get_node(^"CabinInterior/DriverEyePoint/InteractionArea")
	_expect(not bool(seat.call(&"_is_occupied")), "Empty seat reads as free")
	var indicator_material: StandardMaterial3D = seat.get(&"_indicator_material")
	var free_color: Color = indicator_material.albedo_color

	# Same trick _is_occupied() itself uses (matching seat_node_path) --
	# doesn't need a real board_seat() RPC round trip to prove the indicator
	# reacts to that replicated state.
	player.set(&"seat_node_path", vehicle.get_node(^"CabinInterior/DriverEyePoint").get_path())
	await process_frame
	_expect(bool(seat.call(&"_is_occupied")), "Matching seat_node_path reads as occupied")
	_expect(indicator_material.albedo_color != free_color, "Occupied indicator visibly differs from the free one")

	player.set(&"seat_node_path", NodePath())
	await process_frame
	_expect(is_equal_approx(indicator_material.albedo_color.r, free_color.r), "Clearing the seat goes back to the free color")

	player.free()
	vehicle.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
