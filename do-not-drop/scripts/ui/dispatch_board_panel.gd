extends Control
class_name DispatchBoardPanel
## The dispatch board of the shed (expansion D-0310, "Modo Empresa").
##
## Lists the sealed boxes waiting in the dispatch zone (customer, district, weight), the vehicle
## at the yard with its slots and weight, and a "Load" button that hands the boxes the crew
## picked to that vehicle through the existing path: DispatchZone.load_boxes() ->
## CompanyTrips.stage_cargo() (D-0716 / D-0717). A box the vehicle cannot take (DispatchRules,
## D-0309) cannot be picked: its row says why. Picking more than the vehicle holds (slots,
## kg: the same checks as DispatchLoading.plan()) is refused with the reason too.
##
## Data comes in through open() / refresh() as one dictionary, no autoload is read, so the panel
## runs headless in a test:
##   zone: DispatchZone, book: OrderBook, trips: CompanyTrips, vehicle_id: StringName,
##   vehicle: VehicleDefinition (null = no vehicle at the yard), vehicle_name: String (optional),
##   box_kg: Dictionary box id -> kg, zones / gates: id -> ZoneDefinition / GateRequirement,
##   owned: CompanyState.gate_owned(), opened_gates: Array, can_act: bool (false on a client:
##   the Load button shows disabled, with the reason, not hidden).
##
## Gamepad first: rows are buttons in one focus column (ui_accept picks / drops a box), then
## Load and Close; blocked rows stay focusable so their reason can be read. Every state has a
## mark besides its colour: "✓" picked, "○" free, "✗" blocked.

## The host loaded `boxes` on `vehicle_id` (the zone and the trip gate already know). The world
## adapter replicates it to the clients.
signal loaded(vehicle_id: StringName, boxes: Array[StringName])
signal closed

const PICKED: String = "✓"
const FREE: String = "○"
const BLOCKED: String = "✗"
## Slot squares drawn at most; a vehicle with more slots shows the numbers only.
const MAX_SLOT_MARKS: int = 12

var _ctx: Dictionary = {}
var _selected: Array[StringName] = []
var _rows: Dictionary = {}
var _status_key: String = ""
var _status_args: Array = []

var _vehicle_label: Label
var _capacity_label: Label
var _slots_label: Label
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _status_label: Label
var _load_button: Button
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	hide()


## Shows the board for `ctx` (see the class doc) and takes focus.
func open(ctx: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_selected.clear()
	_clear_status()
	refresh(ctx)
	show()
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_OPEN)
	_focus_first.call_deferred()


func close() -> void:
	UiTheme.UI_SOUNDS.play(self, UiTheme.UI_SOUNDS.PANEL_CLOSE)
	hide()
	closed.emit()


## Redraws the board from `ctx`. The picks that are still waiting in the zone are kept.
func refresh(ctx: Dictionary) -> void:
	_ctx = ctx
	if _rows_box == null:
		return
	var waiting: Array[StringName] = _waiting()
	var kept: Array[StringName] = []
	for box_id: StringName in _selected:
		if waiting.has(box_id):
			kept.append(box_id)
	_selected = kept
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	if waiting.is_empty():
		UiTheme.label(_rows_box, tr("UI_DISPATCH_EMPTY"), 17, UiTheme.MUTED).name = "Empty"
	for box_id: StringName in waiting:
		var row: Button = UiTheme.button(_rows_box, "", false, Vector2(0, 52))
		row.name = "Box_%s" % box_id
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiTheme.register_font_size(row, 17)
		row.pressed.connect(toggle.bind(box_id))
		_rows[box_id] = row
	_update_view()


## Picks `box_id`, or drops it when it was picked. Returns {"ok", "key", "args"}: when not ok
## the box stays as it was and key / args say why (also shown on the board).
func toggle(box_id: StringName) -> Dictionary:
	if _selected.has(box_id):
		_selected.erase(box_id)
		_clear_status()
		_update_view()
		return {"ok": true, "key": "", "args": []}
	var verdict: Dictionary = _can_pick(box_id)
	if verdict["ok"]:
		_selected.append(box_id)
		_clear_status()
	else:
		_status_key = String(verdict["key"])
		_status_args = verdict["args"]
	_update_view()
	return verdict


## Hands the picked boxes to the vehicle: DispatchZone.load_boxes() stages them in the trip gate
## and the zone forgets them; the rest keep waiting. Returns how many went (0 when the board is
## not allowed to act, nothing is picked or there is no vehicle).
func confirm() -> int:
	if not can_confirm():
		return 0
	var zone: DispatchZone = _ctx.get("zone")
	var chosen: Array[StringName] = _selected.duplicate()
	var count: int = zone.load_boxes(_ctx.get("trips"), _vehicle_id(), chosen)
	if count <= 0:
		return 0
	_selected.clear()
	_status_key = "UI_DISPATCH_LOADED"
	_status_args = [count]
	loaded.emit(_vehicle_id(), chosen)
	refresh(_ctx)
	_focus_first()
	return count


## True when Load would do something: the board may act, a vehicle is there and a box is picked.
func can_confirm() -> bool:
	return _acts() and _ctx.get("vehicle") != null and _ctx.get("zone") != null and not _selected.is_empty()


func selected() -> Array[StringName]:
	return _selected.duplicate()


func row_button(box_id: StringName) -> Button:
	return _rows.get(box_id)


func load_button() -> Button:
	return _load_button


func close_button() -> Button:
	return _close_button


## The line under the list: the last refusal, "loaded N", or the reason Load is off.
func status_text() -> String:
	return _status_label.text if _status_label != null else ""


## Translated "key % args", tolerant of a key that takes fewer values than it was given.
static func reason_text(key: String, args: Array) -> String:
	var text: String = TranslationServer.translate(key)
	var needed: int = text.count("%")
	if needed == 0:
		return text
	var values: Array = args.duplicate()
	while values.size() < needed:
		values.append("")
	return text % values.slice(0, needed)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = UiTheme.panel(center, Vector2(700, 0), 22)
	column.add_theme_constant_override("separation", 8)
	UiTheme.title(column, tr("UI_DISPATCH_TITLE"), 34)
	_vehicle_label = UiTheme.label(column, "", 19, UiTheme.INK, true)
	_vehicle_label.name = "Vehicle"
	_capacity_label = UiTheme.label(column, "", 16, UiTheme.MUTED)
	_capacity_label.name = "Capacity"
	_slots_label = UiTheme.label(column, "", 20, UiTheme.INK)
	_slots_label.name = "Slots"
	UiTheme.label(column, tr("UI_DISPATCH_HINT"), 15, UiTheme.MUTED)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 250)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows_box)
	_status_label = UiTheme.label(column, "", 16, UiTheme.ORANGE)
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_load_button = UiTheme.button(buttons, tr("UI_DISPATCH_LOAD"), true)
	_load_button.name = "Load"
	_load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_button.pressed.connect(confirm)
	_close_button = UiTheme.button(buttons, tr("UI_DISPATCH_CLOSE"))
	_close_button.name = "Close"
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(close)


## Texts, marks, the Load button and the focus chain from the current picks.
func _update_view() -> void:
	var vehicle: VehicleDefinition = _ctx.get("vehicle")
	var slots: int = vehicle.cargo_slots if vehicle != null else 0
	var max_kg: float = vehicle.cargo_kg if vehicle != null else 0.0
	var kg: float = _selected_kg()
	if vehicle == null:
		_vehicle_label.text = tr("UI_DISPATCH_NO_VEHICLE")
		_capacity_label.text = ""
		_slots_label.text = ""
	else:
		_vehicle_label.text = tr("UI_DISPATCH_VEHICLE") % _vehicle_name(vehicle)
		_capacity_label.text = tr("UI_DISPATCH_CAPACITY") % [_selected.size(), slots, kg, max_kg]
		_slots_label.text = _slot_marks(_selected.size(), slots)
	for box_id: StringName in _rows:
		var row: Button = _rows[box_id]
		var verdict: Dictionary = _rules_verdict(box_id)
		var mark: String = PICKED if _selected.has(box_id) else FREE
		var line: String = tr("UI_DISPATCH_ROW") % [_customer(box_id), _zone_name(box_id), _kg_of(box_id)]
		if not verdict["ok"]:
			mark = BLOCKED
			line += "\n" + reason_text(String(verdict["key"]), verdict["args"])
		row.text = "%s  %s" % [mark, line]
	_load_button.disabled = not can_confirm()
	_load_button.text = tr("UI_DISPATCH_LOAD")
	if not _selected.is_empty():
		_load_button.text = tr("UI_DISPATCH_LOAD_N") % _selected.size()
	_status_label.text = _status_line()
	_link_focus()


func _status_line() -> String:
	if _status_key != "":
		return reason_text(_status_key, _status_args)
	if not _acts():
		return tr("UI_DISPATCH_HOST_ONLY")
	if _ctx.get("vehicle") == null:
		return ""
	if _rows.size() > 0 and _selected.is_empty():
		return tr("UI_DISPATCH_PICK")
	return ""


## Focus column: rows top to bottom, then Load (when on) and Close. Horizontal moves stay put.
func _link_focus() -> void:
	var chain: Array[Control] = []
	for box_id: StringName in _waiting():
		if _rows.has(box_id):
			chain.append(_rows[box_id])
	var last_row: Control = chain.back() if not chain.is_empty() else null
	if not _load_button.disabled:
		chain.append(_load_button)
	chain.append(_close_button)
	for i: int in chain.size():
		var node: Control = chain[i]
		node.focus_neighbor_top = node.get_path_to(chain[maxi(i - 1, 0)])
		node.focus_neighbor_bottom = node.get_path_to(chain[mini(i + 1, chain.size() - 1)])
		node.focus_neighbor_left = node.get_path_to(node)
		node.focus_neighbor_right = node.get_path_to(node)
	if not _load_button.disabled:
		_load_button.focus_neighbor_right = _load_button.get_path_to(_close_button)
		_close_button.focus_neighbor_left = _close_button.get_path_to(_load_button)
		if last_row != null:
			_close_button.focus_neighbor_top = _close_button.get_path_to(last_row)


func _focus_first() -> void:
	var waiting: Array[StringName] = _waiting()
	if not waiting.is_empty() and _rows.has(waiting[0]):
		(_rows[waiting[0]] as Button).grab_focus()
	else:
		_close_button.grab_focus()


func _can_pick(box_id: StringName) -> Dictionary:
	var vehicle: VehicleDefinition = _ctx.get("vehicle")
	if vehicle == null:
		return {"ok": false, "key": "UI_DISPATCH_NO_VEHICLE", "args": []}
	var verdict: Dictionary = _rules_verdict(box_id)
	if not verdict["ok"]:
		return verdict
	if _selected.size() >= vehicle.cargo_slots:
		return {"ok": false, "key": DispatchLoading.NO_SLOTS, "args": [vehicle.cargo_slots]}
	if _selected_kg() + _kg_of(box_id) > vehicle.cargo_kg:
		return {"ok": false, "key": DispatchLoading.NO_WEIGHT, "args": [vehicle.cargo_kg]}
	return {"ok": true, "key": "", "args": []}


func _rules_verdict(box_id: StringName) -> Dictionary:
	var vehicle: VehicleDefinition = _ctx.get("vehicle")
	if vehicle == null:
		return {"ok": false, "key": "UI_DISPATCH_NO_VEHICLE", "args": []}
	var book: OrderBook = _ctx.get("book")
	var order: Dictionary = book.get_order(_order_of(box_id)) if book != null else {}
	return DispatchRules.check_order(
		order, vehicle, _ctx.get("zones", {}), _ctx.get("gates", {}), _ctx.get("owned", {}),
		_ctx.get("opened_gates", [])
	)


func _waiting() -> Array[StringName]:
	var zone: DispatchZone = _ctx.get("zone")
	return zone.boxes() if zone != null else ([] as Array[StringName])


func _order_of(box_id: StringName) -> StringName:
	var zone: DispatchZone = _ctx.get("zone")
	return zone.order_of(box_id) if zone != null else &""


func _vehicle_id() -> StringName:
	return StringName(_ctx.get("vehicle_id", &""))


func _acts() -> bool:
	return bool(_ctx.get("can_act", true))


func _kg_of(box_id: StringName) -> float:
	return float((_ctx.get("box_kg", {}) as Dictionary).get(box_id, 0.0))


func _selected_kg() -> float:
	var kg: float = 0.0
	for box_id: StringName in _selected:
		kg += _kg_of(box_id)
	return kg


func _customer(box_id: StringName) -> String:
	var book: OrderBook = _ctx.get("book")
	if book == null:
		return str(_order_of(box_id))
	return str(book.get_order(_order_of(box_id)).get("customer", _order_of(box_id)))


func _zone_name(box_id: StringName) -> String:
	var book: OrderBook = _ctx.get("book")
	var zone_id: StringName = &""
	if book != null:
		zone_id = StringName(book.get_order(_order_of(box_id)).get("zone", ""))
	var zone: ZoneDefinition = (_ctx.get("zones", {}) as Dictionary).get(zone_id)
	if zone != null and zone.display_key != "":
		var text: String = TranslationServer.translate(zone.display_key)
		if text != zone.display_key:
			return text
	return String(zone_id).capitalize()


func _vehicle_name(vehicle: VehicleDefinition) -> String:
	var given: String = String(_ctx.get("vehicle_name", ""))
	return given if given != "" else String(vehicle.id).capitalize()


## "■ ■ □ □" for 2 of 4 slots used: the fill reads by shape, not by colour.
static func _slot_marks(used: int, total: int) -> String:
	if total > MAX_SLOT_MARKS:
		return "%d / %d" % [used, total]
	var marks: PackedStringArray = []
	for i: int in total:
		marks.append("■" if i < used else "□")
	return " ".join(marks)


func _clear_status() -> void:
	_status_key = ""
	_status_args = []


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
