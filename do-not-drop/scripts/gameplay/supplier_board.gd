class_name SupplierBoard
extends Node
## Opens the supplier order screen (SupplierOrderPanel, D-0603.b) in the company's world and sends its
## order to the host (expansion D-0603.b.2).
##
## The shed's supplier board (SupplierBoardPoint, CompanyShed.supplier_board_opened) opens it on the
## screen of whoever used it, on any peer. "Order" never writes the calendar here: the panel's
## `request` asks CompanyNet for a supplier_order with the cart's lines, the host (solo too) checks it
## (CompanySupplierNet) and publishes supplier_ordered, which every peer applies to its calendar. The
## panel waits for the answer:
##   - the event that names this peer: placed();
##   - the refusal (CompanyNet.request_rejected): refused() with its reason;
##   - a snapshot that covers the event (a resync while it was held, so it never fires event_applied
##     here): placed() when the calendar of the arrival day grew by the lines sent, else refused();
##   - nothing within ANSWER_TIMEOUT_MSEC (the host dropped the request, which tells nobody): refused().
## The wallet and the day it shows are this peer's copy of the company (the host's, by snapshot, on a
## client): the host checks again.
##
## While it is open the mouse is free and the local player's input is off; closing it gives both back.
## The build mode does not start while it is open (CompanyRoot hands ShedBuilder.busy is_open()), nor it
## while the mode is on (`busy`). Every event and snapshot rewrites its totals, day and Order (money and
## the day may have changed) without rebuilding the rows, so the focus stays.

## Reason of a refusal (CompanyNet / CompanySupplierNet) -> translation key of the line under the list.
const REASON_KEYS: Dictionary = {
	CompanySupplierNet.REASON_NO_FUNDS: "UI_SUPPLIER_NO_FUNDS",
	CompanySupplierNet.REASON_DAY_CLOSED: "UI_SUPPLIER_DAY_CLOSED",
	CompanySupplierNet.REASON_TOO_MUCH: "UI_SUPPLIER_TOO_MUCH",
}
## Supplier id -> translation key of its name (a supplier without one shows its id).
const NAME_KEYS: Dictionary = {
	&"distribuidora_central": "UI_SUPPLIER_NAME_DISTRIBUIDORA_CENTRAL",
}
## How long an order waits for the host's answer before the screen gives up on it.
const ANSWER_TIMEOUT_MSEC: int = 5000

var panel: SupplierOrderPanel
var net: CompanyNet
## What this peer's screen is filling in; kept between openings.
var cart: SupplierOrderCart = SupplierOrderCart.new()
var supplier_name: String = ""
## Returns the local player (or null); its input is off while the screen is open.
var player_of: Callable = Callable()
## Returns true while something else owns the screen (the build mode).
var busy: Callable = Callable()

## The order awaited: CompanyNet.request()'s id (0 for none), when it was sent (msec), the lines and total
## it was sent with, the day its truck comes and what that truck carried before ({product: units}).
var _pending_rid: int = 0
var _sent_msec: int = 0
var _sent_lines: Array[Dictionary] = []
var _sent_total: int = 0
var _sent_arrival: int = 0
var _sent_before: Dictionary = {}
## True inside send(): a host answers its own request before request() returns.
var _sending: bool = false
var _answered: bool = false
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_off: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	var layer := CanvasLayer.new()
	layer.name = "SupplierOrderLayer"
	add_child(layer)
	panel = SupplierOrderPanel.new()
	panel.name = "SupplierOrderPanel"
	layer.add_child(panel)
	panel.closed.connect(_on_closed)


## Hooks the screen to `company_net` and the supplier `seller` with the catalog `defs` (product id ->
## ProductDefinition), the ones the host checks with.
func setup(company_net: CompanyNet, seller: SupplierDefinition, defs: Dictionary) -> void:
	net = company_net
	cart.supplier = seller
	cart.products = defs
	if seller != null:
		supplier_name = tr(NAME_KEYS[seller.id]) if NAME_KEYS.has(seller.id) else String(seller.id)
	if net == null:
		return
	net.event_applied.connect(_on_event_applied)
	net.company_state_restored.connect(_on_restored)
	net.request_rejected.connect(_on_rejected)


func is_open() -> bool:
	return panel != null and panel.visible


## True while an order sent waits for the host's answer.
func is_pending() -> bool:
	return _pending_rid != 0


## Opens the screen. False when there is no CompanyNet, it is already open or the screen is taken.
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
	panel.open(context())
	return true


func close() -> void:
	if is_open():
		panel.close()


## The panel's data from this peer's copy: the cart, the wallet and day of the company, the calendar,
## and the request that sends the order to the host.
func context() -> Dictionary:
	var company: Object = net.company if net != null else null
	return {
		"cart": cart, "wallet": company, "schedule": net.supplier.schedule if net != null else null,
		"day": _day(), "supplier_name": supplier_name, "can_act": true, "request": send,
	}


## The panel's `request`: asks the host for an order of `lines` (CompanySupplierNet.ORDER) and returns
## the request id (0 when nobody could be asked or the lines do not make an order).
func send(lines: Array[Dictionary]) -> int:
	var data: Dictionary = CompanySupplierNet.request_data(lines)
	if net == null or data.is_empty():
		return 0
	_sent_lines = lines.duplicate(true)
	_sent_total = cart.total()
	_sent_arrival = SupplierSchedule.arrival_day(_day())
	_sent_before = net.supplier.schedule.ordered_for(_sent_arrival)
	_sent_msec = Time.get_ticks_msec()
	_answered = false
	_sending = true
	var rid: int = net.request(CompanySupplierNet.ORDER, data)
	_sending = false
	_pending_rid = 0 if _answered else rid
	set_process(is_pending())
	return rid


## While an order waits: gives up on it once ANSWER_TIMEOUT_MSEC passed since it was sent (`now_msec` is
## Time.get_ticks_msec(), or a clock a test drives). True when it gave up.
func poll_answer(now_msec: int) -> bool:
	if not is_pending() or now_msec - _sent_msec < ANSWER_TIMEOUT_MSEC:
		return false
	_settle()
	panel.refused("UI_SUPPLIER_REFUSED")
	return true


func _process(_delta: float) -> void:
	poll_answer(Time.get_ticks_msec())


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	var awaited: bool = _sending or is_pending()
	if kind == CompanySupplierNet.ORDERED and awaited and int(data.get("peer", 0)) == _my_id():
		_settle()
		_answered = true
		panel.placed(SupplierSchedule.arrival_day(int(data.get("order_day", 0))))
	elif is_open():
		panel.update_totals(context())


## A snapshot replaced the calendar. An order still awaited is settled against it: its event may be one
## the snapshot covered (held while this peer resynced), which never comes as event_applied.
func _on_restored(_snapshot_seq: int) -> void:
	if is_pending():
		var arrival: int = _sent_arrival
		var grew: bool = _calendar_took_order()
		_settle()
		if grew:
			panel.placed(arrival)
		else:
			panel.refused("UI_SUPPLIER_REFUSED")
	if is_open():
		panel.update_totals(context())


func _on_rejected(rid: int, reason: StringName) -> void:
	if not _sending and (rid == 0 or rid != _pending_rid):
		return
	var total: int = _sent_total
	_settle()
	_answered = true
	var key: String = String(REASON_KEYS.get(reason, "UI_SUPPLIER_REFUSED"))
	panel.refused(key, [total] if reason == CompanySupplierNet.REASON_NO_FUNDS else [])


## True when the truck of the order's day now carries, for every line sent, at least what it carried
## before plus that line.
func _calendar_took_order() -> bool:
	var now: Dictionary = net.supplier.schedule.ordered_for(_sent_arrival)
	for line: Dictionary in _sent_lines:
		var product := StringName(line["product"])
		if int(now.get(product, 0)) < int(_sent_before.get(product, 0)) + int(line["qty"]):
			return false
	return not _sent_lines.is_empty()


## No order awaited any more.
func _settle() -> void:
	_pending_rid = 0
	_sent_lines = []
	set_process(false)


func _day() -> int:
	var company: Object = net.company if net != null else null
	return int(company.get("day")) if company != null else CompanyTuning.STARTING_DAY


func _my_id() -> int:
	return multiplayer.get_unique_id() if is_inside_tree() and multiplayer != null else 1


func _on_closed() -> void:
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null
