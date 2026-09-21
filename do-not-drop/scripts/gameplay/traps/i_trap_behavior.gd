class_name ITrapBehavior
extends Resource
## Mutable simulation state belongs to one package, never to a shared .tres.

enum TrapState { OK, AT_RISK, RUINED }

var integrity: float = 100.0
var integrity_max: float = 100.0


func on_setup(_package: Node, config: Dictionary) -> void:
	integrity_max = maxf(float(config.get("integrity_max", 100.0)), 1.0)
	integrity = integrity_max


func on_physics_process(_package: Node, _delta: float, _vehicle_state: Dictionary) -> void:
	pass


func on_player_input(_package: Node, _input_event: InputEvent) -> void:
	pass


func on_impact(_delta_velocity: float) -> float:
	return 0.0


func get_state() -> int:
	return TrapState.OK
