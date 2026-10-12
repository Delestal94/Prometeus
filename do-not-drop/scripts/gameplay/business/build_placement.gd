class_name BuildPlacement
extends RefCounted
## Checks and commits the placement of a warehouse object (expansion D-0902, "Modo Empresa").
##
## Pure logic over the grid of BuildMode: `preview()` says whether an object fits at a cell with a
## given rotation (green) or not (red, with the reason), and `place()` buys it through PlaceableShop
## only when the preview is green. The world adapter draws the footprint with `preview_color()`.
## Fixed areas that can never be covered (loading dock, exit: D-0906) arrive as `fixed_blocked`
## rectangles in grid cells. Nothing here names autoloads or UI classes (N-919).

const REASON_OK: StringName = &""
const REASON_OUT_OF_BOUNDS: StringName = &"out_of_bounds"
const REASON_OVERLAP: StringName = &"overlap"
const REASON_FIXED: StringName = &"fixed_area"
const REASON_NO_DEFINITION: StringName = &"no_definition"
const REASON_NO_MONEY: StringName = &"no_money"

const COLOR_OK: Color = Color(0.2, 0.85, 0.3, 0.55)
const COLOR_BAD: Color = Color(0.9, 0.2, 0.2, 0.55)

## Floor in grid cells (X x Z), as BuildMode.grid_size.
var grid_size: Vector2i = Vector2i(12, 8)
## Cells that no object may cover, as Rect2i in grid cells.
var fixed_blocked: Array[Rect2i] = []


func _init(size: Vector2i = Vector2i(12, 8)) -> void:
	grid_size = size


## Rect of cells the object would cover with its corner at (x, z) after `turns` quarter turns.
func footprint_rect(def: PlaceableDefinition, x: int, z: int, turns: int) -> Rect2i:
	return Rect2i(Vector2i(x, z), def.footprint_for(turns))


## Result for putting `def` at (x, z): {ok: bool, reason: StringName, rect: Rect2i}.
## `layout` is the CompanyState.layout array ({id, x, z, turns} per piece); `money` < 0 skips
## the wallet check (the preview only needs the grid; place() always checks it).
func preview(layout: Array, def: PlaceableDefinition, x: int, z: int, turns: int = 0,
		money: int = -1) -> Dictionary:
	if def == null:
		return {"ok": false, "reason": REASON_NO_DEFINITION, "rect": Rect2i()}
	var rect: Rect2i = footprint_rect(def, x, z, turns)
	var reason: StringName = _reason_for(layout, rect)
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
	return result


func _reason_for(layout: Array, rect: Rect2i) -> StringName:
	if rect.position.x < 0 or rect.position.y < 0 \
			or rect.end.x > grid_size.x or rect.end.y > grid_size.y:
		return REASON_OUT_OF_BOUNDS
	for area: Rect2i in fixed_blocked:
		if area.intersects(rect):
			return REASON_FIXED
	for piece: Variant in layout:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		if def == null:
			continue
		var other := Rect2i(Vector2i(int(piece.get("x", 0)), int(piece.get("z", 0))),
				def.footprint_for(int(piece.get("turns", 0))))
		if other.intersects(rect):
			return REASON_OVERLAP
	return REASON_OK
