class_name ShedIndicators
extends Node3D
## Indicators in the shed (expansion D-1907, diseno/referencias-logistica.md §3: "the delay is told in the
## world, over the station, before it costs"): a bobbing arrow with a short line over the piece that needs
## someone. Drawn on every peer from what every peer already has (the shed's tables and the order book), never
## sent; it reads them every SCAN_SECONDS.
##
## - A packing table low on a supply (PackingStation.supplies.low_kinds(): tape, filler, boxes) gets an orange
##   arrow: "Faltan insumos".
## - A dispatch zone gets a red arrow while orders are late (open orders past their due_min): "N atrasados".
## Nothing needed, no arrow; an arrow goes when its need is gone.

const SCAN_SECONDS: float = 0.5
## Height of the arrow over the floor, and how far it bobs.
const HEIGHT_M: float = 2.3
const BOB_M: float = 0.12
const BOB_HZ: float = 1.2
const KIND_SUPPLIES: StringName = &"supplies"
const KIND_LATE: StringName = &"late"
const KEY_SUPPLIES: String = "WORLD_INDICATOR_SUPPLIES"
const KEY_LATE: String = "WORLD_INDICATOR_LATE"
const ARROW: String = "▼"

## () -> Array: the shed's pieces ({uid, id, rect}); () -> Dictionary: uid -> PackingStation;
## (id) -> StringName: a piece's role; (uid) -> Vector3: where a piece stands (local to this node);
## () -> Array: the open orders; () -> float: the game minute now.
var pieces_of: Callable = func() -> Array: return []
var stations_of: Callable = func() -> Dictionary: return {}
var role_of: Callable = func(_id: StringName) -> StringName: return &""
var spot_of: Callable = func(_uid: StringName) -> Vector3: return Vector3.ZERO
var orders_of: Callable = func() -> Array: return []
var minute_of: Callable = func() -> float: return 0.0

## uid -> Label3D shown.
var _marks: Dictionary = {}
var _wait: float = 0.0
var _time: float = 0.0


## The indicators under `root`'s shed (CompanyRoot: shed, net, clock).
static func add_to(root: Node) -> ShedIndicators:
	var shed: Node3D = root.get(&"shed")
	var indicators := ShedIndicators.new()
	indicators.name = "ShedIndicators"
	if shed == null:
		root.add_child(indicators)
		return indicators
	# A redraw of the shed keeps the nodes of this group (CompanyShed.OVERLAY_GROUP).
	indicators.add_to_group(CompanyShed.OVERLAY_GROUP)
	shed.add_child(indicators)
	indicators.pieces_of = func() -> Array: return shed.get(&"pieces")
	indicators.stations_of = func() -> Dictionary: return shed.get(&"stations")
	indicators.role_of = func(id: StringName) -> StringName:
		var def: PlaceableDefinition = PlaceableShop.definition(id)
		return def.role if def != null else &""
	indicators.spot_of = func(uid: StringName) -> Vector3:
		for piece: Dictionary in shed.get(&"pieces"):
			if piece.get("uid") == uid:
				var rect: Rect2i = piece.get("rect", Rect2i())
				return shed.call(&"cell_to_local", Vector2(rect.position) + Vector2(rect.size) * 0.5)
		return Vector3.ZERO
	var net: Object = root.get(&"net")
	var clock: Object = root.get(&"clock")
	if net != null:
		indicators.orders_of = func() -> Array: return net.orders.book.open_orders() if net.orders != null else []
	if clock != null:
		indicators.minute_of = func() -> float: return clock.minute_now()
	return indicators


func _process(delta: float) -> void:
	_time += delta
	_wait -= delta
	if _wait <= 0.0:
		_wait = SCAN_SECONDS
		refresh()
	for uid: StringName in _marks:
		var mark: Label3D = _marks[uid]
		mark.position.y = HEIGHT_M + sin(_time * TAU * BOB_HZ) * BOB_M


## What needs someone now: [{uid, kind, count}], tables first in piece order, then dispatch zones.
func needs() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var stations: Dictionary = stations_of.call()
	var late: int = CompanyDayHud.late_count(orders_of.call(), float(minute_of.call()))
	for raw: Variant in pieces_of.call():
		if not raw is Dictionary:
			continue
		var piece: Dictionary = raw
		var uid := StringName(str(piece.get("uid", "")))
		var role: StringName = role_of.call(StringName(str(piece.get("id", ""))))
		if role == &"assembly" and stations.get(uid) is PackingStation:
			var low: Array[StringName] = (stations[uid] as PackingStation).supplies.low_kinds()
			if not low.is_empty():
				found.append({"uid": uid, "kind": KIND_SUPPLIES, "count": low.size()})
		elif role == &"dispatch" and late > 0:
			found.append({"uid": uid, "kind": KIND_LATE, "count": late})
	return found


## Draws the arrows of needs(): one per piece, gone when its need is.
func refresh() -> void:
	var wanted: Dictionary = {}
	for need: Dictionary in needs():
		wanted[need["uid"]] = need
	for uid: StringName in _marks.keys():
		if not wanted.has(uid):
			(_marks[uid] as Node).queue_free()
			_marks.erase(uid)
	for uid: StringName in wanted:
		var need: Dictionary = wanted[uid]
		var mark: Label3D = _marks.get(uid)
		if mark == null:
			mark = _new_mark(uid)
			_marks[uid] = mark
		var spot: Vector3 = spot_of.call(uid)
		mark.position = Vector3(spot.x, HEIGHT_M, spot.z)
		mark.text = "%s\n%s" % [line_of(need), ARROW]
		mark.modulate = UiTheme.ORANGE if need["kind"] == KIND_SUPPLIES else UiTheme.RED


## The arrow's line in the current language.
func line_of(need: Dictionary) -> String:
	if need.get("kind") == KIND_LATE:
		return tr(KEY_LATE) % int(need.get("count", 0))
	return tr(KEY_SUPPLIES)


## uid -> the line shown, for a test.
func shown() -> Dictionary:
	var out: Dictionary = {}
	for uid: StringName in _marks:
		out[uid] = (_marks[uid] as Label3D).text
	return out


func _new_mark(uid: StringName) -> Label3D:
	var mark := Label3D.new()
	mark.name = "Need_%s" % uid
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = false
	mark.pixel_size = 0.006
	mark.font_size = 64
	mark.outline_size = 14
	mark.outline_modulate = UiTheme.INK
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(mark)
	return mark
