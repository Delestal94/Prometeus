extends SceneTree
## Rendered comparison for S-311.37. Run with a display and the same renderer
## used by the game:
##   <godot> --gpu-profile --path do-not-drop --rendering-method mobile
##     --script res://tests/bench_gel_character.gd
##
## It renders the same fixed studio twice: first four copies of today's rounded
## character, then four LOD0 gel bodies with different saved proportions. GPU
## timestamps come from RenderingServer, not from CPU frame duration. The run
## fails when the gel median costs more than 0.5 ms above the current character.
## Optional user args: -- --seconds=5 --warmup=60

const PREFIX: String = "BENCH_GEL"
const GPU_BUDGET_MS: float = 0.5
const DEFAULT_SECONDS: float = 5.0
const DEFAULT_WARMUP_FRAMES: int = 60
const CHARACTER_COUNT: int = 4
const CURRENT_SCENE: PackedScene = preload(
	"res://assets/models/characters/sm_char_player_rounded.glb"
)
const GEL_SCENE: PackedScene = preload(
	"res://assets/models/characters/gel/gel_body_lod0.glb"
)
const GEL_PRESETS: Array[StringName] = [
	&"delgada", &"flaca", &"rellena", &"larguirucha",
]
const SUMMARY_KEYS: Array[String] = [
	"characters",
	"current_gpu_ms_p50",
	"gel_gpu_ms_p50",
	"delta_gpu_ms",
	"budget_gpu_ms",
	"within_budget",
	"current_draw_calls",
	"gel_draw_calls",
	"current_primitives",
	"gel_primitives",
]

var _characters := Node3D.new()
var _finished: bool = false
var _device: RenderingDevice
var _captured_gpu_ms: float = -1.0
var _timestamp_read_ready: bool = false


func _initialize() -> void:
	_run.call_deferred()


static func percentile(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(q * sorted.size()), 0, sorted.size() - 1)]


static func result(current_gpu_ms: float, gel_gpu_ms: float) -> Dictionary:
	var delta: float = gel_gpu_ms - current_gpu_ms
	return {
		"current_gpu_ms_p50": current_gpu_ms,
		"gel_gpu_ms_p50": gel_gpu_ms,
		"delta_gpu_ms": delta,
		"budget_gpu_ms": GPU_BUDGET_MS,
		"within_budget": delta <= GPU_BUDGET_MS,
	}


static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in SUMMARY_KEYS:
		var value: Variant = stats.get(key, "n/a")
		var rendered: String
		if value is float:
			rendered = "%.3f" % value
		elif value is bool:
			rendered = "true" if value else "false"
		else:
			rendered = str(value)
		lines.append("%s %s=%s" % [PREFIX, key, rendered])
	return lines


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bench_gel_character needs a rendering display; omit --headless")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	_device = RenderingServer.get_rendering_device()
	if _device == null:
		push_error(
			"bench_gel_character needs RenderingDevice GPU timestamps; "
			+ "run with --gpu-profile --rendering-method mobile"
		)
		quit(2)
		return
	_build_stage()
	var seconds: float = maxf(float(_arg("seconds", str(DEFAULT_SECONDS))), 0.5)
	var warmup: int = maxi(int(_arg("warmup", str(DEFAULT_WARMUP_FRAMES))), 4)

	_build_current_characters()
	var current: Dictionary = await _measure(seconds, warmup)
	_clear_characters()
	_build_gel_characters()
	var gel: Dictionary = await _measure(seconds, warmup)

	var stats: Dictionary = result(current.gpu_ms_p50, gel.gpu_ms_p50)
	stats["characters"] = CHARACTER_COUNT
	stats["current_draw_calls"] = current.draw_calls
	stats["gel_draw_calls"] = gel.draw_calls
	stats["current_primitives"] = current.primitives
	stats["gel_primitives"] = gel.primitives
	for line: String in summary_lines(stats):
		print(line)
	_finished = true
	if not bool(stats.within_budget):
		print("%s_FAIL delta %.3f ms exceeds %.3f ms" % [
			PREFIX, stats.delta_gpu_ms, GPU_BUDGET_MS,
		])
		quit(1)
		return
	print("%s_OK" % PREFIX)
	quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182230")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("9eb4ca")
	environment.environment.ambient_light_energy = 0.35
	root.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	fill.light_color = Color("b7d8ff")
	fill.light_energy = 0.45
	root.add_child(fill)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 5.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("526070")
	floor_material.roughness = 0.85
	floor.material_override = floor_material
	root.add_child(floor)

	_characters.name = "Characters"
	root.add_child(_characters)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 1.05, -5.7)
	camera.look_at(Vector3(0.0, 0.85, 0.0))
	camera.fov = 34.0
	camera.make_current()


func _build_current_characters() -> void:
	for index: int in CHARACTER_COUNT:
		var character := CURRENT_SCENE.instantiate() as Node3D
		character.position = _position_for(index)
		_characters.add_child(character)
		PlayerAppearance.enable_shadows(character)
		var animation: AnimationPlayer = PlayerAppearance.find_animation_player(character)
		_start_idle(animation, index)


func _build_gel_characters() -> void:
	for index: int in CHARACTER_COUNT:
		var character := GEL_SCENE.instantiate() as Node3D
		character.position = _position_for(index)
		_characters.add_child(character)
		PlayerAppearance.enable_shadows(character)
		PlayerAppearance.set_gel_material(character, false)
		PlayerAppearance.set_gel_look(
			character,
			[Color("58c9ff"), Color("ff7f92"), Color("ffd166"), Color("8de28b")][index],
			0.82,
			1.0
		)
		var shaper := GelBodyShaper.new()
		if not shaper.setup(character):
			push_error("Gel character %d has no proportion-ready rig" % index)
			_finished = true
			quit(3)
			return
		var proportions: GelBodyProportions = GelProportionPresets.load_preset(GEL_PRESETS[index])
		shaper.apply(proportions)
		var animation: AnimationPlayer = PlayerAppearance.find_animation_player(character)
		_start_idle(animation, index)


func _start_idle(animation: AnimationPlayer, index: int) -> void:
	if animation == null or not animation.has_animation(&"Idle"):
		return
	animation.play(&"Idle")
	animation.seek(float(index) * 0.17, true)


func _position_for(index: int) -> Vector3:
	return Vector3((float(index) - 1.5) * 1.15, 0.0, 0.0)


func _clear_characters() -> void:
	for child: Node in _characters.get_children():
		child.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw


func _measure(seconds: float, warmup: int) -> Dictionary:
	for _frame: int in warmup:
		_queue_gpu_timestamp("S311.37 warmup")
		await process_frame
		await RenderingServer.frame_post_draw
	var gpu_samples: Array[float] = []
	var draw_calls: float = 0.0
	var primitives: float = 0.0
	var start: int = Time.get_ticks_usec()
	while (Time.get_ticks_usec() - start) / 1000000.0 < seconds and not _finished:
		_queue_gpu_timestamp("S311.37 sample")
		await process_frame
		await RenderingServer.frame_post_draw
		var gpu_ms: float = await _captured_gpu_frame_ms()
		if gpu_ms > 0.0:
			gpu_samples.append(gpu_ms)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if gpu_samples.is_empty():
		push_error("RenderingServer returned no GPU timestamps; add --gpu-profile")
		_finished = true
		quit(4)
		return {}
	var count: float = float(gpu_samples.size())
	return {
		"gpu_ms_p50": percentile(gpu_samples, 0.5),
		"draw_calls": roundi(draw_calls / count),
		"primitives": roundi(primitives / count),
	}


func _queue_gpu_timestamp(label: String) -> void:
	RenderingServer.call_on_render_thread(_capture_gpu_timestamp.bind(label))


func _capture_gpu_timestamp(label: String) -> void:
	_device.capture_timestamp(label)


## Godot captures the beginning/end of a rendered frame together with the
## marker requested above. The distance between the first and last GPU clocks
## is the renderer's completed GPU work for that frame.
func _captured_gpu_frame_ms() -> float:
	_timestamp_read_ready = false
	_captured_gpu_ms = -1.0
	RenderingServer.call_on_render_thread(_read_gpu_frame_ms_on_render_thread)
	while not _timestamp_read_ready:
		await process_frame
	return _captured_gpu_ms


func _read_gpu_frame_ms_on_render_thread() -> void:
	var count: int = _device.get_captured_timestamps_count()
	if count < 2:
		_timestamp_read_ready = true
		return
	var first_ticks: int = _device.get_captured_timestamp_gpu_time(0)
	var last_ticks: int = _device.get_captured_timestamp_gpu_time(count - 1)
	# The RenderingDevice clock is nanoseconds on the Vulkan and D3D12 drivers.
	# Dividing by 1e6 matches the engine's own `GPU PROFILE total ... ms` line.
	_captured_gpu_ms = maxf(0.0, float(last_ticks - first_ticks) / 1000000.0)
	_timestamp_read_ready = true
