extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_invalid_layouts.gd
##
## Invalid shed layouts (expansion D-0948, includes D-0940; rule D-0902/D-0907: a station always
## keeps a free cell to walk up to, otherwise the preview is red). Over BuildPlacement (local
## build mode), CompanyLayoutNet (the host's check/apply that the game really uses),
## BuildLayoutSave (saves and snapshots) on the small shed (stage 0):
## - placing, moving or turning a piece so that it closes the last free side of a station, or so
##   that the new piece is itself shut in, is red with `blocks_path` (the preview colour is red);
##   the layout, the money and the stock stay exactly as they were, locally and through the host's
##   check (no event is granted). The same moves one cell away are green, so the rule is not a
##   blanket refusal;
## - a layout loaded from a save (after a JSON round trip) or from the host's snapshot
##   (CompanyState.from_dict) with a shut-in station, an overlap, a piece out of the floor or on the
##   dock, an unknown id or junk is cleaned: what comes out is always walkable, every piece that
##   fits keeps its place, its uid and its integer cells, and the stock is not touched (a piece that
##   cannot be kept leaves its units in the Inventory, they are not deleted); a valid layout and
##   the default shed lose nothing;
## - moving or turning a shelf that holds units keeps the piece (same uid) and the Inventory
##   intact (units under shelf:<uid>_<slot>), for pieces with a stored uid and for ones without;
##   selling it is refused with `not_empty` and changes nothing; once emptied it can be sold and
##   a neighbour that had no uid keeps its name and its units; a refused move of a stocked shelf
##   changes nothing either (D-0940);
## - undo_last_placement() leaves layout and money exactly as before the placement, also after the
##   piece was moved or turned, one by one for several placements; a refused placement leaves
##   nothing to undo.
## It protects against a layout that traps a packing station (workers stuck, orders never done) and
## against losing a player's stock or pieces when the shed is rearranged or loaded.

const BLOCKED: StringName = BuildPlacement.REASON_BLOCKS_PATH

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Invalid Co")
	_check_red_edits(state)
	_check_loaded(state)
	_check_stock(state)
	_check_undo(state)
	state.reset()
	if _failures == 0:
		print("PASS: moves that shut in a station are red and change nothing, bad layouts load"
			+ " cleaned, stocked shelves keep their units, undo restores the exact state")
	quit(_failures)


## Corner table at (0,3) 2x1: shelves above and below it, so its only way in is the cell (2,3).
func _corner_layout() -> Array:
	return [
		{"id": "assembly_table", "x": 0, "z": 3, "turns": 0, "uid": "table_1"},  # 0
		{"id": "shelf", "x": 0, "z": 2, "turns": 0, "uid": "shelf_top"},         # 1
		{"id": "shelf", "x": 0, "z": 4, "turns": 0, "uid": "shelf_low"},         # 2
		{"id": "shelf", "x": 2, "z": 2, "turns": 0, "uid": "shelf_r"},           # 3 turned shuts (2,3)
		{"id": "shelf", "x": 8, "z": 3, "turns": 0, "uid": "shelf_spare"},       # 4 moved to (2,3) shuts it
		{"id": "shelf", "x": 1, "z": 0, "turns": 0, "uid": "shelf_n"},           # 5 makes a pocket at (0,0)
		{"id": "fridge", "x": 0, "z": 1, "turns": 0, "uid": "fridge_1"},         # 6
	]


func _set_layout(state: Node, pieces: Array) -> void:
	state.layout.clear()
	for piece: Dictionary in pieces:
		state.layout.append(piece.duplicate(true))


func _placement() -> BuildPlacement:
	var grid := BuildPlacement.new()
	WarehouseStages.apply_to(0, grid)
	return grid


# --- 1. Edits that shut in a station ---


func _check_red_edits(state: Node) -> void:
	var grid: BuildPlacement = _placement()
	var net := CompanyLayoutNet.new()
	_set_layout(state, _corner_layout())
	state.money = 1000
	_expect(WalkReachability.is_walkable(grid.grid_size, state.layout, grid.entry_areas),
		"The starting corner layout is walkable")
	var before: Array = state.layout.duplicate(true)
	var stock: Inventory = state.stock()

	# Turning the shelf beside the access cell: 2x1 at (2,2) becomes 1x2 and covers (2,3).
	var turned: Dictionary = grid.rotate_piece(state, 3)
	_expect(not turned["ok"] and turned["reason"] == BLOCKED,
		"Turning a shelf over the last access cell is red blocks_path (got %s)" % turned["reason"])
	_expect(grid.preview_color(turned) == BuildPlacement.COLOR_BAD, "...and the preview is red")
	_expect(state.layout == before, "...and the layout is exactly as before")
	var asked: Dictionary = net.check(state, stock, CompanyLayoutNet.ROTATE, {"uid": &"shelf_r", "turns": 1}, true)
	_expect(asked["reason"] == BLOCKED and not asked.has("kind"),
		"The host refuses the same turn with blocks_path and grants no event (got %s)" % [asked])

	# Moving the spare shelf over (2,3).
	var money: int = state.money
	var moved: Dictionary = grid.move_piece(state, 4, 2, 3)
	_expect(not moved["ok"] and moved["reason"] == BLOCKED,
		"Moving a shelf over the access cell is red blocks_path (got %s)" % moved["reason"])
	_expect(state.layout == before and state.money == money, "...and nothing changed")
	asked = net.check(state, stock, CompanyLayoutNet.MOVE, {"uid": &"shelf_spare", "x": 2, "z": 3}, true)
	_expect(asked["reason"] == BLOCKED, "The host refuses the same move (got %s)" % [asked])

	# Placing a new piece on the access cell.
	var fridge: PlaceableDefinition = PlaceableShop.definition(&"fridge")
	var placed: Dictionary = grid.place(state, fridge, 2, 3)
	_expect(not placed["ok"] and placed["reason"] == BLOCKED,
		"Placing a fridge on the access cell is red blocks_path (got %s)" % placed["reason"])
	_expect(state.layout == before and state.money == money, "...and charges nothing")
	asked = net.check(state, stock, CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 2, "z": 3, "turns": 0}, true)
	_expect(asked["reason"] == BLOCKED, "The host refuses the same placement (got %s)" % [asked])

	# The new piece is the one that gets shut in: (0,0) has a shelf on one side, a fridge on the other.
	placed = grid.place(state, fridge, 0, 0)
	_expect(not placed["ok"] and placed["reason"] == BLOCKED,
		"A piece placed inside a closed pocket is red blocks_path (got %s)" % placed["reason"])
	_expect(state.layout == before and state.money == money, "...and changes nothing")

	# Controls: one cell away is green, the rule is not a blanket refusal.
	_expect(grid.preview(state.layout, fridge, 3, 4)["ok"], "A fridge one cell off the access cell is green")
	_expect(grid.move_piece(state, 4, 8, 5)["ok"], "Moving the spare shelf somewhere open is green")
	_expect(WalkReachability.is_walkable(grid.grid_size, state.layout, grid.entry_areas),
		"The layout is still walkable after the green move")

	# A dispatch zone is painted on the floor: it never closes a station.
	var zone: PlaceableDefinition = PlaceableShop.definition(&"dispatch_zone")
	_expect(grid.preview(state.layout, zone, 2, 3)["ok"], "A dispatch zone on the access cell stays green")

	# The enclosing wall of a whole pocket: the dock stays joined to the exit.
	var wall: Array = []
	for i: int in 6:
		wall.append({"id": "assembly_table", "x": i * 2, "z": 3, "turns": 0})
	_set_layout(state, wall.slice(0, 5))
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var closing: Dictionary = grid.place(state, table, 10, 3)
	_expect(not closing["ok"] and closing["reason"] == BLOCKED and state.layout.size() == 5,
		"A table that cuts the dock from the exit is red and not added (got %s)" % closing["reason"])


# --- 2. Loading an invalid layout ---


func _check_loaded(state: Node) -> void:
	var valid: Array = _corner_layout()
	var junk: Array = [
		{"id": "shelf", "x": 2, "z": 3, "turns": 0, "uid": "shelf_trap"},    # shuts the table in
		{"id": "shelf", "x": 0, "z": 2, "turns": 0, "uid": "shelf_dup"},     # overlaps shelf_top
		{"id": "shelf", "x": 11, "z": 7, "turns": 0, "uid": "shelf_out"},    # sticks out of the floor
		{"id": "shelf", "x": 4, "z": 6, "turns": 0, "uid": "shelf_dock"},    # on the loading dock
		{"id": "hologram", "x": 5, "z": 5, "turns": 0, "uid": "ghost"},      # unknown piece
		42, "text", {"id": "shelf"}, {"id": "shelf", "x": "a", "z": 1},
	]
	var raw: Array = valid.duplicate(true) + junk
	var stock: Inventory = state.stock()
	stock.receive(&"mug", 4, DefaultShed.shelf_location(&"shelf_trap", 0))
	state.store_stock(stock)
	var units: int = state.stock().total_units()
	var grid: BuildPlacement = _placement()

	var data: Dictionary = state.to_dict()
	data["layout"] = JSON.parse_string(JSON.stringify(raw))  # numbers come back as floats
	var loaded: Node = state
	loaded.from_dict(data)
	_expect(_same_pieces(loaded.layout, valid),
		"A save with a shut-in station and junk loads only the valid pieces, same uids and order (got %d: %s)"
		% [loaded.layout.size(), _uids(loaded.layout)])
	_expect(WalkReachability.is_walkable(grid.grid_size, loaded.layout, grid.entry_areas),
		"The cleaned layout is walkable")
	_expect(loaded.stock().total_units() == units,
		"The stock of the dropped piece is not deleted (got %d of %d)" % [loaded.stock().total_units(), units])
	for piece: Dictionary in loaded.layout:
		var ints: bool = typeof(piece["x"]) == TYPE_INT and typeof(piece["z"]) == TYPE_INT
		_expect(ints and typeof(piece["turns"]) == TYPE_INT, "Cells of %s come back as ints" % piece["uid"])

	# The blocker first: whatever the order, the result is valid and only the one that closes it goes.
	var swapped: Array = [valid[0], {"id": "shelf", "x": 2, "z": 3, "turns": 0, "uid": "shelf_trap"},
		valid[1], valid[2]]
	var cleaned: Array[Dictionary] = BuildLayoutSave.sanitize(swapped, 0)
	_expect(WalkReachability.is_walkable(grid.grid_size, cleaned, grid.entry_areas),
		"A blocker listed first still leaves a walkable layout")
	_expect(cleaned.size() == 3, "...and exactly one piece is dropped (got %s)" % _uids(cleaned))

	# A snapshot from the host is the same call; a valid one loses nothing.
	var snap: Dictionary = loaded.to_dict()
	loaded.from_dict(snap)
	_expect(_same_pieces(loaded.layout, valid), "A valid layout survives to_dict/from_dict untouched")

	# A stage change cannot be used to smuggle pieces in: a big-stage cell on stage 0 is dropped.
	var big: Array[Dictionary] = BuildLayoutSave.sanitize(
		[{"id": "shelf", "x": 20, "z": 10, "turns": 0}], 0)
	_expect(big.is_empty(), "A piece from a bigger stage is dropped on stage 0")

	# The default shed has to be a layout the loader keeps whole.
	var fresh: Node = state
	fresh.new_company("Default Co")
	DefaultShed.load_default().apply_to(fresh)
	var count: int = fresh.layout.size()
	var again: Array[Dictionary] = BuildLayoutSave.sanitize(fresh.layout.duplicate(true), 0)
	_expect(count > 0 and again.size() == count and _same_pieces(again, fresh.layout),
		"The default shed loses no piece through the loader (got %d of %d)" % [again.size(), count])
	state.new_company("Invalid Co")


# --- 3. Stocked shelves (D-0940) ---


func _check_stock(state: Node) -> void:
	var grid: BuildPlacement = _placement()
	var net := CompanyLayoutNet.new()
	_set_layout(state, [
		{"id": "assembly_table", "x": 5, "z": 3, "turns": 0, "uid": "table_1"},
		{"id": "shelf", "x": 8, "z": 3, "turns": 0, "uid": "shelf_s"},
		{"id": "shelf", "x": 2, "z": 5, "turns": 0},   # no uid: shelf_1
		{"id": "shelf", "x": 2, "z": 1, "turns": 0},   # no uid: shelf_2
	])
	state.money = 1000
	var stock: Inventory = state.stock()
	stock.receive(&"mug", 5, DefaultShed.shelf_location(&"shelf_s", 0))
	stock.receive(&"plate", 3, DefaultShed.shelf_location(&"shelf_s", 2))
	stock.receive(&"lamp", 2, DefaultShed.shelf_location(&"shelf_2", 1))
	state.store_stock(stock)
	var inventory_before: Dictionary = state.inventory.duplicate(true)

	# Move through the host.
	var granted: Dictionary = net.check(state, state.stock(), CompanyLayoutNet.MOVE,
		{"uid": &"shelf_s", "x": 8, "z": 5}, true)
	_expect(granted["reason"] == &"", "Moving a stocked shelf to free floor is allowed (got %s)" % [granted])
	_expect(net.apply(state, granted["kind"], granted["data"]), "...and the event applies")
	var index: int = CompanyLayoutNet.piece_index(state.layout, &"shelf_s")
	_expect(index >= 0 and state.layout[index]["z"] == 5 and state.layout.size() == 4,
		"...the same piece (uid shelf_s) is now at z 5 and no piece was lost")
	_expect(state.inventory == inventory_before, "...and the Inventory is exactly as before")
	_expect(state.stock().count(&"mug", DefaultShed.shelf_location(&"shelf_s", 0)) == 5
		and state.stock().count(&"plate", DefaultShed.shelf_location(&"shelf_s", 2)) == 3,
		"...with the units still in their slots under the same name")

	granted = net.check(state, state.stock(), CompanyLayoutNet.ROTATE, {"uid": &"shelf_s", "turns": 1}, true)
	_expect(granted["reason"] == &"" and net.apply(state, granted["kind"], granted["data"]),
		"Turning the stocked shelf is allowed (got %s)" % [granted])
	_expect(state.inventory == inventory_before and state.layout[index]["turns"] == 1,
		"...keeps the Inventory and the new turn")

	# Moving a shelf without a stored uid names every piece first; its units follow the name.
	granted = net.check(state, state.stock(), CompanyLayoutNet.MOVE, {"uid": &"shelf_2", "x": 3, "z": 1}, true)
	_expect(granted["reason"] == &"" and net.apply(state, granted["kind"], granted["data"]),
		"Moving a shelf saved without a uid is allowed (got %s)" % [granted])
	var named: int = CompanyLayoutNet.piece_index(state.layout, &"shelf_2")
	_expect(named >= 0 and state.layout[named]["x"] == 3 and state.layout[named].get("uid") == "shelf_2",
		"...it keeps the name shelf_2 and now stores it")
	_expect(state.stock().count(&"lamp", DefaultShed.shelf_location(&"shelf_2", 1)) == 2,
		"...and its lamps are still counted under shelf:shelf_2_1")

	# Selling a stocked shelf is refused and changes nothing.
	var layout_before: Array = state.layout.duplicate(true)
	var money: int = state.money
	inventory_before = state.inventory.duplicate(true)
	var sell: Dictionary = net.check(state, state.stock(), CompanyLayoutNet.SELL, {"uid": &"shelf_s"}, true)
	_expect(sell["reason"] == CompanyLayoutNet.REASON_NOT_EMPTY and not sell.has("kind"),
		"Selling a shelf with units is refused with not_empty (got %s)" % [sell])
	_expect(state.layout == layout_before and state.money == money and state.inventory == inventory_before,
		"...and layout, money and Inventory are untouched")

	# A red move of a stocked shelf (over the table's last access cell) changes nothing either.
	_set_layout(state, _corner_layout())
	state.layout[4]["uid"] = "shelf_s"
	state.layout.remove_at(4)
	state.layout.append({"id": "shelf", "x": 8, "z": 3, "turns": 0, "uid": "shelf_s"})
	layout_before = state.layout.duplicate(true)
	var red: Dictionary = net.check(state, state.stock(), CompanyLayoutNet.MOVE,
		{"uid": &"shelf_s", "x": 2, "z": 3}, true)
	_expect(red["reason"] == BLOCKED, "A stocked shelf cannot be moved over the access cell (got %s)" % [red])
	var local: Dictionary = grid.move_piece(state, state.layout.size() - 1, 2, 3)
	_expect(not local["ok"] and state.layout == layout_before and state.inventory == inventory_before,
		"...and the local move changes neither the layout nor the Inventory")

	# Local build mode: move and turn never touch the stock.
	_expect(grid.move_piece(state, state.layout.size() - 1, 8, 5)["ok"]
		and state.inventory == inventory_before, "A local move keeps the Inventory")

	# Empty it, then it sells; a uid-less neighbour keeps its name and units.
	_set_layout(state, [
		{"id": "shelf", "x": 2, "z": 5, "turns": 0},   # shelf_1, empty
		{"id": "shelf", "x": 2, "z": 1, "turns": 0},   # shelf_2, holds lamps
	])
	var cart: Inventory = state.stock()
	cart.consume(&"mug", 5, DefaultShed.shelf_location(&"shelf_s", 0))
	cart.consume(&"plate", 3, DefaultShed.shelf_location(&"shelf_s", 2))
	state.store_stock(cart)
	money = state.money
	sell = net.check(state, state.stock(), CompanyLayoutNet.SELL, {"uid": &"shelf_1"}, true)
	_expect(sell["reason"] == &"" and net.apply(state, sell["kind"], sell["data"]),
		"An empty shelf can be sold (got %s)" % [sell])
	_expect(state.layout.size() == 1 and state.layout[0].get("uid") == "shelf_2",
		"...the other shelf stays and keeps its name")
	_expect(state.stock().count(&"lamp", DefaultShed.shelf_location(&"shelf_2", 1)) == 2,
		"...and its lamps are not lost or moved to another shelf")
	_expect(state.money > money, "...and the sale paid the refund")


# --- 4. Undo ---


func _check_undo(state: Node) -> void:
	var grid: BuildPlacement = _placement()
	_set_layout(state, _corner_layout())
	state.money = 1000
	var layout_before: Array = state.layout.duplicate(true)
	var money_before: int = state.money
	var fridge: PlaceableDefinition = PlaceableShop.definition(&"fridge")
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")

	# A refused placement leaves nothing to undo.
	var red: Dictionary = grid.place(state, fridge, 2, 3)
	_expect(not red["ok"] and not grid.can_undo(state) and grid.undo_last_placement(state) == -1,
		"A red placement leaves nothing to undo")
	_expect(state.layout == layout_before and state.money == money_before, "...and nothing changed")

	# Place, move and turn, then undo: back to the exact starting state.
	_expect(grid.place(state, table, 8, 5)["ok"], "A table on free floor is placed")
	var index: int = state.layout.size() - 1
	grid.move_piece(state, index, 9, 4)
	grid.rotate_piece(state, index)
	_expect(state.layout.size() == layout_before.size() + 1 and state.money == money_before - table.price,
		"The placement cost its price")
	_expect(grid.undo_last_placement(state) == table.price, "Undo gives the full price back")
	_expect(state.layout == layout_before and state.money == money_before,
		"Layout and money are exactly as before the placement (got %d pieces, %d money)"
		% [state.layout.size(), state.money])

	# Several placements, undone newest first, each step restores the state before it.
	var steps: Array = []
	for cell: Vector2i in [Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5)]:
		steps.append([state.layout.duplicate(true), state.money])
		_expect(grid.place(state, fridge, cell.x, cell.y)["ok"], "A fridge goes to %s" % cell)
	for i: int in range(steps.size() - 1, -1, -1):
		grid.undo_last_placement(state)
		_expect(state.layout == steps[i][0] and state.money == steps[i][1],
			"Undo step %d restores the exact earlier state" % i)
	_expect(state.layout == layout_before and state.money == money_before and not grid.can_undo(state),
		"After undoing everything the shed is as it was and nothing is left to undo")

	# Undo never removes a piece that was already there, even when it is the newest in the layout.
	_expect(grid.undo_last_placement(state) == -1 and state.layout == layout_before,
		"Undo with an empty stack removes nothing")


# --- helpers ---


func _same_pieces(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i: int in got.size():
		for key: String in ["id", "x", "z", "turns"]:
			if int(got[i].get(key, -1)) != int(want[i].get(key, -1)) and key != "id":
				return false
		if str(got[i].get("id", "")) != str(want[i].get("id", "")) \
				or str(got[i].get("uid", "")) != str(want[i].get("uid", "")):
			return false
	return true


func _uids(layout: Array) -> String:
	var names: Array[String] = []
	for piece: Dictionary in layout:
		names.append(str(piece.get("uid", piece.get("id", "?"))))
	return ", ".join(names)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
