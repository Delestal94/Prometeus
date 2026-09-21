extends Node
## Only current-run state. All numbers here are provisional for the test route.

const PAR_SECONDS: float = 75.0
var is_running: bool = false
var elapsed_seconds: float = 0.0
var results: Dictionary = {}
var package_integrity: float = 100.0
var package_maximum: float = 100.0
var package_state: int = 0


func _ready() -> void:
	EventBus.package_integrity_changed.connect(_on_integrity_changed)
	EventBus.package_state_changed.connect(_on_state_changed)
	EventBus.package_ruined.connect(_on_package_ruined)


func _physics_process(delta: float) -> void:
	if is_running:
		elapsed_seconds += delta


func reset_run() -> void:
	is_running = false
	elapsed_seconds = 0.0
	results = {}
	package_integrity = 100.0
	package_maximum = 100.0
	package_state = 0


func start_run() -> void:
	if is_running or not results.is_empty():
		return
	is_running = true
	EventBus.run_started.emit(&"test_route", [1])


func finish_run(delivered: bool, reason: String = "") -> void:
	if not is_running:
		return
	is_running = false
	var successful: bool = delivered and package_state != 2
	var package_points: int = (100 if package_state == 0 else 50) if successful else 0
	var time_bonus: int = roundi(50.0 * clampf(1.0 - elapsed_seconds / PAR_SECONDS, 0.0, 1.0)) if successful else 0
	var score: int = package_points + time_bonus
	results = {
		"delivered": successful,
		"reason": reason,
		"elapsed_seconds": elapsed_seconds,
		"integrity": package_integrity,
		"package_state": package_state,
		"package_points": package_points,
		"time_bonus": time_bonus,
		"score": score,
	}
	print("[Run] ", results)
	EventBus.run_ended.emit(score, results.duplicate(true))


func _on_integrity_changed(_id: StringName, integrity: float, maximum: float) -> void:
	package_integrity = integrity
	package_maximum = maximum


func _on_state_changed(id: StringName, state: int) -> void:
	package_state = state
	print("[Package] ", id, " -> ", ["OK", "EnRiesgo", "Arruinado"][state])


func _on_package_ruined(id: StringName, cause: String) -> void:
	print("[Package] ", id, " ruined: ", cause)
	finish_run(false, "El paquete se arruinó. Probá bajar la velocidad antes de las lomadas.")
