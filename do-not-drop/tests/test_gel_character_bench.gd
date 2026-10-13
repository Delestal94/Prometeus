extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_character_bench.gd
## Guards the non-rendered S-311.37 benchmark contract: four distinct gel
## proportions, the +0.5 ms budget, stable output and informational CI wiring.

const BENCH := preload("res://tests/bench_gel_character.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(BENCH.CHARACTER_COUNT == 4, "the comparison renders exactly four characters")
	_expect(BENCH.GEL_PRESETS.size() == 4, "four gel proportion presets are selected")
	var unique: Dictionary = {}
	for preset_id: StringName in BENCH.GEL_PRESETS:
		unique[preset_id] = true
		_expect(GelProportionPresets.load_preset(preset_id) != null, "%s is a saved preset" % preset_id)
	_expect(unique.size() == 4, "the four gel bodies use different proportions")
	_expect(is_equal_approx(BENCH.GPU_BUDGET_MS, 0.5), "the item 7 GPU budget is +0.5 ms")

	var passing: Dictionary = BENCH.result(1.25, 1.75)
	var failing: Dictionary = BENCH.result(1.25, 1.751)
	_expect(passing.within_budget and is_equal_approx(passing.delta_gpu_ms, 0.5),
		"the exact +0.5 ms boundary passes")
	_expect(not failing.within_budget, "a delta above +0.5 ms fails")
	var lines: PackedStringArray = BENCH.summary_lines(passing.merged({
		"characters": 4,
		"current_draw_calls": 8,
		"gel_draw_calls": 4,
		"current_primitives": 12_000,
		"gel_primitives": 18_816,
	}))
	_expect(lines.size() == BENCH.SUMMARY_KEYS.size(), "the summary prints every required metric")
	_expect("BENCH_GEL delta_gpu_ms=0.500" in lines, "GPU delta keeps millisecond precision")
	_expect("BENCH_GEL within_budget=true" in lines, "the verdict is machine-readable")

	var workflow_path: String = ProjectSettings.globalize_path("res://") + "../.github/workflows/tests.yml"
	var workflow: String = FileAccess.get_file_as_string(workflow_path)
	if not workflow.is_empty():
		var step: int = workflow.find("bench_gel_character.gd")
		_expect(step > 0 and workflow.find("|| true", step) > step,
			"CI records the rendered comparison without treating software GPU time as a gate")
	if _failures == 0:
		print("PASS: S-311.37 compares four gel proportions within the +0.5 ms GPU budget")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
