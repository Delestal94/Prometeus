extends SceneTree
## S-109: one primary tender plus one helper. Continuous help counts at half
## strength, either player may send a sequence direction, and a third peer
## cannot take over the same package.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var package := DeliveryPackage.new()
	package.package_id = &"assist_test"
	package.freeze = true
	root.add_child(package)
	await process_frame
	package.set_tender(1)
	_expect(package.set_assistant(2), "A second peer can become the helper")
	_expect(not package.set_assistant(3), "A third peer is ignored while the helper slot is occupied")

	package._accept_tender_input(2, {"steady": true, "calm": true, "direction_pressed": &"left"})
	_expect(is_equal_approx(float(package.player_input.get("steady_strength", 0.0)), 0.5),
		"Helper steady input contributes half strength")
	_expect(is_equal_approx(float(package.player_input.get("calm_strength", 0.0)), 0.5),
		"Helper calm input contributes half strength")
	_expect(StringName(package.player_input.get("direction_pressed", &"")) == &"left",
		"The helper can advance a directional sequence")

	package._accept_tender_input(1, {"steady": true, "calm": true, "direction_pressed": null})
	_expect(is_equal_approx(float(package.player_input.get("steady_strength", 0.0)), 1.5),
		"Primary and helper correction combine to 150 percent")
	var before: Dictionary = package.player_input.duplicate(true)
	_expect(not package._accept_tender_input(3, {"steady": true, "direction_pressed": &"up"}) and package.player_input == before,
		"Input from a third peer cannot affect the package")
	_expect(package.assist_prompt().contains("amarillo"), "The interaction prompt identifies the primary tender by colour")

	var tilted := Node3D.new()
	root.add_child(tilted)
	tilted.rotation_degrees.z = 20.0
	var balance := BalanceTrapBehavior.new()
	balance.on_setup(tilted, {"correction_strength": 20.0, "angle_ok_max": 15.0, "angle_at_risk_max": 30.0})
	balance.on_physics_process(tilted, 1.0, {"input": {"steady": true, "steady_strength": 0.5}})
	var remaining_tilt: float = rad_to_deg(tilted.global_basis.y.angle_to(Vector3.UP))
	_expect(remaining_tilt > 5.0 and remaining_tilt < 15.0,
		"Half-strength help applies half of the normal balance correction (got %.1f°)" % remaining_tilt)

	var hostile_definition: Resource = load("res://data/traps/hostile.tres")
	var hostile_params: Dictionary = hostile_definition.get(&"params")
	_expect(is_equal_approx(float(hostile_params.get("calm_strength_required", 0.0)), 1.5),
		"Hostile declares its two-person calm strength in data")
	var hostile: Resource = hostile_definition.call(&"create_behavior")
	hostile.call(&"on_setup", null, hostile_params.duplicate(true))
	hostile.set(&"aggression", 60.0)
	hostile.set(&"command_calm", true)
	hostile.call(&"on_physics_process", null, 1.0, {"input": {"calm": true, "calm_strength": 1.0}})
	var solo_aggression: float = float(hostile.get(&"aggression"))
	hostile.set(&"aggression", 60.0)
	hostile.set(&"command_calm", true)
	hostile.call(&"on_physics_process", null, 1.0, {"input": {"calm": true, "calm_strength": 1.5}})
	_expect(float(hostile.get(&"aggression")) < solo_aggression,
		"Two combined players calm Hostile faster than one")

	package.queue_free()
	tilted.queue_free()
	if _failures == 0:
		print("PASS: two peers combine package care, sequences accept either, and a third peer is ignored")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
