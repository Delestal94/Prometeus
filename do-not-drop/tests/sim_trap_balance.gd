extends SceneTree
## Replays recorded real drives through every real trap behavior (S-108).
## Not part of the unit-test battery: record drives first, then run:
##   <godot> --headless --path do-not-drop --script res://tests/sim_trap_balance.gd

const TRIALS_PER_DRIVE: int = 50
const LATENCIES: Array[float] = [0.0, 0.15]
## Liquid's scrub (N-117 "Fregá"): swings per second while the bot is scrubbing.
## Left-right-left-right at a hand's pace; an assumption of the harness.
const SCRUB_RATE_CLUMSY: float = 4.5
const SCRUB_RATE_EXPERT: float = 5.5
const PROFILE_ORDER: Array[String] = ["absent", "clumsy", "expert", "always"]
const PROFILES := {
	"absent": {"reaction": INF, "accuracy": 0.0, "dropout": 1.0},
	"clumsy": {"reaction": 0.8, "accuracy": 0.60, "dropout": 0.20, "scrub_rate": SCRUB_RATE_CLUMSY},
	"expert": {"reaction": 0.25, "accuracy": 0.95, "dropout": 0.0, "scrub_rate": SCRUB_RATE_EXPERT},
	# N-117: holds the primary action the whole run and never taps anything.
	"always": {"reaction": INF, "accuracy": 1.0, "dropout": 0.0},
}
const DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]
## Fragile (N-117 "Amortiguá"): the recorded drives take every bump gently
## (the autopilot's speed never hurts a box), so the road gets bumps taken at
## the drive's cruise speed, announced like the game announces them. The
## crashes nobody announces are the ones already in the recordings (seed
## 1085). Same schedule for every profile of a trial.
const FRAGILE_BUMPS: int = 3
const FRAGILE_FIRST_HIT: float = 15.0
const FRAGILE_LAST_MARGIN: float = 8.0
## How far off the middle of the window a tap lands (s), by profile: timing
## a ring is skill, not reaction. Network latency blurs it a little more.
## % of boxes lost per profile (absent, clumsy, expert, always) just before N-117.4
## touched Hostile (the state after N-117.3), measured by this same harness.
const BEFORE_TANDA_3 := {
	"balance": [100.0, 46.0, 0.0, 100.0],
	"explosive": [100.0, 45.2, 0.0, 100.0],
	"fragile": [100.0, 49.2, 2.8, 100.0],
	"growing_weight": [100.0, 53.6, 0.0, 100.0],
	"hostile": [100.0, 83.2, 0.0, 100.0],
	"liquid": [100.0, 38.0, 0.0, 100.0],
	"noisy": [100.0, 44.8, 0.8, 0.0],
}
const TAP_SPREAD := {"clumsy": 0.20, "expert": 0.05}
const LATENCY_BLUR: float = 0.25

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
						var seed_value: int = hash("%s:%s:%.2f:%d:%d" % [definition.id, profile_name, latency,
								drive_index, trial])
						var scenario_seed: int = hash("%s:%d:%d" % [definition.id, drive_index, trial])
						var result: Dictionary = _simulate(definition, drives[drive_index], profile_name, latency,
								seed_value, scenario_seed)
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
		print("PASS sim_trap_balance calibration: %s × 3 profiles × 2 latencies × 5 drives × %d trials" % [only_trap,
				_trials_per_drive])
		quit(0)
		return
	var report: String = _make_report(rows, drives)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/sim_data"))
	var file := FileAccess.open("res://tests/sim_data/balance_report.md", FileAccess.WRITE)
	file.store_string(report)
	file.close()
	print(report)
	print("PASS sim_trap_balance: %d traps × 3 profiles × 2 latencies × 5 drives × %d trials" % [traps.size(),
			_trials_per_drive])
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


func _simulate(definition: TrapDefinition, drive: Dictionary, profile_name: String, latency: float,
		seed_value: int, scenario_seed: int = 0) -> Dictionary:
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
	var hits: Array[Dictionary] = []
	if definition.id == &"fragile":
		hits = _plan_fragile_hits(behavior, drive, profile_name, latency, profile, scenario_seed, rng)
	var next_hit: int = 0
	var reaction: float = float(profile.reaction) + latency
	var time: float = 0.0
	var next_press: float = reaction
	var scrub_wait: float = 0.0
	var scrub_side: StringName = &"right"
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
		if profile_name == "always":
			# Holds and never moves: not the lean, not the scrub.
			input = {"steady": true, "calm": true, "lean": 0.0}
		elif profile_name != "absent":
			if definition.id == &"growing_weight" or definition.id == &"explosive":
				if time >= next_press:
					next_press = time + reaction
					if rng.randf() >= float(profile.dropout):
						var wanted: StringName = _wanted_direction(behavior, definition.id)
						if not wanted.is_empty():
							input.direction_pressed = (wanted if rng.randf() <= float(profile.accuracy)
									else _wrong_direction(wanted, rng))
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
					# Balance: hold and lean against the tilt (the recorded roll
					# always leans to the right, so left is the way).
					input.steady = holding
					input.lean = -1.0 if holding else 0.0
				elif definition.id == &"liquid":
					# Liquid: while it scrubs, a swing to the other side at its pace.
					scrub_wait -= dt
					if holding and scrub_wait <= 0.0:
						scrub_wait = 1.0 / float(profile.scrub_rate)
						scrub_side = &"left" if scrub_side == &"right" else &"right"
						input.direction_pressed = scrub_side
				else:
					input.calm = holding
		var context: Dictionary = {"input": input, "truck_right": Vector3.RIGHT}
		if definition.id == &"fragile":
			for hit: Dictionary in hits:
				if hit.tap_time >= 0.0 and not hit.tapped and time >= hit.tap_time:
					hit.tapped = true
					input["tap"] = true
			context["impact_ahead"] = _eta_to_next(hits, next_hit, time)
		behavior.on_physics_process(package, dt, context)
		while next_hit < hits.size() and time >= float(hits[next_hit].time):
			behavior.on_impact(float(hits[next_hit].strength))
			next_hit += 1
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


## The bumps Fragile is put through in a drive, and when each tap of this
## profile lands ({time, strength, tap_time, tapped}).
func _plan_fragile_hits(behavior: ITrapBehavior, drive: Dictionary, profile_name: String, latency: float,
		profile: Dictionary, scenario_seed: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var scenario := RandomNumberGenerator.new()
	scenario.seed = scenario_seed
	var count: int = FRAGILE_BUMPS
	var duration: float = drive.frames.size() * float(drive.get("dt", 1.0 / 60.0))
	var slot: float = (duration - FRAGILE_FIRST_HIT - FRAGILE_LAST_MARGIN) / count
	var bump_strength: float = float(behavior.call(&"road_jolt_strength", float(drive.get("cruise_kmh", 50.0)) / 3.6))
	var window: float = float(behavior.get("_cushion_window"))
	var hits: Array[Dictionary] = []
	for index: int in range(count):
		var hit_time: float = FRAGILE_FIRST_HIT + slot * (index + scenario.randf_range(0.2, 0.8))
		var tap_time: float = -1.0
		if profile_name in TAP_SPREAD:
			# Sees the ring and taps, or misses it: the profile's attention.
			if rng.randf() <= float(profile.accuracy) * (1.0 - float(profile.dropout)):
				var spread: float = sqrt(pow(float(TAP_SPREAD[profile_name]), 2.0) + pow(LATENCY_BLUR * latency, 2.0))
				tap_time = hit_time - (window * 0.5 + rng.randfn(0.0, spread))
		hits.append({"time": hit_time, "strength": bump_strength, "tap_time": tap_time, "tapped": false})
	return hits


## Seconds to the next bump, INF if none.
func _eta_to_next(hits: Array[Dictionary], from_index: int, time: float) -> float:
	return maxf(float(hits[from_index].time) - time, 0.0) if from_index < hits.size() else INF


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
	var interactive: Array[String] = ["balance", "explosive", "fragile", "growing_weight", "hostile", "liquid", "noisy"]
	var lines: Array[String] = [
		"# S-108 · Balance de trampas",
		"",
		("Generado por `tests/sim_trap_balance.gd` con los comportamientos reales: 5 recorridos × %d repeticiones"
		+ " por combinación.") % _trials_per_drive,
		"Perfiles: ausente; torpe (0,8 s, 60 % de acierto, 20 % de abandono); experto (0,25 s, 95 %); siempre mantiene"
		+ " (aprieta el botón principal toda la partida y no toca nada más). Cada uno se mide con 0 y 150 ms"
		+ " adicionales.",
		"",
		"## Resumen: % de cajas perdidas por trampa y perfil (0 ms)",
		"",
		"| Trampa | Ausente | Torpe | Experto | Siempre mantiene |",
		"|---|---:|---:|---:|---:|",
	]
	var always_lost: int = 0
	for trap_id: String in interactive:
		var cells: Array[String] = []
		for profile_name: String in PROFILE_ORDER:
			cells.append("%.1f%%" % _find_row(rows, trap_id, profile_name, 0).get("ruined_pct", NAN))
		always_lost += int(_find_row(rows, trap_id, "always", 0).get("ruined_pct", 0.0) >= 80.0)
		lines.append("| %s | %s |" % [trap_id, " | ".join(cells)])
	lines.append_array(["", "Antes de N-117.4 (los mismos recorridos con Hostil de antes: órdenes de 11 s y"
		+ " decaimiento de 14 por segundo, que dejaba al torpe en 83 %):", "", "| Trampa | Ausente | Torpe | Experto | Siempre mantiene |",
		"|---|---:|---:|---:|---:|"])
	for trap_id: String in BEFORE_TANDA_3:
		var before: Array = BEFORE_TANDA_3[trap_id]
		lines.append("| %s | %.1f%% | %.1f%% | %.1f%% | %.1f%% |" % [trap_id, before[0], before[1], before[2], before[3]])
	lines.append_array([
		"",
		("El que siempre mantiene pierde el 80 %% o más en %d de %d trampas (meta de N-117: 5 de 7, cuando cada"
		+ " trampa tenga su acción propia).") % [always_lost, interactive.size()],
		"",
		"## Todas las filas",
		"",
		"| Trampa | Perfil | Latencia | Perdidos | Segundos en riesgo | Casi pérdida |",
		"|---|---|---:|---:|---:|---:|",
	])
	for row: Dictionary in rows:
		lines.append("| %s | %s | %d ms | %.1f%% | %.1f | %.1f%% |" % [
			row.trap, row.profile, row.latency_ms, row.ruined_pct, row.risk_seconds, row.near_miss_pct])
	lines.append_array(["", "## Objetivos", ""])
	var all_targets: bool = true
	# Near misses are counted per complete seven-package trip.
	var clumsy_near_misses: float = 0.0
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
		"`fragile` (N-117, Amortiguá): los recorridos grabados pasan los baches sin golpe (la suspensión se los come,"
		+ " ver `docs/parametros-diseno.md`), así que el arnés le suma a cada recorrido %d baches a la velocidad de"
		% FRAGILE_BUMPS + " crucero, anunciados como los anuncia el juego. Los choques sin anunciar (que nadie puede"
		+ " amortiguar) son los que ya traen los recorridos grabados (el de la semilla 1085). El torpe y el experto"
		+ " ven el aviso con una atención del 48 % y 95 % y clavan el toque con una dispersión de 0,20 s y 0,05 s"
		+ " alrededor del medio de la ventana (0,35 s). Mantener apretado no protege.",
		"",
		"`fragile` (N-229): `cushion_leak` 0,1 a 0,15. El torpe que falla dos de los tres baches y amortigua el"
		+ " tercero quedaba en 26,5 de integridad, a 1,5 del borde de casi pérdida (25); con 0,15 queda en 24,75."
		+ " Su casi pérdida pasa de 0,8 % a 37,2 % y las casi pérdidas por viaje torpe de 0,73 a 1,10; ningún"
		+ " perfil pierde más cajas (el daño que salva un toque bueno baja de 90 % a 85 %, los golpes sin"
		+ " amortiguar no cambian). El experto baja de 16,8 % a 1,2 % de casi pérdida: en el recorrido 1085 (choque"
		+ " sin anunciar) ahora termina debajo de 5, un punto que el arnés ya no cuenta como casi pérdida pero"
		+ " tampoco pierde la caja.",
		"",
		"`hostile` (N-117.4): `command_seconds` 11 a 9 y `correct_decay` 14 a 16 por segundo. Con órdenes de 9 s el"
		+ " ausente sigue perdiendo en la primera calma y el que siempre mantiene en las órdenes de soltar; el torpe"
		+ " (que se equivoca el 40 % del tiempo) pasa de 83 % a la mitad. La orden también se lee en la caja"
		+ " (`>:(` soltá, `:)` mantené).",
		"",
		"`balance` y `liquid` (N-117.3): el gesto nuevo se modela con los mismos tiempos de reacción, atención y"
		+ " abandono de cada perfil. Equilibrio: mientras el bot mantiene también se inclina hacia el lado contrario"
		+ " (los recorridos grabados siempre se inclinan a la derecha). Líquido: mientras friega alterna izquierda"
		+ " y derecha a %.1f (torpe) y %.1f (experto) golpes por segundo, un supuesto del arnés. El que siempre"
		% [SCRUB_RATE_CLUMSY, SCRUB_RATE_EXPERT] + " mantiene aprieta el botón y no se inclina ni friega: no protege.",
		"",
		"Recorridos: %s." % _drive_summary(drives),
		"",
	])
	return "
".join(lines)


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
