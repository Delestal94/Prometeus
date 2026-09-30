extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_liquid_visual.gd
## Liquid trap feedback: the puddle under the box grows with the spill and the
## slosh sound plays. "Fregá" (N-117.3): the puddle also visibly shrinks as the
## scrub dries it (and swings A/D alternately), and holding the action leaves it
## as it was.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	package.trap_definition = load("res://data/traps/liquid.tres")
	package.gravity_scale = 0.0
	package.spawn_grace_time = 0.0
	root.add_child(package)
	await process_frame
	await process_frame
	var feedback := package.get_node("PackageFeedbackComponent")
	_expect(feedback.get_node_or_null("../Box/LiquidPuddle") != null, "Líquido debe crear un charco visible")
	package.trap_behavior.set("spill_amount", 50.0)
	await process_frame
	var puddle := feedback.get_node("../Box/LiquidPuddle") as MeshInstance3D
	_expect(puddle.visible and puddle.scale.x > 0.08, "El charco debe crecer al derramarse")
	var wide: float = puddle.scale.x
	_expect(feedback.get("_liquid_slosh_player") != null, "Líquido debe tener sonido propio")

	# Holding does nothing to it.
	for tick: int in 10:
		package.trap_behavior.call(&"on_physics_process", package, 0.1,
			{"input": {"steady": true, "calm": true, "steady_strength": 1.0, "calm_strength": 1.0}})
	await process_frame
	_expect(is_equal_approx(puddle.scale.x, wide), "Mantener la acción no achica el charco")

	# Scrubbing does, swing by swing.
	var sides: Array[StringName] = [&"left", &"right"]
	for tick: int in 12:
		package.trap_behavior.call(&"on_physics_process", package, 0.15,
			{"input": {"direction_pressed": sides[tick % 2]}})
	await process_frame
	_expect(puddle.scale.x < wide - 0.03, "Fregar achica el charco (%.2f a %.2f)" % [wide, puddle.scale.x])
	for tick: int in 200:
		package.trap_behavior.call(&"on_physics_process", package, 0.15,
			{"input": {"direction_pressed": sides[tick % 2]}})
	await process_frame
	_expect(not puddle.visible, "Seco del todo, el charco desaparece")
	package.free()
	if _failures == 0:
		print("PASS: liquid puddle grows, shrinks under the scrub, ignores holding, and sloshes")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
