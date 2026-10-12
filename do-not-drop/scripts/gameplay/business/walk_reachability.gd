class_name WalkReachability
extends RefCounted
## Walking paths over the warehouse grid (expansion D-0907, "Modo Empresa").
##
## Pure grid logic: floods the free cells from the entry areas (loading dock and customer exit,
## D-0906) and says which placed pieces can be reached by walking up to them. A piece that blocks
## walking is reached from any free cell that touches one of its sides; one that does not (the
## dispatch zone painted on the floor) is reached when a cell of it is. BuildPlacement uses it so
## a piece that would wall off a station, or cut the dock from the exit, is red (`blocks_path`).
## Same 4-neighbour grid the employees' navmesh bake will follow (D-0908). Nothing here names
## autoloads or UI classes (N-919).

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Cells (Vector2i -> true) that a piece of `layout` covers and stops people walking over.
static func blocked_cells(layout: Array) -> Dictionary:
	var blocked: Dictionary = {}
	for piece: Variant in layout:
		var def: PlaceableDefinition = _definition(piece)
		if def == null or not def.blocks_walking:
			continue
		var rect: Rect2i = _rect(piece, def)
		for x: int in range(rect.position.x, rect.end.x):
			for z: int in range(rect.position.y, rect.end.y):
				blocked[Vector2i(x, z)] = true
	return blocked


## Free cells (Vector2i -> true) reachable on foot from any cell of `entries` (Rect2i in grid cells).
static func reachable_cells(grid_size: Vector2i, layout: Array, entries: Array[Rect2i]) -> Dictionary:
	var blocked: Dictionary = blocked_cells(layout)
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for area: Rect2i in entries:
		for x: int in range(area.position.x, area.end.x):
			for z: int in range(area.position.y, area.end.y):
				var cell := Vector2i(x, z)
				if _free(cell, grid_size, blocked) and not seen.has(cell):
					seen[cell] = true
					queue.append(cell)
	var head: int = 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		for dir: Vector2i in DIRS:
			var next: Vector2i = here + dir
			if not seen.has(next) and _free(next, grid_size, blocked):
				seen[next] = true
				queue.append(next)
	return seen


## Indices of the pieces nobody can walk up to. Empty `entries` means no check: returns [].
static func unreachable_pieces(grid_size: Vector2i, layout: Array, entries: Array[Rect2i]) -> Array[int]:
	var out: Array[int] = []
	if entries.is_empty():
		return out
	var reached: Dictionary = reachable_cells(grid_size, layout, entries)
	for i: int in layout.size():
		var def: PlaceableDefinition = _definition(layout[i])
		if def == null:
			continue
		if not _touches(reached, _rect(layout[i], def), def.blocks_walking):
			out.append(i)
	return out


## Whether every entry area can walk to the first one (dock to exit). One area or none: true.
static func entries_connected(grid_size: Vector2i, layout: Array, entries: Array[Rect2i]) -> bool:
	if entries.size() < 2:
		return true
	var reached: Dictionary = reachable_cells(grid_size, layout, [entries[0]] as Array[Rect2i])
	for area: Rect2i in entries:
		if not _touches(reached, area, false):
			return false
	return true


## True when `layout` leaves the entries joined and every piece reachable (or there are no entries).
static func is_walkable(grid_size: Vector2i, layout: Array, entries: Array[Rect2i]) -> bool:
	return entries_connected(grid_size, layout, entries) \
			and unreachable_pieces(grid_size, layout, entries).is_empty()


static func _free(cell: Vector2i, grid_size: Vector2i, blocked: Dictionary) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y \
			and not blocked.has(cell)


## A blocking piece is reached by a reached cell one step outside its rect; others by a cell in it.
static func _touches(reached: Dictionary, rect: Rect2i, from_outside: bool) -> bool:
	var area: Rect2i = rect.grow(1) if from_outside else rect
	for x: int in range(area.position.x, area.end.x):
		for z: int in range(area.position.y, area.end.y):
			var cell := Vector2i(x, z)
			if not reached.has(cell):
				continue
			if from_outside and rect.has_point(cell):
				continue
			# grow(1) also holds the four corners, which are not a step away: skip them.
			if from_outside and not _is_side(rect, cell):
				continue
			return true
	return false


static func _is_side(rect: Rect2i, cell: Vector2i) -> bool:
	var inside_x: bool = cell.x >= rect.position.x and cell.x < rect.end.x
	var inside_z: bool = cell.y >= rect.position.y and cell.y < rect.end.y
	return inside_x or inside_z


static func _definition(piece: Variant) -> PlaceableDefinition:
	return PlaceableShop.definition(StringName(str(piece.get("id", ""))))


static func _rect(piece: Variant, def: PlaceableDefinition) -> Rect2i:
	return Rect2i(Vector2i(int(piece.get("x", 0)), int(piece.get("z", 0))),
			def.footprint_for(int(piece.get("turns", 0))))
