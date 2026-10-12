class_name WalkNavigation
extends RefCounted
## Walking navigation over the warehouse grid (expansion D-0908, "Modo Empresa").
##
## What the employees' pathfinding (F2, D-1011) asks: the way from a cell to another around the
## placed pieces. It is the same 4-neighbour grid as WalkReachability (D-0907), so "reachable"
## there and "has a path" here always agree. `rebake()` rebuilds it from the layout; BuildPlacement
## calls it after every placement, move, turn or sale, so a new piece changes the paths at once.
## It is a grid A* and not an engine NavigationMesh on purpose: it is deterministic, runs in
## headless tests and gives the same path on every peer. Nothing here names autoloads (N-919).

## Bumped on every rebake; a walker that cached a path compares it to know the path is stale.
var version: int = 0
var grid_size: Vector2i = Vector2i.ZERO

var _astar: AStarGrid2D = AStarGrid2D.new()


## Rebuilds the grid from `layout` ({id, x, z, turns} per piece), solid where a piece blocks walking.
func rebake(size: Vector2i, layout: Array) -> void:
	grid_size = size
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	for cell: Vector2i in WalkReachability.blocked_cells(layout):
		if _astar.is_in_boundsv(cell):
			_astar.set_point_solid(cell, true)
	version += 1


## True when people can step on `cell` (inside the floor and not under a blocking piece).
func is_walkable(cell: Vector2i) -> bool:
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


## Cells from `from` to `to`, both included. Empty when either is not walkable or none connects them.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_walkable(from) or not is_walkable(to):
		return out
	for cell: Vector2i in _astar.get_id_path(from, to):
		out.append(cell)
	return out


## Shortest path from `from` to a walkable cell that touches a side of `rect` (a station to work
## at), or to a cell of it when `rect` does not block walking. Empty when none is reachable.
func find_path_to_rect(from: Vector2i, rect: Rect2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for cell: Vector2i in _goal_cells(rect):
		var path: Array[Vector2i] = find_path(from, cell)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
			best = path
	return best


func _goal_cells(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(rect.position.x - 1, rect.end.x + 1):
		for z: int in range(rect.position.y - 1, rect.end.y + 1):
			var cell := Vector2i(x, z)
			var inside: bool = rect.has_point(cell)
			var corner: bool = (x < rect.position.x or x >= rect.end.x) \
					and (z < rect.position.y or z >= rect.end.y)
			if corner or (inside and not is_walkable(cell)):
				continue
			cells.append(cell)
	return cells
