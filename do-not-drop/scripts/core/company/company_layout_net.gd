class_name CompanyLayoutNet
extends RefCounted
## The shed layout built over the network (expansion D-0910): placing, moving, turning and selling
## a piece are CompanyNet requests the host checks and events every peer applies the same way
## (contract docs/expansion-distritos/diseno/red-autoridad.md, section 2 "Construir el galpón").
##
## CompanyNet hands it the build requests (check(), host only) and the layout events (apply(),
## every peer); it lives there as CompanyNet.build. Nothing here sends anything, names an autoload
## or keeps the layout: the layout is the company's (CompanyState.layout), which the snapshot
## already carries (D-2004), so a late joiner gets the host's shed with no snapshot part of its own.
##
## The host checks a request with exactly what the build mode checks on its own (BuildPlacement
## .preview() on the grid of the company's stage, WarehouseStages.apply_to(): inside the floor, off
## the dock and the exit, no overlap, every station still walkable) and the wallet (placing pays
## the price), then publishes one small event that carries the result as absolute values. Every
## peer, the host too, applies it in apply() with the same PlaceableShop calls and checks only that
## the data fits (rule 6); a client whose copy does not take it waits for a snapshot (CompanyNet).
## What the build mode shows before confirming (green or red, the turned footprint) is local
## (rule 9): placement_for() gives the adapter the same checker the host uses.
##
## Decision (D-0910): only the host builds. A client may ask, and hears host_only, so the build
## mode can tell it why nothing happened; the crew's vote is D-0910.1. Neither the day's phase nor
## the frozen shed (DayCycle, D-0203) gate building: the contract and D-0203 do not ask for it, and
## a layout event touches neither (whether the player may enter the build mode is BuildMode.enter's
## can_build, in the adapter).
##
## A piece is named by its uid (DefaultShed.piece_uid()), never by its index: two requests in flight
## cannot mix pieces up, and a shelf's units lie under that name (shelf:<uid>_<slot>). The host gives
## a placed piece a fresh uid ("<id>_<n>", the lowest n free) in its event; before any layout event
## is applied every piece without a stored uid gets its derived name stored (stamp_uids()), so
## selling one never renames another. A piece that holds units is not sold (not_empty).
##
## Requests (CompanyNet.request(kind, data); cells as ints, never Vector2i, rule 5):
##   layout_place   {id: placeable id, x, z, turns: 0..3}  ->  layout_placed {id, x, z, turns, uid, minute}
##   layout_move    {uid, x, z}                            ->  layout_moved  {uid, x, z, turns}
##   layout_rotate  {uid, turns: 1..3 quarter turns more}  ->  layout_moved  {uid, x, z, turns}
##   layout_sell    {uid}                                  ->  layout_sold   {uid, minute}
## `minute` is the host's CompanyState.clock_minutes: the wallet entry (placeable_buy,
## placeable_sell) is written with the same minute on every peer (only the host's clock writes it).
## Refusals: host_only, bad_data, no_piece, not_empty and BuildPlacement's out_of_bounds,
## fixed_area, overlap, blocks_path, no_definition and no_money.

const PLACE: StringName = &"layout_place"
const MOVE: StringName = &"layout_move"
const ROTATE: StringName = &"layout_rotate"
const SELL: StringName = &"layout_sell"
const REQUEST_KINDS: Array[StringName] = [PLACE, MOVE, ROTATE, SELL]
const PLACED: StringName = &"layout_placed"
const MOVED: StringName = &"layout_moved"
const SOLD: StringName = &"layout_sold"
const EVENT_KINDS: Array[StringName] = [PLACED, MOVED, SOLD]

## The requester is not the host: only the host builds (D-0910; the crew's vote is D-0910.1).
const REASON_HOST_ONLY: StringName = &"host_only"
## No piece of the layout has that uid.
const REASON_NO_PIECE: StringName = &"no_piece"
## The piece still holds units (a shelf slot, a packing table): selling it would lose them.
const REASON_NOT_EMPTY: StringName = &"not_empty"
const REASON_BAD_DATA: StringName = &"bad_data"
## Cells a request or an event may name, from the corner either way: far past the biggest stage
## (32 x 20) and small enough that a Vector2i never wraps one back onto the floor.
const MAX_CELL: int = 256

## The employees' walking grid (D-0908), rebaked on this peer after every layout event that sticks;
## null (until the world gives one, D-1011): nothing to rebake. Its owner calls rebake() after a
## snapshot too.
var navigation: WalkNavigation = null

## Placeable ids of the catalog, read once ({StringName: true}).
static var _known: Dictionary = {}
static var _catalog_read: bool = false


## The checker the build mode uses for the company's current stage: grid, dock and exit, entries,
## and this peer's navigation.
func placement_for(state: Object) -> BuildPlacement:
	var checker := BuildPlacement.new()
	WarehouseStages.apply_to(int(state.get(&"warehouse_stage")), checker)
	checker.navigation = navigation
	return checker


## Host: a build request, as {reason} when it is refused or {reason: &"", kind, data} with the one
## event it leads to. `by_host` is whether the host itself asked (CompanyNet knows the sender);
## `stock` is the live Inventory (a piece that holds units is not sold).
func check(state: Object, stock: Inventory, kind: StringName, data: Dictionary,
		by_host: bool) -> Dictionary:
	if not by_host:
		return _refused(REASON_HOST_ONLY)
	if state == null or not is_instance_valid(state):
		return _refused(REASON_BAD_DATA)
	match kind:
		PLACE:
			return _check_place(state, data)
		MOVE, ROTATE:
			return _check_move(state, kind, data)
		SELL:
			return _check_sell(state, stock, data)
	return _refused(REASON_BAD_DATA)


## Every peer, the host too (CompanyNet._apply_state()): a layout event in place with the same calls
## on every peer, then the navigation rebaked. Checked only as data (rule 6): a placeable of the
## catalog, ints in range, a uid that names a piece (or, placing, a free one), money for the price.
## False, changing nothing, when it doesn't fit.
func apply(state: Object, kind: StringName, data: Dictionary) -> bool:
	if state == null or not is_instance_valid(state):
		push_warning("CompanyLayoutNet: a %s event but no company here" % kind)
		return false
	var applied: bool = false
	match kind:
		PLACED:
			applied = _apply_placed(state, data)
		MOVED:
			applied = _apply_moved(state, data)
		SOLD:
			applied = _apply_sold(state, data)
	if applied:
		rebake(state)
	return applied


## The navigation (if any) from the layout as it stands: after every applied event and after a
## snapshot replaced the layout.
func rebake(state: Object) -> void:
	if navigation != null:
		navigation.rebake(WarehouseStages.grid_size_for(int(state.get(&"warehouse_stage"))), state.layout)


## Index of the piece called `uid` in `layout`, -1 when none is (or `uid` is not text).
static func piece_index(layout: Array, uid: Variant) -> int:
	if not CompanyAsk.is_id(uid):
		return -1
	for index: int in layout.size():
		if DefaultShed.piece_uid(layout, index) == StringName(uid):
			return index
	return -1


## A name no piece of `layout` has: "<id>_<n>" with the lowest n from 1.
static func new_uid(layout: Array, id: StringName) -> StringName:
	var taken: Dictionary = {}
	for index: int in layout.size():
		taken[DefaultShed.piece_uid(layout, index)] = true
	var n: int = 1
	while taken.has(StringName("%s_%d" % [id, n])):
		n += 1
	return StringName("%s_%d" % [id, n])


## Stores the derived name of every piece that has no uid. All names are worked out first: storing
## one changes how the next is counted (DefaultShed.piece_uid()). Peers holding the same layout at
## the same seq store the same names.
static func stamp_uids(layout: Array) -> void:
	var names: Array[StringName] = []
	for index: int in layout.size():
		names.append(DefaultShed.piece_uid(layout, index))
	for index: int in layout.size():
		if str(layout[index].get("uid", "")) == "":
			layout[index]["uid"] = String(names[index])


## True while the piece `uid` holds units under its name: a shelf slot (shelf:<uid>_<slot>) or a
## packing table (table:<uid>, the contract's rule 4).
static func holds_units(stock: Inventory, uid: StringName, def: PlaceableDefinition) -> bool:
	if stock == null:
		return false
	var places: Array[StringName] = [StringName("table:%s" % uid)]
	for slot: int in range(def.slots):
		places.append(DefaultShed.shelf_location(uid, slot))
	for place: StringName in places:
		if not stock.contents_at(place).is_empty():
			return true
	return false


## A placeable id that came over the network names an object of the catalog: exactly the name of
## one of its files, never a path (like CompanyAsk.product_exists()).
static func placeable_exists(id: Variant) -> bool:
	if not CompanyAsk.is_id(id):
		return false
	if not _catalog_read:
		_catalog_read = true
		for file: String in ResourceLoader.list_directory(PlaceableShop.DEFINITIONS_DIR):
			if file.ends_with(".tres") or file.ends_with(".res"):
				_known[StringName(file.get_basename())] = true
	return _known.has(StringName(id))


func _check_place(state: Object, data: Dictionary) -> Dictionary:
	var id: Variant = data.get("id")
	var turns: Variant = data.get("turns", 0)
	if not (placeable_exists(id) and _cell_ok(data.get("x")) and _cell_ok(data.get("z")) and _turns_ok(turns)):
		return _refused(REASON_BAD_DATA)
	var def: PlaceableDefinition = PlaceableShop.definition(StringName(id))
	var x: int = data["x"]
	var z: int = data["z"]
	var result: Dictionary = placement_for(state).preview(state.layout, def, x, z, turns, int(state.money))
	if not bool(result["ok"]):
		return _refused(result["reason"])
	return _granted(PLACED, {
		"id": StringName(id), "x": x, "z": z, "turns": int(turns),
		"uid": new_uid(state.layout, StringName(id)), "minute": int(state.clock_minutes),
	})


## layout_move takes the corner to (x, z); layout_rotate turns it `turns` quarter turns more around
## its corner cell (BuildPlacement.rotate_piece()). Either way the same preview, ignoring the piece.
func _check_move(state: Object, kind: StringName, data: Dictionary) -> Dictionary:
	if not _uid_ok(data.get("uid")):
		return _refused(REASON_BAD_DATA)
	var index: int = piece_index(state.layout, data["uid"])
	if index < 0:
		return _refused(REASON_NO_PIECE)
	var piece: Dictionary = state.layout[index]
	var x: int = int(piece.get("x", 0))
	var z: int = int(piece.get("z", 0))
	var turns: int = posmod(int(piece.get("turns", 0)), 4)
	if kind == MOVE:
		if not (_cell_ok(data.get("x")) and _cell_ok(data.get("z"))):
			return _refused(REASON_BAD_DATA)
		x = data["x"]
		z = data["z"]
	else:
		var more: Variant = data.get("turns")
		if typeof(more) != TYPE_INT or int(more) < 1 or int(more) > 3:
			return _refused(REASON_BAD_DATA)
		turns = posmod(turns + int(more), 4)
	var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
	var result: Dictionary = placement_for(state).preview(state.layout, def, x, z, turns, -1, index)
	if not bool(result["ok"]):
		return _refused(result["reason"])
	return _granted(MOVED, {"uid": DefaultShed.piece_uid(state.layout, index), "x": x, "z": z, "turns": turns})


func _check_sell(state: Object, stock: Inventory, data: Dictionary) -> Dictionary:
	if not _uid_ok(data.get("uid")):
		return _refused(REASON_BAD_DATA)
	var index: int = piece_index(state.layout, data["uid"])
	if index < 0:
		return _refused(REASON_NO_PIECE)
	var uid: StringName = DefaultShed.piece_uid(state.layout, index)
	var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(state.layout[index].get("id", ""))))
	if def == null:
		return _refused(BuildPlacement.REASON_NO_DEFINITION)
	if holds_units(stock, uid, def):
		return _refused(REASON_NOT_EMPTY)
	return _granted(SOLD, {"uid": uid, "minute": int(state.clock_minutes)})


func _apply_placed(state: Object, data: Dictionary) -> bool:
	var id: Variant = data.get("id")
	var uid: Variant = data.get("uid")
	var turns: Variant = data.get("turns")
	if not (placeable_exists(id) and _uid_ok(uid) and _turns_ok(turns) and _minute_ok(data.get("minute"))):
		return false
	if not (_cell_ok(data.get("x")) and _cell_ok(data.get("z"))):
		return false
	var def: PlaceableDefinition = PlaceableShop.definition(StringName(id))
	if def == null or piece_index(state.layout, uid) >= 0 or not state.can_afford(def.price):
		return false
	stamp_uids(state.layout)
	_set_minute(state, data["minute"])
	if not PlaceableShop.buy(state, def, data["x"], data["z"], turns):
		return false
	state.layout[state.layout.size() - 1]["uid"] = String(uid)
	return true


func _apply_moved(state: Object, data: Dictionary) -> bool:
	var uid: Variant = data.get("uid")
	if not (_uid_ok(uid) and _cell_ok(data.get("x")) and _cell_ok(data.get("z")) and _turns_ok(data.get("turns"))):
		return false
	var index: int = piece_index(state.layout, uid)
	if index < 0:
		return false
	stamp_uids(state.layout)
	var piece: Dictionary = state.layout[index]
	piece["x"] = int(data["x"])
	piece["z"] = int(data["z"])
	piece["turns"] = int(data["turns"])
	return true


func _apply_sold(state: Object, data: Dictionary) -> bool:
	var uid: Variant = data.get("uid")
	if not (_uid_ok(uid) and _minute_ok(data.get("minute"))):
		return false
	var index: int = piece_index(state.layout, uid)
	if index < 0 or PlaceableShop.definition(StringName(str(state.layout[index].get("id", "")))) == null:
		return false
	stamp_uids(state.layout)
	_set_minute(state, data["minute"])
	return PlaceableShop.sell(state, index) >= 0


## The host's minute in this peer's company before its wallet moves (on the host, the same value).
static func _set_minute(state: Object, minute: int) -> void:
	if int(state.get(&"clock_minutes")) != minute:
		state.set(&"clock_minutes", minute)


static func _refused(reason: StringName) -> Dictionary:
	return {"reason": reason}


static func _granted(kind: StringName, data: Dictionary) -> Dictionary:
	return {"reason": &"", "kind": kind, "data": data}


static func _uid_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and not String(value).is_empty() \
		and String(value).length() <= RpcGuard.MAX_TEXT_LENGTH


static func _cell_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and absi(int(value)) <= MAX_CELL


static func _turns_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= 3


static func _minute_ok(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) < CompanyTuning.MINUTES_PER_DAY
