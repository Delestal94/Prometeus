extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/scene_loader/tests/test_scene_loader_gates.gd
##
## What keeps the scene_loader cover up, on the module alone (N-408): a node
## of the new scene in BUSY_GROUP holds it until it leaves the group, and the
## bar follows its loading_progress(); _scene_ready() holds it too; the
## reveal_paths are hidden at the swap and shown before the cover lifts;
## prefetch_paths are loaded and cached during LOADING; a carried
## AudioStreamPlayer moves under the loader at the swap instead of dying with
## the old scene; redirect_to() lands on another scene before the cover lifts.

const DIR: String = "user://test_scene_loader_gates"
const BUILD_FRAMES: int = 20
const BUILDER_SOURCE: String = """extends Node3D
var frames: int = 0
func _ready() -> void:
	add_to_group(&"scene_loader_busy")
func _process(_delta: float) -> void:
	frames += 1
	if frames >= %d:
		remove_from_group(&"scene_loader_busy")
func loading_progress() -> float:
	return minf(float(frames) / %d.0, 1.0)
"""

var _failures: int = 0


class GateLoader extends SceneLoader:
	var open: bool = false
	var max_build_target: float = 0.0

	func _scene_ready(_scene: Node) -> bool:
		return open

	func _show_progress(_ratio: float, current: Stage) -> void:
		if current == Stage.BUILDING:
			max_build_target = maxf(max_build_target, target_progress)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var builder_path: String = DIR + "/builder.gd"
	var file := FileAccess.open(builder_path, FileAccess.WRITE)
	file.store_string(BUILDER_SOURCE % [BUILD_FRAMES, BUILD_FRAMES])
	file.close()
	var level_path: String = _save_level(load(builder_path) as Script)
	var other_path: String = _save_plain("Other")
	var prefetch_path: String = _save_plain("Prefetched")

	var old := Node.new()
	old.name = "Old"
	root.add_child(old)
	current_scene = old
	var music := AudioStreamPlayer.new()
	music.name = "Music"
	var tone := AudioStreamWAV.new()
	var samples := PackedByteArray()
	samples.resize(8000)
	tone.data = samples
	tone.loop_mode = AudioStreamWAV.LOOP_FORWARD
	tone.loop_end = 4000
	music.stream = tone
	old.add_child(music)
	music.play()

	var loader := GateLoader.new()
	loader.fade_seconds = 0.0
	loader.minimum_seconds = 0.0
	loader.smooth_frame_seconds = 10.0
	loader.reveal_paths = [^"Hidden"]
	loader.prefetch_paths = PackedStringArray([prefetch_path])
	loader.carry_audio(music)
	loader.audio_fade_seconds = 0.2
	var finished: Array[bool] = [false]
	# Read inside the callback: the loader may be freed by the next frame.
	var build_target: Array[float] = [0.0]
	var music_playing_at_finish: Array[bool] = [false]
	loader.finished.connect(func() -> void:
		finished[0] = true
		build_target[0] = loader.max_build_target
		music_playing_at_finish[0] = is_instance_valid(music) and music.playing)
	SceneLoader.change_scene(self, level_path, loader)

	var prefetch_seen: bool = false
	var hidden_at_swap: int = -1
	var builder_frames_at_settle: int = -1
	var held_for_ready: bool = false
	var frames: int = 0
	while not finished[0] and frames < 2000:
		await process_frame
		frames += 1
		if not is_instance_valid(loader):
			break
		if loader.stage != SceneLoader.Stage.DONE and ResourceLoader.has_cached(prefetch_path):
			prefetch_seen = true
		var level: Node = current_scene
		if level != null and level.name == "Level":
			var hidden: Node3D = level.get_node(^"Hidden")
			if hidden_at_swap == -1:
				hidden_at_swap = 1 if not hidden.visible else 0
				_expect(music.get_parent() == loader, "The carried music moved under the loader at the swap")
			var builder: Node = level.get_node(^"Builder")
			if int(builder.get(&"frames")) >= BUILD_FRAMES + 5 and not loader.open:
				held_for_ready = loader.stage == SceneLoader.Stage.BUILDING
				loader.open = true
			if builder_frames_at_settle == -1 and loader.stage == SceneLoader.Stage.SETTLING:
				builder_frames_at_settle = int(builder.get(&"frames"))
	_expect(finished[0], "The swap finishes (%d frames)" % frames)
	_expect(prefetch_seen, "The prefetch path is loaded and kept cached while the cover is up")
	_expect(hidden_at_swap == 1, "A reveal path is hidden when the scene comes in")
	_expect(current_scene != null and (current_scene.get_node(^"Hidden") as Node3D).visible,
		"It is shown again before the cover lifts")
	_expect(held_for_ready, "_scene_ready() keeps the cover up after the builders are done")
	_expect(builder_frames_at_settle >= BUILD_FRAMES,
		"A BUSY_GROUP node holds the cover until it leaves the group (%d frames)" % builder_frames_at_settle)
	_expect(build_target[0] > 0.45 + 0.01,
		"The bar follows loading_progress() while building (%.2f)" % build_target[0])
	_expect(music_playing_at_finish[0], "The carried music is still playing when the cover lifts")
	frames = 0
	while is_instance_valid(loader) and frames < 600:
		await process_frame
		frames += 1
	_expect(not is_instance_valid(loader) and not is_instance_valid(music),
		"The loader goes, with the music it carried")

	# Redirect: too late to cancel, it lands on another scene instead.
	var redirected := SceneLoader.new()
	redirected.fade_seconds = 0.0
	redirected.minimum_seconds = 0.0
	redirected.smooth_frame_seconds = 10.0
	redirected.redirect_to(other_path)
	SceneLoader.change_scene(self, _save_plain("Detour"), redirected)
	frames = 0
	while is_instance_valid(redirected) and frames < 600:
		await process_frame
		frames += 1
	_expect(current_scene != null and current_scene.name == "Other", "redirect_to() lands on the other scene")

	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join(file_name))
	if _failures == 0:
		print("PASS: the cover waits for builders, readiness and reveals; carries music and redirects")
	quit(_failures)


func _save_level(builder_script: Script) -> String:
	var level := Node3D.new()
	level.name = "Level"
	var builder := Node3D.new()
	builder.name = "Builder"
	builder.set_script(builder_script)
	level.add_child(builder)
	builder.owner = level
	var hidden := Node3D.new()
	hidden.name = "Hidden"
	level.add_child(hidden)
	hidden.owner = level
	return _pack(level, "level")


func _save_plain(scene_name: String) -> String:
	var node := Node3D.new()
	node.name = scene_name
	return _pack(node, scene_name.to_lower())


func _pack(node: Node, file_stem: String) -> String:
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path: String = DIR + "/" + file_stem + ".tscn"
	ResourceSaver.save(packed, path)
	return path


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
