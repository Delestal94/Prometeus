class_name StockBoard
extends Node
## Opens the stock list (StockPanel, D-0612) in the company's world and keeps it up to date.
##
## One key (I) or the gamepad's d-pad right toggles it, same as the build mode's actions are
## registered in code. While it is open the mouse is free and the local player's input is off; closing
## it gives both back. Every change the net applies (units moved, snapshot) redraws the list from this
## peer's own copy of the Inventory, so a client sees what the host sees; a cart that rolls does not.
##
## The "missing for pending orders" marks (StockAlert) read the order book every peer shares
## (CompanyNet.orders.book, D-0813.1), so a client marks the same as the host; without a book (book_of
## unset or null) the list has no marks. With only_today (CompanyRoot) only today's pending orders
## count: nothing closes an order of that book yet (D-0815.b, D-0302), so past days' pile up there.
## The units already ordered from a supplier count as "on the way" when `real_calendar` (CompanyRoot sets
## it: since D-0603.b.2 the calendar holds only real orders, by CompanyNet on every peer).
##
## In the company's world the list is the Stock sheet of the clipboard (CompanyClipboard, D-1902): `sheet_mode`
## stops this board listening to its key and show_sheet() / hide_sheet() draw the list (embedded) with no screen
## of its own; the board stays the sheet's source of data and keeps it up to date.

const ACTION_TOGGLE: StringName = &"company_stock"
## Events that change nothing the list shows (where a picking cart stands): no redraw for them.
const IGNORED_EVENTS: Array[StringName] = [CompanyCarts.MOVED]

var panel: StockPanel
var net: CompanyNet
## Returns the OrderBook to read (CompanyRoot: the shared one, CompanyNet.orders.book), or null.
var book_of: Callable = Callable()
## Only the orders of the company's day (OrderGenerator.is_of_day()) count for the marks.
var only_today: bool = false
var schedule: SupplierSchedule
## True when the calendar holds real orders (CompanyRoot, D-0603.b.2); false counts nothing "on the way".
var real_calendar: bool = false
## id -> ProductDefinition, only for the names.
var products: Dictionary = {}
## Returns the local player (or null); its input is off while the list is open.
var player_of: Callable = Callable()
## Returns true while something else owns the screen (the build mode).
var busy: Callable = Callable()
## The list is the clipboard's Stock sheet (see the class doc): the key is the clipboard's.
var sheet_mode: bool = false

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
## supplier for the days from `from_day` on (counted only when `real_calendar`). With a `day` over 0 only
## that day's pending orders count (OrderGenerator.is_of_day()).
static func context(
	inventory: Inventory, book: OrderBook, incoming: Dictionary, defs: Dictionary, day: int = 0
) -> Dictionary:
	var shortages: Array[Dictionary] = []
	if inventory != null and book != null:
		var pending: Array[Dictionary] = []
		for order: Dictionary in book.open_orders():
			if day <= 0 or OrderGenerator.is_of_day(order["id"], day):
				pending.append(order)
		shortages = StockAlert.shortages(inventory, pending, incoming)
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


## The company world's board: it marks what today's orders of the book every peer shares miss
## (CompanyNet.orders.book, D-0813.1; read only, so a client marks the same as the host; only today's
## until D-0815.b and D-0302 close orders there, or the past days' would pile up). The calendar holds
## real orders (D-0603.b.2), so what is ordered counts as on the way. Not in the tree yet.
static func for_company(company_net: CompanyNet, calendar: SupplierSchedule, player_fn: Callable,
		busy_fn: Callable) -> StockBoard:
	var board := StockBoard.new()
	board.name = "StockBoard"
	board.setup(company_net)
	board.schedule = calendar
	board.real_calendar = true
	board.book_of = func() -> OrderBook:
		return company_net.orders.book if is_instance_valid(company_net) else null
	board.only_today = true
	board.player_of = player_fn
	board.busy = busy_fn
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		board.products[id] = catalog.product(id)
	return board


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


## The clipboard shows the Stock sheet: the list drawn from this peer's copy, nothing else taken.
func show_sheet() -> void:
	if panel != null:
		panel.open(_context())


## The clipboard put the Stock sheet away (or went down): the list stops redrawing.
func hide_sheet() -> void:
	if panel != null:
		panel.hide()


func _context() -> Dictionary:
	var book: OrderBook = book_of.call() as OrderBook if book_of.is_valid() else null
	var incoming: Dictionary = {}
	if real_calendar and net != null and net.company != null:
		incoming = incoming_from(schedule, int(net.company.get("day")))
	var today: int = int(net.company.get("day")) if only_today and net != null and net.company != null else 0
	return context(net.inventory if net != null else null, book, incoming, products, today)


func _refresh() -> void:
	if is_open():
		panel.refresh(_context())


## Every applied event redraws the open list, except the ones that move no unit: a held cart rolls with a
## cart_moved every CompanyTuning.CART_GRIP_INTERVAL_S (D-0610.c2.b), and the list does not change with it.
func _on_event_applied(_seq: int, kind: StringName, _data: Dictionary) -> void:
	if IGNORED_EVENTS.has(kind):
		return
	_refresh()


func _on_restored(_snapshot_seq: int) -> void:
	_refresh()


func _on_closed() -> void:
	if sheet_mode:
		return
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null


func _unhandled_input(event: InputEvent) -> void:
	if sheet_mode or not event.is_action_pressed(ACTION_TOGGLE):
		return
	if is_open():
		close()
	else:
		open()
	get_viewport().set_input_as_handled()
