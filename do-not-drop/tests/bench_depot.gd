extends SceneTree
## Depot frame cost: packages + HUD (tareas de Nacho S-208).
##   <godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_depot.gd
## Optional user args: -- --frames=600 --players=5 --seed=4242
##
## Builds the real level in its depot phase (14 boxes on the shelves, HUD up,
## the local player plus fake remote ones -- the same "Player_<peer>" nodes a
## spawner would replicate) with a fixed world seed, and runs it for N frames
## in three passes over the same scene:
##   1. everything running (measured twice, before and after pass 2): average and p95 of Performance.TIME_PROCESS (the
##      whole idle frame, s) and of the wall time of each frame;
##   2. the scripts under test switched off (every package_feedback.gd node
##      and the HUD's own _process, so their `text =` writes, relayouts and
##      lookups don't happen), same scenario: the frame cost without them;
##   3. those same _process calls made by hand from process_frame and timed
##      with Time.get_ticks_usec(): the cost of the callbacks alone, split
##      into "packages" (all package_feedback.gd nodes) and "hud".
## Pass 3 is the number the goal uses (packages + HUD < 1.5 ms per frame): it
## is exact for the script bodies. Pass 1 minus pass 2 in wall time is the
## cross-check that also catches what those scripts cause later in the frame
## (relayout of labels whose text they rewrote). TIME_PROCESS itself swings by
## several ms between identical passes in headless software runs (the two
## "running" rows show it), so it is printed for the record, not judged. Software timings on a CPU-only machine:
## compare before/after on the same box, not against a GPU number.
## Prints one summary table and "RESULT" plus PASS or FAIL against the goal.

const GOAL_MS: float = 1.5
const WARMUP_FRAMES: int = 60

var _frames: int = 600
var _players: int = 5
var _seed: int = 4242
var _level: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	_frames = int(_arg("frames", "600"))
	_players = int(_arg("players", "5"))
	_seed = int(_arg("seed", "4242"))
	root.get_node(^"/root/NetworkManager").set(&"world_seed", _seed)
	root.get_node(^"/root/CrewProgression").call(&"reset_campaign")
	for unlock_id: StringName in (root.get_node(^"/root/UnlockManager").get(&"TRAP_UNLOCKS") as Dictionary).values():
		root.get_node(^"/root/UnlockManager").unlocked[unlock_id] = true
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	await process_frame
	await physics_frame
	for peer: int in range(2, _players + 1):
		_spawn_remote(peer)
	for i: int in range(WARMUP_FRAMES):
		await process_frame

	var packages: Array = _level.get(&"packages")
	var feedbacks: Array[Node] = _feedback_nodes()
	var hud: Node = _level.get_node(^"HUD")
	var players: int = get_nodes_in_group(&"player").size()
	print("Depot: %d boxes, %d package_feedback nodes, %d players, %d nodes, seed %d, %d frames" % [
			packages.size(), feedbacks.size(), players, _node_count(), _seed, _frames])

	# 1. Everything running.
	var full: Dictionary = await _measure_frames()
	# 2. Scripts under test off.
	for node: Node in feedbacks:
		node.set_process(false)
	hud.set_process(false)
	var idle: Dictionary = await _measure_frames()
	# Back on again: the same scene once more, so an order effect (physics
	# settling between passes) would show as a gap between the two "on" rows.
	for node: Node in feedbacks:
		node.set_process(true)
	hud.set_process(true)
	var full_again: Dictionary = await _measure_frames()
	for node: Node in feedbacks:
		node.set_process(false)
	hud.set_process(false)
	# 3. Same calls by hand, timed.
	var packages_us := PackedFloat64Array()
	var hud_us := PackedFloat64Array()
	for i: int in range(_frames):
		await process_frame
		var delta: float = 1.0 / 60.0
		var t0: int = Time.get_ticks_usec()
		for node: Node in feedbacks:
			node.call(&"_process", delta)
		var t1: int = Time.get_ticks_usec()
		hud.call(&"_process", delta)
		var t2: int = Time.get_ticks_usec()
		packages_us.append(t1 - t0)
		hud_us.append(t2 - t1)
	var combined := PackedFloat64Array()
	for i: int in range(_frames):
		combined.append(packages_us[i] + hud_us[i])

	print("")
	print("| Metric | avg ms | p95 ms |")
	print("|---|---|---|")
	_row("TIME_PROCESS, everything running", full.process)
	_row("TIME_PROCESS, everything running (again)", full_again.process)
	_row("TIME_PROCESS, packages + HUD off", idle.process)
	_row("frame wall time, everything running", full.wall)
	_row("frame wall time, packages + HUD off", idle.wall)
	_row("package_feedback.gd (%d nodes), timed" % feedbacks.size(), _to_ms(packages_us))
	_row("HUD _process, timed", _to_ms(hud_us))
	_row("packages + HUD, timed", _to_ms(combined))
	var diff: float = (_avg(full.process) + _avg(full_again.process)) * 0.5 - _avg(idle.process)
	var wall_diff: float = _avg(full.wall) - _avg(idle.wall)
	print("TIME_PROCESS difference (mean of both running passes - off): %.3f ms (noisy here, see header)" % diff)
	print("Wall time difference (running - off): %.3f ms" % wall_diff)
	var total: float = _avg(_to_ms(combined))
	var verdict: String = "PASS" if total < GOAL_MS else "FAIL"
	print("RESULT packages + HUD %.3f ms/frame (goal < %.1f ms): %s" % [total, GOAL_MS, verdict])
	quit(0)


func _feedback_nodes() -> Array[Node]:
	var found: Array[Node] = []
	for package: Node in _level.get(&"packages"):
		for child: Node in package.get_children():
			var script: Script = child.get_script()
			if script != null and script.resource_path.ends_with("package_feedback.gd"):
				found.append(child)
	return found


func _spawn_remote(peer: int) -> void:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % peer
	player.position = Vector3(float(peer) * 1.2 - 4.0, 1.0, 10.0)
	_level.add_child(player)
	player.set(&"net_position", player.position)


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## {"process": ms per frame from TIME_PROCESS, "wall": wall ms per frame}.
func _measure_frames() -> Dictionary:
	var process_ms := PackedFloat64Array()
	var wall_ms := PackedFloat64Array()
	var last: int = Time.get_ticks_usec()
	for i: int in range(_frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		wall_ms.append(float(now - last) / 1000.0)
		last = now
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	return {"process": process_ms, "wall": wall_ms}


func _to_ms(values_us: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for value: float in values_us:
		out.append(value / 1000.0)
	return out


func _avg(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / maxf(float(values.size()), 1.0)


func _p95(values: PackedFloat64Array) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)]


func _row(label: String, values: PackedFloat64Array) -> void:
	print("| %s | %.3f | %.3f |" % [label, _avg(values), _p95(values)])
