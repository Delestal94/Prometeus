class_name WarehouseStages
extends RefCounted
## Shed stages and upgrading between them (expansion D-0905, "Modo Empresa").
##
## Four stages (small, medium, large, logistics center) that grow the build grid of BuildMode and
## BuildPlacement. The sizes and prices live in CompanyTuning. Every stage keeps the corner
## (0, 0) of the previous one, so pieces already placed stay where they are when the shed grows.
## `expand()` charges the upgrade and moves `state.warehouse_stage`; the world adapter then calls
## `apply_to()` to resize the grid and rebuilds the walls from `wall_rects()` without reloading
## the level. Static helpers over a CompanyState-shaped object (no autoload is named, N-919).

const REASON_EXPAND: StringName = &"warehouse_expand"
const REFUSAL_MAX_STAGE: StringName = &"max_stage"
const REFUSAL_NO_MONEY: StringName = &"no_money"
const REFUSAL_LOCKED: StringName = &"locked"


static func stage_count() -> int:
	return CompanyTuning.WAREHOUSE_STAGE_IDS.size()


static func stage_id(stage: int) -> StringName:
	return CompanyTuning.WAREHOUSE_STAGE_IDS[clampi(stage, 0, stage_count() - 1)]


## Floor in grid cells (X x Z) of a stage.
static func grid_size_for(stage: int) -> Vector2i:
	return CompanyTuning.WAREHOUSE_STAGE_GRID[clampi(stage, 0, stage_count() - 1)]


## Floor in meters.
static func floor_size_m(stage: int) -> Vector2:
	return Vector2(grid_size_for(stage)) * CompanyTuning.WAREHOUSE_GRID_M


## Price of upgrading INTO `stage` from the one before it.
static func price_for(stage: int) -> int:
	return CompanyTuning.WAREHOUSE_STAGE_PRICE[clampi(stage, 0, stage_count() - 1)]


## The four wall segments of a stage as thin rects in grid cells (north, south, west, east),
## lying just outside the floor, so the world adapter places the wall meshes from them.
static func wall_rects(stage: int) -> Array[Rect2i]:
	var size: Vector2i = grid_size_for(stage)
	return [
		Rect2i(-1, -1, size.x + 2, 1),
		Rect2i(-1, size.y, size.x + 2, 1),
		Rect2i(-1, 0, 1, size.y),
		Rect2i(size.x, 0, 1, size.y),
	]


## {ok, reason, price, stage}: whether the company can upgrade to the next stage now.
## `unlocked_stage` is the biggest stage progression allows (D-0436); -1 means no limit.
static func preview(state: Object, unlocked_stage: int = -1) -> Dictionary:
	var next: int = int(state.warehouse_stage) + 1
	if next >= stage_count():
		return {"ok": false, "reason": REFUSAL_MAX_STAGE, "price": 0, "stage": next - 1}
	var price: int = price_for(next)
	var reason: StringName = &""
	if unlocked_stage >= 0 and next > unlocked_stage:
		reason = REFUSAL_LOCKED
	elif not state.can_afford(price):
		reason = REFUSAL_NO_MONEY
	return {"ok": reason == &"", "reason": reason, "price": price, "stage": next}


## Pays and moves to the next stage. Returns the preview result; nothing changes when it is red.
## The layout is kept as it is: every old cell is still on the bigger floor.
static func expand(state: Object, unlocked_stage: int = -1) -> Dictionary:
	var result: Dictionary = preview(state, unlocked_stage)
	if not bool(result["ok"]):
		return result
	if not state.spend(int(result["price"]), REASON_EXPAND):
		result["ok"] = false
		result["reason"] = REFUSAL_NO_MONEY
		return result
	state.warehouse_stage = int(result["stage"])
	return result


## Floor cells in front of the loading dock (south wall, centered) that nothing can cover (D-0906).
static func dock_rect(stage: int) -> Rect2i:
	var size: Vector2i = grid_size_for(stage)
	var cells: Vector2i = CompanyTuning.WAREHOUSE_DOCK_CELLS
	return Rect2i(Vector2i((size.x - cells.x) / 2, size.y - cells.y), cells)


## Floor cells in front of the customer exit (north wall, centered) that nothing can cover.
static func exit_rect(stage: int) -> Rect2i:
	var size: Vector2i = grid_size_for(stage)
	var cells: Vector2i = CompanyTuning.WAREHOUSE_EXIT_CELLS
	return Rect2i(Vector2i((size.x - cells.x) / 2, 0), cells)


## Both fixed areas of a stage: BuildPlacement.fixed_blocked.
static func fixed_rects(stage: int) -> Array[Rect2i]:
	return [dock_rect(stage), exit_rect(stage)]


## The gate openings in the wall line (cells just outside the floor, same span as the fixed
## areas), so the world adapter leaves a gap in the wall meshes there: dock south, exit north.
static func gate_rects(stage: int) -> Array[Rect2i]:
	var size: Vector2i = grid_size_for(stage)
	var dock: Rect2i = dock_rect(stage)
	var door: Rect2i = exit_rect(stage)
	return [Rect2i(dock.position.x, size.y, dock.size.x, 1), Rect2i(door.position.x, -1, door.size.x, 1)]


## Resizes the build grid and the placement checks to the stage the company is at, and sets the
## fixed areas (dock, exit). Returns the new grid size.
static func apply_to(stage: int, placement: BuildPlacement, mode: BuildMode = null) -> Vector2i:
	var size: Vector2i = grid_size_for(stage)
	placement.grid_size = size
	placement.fixed_blocked = fixed_rects(stage)
	placement.entry_areas = fixed_rects(stage)
	if mode != null:
		mode.grid_size = size
	return size
