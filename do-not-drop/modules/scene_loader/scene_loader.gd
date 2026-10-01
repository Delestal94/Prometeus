class_name SceneLoader
extends CanvasLayer
## Swaps the current scene for another behind a cover. A bare
## change_scene_to_file() freezes the window on the old frame for as long as
## the new scene takes to load, build and draw its first frames, which reads
## as "the game hung". This loads the scene on a thread while the cover fades
## in and animates, builds it with the cover up, and only lifts the cover once
## the new scene has drawn a few frames (the first ones compile shaders and
## upload meshes: the hitch the player would otherwise see).
##
## Portable module (docs/modulos.md): the cover is a plain black rect here.
## The game extends this class and overrides _build_cover() and
## _show_progress() with its own look.
##
##   SceneLoader.change_scene(get_tree(), "res://levels/one.tscn")
##
## Lives under the root, not under the current scene, so it survives the
## swap; frees itself once the cover is gone.

signal stage_changed(stage: Stage)
## Emitted once the cover is gone (or the swap was cancelled or failed).
signal finished
## The scene could not be loaded; the old scene stays.
signal failed(path: String)

enum Stage { LOADING, BUILDING, SETTLING, DONE }

## The scene to change to. Set before the node enters the tree.
var target_path: String = ""
## Seconds the cover takes to fade in, and out.
var fade_seconds: float = 0.25
## The cover stays at least this long, so a fast load doesn't flash.
var minimum_seconds: float = 0.9
## Frames the new scene draws behind the cover before it lifts.
var settle_frames: int = 6
## Share of the bar the threaded load fills; building the scene and its
## first frames fill the rest.
var load_share: float = 0.7
## Off: load() on the main thread (the cover still hides the swap).
var use_threads: bool = true
## Over everything the scenes draw.
var cover_layer: int = 120

var stage: Stage = Stage.LOADING
## Where the bar is heading, 0..1; the drawn value eases toward it.
var target_progress: float = 0.0
var shown_progress: float = 0.0

var _cover: Control
var _fade_tween: Tween
var _started_msec: int = 0
var _cancelled: bool = false
var _threaded: bool = false


## Adds a loader for `path` under the root and returns it. Pass `loader` to
## use a configured instance (a subclass with the game's cover). Deferred:
## the caller may be a scene still in its own _ready().
static func change_scene(tree: SceneTree, path: String, loader: SceneLoader = null) -> SceneLoader:
	if loader == null:
		loader = SceneLoader.new()
	loader.target_path = path
	tree.root.add_child.call_deferred(loader)
	return loader


func _ready() -> void:
	name = "SceneLoader"
	if _cancelled:
		finished.emit()
		queue_free()
		return
	layer = cover_layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = Control.new()
	_cover.name = "Cover"
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.modulate.a = 0.0 if fade_seconds > 0.0 else 1.0
	add_child(_cover)
	_build_cover(_cover)
	_started_msec = Time.get_ticks_msec()
	_show_progress(0.0, stage)
	_run()


func _process(delta: float) -> void:
	shown_progress = lerpf(shown_progress, target_progress, 1.0 - exp(-delta * 9.0))
	if absf(target_progress - shown_progress) < 0.002:
		shown_progress = target_progress
	_show_progress(shown_progress, stage)


## Keys and buttons stay out of both scenes while the cover is up: the old
## one is on its way out and the new one isn't on screen yet.
func _input(_event: InputEvent) -> void:
	if stage != Stage.DONE:
		get_viewport().set_input_as_handled()


## Drops the swap if the scene isn't being built yet (a connection that fell
## through while the level loaded), even before the loader entered the tree.
## Returns false once it's too late.
func cancel() -> bool:
	if stage != Stage.LOADING or _cancelled:
		return false
	_cancelled = true
	if is_inside_tree():
		_close()
	return true


## The game's look, built into `cover`: already in the tree, filled to the
## screen and catching the mouse.
func _build_cover(cover: Control) -> void:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(rect)


## Called every frame with the eased value, and on every stage change.
func _show_progress(_ratio: float, _stage: Stage) -> void:
	pass


func elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _run() -> void:
	var tree: SceneTree = get_tree()
	# By id: the old scene is freed during the swap.
	var old_scene_id: int = tree.current_scene.get_instance_id() if tree.current_scene != null else 0
	_fade_to(1.0)
	var packed: PackedScene = await _load_packed()
	if _cancelled:
		return
	if packed == null:
		push_warning("[SceneLoader] Could not load " + target_path)
		failed.emit(target_path)
		_close()
		return
	if _fade_tween != null and _fade_tween.is_running():
		await _fade_tween.finished
	_set_stage(Stage.BUILDING, load_share + (1.0 - load_share) * 0.5)
	shown_progress = target_progress
	_show_progress(shown_progress, stage)
	# Two frames so the cover is on screen saying "building" before the swap
	# blocks this thread instancing the new scene.
	await tree.process_frame
	await tree.process_frame
	var error: Error = tree.change_scene_to_packed(packed)
	if error != OK:
		push_warning("[SceneLoader] Could not change to %s (error %d)" % [target_path, error])
		failed.emit(target_path)
		_close()
		return
	var waited: int = 0
	while _new_scene_pending(tree, old_scene_id) and waited < 300:
		await tree.process_frame
		waited += 1
	_set_stage(Stage.SETTLING, target_progress)
	var from: float = target_progress
	for frame: int in settle_frames:
		target_progress = lerpf(from, 0.97, float(frame + 1) / float(settle_frames))
		await tree.process_frame
	while elapsed_seconds() < minimum_seconds:
		await tree.process_frame
	_set_stage(Stage.DONE, 1.0)
	# Let the bar be seen full for a moment before the cover goes.
	var full_by: float = elapsed_seconds() + 0.25
	while shown_progress < 1.0 and elapsed_seconds() < full_by:
		await tree.process_frame
	_close()


func _new_scene_pending(tree: SceneTree, old_scene_id: int) -> bool:
	var scene: Node = tree.current_scene
	return scene == null or scene.get_instance_id() == old_scene_id or not scene.is_node_ready()


## The packed scene, through the threaded loader when it can be used; the
## bar follows its progress. null if the path doesn't load.
func _load_packed() -> PackedScene:
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		return null
	if use_threads:
		_threaded = ResourceLoader.load_threaded_request(target_path, "PackedScene") == OK
	if not _threaded:
		# One frame for the cover to show before the blocking load.
		await get_tree().process_frame
		return ResourceLoader.load(target_path, "PackedScene") as PackedScene
	var status_progress: Array = []
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			target_path, status_progress)
		if _cancelled:
			return null
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not status_progress.is_empty():
				target_progress = maxf(target_progress, float(status_progress[0]) * load_share)
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			target_progress = load_share
			return ResourceLoader.load_threaded_get(target_path) as PackedScene
		return null
	return null


func _set_stage(next: Stage, progress: float) -> void:
	stage = next
	target_progress = maxf(target_progress, progress)
	stage_changed.emit(stage)
	_show_progress(shown_progress, stage)


func _fade_to(alpha: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = null
	if _cover == null:
		return
	if fade_seconds <= 0.0:
		_cover.modulate.a = alpha
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_cover, "modulate:a", alpha, fade_seconds)


func _close() -> void:
	stage = Stage.DONE
	_fade_to(0.0)
	if _fade_tween != null:
		await _fade_tween.finished
	finished.emit()
	queue_free()
