extends Node
## Only current-run state. All numbers here are provisional for the test route.
##
## Tracks every package in the van, not just one: losing a box no longer ends
## the delivery, it just scores less. With four passengers, one person's
## mistake ending everyone's run would be miserable -- the run only collapses
## if every last package is gone.

const PAR_SECONDS: float = 75.0
const POINTS_INTACT: int = 100
const POINTS_AT_RISK: int = 50
const CHAOS_MULTIPLIER: float = 1.2

var is_running: bool = false
var elapsed_seconds: float = 0.0
var results: Dictionary = {}
## id -> {"integrity": float, "maximum": float, "state": int}
var cargo: Dictionary = {}
## True once two or more packages were in trouble at the same moment. The
## score rewards it: surviving a shared scare is the story people retell.
var had_simultaneous_risk: bool = false


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
	cargo = {}
	had_simultaneous_risk = false


func start_run() -> void:
	if is_running or not results.is_empty():
		return
	is_running = true
	EventBus.run_started.emit(&"test_route", [1])


func finish_run(delivered: bool, reason: String = "") -> void:
	if not is_running:
		return
	is_running = false
	var cargo_points: int = 0
	var intact: int = 0
	var ruined: int = 0
	if delivered:
		for entry: Dictionary in cargo.values():
			match int(entry.get("state", 0)):
				ITrapBehavior.TrapState.OK:
					cargo_points += POINTS_INTACT
					intact += 1
				ITrapBehavior.TrapState.AT_RISK:
					cargo_points += POINTS_AT_RISK
				_:
					ruined += 1
	else:
		ruined = cargo.size()
	var successful: bool = delivered and cargo_points > 0
	var time_bonus: int = roundi(50.0 * clampf(1.0 - elapsed_seconds / PAR_SECONDS, 0.0, 1.0)) if successful else 0
	var multiplier: float = CHAOS_MULTIPLIER if (successful and had_simultaneous_risk) else 1.0
	var score: int = roundi((cargo_points + time_bonus) * multiplier)
	results = {
		"delivered": successful,
		"reason": reason,
		"elapsed_seconds": elapsed_seconds,
		"cargo_total": cargo.size(),
		"cargo_intact": intact,
		"cargo_ruined": ruined,
		"cargo_points": cargo_points,
		"time_bonus": time_bonus,
		"chaos_multiplier": multiplier,
		"score": score,
	}
	print("[Run] ", results)
	EventBus.run_ended.emit(score, results.duplicate(true))


## Worst state across the cargo, for readouts that only have room for one.
func worst_state() -> int:
	var worst: int = ITrapBehavior.TrapState.OK
	for entry: Dictionary in cargo.values():
		worst = maxi(worst, int(entry.get("state", 0)))
	return worst


func _entry(id: StringName) -> Dictionary:
	if not cargo.has(id):
		cargo[id] = {"integrity": 100.0, "maximum": 100.0, "state": ITrapBehavior.TrapState.OK}
	return cargo[id]


func _on_integrity_changed(id: StringName, integrity: float, maximum: float) -> void:
	var entry: Dictionary = _entry(id)
	entry["integrity"] = integrity
	entry["maximum"] = maximum


func _on_state_changed(id: StringName, state: int) -> void:
	_entry(id)["state"] = state
	if _count_in_trouble() >= 2:
		had_simultaneous_risk = true


func _on_package_ruined(id: StringName, cause: String) -> void:
	print("[Package] ", id, " ruined: ", cause)
	_entry(id)["state"] = ITrapBehavior.TrapState.RUINED
	if _count_ruined() >= cargo.size():
		finish_run(false, "Se arruinó toda la carga. No queda nada que entregar.")


func _count_in_trouble() -> int:
	var total: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.AT_RISK:
			total += 1
	return total


func _count_ruined() -> int:
	var total: int = 0
	for entry: Dictionary in cargo.values():
		if int(entry.get("state", 0)) == ITrapBehavior.TrapState.RUINED:
			total += 1
	return total
