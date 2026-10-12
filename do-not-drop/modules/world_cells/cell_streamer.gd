class_name WorldCellStreamer
extends Node3D
## Keeps the cells of a big map loaded around moving anchors (WorldCellGrid
## decides which). A cell comes from one of two places, both handed in by the
## game:
## - `path_for.call(cell) -> String`: a scene file, loaded on a thread
##   (`ResourceLoader.load_threaded_request`);
## - `build_for.call(cell) -> Node3D`: built from data, used when `path_for`
##   gives "" (or isn't set). May return null for an empty cell.
## Whatever is ready is instanced and added in slices of `slice_msec` per
## frame, so crossing a border never costs one big frame. Cells that are not
## loaded but near get `impostor_for.call(cell) -> Node3D` (default: a flat
## one-piece block).
##
## A cell's content is authored in world coordinates (the streamer does not move it).
##
## Anchors are set by the game each frame (`anchors`). `step()` is what
## `_process` runs; a test calls it with its own clock.

signal cell_loaded(cell: Vector2i, node: Node3D)
signal cell_unloaded(cell: Vector2i)

var grid := WorldCellGrid.new()
## Where the anchors are now (players, vehicles), world positions.
var anchors: Array[Vector3] = []
var path_for: Callable
var build_for: Callable
var impostor_for: Callable
## Work budget per frame for instancing, in milliseconds.
var slice_msec: float = 4.0
## Seconds between two looks at the anchors (the cell of an anchor changes slowly).
var update_interval_sec: float = 0.25
var impostor_color: Color = Color(0.36, 0.42, 0.3)

var _last_update: float = -1.0e9
## cell -> loaded Node3D (null for an empty cell).
var _nodes: Dictionary = {}
## cell -> scene path being loaded on a thread.
var _threaded: Dictionary = {}
## Ready to instance: [{cell, scene or node}], closest first as asked.
var _ready_queue: Array = []
var _impostors: Dictionary = {}
## Longest single instancing step so far, microseconds (tests and tuning).
var longest_step_usec: int = 0


func _process(_delta: float) -> void:
	step(Time.get_ticks_msec() / 1000.0)


## One tick: look at the anchors if it is time, poll the threads, instance what
## is ready within the slice budget.
func step(now_sec: float) -> void:
	if now_sec - _last_update >= update_interval_sec:
		_last_update = now_sec
		_apply(grid.update(anchors, now_sec))
		_sync_impostors()
	_poll_threads()
	_instance_ready()


func is_loaded(cell: Vector2i) -> bool:
	return _nodes.has(cell)


## True while some cell is still waiting for its thread or its slice.
func is_busy() -> bool:
	return not _threaded.is_empty() or not _ready_queue.is_empty()


func loaded_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _nodes:
		out.append(cell)
	return out


func cell_node(cell: Vector2i) -> Node3D:
	return _nodes.get(cell)


func impostor_count() -> int:
	return _impostors.size()


func _apply(changes: Dictionary) -> void:
	for cell: Vector2i in changes["unload"]:
		_unload(cell)
	for cell: Vector2i in changes["load"]:
		_request(cell)


func _request(cell: Vector2i) -> void:
	var path: String = ""
	if path_for.is_valid():
		path = String(path_for.call(cell))
	if path != "":
		if ResourceLoader.load_threaded_request(path) == OK:
			_threaded[cell] = path
			return
		push_warning("WorldCellStreamer: cannot load %s" % path)
	_ready_queue.append({"cell": cell})


func _poll_threads() -> void:
	for cell: Vector2i in _threaded.keys():
		var path: String = _threaded[cell]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_threaded.erase(cell)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_ready_queue.append({"cell": cell, "scene": ResourceLoader.load_threaded_get(path)})
		else:
			push_warning("WorldCellStreamer: %s failed to load" % path)
			_ready_queue.append({"cell": cell})


func _instance_ready() -> void:
	var start := Time.get_ticks_usec()
	var budget := int(slice_msec * 1000.0)
	while not _ready_queue.is_empty():
		var item: Dictionary = _ready_queue.pop_front()
		var cell: Vector2i = item["cell"]
		if not grid.is_loaded(cell) or _nodes.has(cell):
			continue
		var t0 := Time.get_ticks_usec()
		var node: Node3D = _make_cell(cell, item.get("scene"))
		if node != null:
			add_child(node)
		_nodes[cell] = node
		_remove_impostor(cell)
		longest_step_usec = maxi(longest_step_usec, Time.get_ticks_usec() - t0)
		cell_loaded.emit(cell, node)
		if Time.get_ticks_usec() - start >= budget:
			break


func _make_cell(cell: Vector2i, scene: Variant) -> Node3D:
	if scene is PackedScene:
		return (scene as PackedScene).instantiate() as Node3D
	if build_for.is_valid():
		return build_for.call(cell) as Node3D
	return null


func _unload(cell: Vector2i) -> void:
	_threaded.erase(cell)
	var node: Node3D = _nodes.get(cell)
	_nodes.erase(cell)
	if node != null:
		remove_child(node)
		node.queue_free()
	cell_unloaded.emit(cell)


func _sync_impostors() -> void:
	var want: Dictionary = {}
	for cell in grid.impostor_cells(anchors):
		want[cell] = true
		if not _impostors.has(cell):
			_add_impostor(cell)
	for cell: Vector2i in _impostors.keys():
		if not want.has(cell):
			_remove_impostor(cell)


func _add_impostor(cell: Vector2i) -> void:
	var node: Node3D = null
	if impostor_for.is_valid():
		node = impostor_for.call(cell) as Node3D
	else:
		node = _default_impostor()
	if node == null:
		return
	node.position = grid.center_of(cell) + Vector3(0.0, -0.6, 0.0)
	add_child(node)
	_impostors[cell] = node


func _remove_impostor(cell: Vector2i) -> void:
	var node: Node3D = _impostors.get(cell)
	if node == null:
		return
	_impostors.erase(cell)
	remove_child(node)
	node.queue_free()


func _default_impostor() -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(grid.cell_size * 0.98, 1.0, grid.cell_size * 0.98)
	var material := StandardMaterial3D.new()
	material.albedo_color = impostor_color
	mesh.material = material
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return piece
