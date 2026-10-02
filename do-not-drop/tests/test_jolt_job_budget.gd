extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_jolt_job_budget.gd
##
## N-917: loading the delivery printed "Jolt Physics job system exceeded the maximum
## number of jobs" and froze frames for up to ~1.8 s under the loading cover. Jolt runs
## its physics jobs on the WorkerThreadPool and only frees each one once a pool thread
## has run it; the sliced terrain build (TerrainField.tiles / .conform) took every
## pool thread for seconds, so the jobs of each physics step piled up until the fixed
## pool ran dry. Protects against:
## - TerrainField.worker_tasks() leaving at least one pool thread free (when there is
##   more than one, also under threading/worker_pool/max_threads), so a terrain group
##   can never hold the whole pool;
## - a sliced route build (Route.always_slice) with an always-awake body in the same
##   world, so every physics step queues Jolt jobs, ending with no such warning (a
##   Logger counts it; the warning is printed once per process, so it is caught here
##   before anything else loads).

const ROUTE_SCENE: String = "res://scenes/gameplay/route/route.tscn"
const ROUTE_SCRIPT: String = "res://scripts/gameplay/route/route.gd"
const JOLT_JOBS_WARNING: String = "Jolt Physics job system exceeded"
const TIMEOUT_MSEC: int = 90_000

var _failures: int = 0


class JoltJobsCatcher extends Logger:
	var count: int = 0
	var _mutex: Mutex = Mutex.new()

	func _log_error(
		_function: String, _file: String, _line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]
	) -> void:
		if error_type == ERROR_TYPE_WARNING and (code + rationale).contains(JOLT_JOBS_WARNING):
			_mutex.lock()
			count += 1
			_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func caught() -> int:
		_mutex.lock()
		var value: int = count
		_mutex.unlock()
		return value


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catcher := JoltJobsCatcher.new()
	OS.add_logger(catcher)
	_test_worker_tasks()
	await _test_sliced_route(catcher)
	OS.remove_logger(catcher)
	if _failures == 0:
		print("PASS: the sliced terrain build leaves a pool thread to Jolt and no job-pool warning shows")
	quit(_failures)


func _test_worker_tasks() -> void:
	var cores: int = OS.get_processor_count()
	var max_threads: int = int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	if max_threads > 0:
		cores = mini(cores, max_threads)
	var tasks: int = TerrainField.worker_tasks()
	_expect(tasks >= 1, "the terrain build takes at least one worker (%d)" % tasks)
	if cores > 1:
		_expect(tasks < cores, "the terrain build leaves a pool thread free (%d of %d)" % [tasks, cores])


func _test_sliced_route(catcher: JoltJobsCatcher) -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var original_seed: Variant = network.get(&"world_seed")
	var original_houses: Variant = network.get(&"world_house_count")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 0)
	var route_script: GDScript = load(ROUTE_SCRIPT) as GDScript
	route_script.set(&"always_slice", true)

	var world := Node3D.new()
	root.add_child(world)
	# An awake body keeps every physics step queueing jobs while the build runs.
	var body := RigidBody3D.new()
	body.can_sleep = false
	body.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = Vector3(0.0, 500.0, 0.0)
	world.add_child(body)

	var route: Node = (load(ROUTE_SCENE) as PackedScene).instantiate()
	world.add_child(route)
	var start: int = Time.get_ticks_msec()
	while not bool(route.get(&"is_built")) and Time.get_ticks_msec() - start < TIMEOUT_MSEC:
		await process_frame
	_expect(bool(route.get(&"is_built")), "the sliced route finishes building")
	for _i: int in range(10):
		await physics_frame
	var caught: int = catcher.caught()
	_expect(caught == 0, "no Jolt job-pool warning while the route builds (%d)" % caught)

	route_script.set(&"always_slice", false)
	world.queue_free()
	await process_frame
	network.set(&"world_seed", original_seed)
	network.set(&"world_house_count", original_houses)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
