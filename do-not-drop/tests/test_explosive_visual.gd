extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	package.trap_definition = load("res://data/traps/explosive.tres")
	root.add_child(package)
	await process_frame
	await process_frame
	var feedback := package.get_node("PackageFeedbackComponent")
	var display := feedback.get_node_or_null("../Box/ExplosiveCountdown") as Label3D
	assert(display != null, "Explosivo debe mostrar su contador en la caja")
	assert("DEFUSE" in display.text, "El contador debe indicar la acción de desactivar")
	assert(feedback.get("_explosive_tick_player") != null, "Explosivo debe tener sonido de tictac")
	package.free()
	print("PASS: explosive package has countdown display and ticking audio presentation.")
	quit(0)
