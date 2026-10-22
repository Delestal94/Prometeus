class_name StockBoard
extends Node
## Opens the stock list (StockPanel, D-0612) in the company's world and keeps it up to date.
##
## One key (I) or the gamepad's d-pad right toggles it, same as the build mode's actions are
## registered in code. While it is open the mouse is free and the local player's input is off; closing
## it gives both back. Every change the net applies (units moved, snapshot) redraws the list from this
## peer's own copy of the Inventory, so a client sees what the host sees.
##
## The "missing for pending orders" marks (StockAlert) need the order book, which is the host's
## until D-0813.1: a client lists its units without marks. The units already ordered from a supplier
## count as "on the way" only when the supplier calendar holds real orders: the stand-in calendar
## (CompanyRoot._seed_stand_in_calendar) brings nothing, so it is not counted.

const ACTION_TOGGLE: StringName = &"company_stock"

var panel: StockPanel
var net: CompanyNet
## Returns the OrderBook to read (the host's), or null.
var book_of: Callable = Callable()
var schedule: SupplierSchedule
## False while the calendar is the stand-in one: nothing is "on the way" then.
var real_calendar: bool = false
## id -> ProductDefinition, only for the names.
var products: Dictionary = {}
## Returns the local player (or null); its input is off while the list is open.
var player_of: Callable = Callable()
## Returns true while something else owns the screen (the build mode).
var busy: Callable = Callable()

var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_off: Node = null


## Registers the action (once): keyboard and gamepad.
static func ensure_action() -> void:
	if InputMap.has_action(ACTION_TOGGLE):
		return
	InputMap.add_action(ACTION_TOGGLE, 0.5)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_I
	InputMap.action_add_event(ACTION_TOGGLE, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_RIGHT
	InputMap.action_add_event(ACTION_TOGGLE, pad)


## The data StockPanel shows, from what this peer holds. `incoming` is product -> units ordered from a
## supplier for the days from `from_day` on (counted only when `real_calendar`).
static func context(
	inventory: Inventory, book: OrderBook, incoming: Dictionary, defs: Dictionary
) -> Dictionary:
	var shortages: Array[Dictionary] = []
	if inventory != null and book != null:
		shortages = StockAlert.shortages(inventory, book.open_orders(), incoming)
	return {"inventory": inventory, "shortages": shortages, "products": defs}


## Units ordered per product on the calendar from `from_day` on.
static func incoming_from(schedule_in: SupplierSchedule, from_day: int) -> Dictionary:
	var out: Dictionary = {}
	if schedule_in == null:
		return out
	for day: int in schedule_in.upcoming_days(from_day):
		var ordered: Dictionary = schedule_in.ordered_for(day)
		for product: StringName in ordered:
			out[product] = int(out.get(product, 0)) + int(ordered[product])
	return out


func _ready() -> void:
	ensure_action()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "StockLayer"
	add_child(layer)
	panel = StockPanel.new()
	panel.name = "StockPanel"
	layer.add_child(panel)
	panel.closed.connect(_on_closed)


func setup(company_net: CompanyNet) -> void:
	net = company_net
	if net != null and not net.event_applied.is_connected(_on_event_applied):
		net.event_applied.connect(_on_event_applied)
		net.company_state_restored.connect(_on_restored)


func is_open() -> bool:
	return panel != null and panel.visible


## Opens the list. False when nothing owns a stock yet or the screen is taken.
func open() -> bool:
	if panel == null or net == null or is_open():
		return false
	if busy.is_valid() and bool(busy.call()):
		return false
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node = player_of.call() as Node if player_of.is_valid() else null
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(false)
		_player_off = player
	panel.open(_context())
	return true


func close() -> void:
	if is_open():
		panel.close()


func _context() -> Dictionary:
	var book: OrderBook = book_of.call() as OrderBook if book_of.is_valid() else null
	var incoming: Dictionary = {}
	if real_calendar and net != null and net.company != null:
		incoming = incoming_from(schedule, int(net.company.get("day")))
	return context(net.inventory if net != null else null, book, incoming, products)


func _refresh() -> void:
	if is_open():
		panel.refresh(_context())


func _on_event_applied(_seq: int, _kind: StringName, _data: Dictionary) -> void:
	_refresh()


func _on_restored(_snapshot_seq: int) -> void:
	_refresh()


func _on_closed() -> void:
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION_TOGGLE):
		return
	if is_open():
		close()
	else:
		open()
	get_viewport().set_input_as_handled()
