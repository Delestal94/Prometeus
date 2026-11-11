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
## - Pinned cells are always wanted and never unloaded, but far ones are
##   parked: past the same radii a normal cell would load and unload at, a
##   pinned cell stays loaded (its collision and nodes are still there) and the
##   streamer stops drawing it. `update` says which cells park and wake.
## - `impostor_radius` cells around the anchors that are not loaded, or are
##   parked, get a cheap stand-in.

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
## Pinned cells an anchor came within `load_radius` of and has not left past `unload_radius`.
var _near: Dictionary = {}
## Vector2i -> true. Pinned, loaded and not to be drawn.
var _parked: Dictionary = {}


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


## Center of a cell on the XZ plane, at y = 0.
func center_of(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


func pin(cell: Vector2i) -> void:
	_pinned[cell] = true


func unpin(cell: Vector2i) -> void:
	_pinned.erase(cell)
	_near.erase(cell)


func is_pinned(cell: Vector2i) -> bool:
	return _pinned.has(cell)


func is_loaded(cell: Vector2i) -> bool:
	return _loaded.has(cell)


## True while `cell` is pinned and no anchor is near it: there, but not drawn.
func is_parked(cell: Vector2i) -> bool:
	return _parked.has(cell)


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
## Returns {"load": [cells, closest first], "unload": [cells], "park": [cells],
## "wake": [cells]} and counts them as done: the next call starts from the new set.
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
	var parking: Dictionary = _update_parked(anchors)
	return {"load": to_load, "unload": to_unload, "park": parking.park, "wake": parking.wake}


## Cells that deserve a stand-in: inside `impostor_radius` of an anchor and not
## showing themselves, because they are not loaded or are parked.
func impostor_cells(anchors: Array[Vector3]) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for pos in anchors:
		var c := cell_of(pos)
		for dx in range(-impostor_radius, impostor_radius + 1):
			for dz in range(-impostor_radius, impostor_radius + 1):
				var cell := Vector2i(c.x + dx, c.y + dz)
				if seen.has(cell) or (_loaded.has(cell) and not _parked.has(cell)):
					continue
				seen[cell] = true
				out.append(cell)
	return out


## Which pinned cells stop or start being drawn. With no anchors nobody says where the view is, so nothing changes.
func _update_parked(anchors: Array[Vector3]) -> Dictionary:
	var park: Array[Vector2i] = []
	var wake: Array[Vector2i] = []
	for cell: Vector2i in _parked.keys():
		if not _pinned.has(cell):
			_parked.erase(cell)
			wake.append(cell)
	if anchors.is_empty():
		return {"park": park, "wake": wake}
	for cell: Vector2i in _pinned:
		var gap: int = distance_to_anchors(cell, anchors)
		if gap <= load_radius:
			_near[cell] = true
		elif gap > unload_radius:
			_near.erase(cell)
		if _near.has(cell) and _parked.has(cell):
			_parked.erase(cell)
			wake.append(cell)
		elif not _near.has(cell) and not _parked.has(cell):
			_parked[cell] = true
			park.append(cell)
	return {"park": park, "wake": wake}
