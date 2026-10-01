extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/scene_loader/tests/test_scene_loader.gd
##
## The scene_loader module on its own (docs/modulos.md): change_scene() swaps
## the current scene for a saved one behind a cover that is up before the
## swap and lifts only after the new scene drew settle_frames frames; the bar
## only goes up and ends full; the stages arrive in order; input is swallowed
## while the cover is up; the loader frees itself. A path that doesn't load
## leaves the old scene, emits failed and closes; cancel() during the load
## leaves the old scene too, and is refused once the scene is being built.

const DIR: String = "user://test_scene_loader"

var _failures: int = 0


class RecordingLoader extends SceneLoader:
	var ratios: Array[float] = []
	var stages: Array[int] = []

	func _build_cover(cover: Control) -> void:
		var mark := Control.new()
		mark.name = "RecordingMark"
		cover.add_child(mark)

	func _show_progress(ratio: float, current: Stage) -> void:
		ratios.append(ratio)
		if stages.is_empty() or stages.back() != int(current):
			stages.append(int(current))


class InputSpy extends Node:
	var seen: int = 0

	func _unhandled_input(_event: InputEvent) -> void:
		seen += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var target_path: String = _save_scene("Target")
	var old := Node.new()
	old.name = "Old"
	root.add_child(old)
	current_scene = old
	var spy := InputSpy.new()
	old.add_child(spy)

	var loader := RecordingLoader.new()
	loader.minimum_seconds = 0.2
	loader.fade_seconds = 0.05
	loader.settle_frames = 4
	var finished: Array[bool] = [false]
	loader.finished.connect(func() -> void: finished[0] = true)
	_expect(SceneLoader.change_scene(self, target_path, loader) == loader, "change_scene() returns the loader it uses")
	await process_frame
	_expect(loader.is_inside_tree() and loader.get_parent() == root, "The loader lives under the root, not the scene")
	var cover: Control = loader.get_node_or_null(^"Cover")
	_expect(cover != null and cover.get_node_or_null(^"RecordingMark") != null
			and cover.mouse_filter == Control.MOUSE_FILTER_STOP
			and cover.anchor_right == 1.0 and cover.anchor_bottom == 1.0,
		"The game's cover is used, filled to the screen and catching the mouse")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key)
	_expect(spy.seen == 0, "Input is swallowed while the cover is up")
	# The loader frees itself the frame it emits finished: keep its records.
	var ratios: Array[float] = loader.ratios
	var stages: Array[int] = loader.stages

	var frames_after_swap: int = -1
	var cover_alpha_at_swap: float = -1.0
	var frames: int = 0
	while not finished[0] and frames < 600:
		await process_frame
		frames += 1
		if frames_after_swap < 0 and current_scene != null and current_scene.name == "Target":
			frames_after_swap = 0
			cover_alpha_at_swap = cover.modulate.a if is_instance_valid(cover) else -1.0
		elif frames_after_swap >= 0 and is_instance_valid(loader) and loader.stage != SceneLoader.Stage.DONE:
			frames_after_swap += 1
	_expect(finished[0], "The swap finishes (took %d frames)" % frames)
	_expect(current_scene != null and current_scene.name == "Target", "The saved scene is the current one")
	_expect(not is_instance_valid(old), "The old scene is gone")
	_expect(is_equal_approx(cover_alpha_at_swap, 1.0),
		"The cover was fully up when the scene swapped (alpha %.2f)" % cover_alpha_at_swap)
	_expect(frames_after_swap >= 4, "The new scene drew settle_frames frames behind the cover (%d)" % frames_after_swap)
	var rising: bool = true
	for index: int in range(1, ratios.size()):
		rising = rising and ratios[index] >= ratios[index - 1] - 0.0001
	_expect(rising and not ratios.is_empty() and ratios.back() > 0.95,
		"The bar only goes up and ends full (last %.3f)" % (-1.0 if ratios.is_empty() else ratios.back()))
	var in_order: Array[int] = [SceneLoader.Stage.LOADING, SceneLoader.Stage.BUILDING,
		SceneLoader.Stage.SETTLING, SceneLoader.Stage.DONE]
	_expect(stages == in_order,
		"The stages arrive in order (got %s)" % [stages])
	await process_frame
	_expect(not is_instance_valid(loader), "The loader frees itself")

	# A path that doesn't load: the old scene stays and failed is emitted.
	var stay: Node = current_scene
	var broken := SceneLoader.new()
	broken.fade_seconds = 0.0
	var failed_path: Array[String] = [""]
	broken.failed.connect(func(path: String) -> void: failed_path[0] = path)
	SceneLoader.change_scene(self, DIR + "/missing.tscn", broken)
	for frame: int in 10:
		await process_frame
	_expect(failed_path[0].ends_with("missing.tscn") and current_scene == stay and not is_instance_valid(broken),
		"A missing scene emits failed, keeps the old one and closes")

	# Cancelled before it starts (a connection that failed the same frame):
	# the old scene stays; too late once building.
	var other_path: String = _save_scene("Other")
	var dropped := SceneLoader.new()
	dropped.fade_seconds = 0.0
	SceneLoader.change_scene(self, other_path, dropped)
	_expect(dropped.cancel(), "cancel() is accepted while loading")
	_expect(not dropped.cancel(), "cancel() twice is refused")
	for frame: int in 30:
		await process_frame
	_expect(current_scene == stay and not is_instance_valid(dropped), "A cancelled swap keeps the old scene")
	var late := SceneLoader.new()
	late.fade_seconds = 0.0
	late.minimum_seconds = 0.0
	late.stage_changed.connect(func(stage: SceneLoader.Stage) -> void:
		if stage == SceneLoader.Stage.BUILDING:
			_expect(not late.cancel(), "cancel() is refused once the scene is being built"))
	SceneLoader.change_scene(self, other_path, late)
	for frame: int in 60:
		await process_frame
	_expect(current_scene != null and current_scene.name == "Other", "That swap still lands")

	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join(file_name))
	if _failures == 0:
		print("PASS: scenes swap behind a cover on the module alone")
	quit(_failures)


func _save_scene(scene_name: String) -> String:
	var node := Node3D.new()
	node.name = scene_name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path: String = DIR + "/" + scene_name.to_lower() + ".tscn"
	ResourceSaver.save(packed, path)
	return path


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
