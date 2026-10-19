class_name BuildCursor
extends RefCounted
## The cursor of the warehouse build mode (expansion D-0917): which cell is aimed, which object
## of the catalog is chosen, the pose it would get and what a press of "confirm" asks the host.
##
## Pure logic, no nodes and no input: the adapter (`ShedBuilder`) turns keyboard, mouse and
## gamepad into these calls, so every device does the same thing. Nothing changes the layout here:
## `confirm()`, `sell()` and `rotate()` only return the request (kind and data of the layout
## requests of CompanyLayoutNet) that the adapter sends through CompanyNet; the host decides.
##
## Flow: the cursor moves one cell at a time. On an empty cell, `confirm()` asks to place the
## chosen object. On a placed piece, `confirm()` grabs it; the next `confirm()` asks to move it to
## the cursor and `cancel()` lets go. `rotate()` turns the chosen object, or the grabbed piece.
## `sell()` asks to sell the piece under the cursor.

const NO_REQUEST: Dictionary = {}

## Grid the cursor moves on, and the layout/wallet it reads (any CompanyState-shaped object).
var mode: BuildMode
var placement: BuildPlacement
var state: Object

## Objects the player can choose from (every PlaceableDefinition), in menu order.
var catalog: Array[PlaceableDefinition] = []
## Index into `catalog` of the chosen object.
var chosen: int = 0
## Cell aimed at, in grid cells from the shed corner.
var cell: Vector2i = Vector2i.ZERO
## Quarter turns of the chosen object (a grabbed piece keeps its own).
var turns: int = 0
## uid of the grabbed piece, &"" when none.
var held: StringName = &""


func _init(build_mode: BuildMode, checker: BuildPlacement, company: Object,
		definitions: Array[PlaceableDefinition] = []) -> void:
	mode = build_mode
	placement = checker
	state = company
	catalog = definitions if not definitions.is_empty() else all_definitions()
	cell = Vector2i(mode.focus.floor())


## Every object of data/placeables/, sorted by id so the menu is the same on every peer.
static func all_definitions() -> Array[PlaceableDefinition]:
	var found: Array[PlaceableDefinition] = []
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at(PlaceableShop.DEFINITIONS_DIR):
		var name: String = file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			ids.append(name.get_basename())
	ids.sort()
	for id: String in ids:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(id))
		if def != null:
			found.append(def)
	return found


func chosen_definition() -> PlaceableDefinition:
	if catalog.is_empty():
		return null
	return catalog[clampi(chosen, 0, catalog.size() - 1)]


## Moves the cursor by `step` cells, kept on the floor.
func move(step: Vector2i) -> void:
	set_cell(cell + step)


func set_cell(target: Vector2i) -> void:
	cell = Vector2i(
		clampi(target.x, 0, maxi(mode.grid_size.x - 1, 0)),
		clampi(target.y, 0, maxi(mode.grid_size.y - 1, 0)))


## Next (`step` > 0) or previous object of the catalog, wrapping around. Not while holding a piece.
func cycle(step: int) -> void:
	if catalog.is_empty() or held != &"":
		return
	chosen = posmod(chosen + step, catalog.size())


## Index in the layout of the piece covering the cursor cell, -1 when the cell is free.
func piece_under_cursor() -> int:
	var layout: Array = state.layout
	for i: int in layout.size():
		var piece: Dictionary = layout[i]
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		if def == null:
			continue
		var rect: Rect2i = placement.footprint_rect(def, int(piece.get("x", 0)), int(piece.get("z", 0)),
			int(piece.get("turns", 0)))
		if rect.has_point(cell):
			return i
	return -1


## The grabbed piece's layout index, -1 when none is grabbed or it is gone (sold meanwhile).
func held_index() -> int:
	if held == &"":
		return -1
	return CompanyLayoutNet.piece_index(state.layout, held)


## What the ghost shows: {ok, reason, rect, def, turns}. For a grabbed piece it is where it would
## stand with the corner at the cursor; for the chosen object, where it would be placed. `def` is
## null (ok false) with nothing to show, e.g. aiming at a piece with nothing grabbed.
func ghost() -> Dictionary:
	var index: int = held_index()
	if held != &"" and index < 0:
		held = &""
	if index >= 0:
		var piece: Dictionary = state.layout[index]
		var held_def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		var held_turns: int = posmod(int(piece.get("turns", 0)), 4)
		var moved: Dictionary = placement.preview(state.layout, held_def, cell.x, cell.y, held_turns, -1, index)
		moved["def"] = held_def
		moved["turns"] = held_turns
		return moved
	var def: PlaceableDefinition = chosen_definition()
	var result: Dictionary = placement.preview(state.layout, def, cell.x, cell.y, turns, int(state.money))
	result["def"] = def
	result["turns"] = turns
	return result


## A press of confirm: the request to send ({kind, data}), or NO_REQUEST when it only grabbed a
## piece or had nothing to do. The request is not sent here; the host may still refuse it.
func confirm() -> Dictionary:
	var index: int = held_index()
	if index >= 0:
		var to: Dictionary = {"uid": held, "x": cell.x, "z": cell.y}
		held = &""
		return {"kind": CompanyLayoutNet.MOVE, "data": to}
	var under: int = piece_under_cursor()
	if under >= 0:
		held = DefaultShed.piece_uid(state.layout, under)
		return NO_REQUEST
	var def: PlaceableDefinition = chosen_definition()
	if def == null:
		return NO_REQUEST
	return {"kind": CompanyLayoutNet.PLACE,
		"data": {"id": def.id, "x": cell.x, "z": cell.y, "turns": turns}}


## Rotate: a grabbed piece asks for a quarter turn (free, host-checked); otherwise the chosen
## object's pose turns locally and nothing is asked.
func rotate() -> Dictionary:
	if held_index() >= 0:
		return {"kind": CompanyLayoutNet.ROTATE, "data": {"uid": held, "turns": 1}}
	turns = posmod(turns + 1, 4)
	return NO_REQUEST


## Sell: the request for the piece under the cursor (or the grabbed one).
func sell() -> Dictionary:
	var index: int = held_index()
	if index < 0:
		index = piece_under_cursor()
	if index < 0:
		return NO_REQUEST
	var uid: StringName = DefaultShed.piece_uid(state.layout, index)
	held = &""
	return {"kind": CompanyLayoutNet.SELL, "data": {"uid": uid}}


## Cancel: lets go of a grabbed piece. True when there was one (the mode stays on); false means
## the press is free to leave the mode.
func cancel() -> bool:
	if held == &"":
		return false
	held = &""
	return true
