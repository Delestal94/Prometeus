extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_bench_drive_caps.gd
##
## N-980: the bench_drive.gd probe must not grow its own memory on a long run:
## - RunningStat gives the mean, peak and spread of a stream without keeping it;
## - the probe source keeps no per-tick or per-frame array of samples (only the
##   one-float-per-frame PackedFloat32Array the percentiles need) and caps the
##   hitch lines it keeps whole;
## - endless has no route to measure progress against, so it reports none.

const BENCH_PATH: String = "res://tests/bench_drive.gd"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_running_stat()
	_check_source_has_no_unbounded_buffers()
	if _failures == 0:
		print("test_bench_drive_caps: OK")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _check_running_stat() -> void:
	var stat_class: GDScript = (load(BENCH_PATH) as GDScript).get_script_constant_map()["RunningStat"]
	var stat: RefCounted = stat_class.new()
	_expect(stat.get(&"count") == 0, "A new RunningStat is empty")
	for value: float in [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]:
		stat.call(&"add", value)
	_expect(stat.get(&"count") == 8, "It counts every sample")
	_expect(is_equal_approx(stat.get(&"mean"), 5.0), "Its mean is the mean of the stream")
	_expect(is_equal_approx(stat.get(&"peak"), 9.0), "Its peak is the largest sample")
	_expect(is_equal_approx(stat.call(&"std"), 2.0), "Its spread is the population std (2.0)")


func _check_source_has_no_unbounded_buffers() -> void:
	var text: String = FileAccess.get_file_as_string(BENCH_PATH)
	_expect(not text.is_empty(), "bench_drive.gd is readable")
	for banned: String in ["\t_frames.append", "_smooth_samples", "_phys_active.append", "_phys_time_ms.append",
			"_bodies_awake.append", "_contacts.append"]:
		_expect(not text.contains(banned), "The probe no longer keeps a sample array: %s" % banned)
	_expect(text.contains("MAX_HITCH_LINES"), "The hitch frames kept whole have a cap")
	_expect(text.contains("ADDED_KEEP_FRAMES"), "The node-added log is pruned")
	_expect(text.contains("if _endless:\n\t\treturn -1.0"), "Endless reports no route progress")
