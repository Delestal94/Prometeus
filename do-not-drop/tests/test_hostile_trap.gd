extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var behavior := preload("res://scripts/gameplay/traps/hostile_trap_behavior.gd").new()
	behavior.on_setup(null, {"integrity_max": 100.0, "command_seconds": 10.0, "correct_decay": 14.0, "wrong_gain": 24.0, "passive_gain": 4.0})
	behavior.aggression = 30.0
	behavior.command_calm = true
	behavior.on_physics_process(null, 0.5, {"input": {"calm": true}})
	assert(behavior.aggression < 30.0, "Calmar cuando se ordena debe bajar la agresión")
	behavior.command_calm = false
	var before: float = behavior.aggression
	behavior.on_physics_process(null, 0.2, {"input": {"calm": true}})
	assert(behavior.aggression > before and behavior.attack_count == 1, "Tocar cuando ordena NO TOCAR debe provocar ataque")
	behavior.aggression = 99.0
	behavior.command_calm = false
	behavior.on_physics_process(null, 1.0, {"input": {"calm": true}})
	assert(behavior.get_state() == ITrapBehavior.TrapState.RUINED, "Ataques ignorados deben dejar escapar a la criatura")
	print("PASS: hostile trap rewards correct responses, attacks wrong input and can escape.")
	quit(0)
