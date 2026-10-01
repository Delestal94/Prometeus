class_name SceneLoader
extends CanvasLayer
## Swaps the current scene for another behind a cover that never freezes and
## never lifts early. A bare change_scene_to_file() stops the window on the
## old frame for as long as the new scene takes to load, build and draw its
## first frames, which reads as "the game hung". This:
##   1. LOADING: fades the cover in and loads the scene on a thread, along
##      with any prefetch_paths (kept referenced so the scene's own load()
##      calls find them cached) and the game's _start_warm() work.
##   2. BUILDING: swaps the scene in with the reveal_paths hidden, then waits
##      for every node in BUSY_GROUP to finish (a scene that builds itself
##      over several frames) and for _scene_ready() (the game: "my player is
##      in"); the bar follows their loading_progress().
##   3. SETTLING: shows the reveal_paths one per frame (each one's first draw
##      compiles its shaders in its own frame, not all in one) and waits for
##      smooth_frames frames in a row under smooth_frame_seconds.
##   4. DONE: the bar is drawn full, the cover fades out, the carried music
##      fades out under the new scene, and the loader frees itself.
## Audio runs on its own thread: carry_audio() keeps the old scene's music
## playing across the swap instead of dying with the old scene.
##
## Portable module (docs/modulos.md): the cover is a plain black rect here.
## The game extends this class and overrides _build_cover(), _show_progress()
## and optionally _start_warm(), _warm_done() and _scene_ready().
##
##   SceneLoader.change_scene(get_tree(), "res://levels/one.tscn")
##
## Lives under the root, not under the current scene, so it survives the
## swap.

signal stage_changed(stage: Stage)
## Emitted once the cover is gone (or the swap was cancelled or failed).
signal finished
## The scene could not be loaded; the old scene stays.
signal failed(path: String)

enum Stage { LOADING, BUILDING, SETTLING, DONE }

## A node of the new scene in this group holds the cover up until it leaves
## the group: a scene that builds itself over several frames joins it in
## _ready() and leaves when it's done. It may define loading_progress()
## -> float (0..1) and the bar follows it while the scene builds.
const BUSY_GROUP: StringName = &"scene_loader_busy"

## The scene to change to. Set before the node enters the tree.
var target_path: String = ""
## Loaded on threads alongside the scene and kept referenced until the
## loader goes, so the new scene's own load() calls hit the cache.
var prefetch_paths: PackedStringArray = PackedStringArray()
## Nodes of the new scene (paths from its root) hidden before its first draw
## and shown one per frame while settling.
var reveal_paths: Array[NodePath] = []
## Seconds the cover takes to fade in, and out.
var fade_seconds: float = 0.25
## The cover stays at least this long, so a fast load doesn't flash.
var minimum_seconds: float = 0.9
## Frames the new scene draws behind the cover at least, once it's built.
var settle_frames: int = 6
## The cover lifts after this many smooth frames in a row...
var smooth_frames: int = 8
## ...each one shorter than this.
var smooth_frame_seconds: float = 0.05
## Give up waiting for smooth frames after this long (a slow machine).
var max_settle_seconds: float = 5.0
## Give up waiting for the scene to build after this long, so a stuck
## scene can never trap the player behind the cover.
var max_build_seconds: float = 120.0
## Share of the bar the threaded load fills...
var load_share: float = 0.45
## ...and the share building the scene fills after it; settling, the rest.
var build_share: float = 0.4
## Off: load() on the main thread (the cover still hides the swap).
var use_threads: bool = true
## Seconds the carried music takes to fade under the new scene.
var audio_fade_seconds: float = 2.5
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
var _redirect_path: String = ""
var _carried: Array[AudioStreamPlayer] = []
var _prefetched: Array[Resource] = []
var _prefetch_pending: PackedStringArray = PackedStringArray()


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
	if absf(target_progress - shown_progress) < 0.004:
		shown_progress = target_progress
	_show_progress(shown_progress, stage)


## Keys and buttons stay out of both scenes while the cover is up: the old
## one is on its way out and the new one isn't on screen yet.
func _input(_event: InputEvent) -> void:
	if stage != Stage.DONE:
		get_viewport().set_input_as_handled()


## Drops the swap if the scene isn't being built yet (a connection that fell
## through while the level loaded), even before the loader entered the tree.
## Returns false once it's too late: use redirect_to() then.
func cancel() -> bool:
	if stage != Stage.LOADING or _cancelled:
		return false
	_cancelled = true
	if is_inside_tree():
		_close()
	return true


## Too late to cancel: once the new scene is in, change again to `path`
## (the menu, say) before the cover lifts, so nobody lands in a scene that
## no longer makes sense.
func redirect_to(path: String) -> void:
	_redirect_path = path


## Keeps `player` playing across the swap (it moves under the loader right
## before the old scene goes) and fades it out under the new scene.
func carry_audio(player: AudioStreamPlayer) -> void:
	if player != null and not _carried.has(player):
		_carried.append(player)


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


## Starts the game's own preparation (sounds on a worker thread...) while the
## scene loads. _warm_done() is polled every frame; the swap waits for it.
func _start_warm() -> void:
	pass


func _warm_done() -> bool:
	return true


## The game's last word on "ready to show", polled while building (its
## player spawned, say). BUSY_GROUP is checked on top of this.
func _scene_ready(_scene: Node) -> bool:
	return true


func elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _run() -> void:
	var tree: SceneTree = get_tree()
	# By id: the old scene is freed during the swap.
	var old_scene_id: int = tree.current_scene.get_instance_id() if tree.current_scene != null else 0
	_fade_to(1.0)
	_start_prefetch()
	_start_warm()
	var packed: PackedScene = await _load_packed()
	if _cancelled:
		return
	if packed == null:
		push_warning("[SceneLoader] Could not load " + target_path)
		failed.emit(target_path)
		_close()
		return
	while not (_prefetch_finished() and _warm_done()):
		if _cancelled:
			return
		await tree.process_frame
	if _cancelled:
		return
	if _fade_tween != null and _fade_tween.is_running():
		await _fade_tween.finished
	_set_stage(Stage.BUILDING, load_share)
	shown_progress = target_progress
	_show_progress(shown_progress, stage)
	# Two frames so the cover is on screen saying "building" before the swap
	# instances the new scene.
	await tree.process_frame
	await tree.process_frame
	_adopt_carried_audio()
	var scene: Node = packed.instantiate()
	var hidden: Array[Node] = _hide_reveals(scene)
	var error: Error = tree.change_scene_to_node(scene)
	if error != OK:
		push_warning("[SceneLoader] Could not change to %s (error %d)" % [target_path, error])
		scene.free()
		failed.emit(target_path)
		_close()
		return
	await _wait_until_built(tree, old_scene_id)
	if not _redirect_path.is_empty():
		await _follow_redirect(tree)
		hidden.clear()
	_set_stage(Stage.SETTLING, load_share + build_share)
	await _settle(tree, hidden)
	while elapsed_seconds() < minimum_seconds:
		await tree.process_frame
	_set_stage(Stage.DONE, 1.0)
	# The bar is seen full before the cover goes.
	var full_by: float = elapsed_seconds() + 0.6
	while shown_progress < 1.0 and elapsed_seconds() < full_by:
		await tree.process_frame
	shown_progress = 1.0
	_show_progress(1.0, stage)
	await tree.process_frame
	_close()


## Waits for the scene to be in, every BUSY_GROUP node done and the game's
## _scene_ready(); the bar follows the builders' progress.
func _wait_until_built(tree: SceneTree, old_scene_id: int) -> void:
	var waited: int = 0
	while _new_scene_pending(tree, old_scene_id) and waited < 300:
		await tree.process_frame
		waited += 1
	var give_up: float = elapsed_seconds() + max_build_seconds
	while elapsed_seconds() < give_up:
		var busy: Array[Node] = tree.get_nodes_in_group(BUSY_GROUP)
		if busy.is_empty() and _scene_ready(tree.current_scene):
			break
		target_progress = maxf(target_progress, load_share + build_share * _build_progress(busy))
		await tree.process_frame
	if elapsed_seconds() >= give_up:
		push_warning("[SceneLoader] %s still building after %.0f s; lifting the cover"
			% [target_path, max_build_seconds])
	target_progress = maxf(target_progress, load_share + build_share)


## Mean loading_progress() of the builders that report one; 0.5 otherwise.
func _build_progress(busy: Array[Node]) -> float:
	if busy.is_empty():
		return 1.0
	var total: float = 0.0
	for node: Node in busy:
		var part: float = float(node.call(&"loading_progress")) if node.has_method(&"loading_progress") else 0.5
		total += clampf(part, 0.0, 1.0)
	return total / float(busy.size())


func _follow_redirect(tree: SceneTree) -> void:
	var redirect_id: int = tree.current_scene.get_instance_id() if tree.current_scene != null else 0
	if tree.change_scene_to_file(_redirect_path) != OK:
		push_warning("[SceneLoader] Could not redirect to " + _redirect_path)
		return
	var waited: int = 0
	while _new_scene_pending(tree, redirect_id) and waited < 300:
		await tree.process_frame
		waited += 1


## Shows the hidden nodes one per frame, then waits for the frames to run
## smooth (or max_settle_seconds); settle_frames frames at least. A node that
## has `reveal_steps() -> Array[Callable]` splits its own first draw over
## several frames (one callable per frame, the first one shows the node itself).
func _settle(tree: SceneTree, hidden: Array[Node]) -> void:
	var from: float = target_progress
	var reveals: Array[Callable] = []
	for node: Node in hidden:
		if not is_instance_valid(node):
			continue
		if node.has_method(&"reveal_steps"):
			reveals.append_array(node.call(&"reveal_steps"))
		else:
			reveals.append(func() -> void:
				if is_instance_valid(node):
					node.set(&"visible", true))
	var steps: int = reveals.size() + maxi(settle_frames, smooth_frames)
	var step: int = 0
	for reveal: Callable in reveals:
		reveal.call()
		step += 1
		target_progress = lerpf(from, 0.98, float(step) / float(steps))
		await tree.process_frame
	var smooth: int = 0
	var frames: int = 0
	var last_usec: int = Time.get_ticks_usec()
	var give_up: float = elapsed_seconds() + max_settle_seconds
	while (smooth < smooth_frames or frames < settle_frames) and elapsed_seconds() < give_up:
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		smooth = smooth + 1 if float(now - last_usec) / 1000000.0 < smooth_frame_seconds else 0
		last_usec = now
		frames += 1
		step = mini(step + 1, steps)
		target_progress = maxf(target_progress, lerpf(from, 0.98, float(step) / float(steps)))


func _new_scene_pending(tree: SceneTree, old_scene_id: int) -> bool:
	var scene: Node = tree.current_scene
	return scene == null or scene.get_instance_id() == old_scene_id or not scene.is_node_ready()


func _hide_reveals(scene: Node) -> Array[Node]:
	var hidden: Array[Node] = []
	for path: NodePath in reveal_paths:
		var node: Node = scene.get_node_or_null(path)
		if node != null and (node is Node3D or node is CanvasItem) and bool(node.get(&"visible")):
			node.set(&"visible", false)
			hidden.append(node)
	return hidden


## Moves the carried players under the loader, picking up where they were:
## a player that leaves the tree stops.
func _adopt_carried_audio() -> void:
	for player: AudioStreamPlayer in _carried:
		if not is_instance_valid(player):
			continue
		var position: float = player.get_playback_position() if player.playing else 0.0
		var was_playing: bool = player.playing
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.reparent(self)
		if was_playing:
			player.play(position)


func _start_prefetch() -> void:
	if not use_threads:
		return
	for path: String in prefetch_paths:
		if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_prefetch_pending.append(path)


## Collects what finished; true once nothing is pending.
func _prefetch_finished() -> bool:
	var still: PackedStringArray = PackedStringArray()
	for path: String in _prefetch_pending:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(path)
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource: Resource = ResourceLoader.load_threaded_get(path)
			if resource != null:
				_prefetched.append(resource)
	_prefetch_pending = still
	return _prefetch_pending.is_empty()


## The packed scene, through the threaded loader when it can be used; the
## bar follows its progress (and the prefetch's). null if it doesn't load.
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
	var prefetch_total: int = maxi(_prefetch_pending.size(), 1)
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			target_path, status_progress)
		if _cancelled:
			return null
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var scene_part: float = float(status_progress[0]) if not status_progress.is_empty() else 0.0
			_prefetch_finished()
			var prefetch_part: float = 1.0 - float(_prefetch_pending.size()) / float(prefetch_total)
			target_progress = maxf(target_progress, (scene_part * 0.7 + prefetch_part * 0.3) * load_share)
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
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
	var music_fade: Tween = _fade_carried_audio()
	if _fade_tween != null:
		await _fade_tween.finished
	if _cover != null:
		_cover.visible = false
	finished.emit()
	if music_fade != null and music_fade.is_running():
		await music_fade.finished
	queue_free()


func _fade_carried_audio() -> Tween:
	var playing: Array[AudioStreamPlayer] = []
	for player: AudioStreamPlayer in _carried:
		if is_instance_valid(player) and player.get_parent() == self and player.playing:
			playing.append(player)
	if playing.is_empty() or audio_fade_seconds <= 0.0:
		return null
	var tween: Tween = create_tween().set_parallel(true)
	for player: AudioStreamPlayer in playing:
		tween.tween_property(player, "volume_db", -60.0, audio_fade_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return tween
