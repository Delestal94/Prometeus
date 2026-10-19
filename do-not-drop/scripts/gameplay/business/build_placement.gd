class_name BuildPlacement
extends RefCounted
## Checks and commits the placement of a warehouse object (expansion D-0902, "Modo Empresa").
##
## Pure logic over the grid of BuildMode: `preview()` says whether an object fits at a cell with a
## given rotation (green) or not (red, with the reason), and `place()` buys it through PlaceableShop
## only when the preview is green. `rotate_piece()`, `move_piece()` and `sell_piece()` (D-0903)
## act on a piece already in the layout: the same checks, ignoring the piece itself.
## A piece that would wall off a station or cut the dock from the exit is red too (D-0907).
## A stage holds at most `max_pieces` pieces (D-0915): one more is red with `piece_limit`.
## The employees' walking grid follows every change that sticks (`navigation`, D-0908).
## `undo_last_placement()` (D-0916) takes back the last piece bought here, with a full refund.
## The world adapter draws the footprint with `preview_color()`.
## Fixed areas that can never be covered (loading dock, exit: D-0906) arrive as `fixed_blocked`
## rectangles in grid cells. Nothing here names autoloads or UI classes (N-919).

const REASON_OK: StringName = &""
const REASON_OUT_OF_BOUNDS: StringName = &"out_of_bounds"
const REASON_OVERLAP: StringName = &"overlap"
const REASON_FIXED: StringName = &"fixed_area"
const REASON_NO_DEFINITION: StringName = &"no_definition"
const REASON_NO_MONEY: StringName = &"no_money"
const REASON_BLOCKS_PATH: StringName = &"blocks_path"
const REASON_PIECE_LIMIT: StringName = &"piece_limit"

const REASON_UNDO: StringName = &"placeable_undo"
## How many placements can be taken back, newest first.
const UNDO_DEPTH: int = 8

const COLOR_OK: Color = Color(0.2, 0.85, 0.3, 0.55)
const COLOR_BAD: Color = Color(0.9, 0.2, 0.2, 0.55)

## Floor in grid cells (X x Z), as BuildMode.grid_size.
var grid_size: Vector2i = Vector2i(12, 8)
## Cells that no object may cover, as Rect2i in grid cells.
var fixed_blocked: Array[Rect2i] = []
## Areas people walk in from (loading dock, exit; D-0907). A piece that would leave one of them
## cut off from the others, or wall off a placed piece, is red. Empty: no walking check.
var entry_areas: Array[Rect2i] = []
## Most pieces the layout may hold (D-0915). 0: no limit. Moving, turning or selling never
## counts against it; only adding a piece does.
var max_pieces: int = 0
## Walking navigation to keep in step with the layout (D-0908): rebaked after every change that
## sticks. Null: nothing to rebake.
var navigation: WalkNavigation = null
## Pieces placed by `place()` (the layout entries themselves), oldest first, for the undo.
var _placed: Array = []


func _init(size: Vector2i = Vector2i(12, 8)) -> void:
	grid_size = size


## Rect of cells the object would cover with its corner at (x, z) after `turns` quarter turns.
func footprint_rect(def: PlaceableDefinition, x: int, z: int, turns: int) -> Rect2i:
	return Rect2i(Vector2i(x, z), def.footprint_for(turns))


## Result for putting `def` at (x, z): {ok: bool, reason: StringName, rect: Rect2i}.
## `layout` is the CompanyState.layout array ({id, x, z, turns} per piece); `money` < 0 skips
## the wallet check (the preview only needs the grid; place() always checks it).
func preview(layout: Array, def: PlaceableDefinition, x: int, z: int, turns: int = 0,
		money: int = -1, ignore_index: int = -1) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": REASON_NO_DEFINITION, "rect": Rect2i()}
	var rect: Rect2i = footprint_rect(def, x, z, turns)
	var reason: StringName = _reason_for(layout, rect, ignore_index)
	if reason == REASON_OK and ignore_index < 0 and max_pieces > 0 and layout.size() >= max_pieces:
		reason = REASON_PIECE_LIMIT
	if reason == REASON_OK and not _keeps_paths(layout, def, x, z, turns, ignore_index):
		reason = REASON_BLOCKS_PATH
	if reason == REASON_OK and money >= 0 and money < def.price:
		reason = REASON_NO_MONEY
	return {"ok": reason == REASON_OK, "reason": reason, "rect": rect}


func preview_color(result: Dictionary) -> Color:
	return COLOR_OK if bool(result.get("ok", false)) else COLOR_BAD


## Buys and places the object when the preview is green. Returns the preview result with
## `ok = false` and its reason when something stops it; nothing changes then.
func place(state: Object, def: PlaceableDefinition, x: int, z: int, turns: int = 0,
		free: bool = false) -> Dictionary:
	var money: int = -1 if free else int(state.money)
	var result: Dictionary = preview(state.layout, def, x, z, turns, money)
	if not bool(result["ok"]):
		return result
	if not PlaceableShop.buy(state, def, x, z, turns, free):
		result["ok"] = false
		result["reason"] = REASON_NO_MONEY
	else:
		_placed.append(state.layout.back())
		if _placed.size() > UNDO_DEPTH:
			_placed.pop_front()
		rebake_navigation(state)
	return result


## Turns the piece at `index` one quarter turn (`quarter_turns` more) around its corner cell.
## Returns the preview result; the piece only changes when it is green. Free: no money moves.
func rotate_piece(state: Object, index: int, quarter_turns: int = 1) -> Dictionary:
	var piece: Dictionary = _piece_at(state, index)
	if piece.is_empty():
		return {"ok": false, "reason": REASON_NO_DEFINITION, "rect": Rect2i()}
	var turns: int = posmod(int(piece.get("turns", 0)) + quarter_turns, 4)
	return _reposition(state, index, int(piece.get("x", 0)), int(piece.get("z", 0)), turns)


## Moves the piece at `index` so its corner is at (x, z), keeping its rotation. Free.
func move_piece(state: Object, index: int, x: int, z: int) -> Dictionary:
	var piece: Dictionary = _piece_at(state, index)
	if piece.is_empty():
		return {"ok": false, "reason": REASON_NO_DEFINITION, "rect": Rect2i()}
	return _reposition(state, index, x, z, int(piece.get("turns", 0)))


## Sells the piece at `index` (partial refund, PlaceableShop.sell). Returns the money given
## back, or -1 when the index is not valid.
func sell_piece(state: Object, index: int) -> int:
	var refund: int = PlaceableShop.sell(state, index)
	if refund >= 0:
		rebake_navigation(state)
	return refund


## D-0916: takes back the newest placement that is still in the layout (moved or turned since is
## fine; sold since is skipped). Pays the full price back, unlike selling. Returns the money
## given back, or -1 when there is nothing to undo.
func undo_last_placement(state: Object) -> int:
	while not _placed.is_empty():
		var piece: Dictionary = _placed.pop_back()
		for i: int in state.layout.size():
			if is_same(state.layout[i], piece):
				var def: PlaceableDefinition = PlaceableShop.definition(
						StringName(str(piece.get("id", ""))))
				state.layout.remove_at(i)
				var price: int = def.price if def != null else 0
				if price > 0:
					state.earn(price, REASON_UNDO)
				rebake_navigation(state)
				return price
	return -1


func can_undo(state: Object) -> bool:
	for piece: Variant in _placed:
		for entry: Variant in state.layout:
			if is_same(entry, piece):
				return true
	return false


## D-0908: rebuilds `navigation` from the current layout (also for a layout loaded or set by hand).
func rebake_navigation(state: Object) -> void:
	if navigation != null:
		navigation.rebake(grid_size, state.layout)


## D-0907: the layout with the piece at (x, z) still lets people walk to every piece.
func _keeps_paths(layout: Array, def: PlaceableDefinition, x: int, z: int, turns: int,
		ignore_index: int) -> bool:
	if entry_areas.is_empty():
		return true
	var after: Array = []
	for i: int in layout.size():
		if i != ignore_index:
			after.append(layout[i])
	after.append({"id": String(def.id), "x": x, "z": z, "turns": turns})
	return WalkReachability.is_walkable(grid_size, after, entry_areas)


func _piece_at(state: Object, index: int) -> Dictionary:
	if index < 0 or index >= state.layout.size():
		return {}
	return state.layout[index]


func _reposition(state: Object, index: int, x: int, z: int, turns: int) -> Dictionary:
	var piece: Dictionary = state.layout[index]
	var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
	var result: Dictionary = preview(state.layout, def, x, z, turns, -1, index)
	if bool(result["ok"]):
		piece["x"] = x
		piece["z"] = z
		piece["turns"] = turns
		rebake_navigation(state)
	return result


func _reason_for(layout: Array, rect: Rect2i, ignore_index: int = -1) -> StringName:
	if rect.position.x < 0 or rect.position.y < 0 \
			or rect.end.x > grid_size.x or rect.end.y > grid_size.y:
		return REASON_OUT_OF_BOUNDS
	for area: Rect2i in fixed_blocked:
		if area.intersects(rect):
			return REASON_FIXED
	for i: int in layout.size():
		if i == ignore_index:
			continue
		var piece: Variant = layout[i]
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		if def == null:
			continue
		var other := Rect2i(Vector2i(int(piece.get("x", 0)), int(piece.get("z", 0))),
				def.footprint_for(int(piece.get("turns", 0))))
		if other.intersects(rect):
			return REASON_OVERLAP
	return REASON_OK
