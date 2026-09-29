extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_contract.gd
##
## S-802 data contract: every trap resource creates a bounded behavior with a
## useful hint, dedicated content, HUD icon, risk sound and progression entry;
## every content resource has the complete model states used by unboxing.

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const UiThemeScript = preload("res://scripts/ui/ui_theme.gd")
const SIMULATION_SECONDS: float = 30.0
const STEP: float = 1.0 / 60.0
const DIRECTIONS: Array[StringName] = [&"up", &"down", &"left", &"right"]

var _failures: int = 0
var _content_owners: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var definitions: Array[Resource] = _load_resources("res://data/traps")
	_expect(definitions.size() == 7, "The trap catalogue contains seven definitions (got %d)" % definitions.size())
	for definition: Resource in definitions:
		await _test_trap(definition)
	_test_contents(_load_resources("res://data/contents"))
	if _failures == 0:
		print("PASS: every trap and content resource satisfies the data contract")
	quit(_failures)


func _test_trap(definition: Resource) -> void:
	var trap_id: StringName = definition.get(&"id")
	var display_name: String = String(definition.get(&"display_name"))
	_expect(not trap_id.is_empty(), "Every trap has a stable id")
	_expect(not display_name.is_empty(), "%s has a display name" % trap_id)

	var behavior: Resource = definition.call(&"create_behavior")
	_expect(behavior != null, "%s creates its behavior" % trap_id)
	if behavior != null:
		behavior.call(&"on_setup", null, (definition.get(&"params") as Dictionary).duplicate(true))
		_expect(not String(behavior.call(&"get_hint")).is_empty(), "%s starts with a non-empty HUD hint" % trap_id)
		_simulate(definition, false)
		_simulate(definition, true)

	var icon: Texture2D = UiThemeScript.trap_icon(display_name)
	_expect(icon != null, "%s has a HUD icon" % trap_id)
	var contents: Array = definition.get(&"contents") as Array
	_expect(not contents.is_empty(), "%s declares at least one content resource" % trap_id)
	for content: Resource in contents:
		var content_id: StringName = content.get(&"id")
		_expect(not _content_owners.has(content_id), "%s content belongs to only one trap (already in %s)" % [
			content_id, _content_owners.get(content_id, &""),
		])
		_content_owners[content_id] = trap_id

	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	var trap_unlocks: Dictionary = unlocks.TRAP_UNLOCKS
	var is_starter: bool = not trap_unlocks.has(trap_id)
	var unlock_id: StringName = StringName(trap_unlocks.get(trap_id, &""))
	_expect(is_starter or unlocks.UNLOCKS.has(unlock_id),
		"%s is a starter trap or has a valid unlock rule" % trap_id)

	var package: RigidBody3D = PACKAGE_SCENE.instantiate()
	package.set(&"trap_definition", definition)
	package.freeze = true
	root.add_child(package)
	await process_frame
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var audio_players: int = 0
	for child: Node in feedback.get_children():
		if child is AudioStreamPlayer3D:
			audio_players += 1
	_expect(audio_players >= 2, "%s has a risk cue in addition to its ruin cue (got %d players)" % [
		trap_id, audio_players,
	])
	package.free()
	await process_frame


func _simulate(definition: Resource, random_input: bool) -> void:
	var trap_id: StringName = definition.get(&"id")
	var behavior: Resource = definition.call(&"create_behavior")
	var package := RigidBody3D.new()
	package.mass = 8.0
	package.freeze = true
	root.add_child(package)
	behavior.call(&"on_setup", package, (definition.get(&"params") as Dictionary).duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(trap_id)) + (802 if random_input else 0)
	var bounded: bool = true
	for frame: int in range(roundi(SIMULATION_SECONDS / STEP)):
		var input: Dictionary = {}
		if random_input:
			input = {
				"steady": rng.randf() < 0.45,
				"steady_strength": rng.randf_range(0.0, 1.5),
				"calm": rng.randf() < 0.45,
				"calm_strength": rng.randf_range(0.0, 1.5),
			}
			if frame % 12 == 0:
				input["direction_pressed"] = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
			if frame % 30 == 0:
				package.rotation_degrees.z = rng.randf_range(-42.0, 42.0)
				behavior.call(&"on_impact", rng.randf_range(0.0, 10.0))
		behavior.call(&"on_physics_process", package, STEP, {"input": input})
		var integrity: float = float(behavior.get(&"integrity"))
		var maximum: float = float(behavior.get(&"integrity_max"))
		if is_nan(integrity) or is_inf(integrity) or integrity < -0.001 or integrity > maximum + 0.001:
			bounded = false
			break
	_expect(bounded, "%s keeps integrity inside [0, max] for 30 simulated seconds with %s input" % [
		trap_id, "random" if random_input else "empty",
	])
	_expect(not String(behavior.call(&"get_hint")).is_empty(),
		"%s keeps a non-empty HUD hint after %s input" % [trap_id, "random" if random_input else "empty"])
	package.free()


func _test_contents(contents: Array[Resource]) -> void:
	_expect(contents.size() == 10, "The content catalogue contains ten definitions (got %d)" % contents.size())
	for content: Resource in contents:
		var content_id: StringName = content.get(&"id")
		_expect(not content_id.is_empty(), "Every content resource has a stable id")
		_expect(_content_owners.has(content_id), "%s is assigned to a trap" % content_id)
		for field: StringName in [&"display_name", &"declared_weight", &"handling"]:
			_expect(not String(content.get(field)).is_empty(), "%s has non-empty %s" % [content_id, field])
		var condition_texts: PackedStringArray = content.get(&"condition_texts")
		_expect(condition_texts.size() >= 3 and _all_non_empty(condition_texts),
			"%s describes intact, damaged and ruined states" % content_id)
		var model: PackedScene = content.get(&"model") as PackedScene
		_expect(model != null, "%s has a content model" % content_id)
		_expect(content.get(&"box_model") is PackedScene, "%s has a box model" % content_id)
		if model == null:
			continue
		var instance: Node = model.instantiate()
		for node_name: String in ["Filler", "Intact", "Damage", "Ruined"]:
			_expect(instance.get_node_or_null(NodePath(node_name)) != null,
				"%s model has %s" % [content_id, node_name])
		instance.free()


func _load_resources(directory: String) -> Array[Resource]:
	var resources: Array[Resource] = []
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	for file: String in files:
		if file.ends_with(".tres"):
			resources.append(load("%s/%s" % [directory, file]) as Resource)
	return resources


func _all_non_empty(values: PackedStringArray) -> bool:
	for value: String in values:
		if value.is_empty():
			return false
	return true


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
