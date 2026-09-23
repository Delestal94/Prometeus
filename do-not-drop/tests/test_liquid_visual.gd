extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	package.trap_definition = load("res://data/traps/liquid.tres")
	package.gravity_scale = 0.0
	package.spawn_grace_time = 0.0
	root.add_child(package)
	await process_frame
	await process_frame
	var feedback := package.get_node("PackageFeedbackComponent")
	assert(feedback.get_node_or_null("../Box/LiquidPuddle") != null, "Líquido debe crear un charco visible")
	package.trap_behavior.set("spill_amount", 50.0)
	await process_frame
	var puddle := feedback.get_node("../Box/LiquidPuddle") as MeshInstance3D
	assert(puddle.visible and puddle.scale.x > 0.08, "El charco debe crecer al inclinarse")
	assert(feedback.get("_liquid_slosh_player") != null, "Líquido debe tener sonido propio")
	package.free()
	print("PASS: liquid package has a growing puddle and slosh audio presentation.")
	quit(0)
