extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_hair_springs.gd
## S-311.63: real spring-bone chains drive locks, pigtails and the braid.

const Library := preload("res://scripts/gameplay/player/gel/gel_hair_library.gd")
const Springs := preload("res://scripts/gameplay/player/gel/gel_hair_springs.gd")
const CASES: Array[Dictionary] = [
	{&"style": &"pigtails", &"chains": [&"pigtail_l", &"pigtail_r"], &"bones": 6},
	{&"style": &"braid", &"chains": [&"braid"], &"bones": 7},
	{&"style": &"long", &"chains": [&"lock_l", &"lock_r"], &"bones": 8},
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for test_case: Dictionary in CASES:
		await _check_style(test_case)
	var static_hair: Node3D = Library.build_hairstyle(&"afro")
	root.add_child(static_hair)
	var static_springs: Node = Springs.new()
	static_hair.add_child(static_springs)
	_expect(not static_springs.setup(static_hair), "static hair does not allocate a spring rig")
	static_hair.free()
	if _failures == 0:
		print("PASS: locks, pigtails and braid use native spring-bone chains")
	quit(_failures)


func _check_style(test_case: Dictionary) -> void:
	var style_id: StringName = test_case[&"style"]
	var hair: Node3D = Library.build_hairstyle(style_id)
	root.add_child(hair)
	var triangles_before: int = Library.triangle_count(hair)
	var springs: Node = Springs.new()
	hair.add_child(springs)
	_expect(springs.setup(hair), "%s builds its spring rig" % style_id)
	var chain_names: Array = test_case[&"chains"]
	_expect(springs.simulator_count() == chain_names.size(),
		"%s has one simulator per moving chain" % style_id)
	_expect(springs.skeleton() != null and springs.skeleton().get_bone_count() == int(test_case[&"bones"]),
		"%s has the expected spring-bone count" % style_id)
	for chain_name: StringName in chain_names:
		var simulator: SpringBoneSimulator3D = springs.simulator_for(chain_name)
		_expect(simulator != null and simulator.setting_count == 1,
			"%s/%s has one native spring setting" % [style_id, chain_name])
		if simulator != null:
			_expect(simulator.is_end_bone_extended(0), "%s/%s simulates its free tip" % [style_id, chain_name])
	springs.reset_motion()
	springs.advance_motion(Vector3.ZERO, 0.0, 0.1)
	springs.advance_motion(Vector3(5.0, 0.0, 0.4), 0.45, 0.1)
	for chain_name: StringName in chain_names:
		_expect(springs.simulator_for(chain_name).external_force.length() > 0.05,
			"%s/%s reacts to acceleration and turning" % [style_id, chain_name])
	for _frame: int in 3:
		await process_frame
	_expect(Library.triangle_count(hair) == triangles_before,
		"%s spring binding preserves its low-poly geometry" % style_id)
	hair.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
