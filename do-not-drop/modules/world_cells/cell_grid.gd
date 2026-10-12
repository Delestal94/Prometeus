class_name WorldCellGrid
extends RefCounted
## Which cells of a square grid should be loaded, given where the anchors are
## (players or vehicles). Pure bookkeeping, no nodes: the streamer asks it what
## to load and unload and does the work.
##
## - A cell is wanted when it is within `load_radius` cells (Chebyshev) of any
##   anchor, and dropped only beyond `unload_radius` (the gap is the
##   hysteresis: standing on a border does not flap).
## - A cell never loads and unloads within `min_stay_sec` of each other, even
##   if an anchor teleports (the streamer would otherwise pay for the load
##   twice in a second).
## - Pinned cells are always wanted and never unloaded.
## - `impostor_radius` cells around the anchors that are not loaded get a
##   cheap stand-in.

## Side of a cell, in meters.
var cell_size: float = 256.0
var load_radius: int = 2
var unload_radius: int = 3
var impostor_radius: int = 5
## A cell stays loaded at least this long, and stays unloaded at least this long.
var min_stay_sec: float = 1.0

## Cells that are loaded (or being loaded): Vector2i -> second they were asked for.
var _loaded: Dictionary = {}
## Cells that were dropped: Vector2i -> second they were dropped.
var _dropped: Dictionary = {}
## Vector2i -> true. Always wanted.
var _pinned: Dictionary = {}


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


## Center of a cell on the XZ plane, at y = 0.
func center_of(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


func pin(cell: Vector2i) -> void:
	_pinned[cell] = true


func unpin(cell: Vector2i) -> void:
	_pinned.erase(cell)


func is_pinned(cell: Vector2i) -> bool:
	return _pinned.has(cell)


func is_loaded(cell: Vector2i) -> bool:
	return _loaded.has(cell)


func loaded_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _loaded:
		out.append(cell)
	return out


## Chebyshev distance, in cells, from `cell` to the closest anchor.
func distance_to_anchors(cell: Vector2i, anchors: Array[Vector3]) -> int:
	var best: int = 1 << 30
	for pos in anchors:
		var c := cell_of(pos)
		best = mini(best, maxi(absi(c.x - cell.x), absi(c.y - cell.y)))
	return best


## Decides the changes for this moment (`now_sec` is any monotonic clock).
## Returns {"load": [cells, closest first], "unload": [cells]} and counts
## them as done: the next call starts from the new set.
func update(anchors: Array[Vector3], now_sec: float) -> Dictionary:
	var to_load: Array[Vector2i] = []
	var to_unload: Array[Vector2i] = []
	var wanted: Dictionary = {}
	for pos in anchors:
		var c := cell_of(pos)
		for dx in range(-load_radius, load_radius + 1):
			for dz in range(-load_radius, load_radius + 1):
				wanted[Vector2i(c.x + dx, c.y + dz)] = true
	for cell: Vector2i in _pinned:
		wanted[cell] = true
	for cell: Vector2i in wanted:
		if _loaded.has(cell):
			continue
		var dropped_at: float = _dropped.get(cell, -1.0e9)
		if now_sec - dropped_at < min_stay_sec:
			continue
		to_load.append(cell)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return distance_to_anchors(a, anchors) < distance_to_anchors(b, anchors))
	for cell: Vector2i in _loaded:
		if _pinned.has(cell):
			continue
		if distance_to_anchors(cell, anchors) <= unload_radius:
			continue
		if now_sec - float(_loaded[cell]) < min_stay_sec:
			continue
		to_unload.append(cell)
	for cell in to_load:
		_loaded[cell] = now_sec
		_dropped.erase(cell)
	for cell in to_unload:
		_loaded.erase(cell)
		_dropped[cell] = now_sec
	# Old drop marks only matter for `min_stay_sec`.
	for cell: Vector2i in _dropped.keys():
		if now_sec - float(_dropped[cell]) >= min_stay_sec:
			_dropped.erase(cell)
	return {"load": to_load, "unload": to_unload}


## Cells that deserve a stand-in: inside `impostor_radius` of an anchor and not
## loaded (a loaded cell shows itself).
func impostor_cells(anchors: Array[Vector3]) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for pos in anchors:
		var c := cell_of(pos)
		for dx in range(-impostor_radius, impostor_radius + 1):
			for dz in range(-impostor_radius, impostor_radius + 1):
				var cell := Vector2i(c.x + dx, c.y + dz)
				if seen.has(cell) or _loaded.has(cell):
					continue
				seen[cell] = true
				out.append(cell)
	return out
