extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_impact_feedback.gd
## Covers the FOV kick that stands in for the "slow-mo breve" of
## docs/requerimientos-tecnicos.md 3.4. The important property isn't the
## exact angle -- it's that the effect is *local and temporary*: real slow
## motion would need Engine.time_scale, which would slow the
## host-authoritative physics for every player at once. This checks the kick
## happens, recovers on its own, and never touches the global time scale.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var camera: Camera3D = load("res://scenes/presentation/first_person_camera.tscn").instantiate()
	root.add_child(camera)
	await process_frame

	var base_fov: float = float(camera.get(&"BASE_FOV"))
	_expect(is_equal_approx(camera.fov, base_fov), "Starts at the base FOV")
	_expect(is_equal_approx(camera.far, 600.0), "Far plane is pinned explicitly, not left at the engine default")

	# An inactive camera ignores impacts entirely -- four passengers plus a
	# driver all have one of these, and only the one you're actually looking
	# through should react. deactivate() explicitly: Godot makes the first
	# Camera3D added to a viewport current on its own, which in-game is
	# undone by whichever seat the player actually boards.
	camera.call(&"deactivate")
	bus.emit_signal(&"vehicle_impact", 6.0, Vector3.ZERO)
	_expect(is_equal_approx(camera.fov, base_fov), "An inactive seat camera doesn't react to impacts")

	camera.call(&"activate")
	var time_scale_before: float = Engine.time_scale
	bus.emit_signal(&"vehicle_impact", 6.0, Vector3.ZERO)
	_expect(camera.fov > base_fov, "A real impact kicks the FOV outward (got %.2f, base %.2f)" % [camera.fov, base_fov])
	_expect(is_equal_approx(Engine.time_scale, time_scale_before),
		"Never touches Engine.time_scale -- that would slow the host's physics for everyone")

	var kicked_fov: float = camera.fov
	for _i: int in range(120):  # ~2s at 60Hz
		await process_frame
		if is_equal_approx(camera.fov, base_fov):
			break
	_expect(camera.fov < kicked_fov, "The kick decays instead of staying zoomed out forever")
	_expect(is_equal_approx(camera.fov, base_fov), "Returns exactly to the base FOV, no drift left behind")

	camera.free()
	if _failures == 0:
		print("PASS: impacts kick the FOV locally and recover, without touching global time scale")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
