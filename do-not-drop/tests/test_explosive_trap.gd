extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var behavior := preload("res://scripts/gameplay/traps/explosive_trap_behavior.gd").new()
	behavior.on_setup(null, {"integrity_max": 100.0, "countdown_seconds": 8.0, "mistake_penalty": 2.0, "sequence": [&"up", &"left", &"down"]})
	behavior.on_physics_process(null, 0.1, {"input": {"direction_pressed": &"up"}})
	behavior.on_physics_process(null, 0.1, {"input": {"direction_pressed": &"left"}})
	behavior.on_physics_process(null, 0.1, {"input": {"direction_pressed": &"down"}})
	assert(behavior.get_hint() == "Desactivada.", "La secuencia correcta debe desactivar la bomba")
	var mistake := preload("res://scripts/gameplay/traps/explosive_trap_behavior.gd").new()
	mistake.on_setup(null, {"countdown_seconds": 8.0, "mistake_penalty": 2.0, "sequence": [&"up", &"left"]})
	var before: float = mistake.seconds_left
	mistake.on_physics_process(null, 0.1, {"input": {"direction_pressed": &"right"}})
	assert(mistake.seconds_left < before - 1.9, "Un input incorrecto debe costar tiempo")
	mistake.on_physics_process(null, 20.0, {"input": {}})
	assert(mistake.get_state() == ITrapBehavior.TrapState.RUINED, "Llegar a cero debe arruinar el paquete")
	print("PASS: explosive trap defuses by sequence, penalizes mistakes and detonates at zero.")
	quit(0)
