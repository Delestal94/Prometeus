extends SceneTree
## Replays recorded real drives through every real trap behavior (S-108).
## Not part of the unit-test battery: record drives first, then run:
##   <godot> --headless --path do-not-drop --script res://tests/sim_trap_balance.gd

const TRIALS_PER_DRIVE: int = 50
const LATENCIES: Array[float] = [0.0, 0.15]
const PROFILE_ORDER: Array[String] = ["absent", "clumsy", "expert"]
const PROFILES := {
	"absent": {"reaction": INF, "accuracy": 0.0, "dropout": 1.0},
	"clumsy": {"reaction": 0.8, "accuracy": 0.60, "dropout": 0.20},
	"expert": {"reaction": 0.25, "accuracy": 0.95, "dropout": 0.0},
}
const DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]

var _trials_per_drive: int = TRIALS_PER_DRIVE


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	_trials_per_drive = maxi(1, int(_arg("trials", str(TRIALS_PER_DRIVE))))
	var only_trap: String = _arg("only", "")
	var drives: Array[Dictionary] = _load_drives()
	if drives.size() != 5:
		push_error("S-108 needs exactly five drive_*.json recordings; found %d" % drives.size())
		quit(1)
		return
	var traps: Array[TrapDefinition] = _load_traps()
	var rows: Array[Dictionary] = []
	for definition: TrapDefinition in traps:
		if not only_trap.is_empty() and String(definition.id) != only_trap:
			continue
		for profile_name: String in PROFILE_ORDER:
			for latency: float in LATENCIES:
				var aggregate := {"runs": 0, "ruined": 0, "risk_seconds": 0.0, "near_misses": 0}
				for drive_index: int in range(drives.size()):
					for trial: int in range(_trials_per_drive):
						var seed_value: int = hash("%s:%s:%.2f:%d:%d" % [definition.id, profile_name, latency, drive_index, trial])
						var result: Dictionary = _simulate(definition, drives[drive_index], profile_name, latency, seed_value)
						aggregate.runs += 1
						aggregate.ruined += int(result.ruined)
						aggregate.risk_seconds += result.risk_seconds
						aggregate.near_misses += int(result.near_miss)
				var row := {
					"trap": String(definition.id),
					"profile": profile_name,
					"latency_ms": roundi(latency * 1000.0),
					"runs": aggregate.runs,
					"ruined_pct": 100.0 * aggregate.ruined / aggregate.runs,
					"risk_seconds": aggregate.risk_seconds / aggregate.runs,
					"near_miss_pct": 100.0 * aggregate.near_misses / aggregate.runs,
				}
				rows.append(row)
				print("ROW %s %s +%dms ruined=%.1f%% risk=%.1fs near=%.1f%%" % [
					row.trap, row.profile, row.latency_ms, row.ruined_pct, row.risk_seconds, row.near_miss_pct])
	if not only_trap.is_empty():
		print("PASS sim_trap_balance calibration: %s × 3 profiles × 2 latencies × 5 drives × %d trials" % [only_trap, _trials_per_drive])
		quit(0)
		return
	var report: String = _make_report(rows, drives)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/sim_data"))
	var file := FileAccess.open("res://tests/sim_data/balance_report.md", FileAccess.WRITE)
	file.store_string(report)
	file.close()
	print(report)
	print("PASS sim_trap_balance: %d traps × 3 profiles × 2 latencies × 5 drives × %d trials" % [traps.size(), _trials_per_drive])
	quit(0)


func _load_drives() -> Array[Dictionary]:
	var paths: PackedStringArray = []
	var directory := DirAccess.open("res://tests/sim_data")
	if directory == null:
		return []
	for name: String in directory.get_files():
		if name.begins_with("drive_") and name.ends_with(".json"):
			paths.append("res://tests/sim_data/%s" % name)
	paths.sort()
	var drives: Array[Dictionary] = []
	for path: String in paths:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			drives.append(parsed as Dictionary)
	return drives


func _load_traps() -> Array[TrapDefinition]:
	var paths: PackedStringArray = []
	for name: String in DirAccess.get_files_at("res://data/traps"):
		if name.ends_with(".tres"):
			paths.append("res://data/traps/%s" % name)
	paths.sort()
	var traps: Array[TrapDefinition] = []
	for path: String in paths:
		var definition := load(path) as TrapDefinition
		if definition != null:
			traps.append(definition)
	return traps


func _simulate(definition: TrapDefinition, drive: Dictionary, profile_name: String, latency: float, seed_value: int) -> Dictionary:
	var package := RigidBody3D.new()
	package.mass = 8.0
	root.add_child(package)
	var behavior := definition.create_behavior() as ITrapBehavior
	behavior.on_setup(package, definition.params.duplicate(true))
	var behavior_rng: Variant = behavior.get("_rng")
	if behavior_rng is RandomNumberGenerator:
		(behavior_rng as RandomNumberGenerator).seed = seed_value
		behavior.call(&"_roll_sequence")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var profile: Dictionary = PROFILES[profile_name]
	var reaction: float = float(profile.reaction) + latency
	var time: float = 0.0
	var next_press: float = reaction
	var last_window: int = -1
	var follows_desired: bool = false
	var desired_history: Array[Dictionary] = []
	var risk_seconds: float = 0.0
	var min_integrity: float = behavior.integrity
	var dt: float = float(drive.get("dt", 1.0 / 60.0))
	var previous_recorded_tilt: float = 0.0
	var simulated_tilt: float = 0.0
	for raw_frame: Variant in drive.frames:
		var frame := raw_frame as Dictionary
		time += dt
		var tilt: float = float(frame.get("tilt", 0.0))
		# Replay the truck's frame-to-frame lean, while retaining any correction
		# the real Balance behavior applied on the previous frame.
		simulated_tilt = maxf(0.0, simulated_tilt + tilt - previous_recorded_tilt)
		previous_recorded_tilt = tilt
		package.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(simulated_tilt)), Vector3.ZERO)
		behavior.on_impact(float(frame.get("impact", 0.0)))
		var input: Dictionary = {}
		if profile_name != "absent":
			if definition.id == &"growing_weight" or definition.id == &"explosive":
				if time >= next_press:
					next_press = time + reaction
					if rng.randf() >= float(profile.dropout):
						var wanted: StringName = _wanted_direction(behavior, definition.id)
						if not wanted.is_empty():
							input.direction_pressed = wanted if rng.randf() <= float(profile.accuracy) else _wrong_direction(wanted, rng)
			else:
				var desired: bool = _wanted_hold(behavior, definition.id, tilt)
				desired_history.append({"time": time, "value": desired})
				var delayed_desired: bool = false
				for index: int in range(desired_history.size() - 1, -1, -1):
					if float(desired_history[index].time) <= time - reaction:
						delayed_desired = bool(desired_history[index].value)
						break
				while desired_history.size() > 2 and float(desired_history[1].time) < time - reaction:
					desired_history.pop_front()
				var window: int = floori(time * 2.0)
				if window != last_window:
					last_window = window
					follows_desired = rng.randf() <= float(profile.accuracy)
					if delayed_desired and rng.randf() < float(profile.dropout):
						follows_desired = false
				var holding: bool = delayed_desired if follows_desired else not delayed_desired
				if definition.id == &"balance":
					input.steady = holding
				else:
					input.calm = holding
		behavior.on_physics_process(package, dt, {"input": input})
		simulated_tilt = rad_to_deg(package.basis.y.angle_to(Vector3.UP))
		if behavior.get_state() == ITrapBehavior.TrapState.AT_RISK:
			risk_seconds += dt
		min_integrity = minf(min_integrity, behavior.integrity)
		if behavior.get_state() == ITrapBehavior.TrapState.RUINED:
			break
	package.free()
	var ruined: bool = behavior.get_state() == ITrapBehavior.TrapState.RUINED
	return {
		"ruined": ruined,
		"risk_seconds": risk_seconds,
		"near_miss": not ruined and min_integrity >= 5.0 and min_integrity <= 25.0,
		"min_integrity": min_integrity,
	}


func _wanted_direction(behavior: ITrapBehavior, trap_id: StringName) -> StringName:
	if trap_id == &"explosive":
		return behavior.call(&"next_direction") as StringName
	var sequence: Array = behavior.get("sequence") as Array
	var index: int = int(behavior.get("sequence_index"))
	return StringName(sequence[index]) if index < sequence.size() else &""


func _wrong_direction(wanted: StringName, rng: RandomNumberGenerator) -> StringName:
	var options: Array[StringName] = DIRECTIONS.duplicate()
	options.erase(wanted)
	return options[rng.randi_range(0, options.size() - 1)]


func _wanted_hold(behavior: ITrapBehavior, trap_id: StringName, tilt: float) -> bool:
	match trap_id:
		&"balance":
			return tilt > 1.0
		&"noisy":
			return float(behavior.get("agitation")) > 0.0
		&"liquid":
			return float(behavior.get("spill_amount")) > 0.0 or tilt > 1.0
		&"hostile":
			return bool(behavior.get("command_calm"))
	return false


func _make_report(rows: Array[Dictionary], drives: Array[Dictionary]) -> String:
	var lines: Array[String] = [
		"# S-108 · Balance de trampas",
		"",
		"Generado por `tests/sim_trap_balance.gd` con los comportamientos reales: 5 recorridos × %d repeticiones por combinación." % _trials_per_drive,
		"Perfiles: ausente; torpe (0,8 s, 60 % de acierto, 20 % de abandono); experto (0,25 s, 95 %). Cada uno se mide con 0 y 150 ms adicionales.",
		"",
		"| Trampa | Perfil | Latencia | Perdidos | Segundos en riesgo | Casi pérdida |",
		"|---|---|---:|---:|---:|---:|",
	]
	for row: Dictionary in rows:
		lines.append("| %s | %s | %d ms | %.1f%% | %.1f | %.1f%% |" % [
			row.trap, row.profile, row.latency_ms, row.ruined_pct, row.risk_seconds, row.near_miss_pct])
	lines.append_array(["", "## Objetivos", ""])
	var interactive: Array[String] = ["balance", "explosive", "growing_weight", "hostile", "liquid", "noisy"]
	var all_targets: bool = true
	# Near misses are counted per complete seven-package trip. Fragile remains
	# outside passenger-profile pass/fail, but its real near miss still happened.
	var fragile_clumsy: Dictionary = _find_row(rows, "fragile", "clumsy", 0)
	var clumsy_near_misses: float = fragile_clumsy.near_miss_pct / 100.0
	for trap_id: String in interactive:
		var absent: Dictionary = _find_row(rows, trap_id, "absent", 0)
		var clumsy: Dictionary = _find_row(rows, trap_id, "clumsy", 0)
		var expert: Dictionary = _find_row(rows, trap_id, "expert", 0)
		var expert_lag: Dictionary = _find_row(rows, trap_id, "expert", 150)
		var passes: bool = absent.ruined_pct >= 80.0 and absent.ruined_pct <= 100.0
		passes = passes and clumsy.ruined_pct >= 30.0 and clumsy.ruined_pct <= 55.0
		passes = passes and expert.ruined_pct < 12.0 and expert_lag.ruined_pct - expert.ruined_pct <= 8.0
		all_targets = all_targets and passes
		clumsy_near_misses += clumsy.near_miss_pct / 100.0
		lines.append("- %s: %s" % [trap_id, "CUMPLE" if passes else "FUERA DE OBJETIVO"])
	all_targets = all_targets and clumsy_near_misses >= 1.0
	lines.append("- Casi pérdidas esperadas por viaje torpe (7 paquetes): %.2f (objetivo ≥ 1)." % clumsy_near_misses)
	lines.append("- Resultado interactivo: **%s**." % ("CUMPLE" if all_targets else "REQUIERE AJUSTE"))
	lines.append_array([
		"",
		"`fragile` se informa aparte: no tiene acción de pasajero por diseño; sus seis filas deben coincidir y miden solamente el manejo del conductor.",
		"",
		"Recorridos: %s." % _drive_summary(drives),
		"",
	])
	return "\n".join(lines)


func _find_row(rows: Array[Dictionary], trap_id: String, profile: String, latency_ms: int) -> Dictionary:
	for row: Dictionary in rows:
		if row.trap == trap_id and row.profile == profile and row.latency_ms == latency_ms:
			return row
	return {}


func _drive_summary(drives: Array[Dictionary]) -> String:
	var values: Array[String] = []
	for drive: Dictionary in drives:
		values.append("seed %d (%.0f m, %.1f s)" % [drive.seed, drive.route_length, drive.frames.size() * drive.dt])
	return ", ".join(values)
