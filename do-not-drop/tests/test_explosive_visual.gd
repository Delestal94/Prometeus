extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_explosive_visual.gd
## Explosive trap feedback: the countdown floats over the box's lid (not inside
## or on a face) and ticks with its own sound. It counts the code's steps and
## shows CÓDIGO -- never the arrows, those are on the driver's dashboard -- and
## shows DESACTIVAR with the next arrow only when the owner reads the code
## themselves (N-117 "Pedí el código").

func _init() -> void:
	call_deferred("_run")

var _failures: int = 0


func _run() -> void:
	var package := (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate() as DeliveryPackage
	package.trap_definition = load("res://data/traps/explosive.tres")
	root.add_child(package)
	await process_frame
	await process_frame
	var feedback := package.get_node("PackageFeedbackComponent")
	var display := feedback.get_node_or_null("../Box/ExplosiveCountdown") as Label3D
	_expect(display != null, "Explosivo debe mostrar su contador en la caja")
	if display == null:
		quit(1)
		return
	_expect("CÓDIGO" in display.text, "El contador cuenta los pasos del código (%s)" % display.text)
	for arrow: String in ["↑", "↓", "←", "→"]:
		_expect(not arrow in display.text, "El contador no muestra flechas (%s)" % display.text)
	_expect("0/3" in display.text, "Cuenta los pasos hechos (%s)" % display.text)
	_expect(display.no_depth_test, "El contador se dibuja encima de la caja, no adentro")
	_expect(display.position.y > 0.3, "El contador flota sobre la tapa, no en una cara de la caja")
	_expect(feedback.get("_explosive_tick_player") != null, "Explosivo debe tener sonido de tictac")
	package.care_state = {"sequence": {"steps": [&"up", &"left", &"down"], "index": 1, "seconds": 9.0,
		"reader": &"driver"}}
	await process_frame
	_expect("CÓDIGO" in display.text and "1/3" in display.text and not "←" in display.text,
		"Publicado para el conductor, sigue sin flechas y avanza (%s)" % display.text)
	package.care_state = {"sequence": {"steps": [&"up", &"left", &"down"], "index": 1, "seconds": 9.0,
		"reader": &"owner"}}
	await process_frame
	_expect("DESACTIVAR" in display.text and "←" in display.text,
		"Si el dueño lee el código, ve la flecha que sigue (%s)" % display.text)
	package.free()
	if _failures == 0:
		print("PASS: explosive package has countdown display and ticking audio presentation.")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
