extends SceneTree
## S-311.73: cape, dinosaur tail, bee antennae and mummy wraps use native spring chains.

const Library := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const Springs := preload("res://scripts/gameplay/player/gel/gel_costume_springs.gd")
const CASES: Array[Dictionary] = [
	{&"costume": &"superhero", &"chains": [&"hero_cape"], &"bones": 3},
	{&"costume": &"dinosaur", &"chains": [&"dino_tail"], &"bones": 4},
	{&"costume": &"bee", &"chains": [&"bee_antenna_l", &"bee_antenna_r"], &"bones": 6},
	{&"costume": &"mummy", &"chains": [&"mummy_wrap"], &"bones": 3},
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for test_case: Dictionary in CASES:
		await _check_costume(test_case)
	var static_costume: Node3D = Library.build_costume(&"courier")
	root.add_child(static_costume)
	var static_springs := Springs.new()
	static_costume.add_child(static_springs)
	_expect(not static_springs.setup(static_costume), "a static costume does not allocate a spring rig")
	static_costume.free()
	if _failures == 0:
		print("PASS: cape, tail, antennae and wraps use native spring-bone chains")
	quit(_failures)


func _check_costume(test_case: Dictionary) -> void:
	var costume_id: StringName = test_case[&"costume"]
	var costume: Node3D = Library.build_costume(costume_id)
	root.add_child(costume)
	var triangles_before: int = Library.triangle_count(costume)
	var springs := Springs.new()
	costume.add_child(springs)
	_expect(springs.setup(costume), "%s builds its spring rig" % costume_id)
	var chain_names: Array = test_case[&"chains"]
	_expect(springs.simulator_count() == chain_names.size(),
		"%s has one simulator per moving part" % costume_id)
	_expect(springs.skeleton() != null and springs.skeleton().get_bone_count() == int(test_case[&"bones"]),
		"%s has the expected spring-bone count" % costume_id)
	_expect(springs.skeleton() != null and springs.skeleton().name == "GelCostumeSkeleton",
		"%s exposes a costume-specific spring rig" % costume_id)
	for chain_name: StringName in chain_names:
		var simulator: SpringBoneSimulator3D = springs.simulator_for(chain_name)
		_expect(simulator != null and simulator.setting_count == 1,
			"%s/%s has one native spring setting" % [costume_id, chain_name])
		if simulator != null:
			_expect(simulator.is_end_bone_extended(0),
				"%s/%s simulates its free tip" % [costume_id, chain_name])
	springs.reset_motion()
	springs.advance_motion(Vector3.ZERO, 0.0, 0.1)
	springs.advance_motion(Vector3(5.0, 0.0, 0.4), 0.45, 0.1)
	for chain_name: StringName in chain_names:
		_expect(springs.simulator_for(chain_name).external_force.length() > 0.05,
			"%s/%s reacts to acceleration and turning" % [costume_id, chain_name])
	for _frame: int in 3:
		await process_frame
	_expect(Library.triangle_count(costume) == triangles_before,
		"%s spring binding preserves its low-poly geometry" % costume_id)
	costume.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
