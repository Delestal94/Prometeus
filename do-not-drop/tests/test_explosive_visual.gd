extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_explosive_visual.gd
## Explosive trap feedback: the countdown floats over the box's lid (not inside
## or on a face), shows DESACTIVAR, and ticks with its own sound.

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
	assert("DESACTIVAR" in display.text, "El contador debe indicar la acción de desactivar")
	assert(display.no_depth_test, "El contador se dibuja encima de la caja, no adentro")
	assert(display.position.y > 0.3, "El contador flota sobre la tapa, no en una cara de la caja")
	assert(feedback.get("_explosive_tick_player") != null, "Explosivo debe tener sonido de tictac")
	package.free()
	print("PASS: explosive package has countdown display and ticking audio presentation.")
	quit(0)
