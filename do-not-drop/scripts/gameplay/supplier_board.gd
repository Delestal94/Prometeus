class_name SupplierBoard
extends Node
## Opens the supplier order screen (SupplierOrderPanel, D-0603.b) in the company's world and sends its
## order to the host (expansion D-0603.b.2).
##
## The shed's supplier board (SupplierBoardPoint, CompanyShed.supplier_board_opened) opens it on the
## screen of whoever used it, on any peer. "Order" never writes the calendar here: the panel's
## `request` asks CompanyNet for a supplier_order with the cart's lines, the host (solo too) checks it
## (CompanySupplierNet) and publishes supplier_ordered, which every peer applies to its calendar. The
## panel waits for that event, the one that names this peer (placed()), or for the refusal
## (CompanyNet.request_rejected, shown with its reason, refused()). The wallet and the day it shows are
## this peer's copy of the company (the host's, by snapshot, on a client): the host checks again.
##
## While it is open the mouse is free and the local player's input is off, as the stock list does
## (StockBoard, D-0612.b); closing it gives both back. Every event and snapshot rewrites its totals, day
## and Order (money and the day may have changed) without rebuilding the rows, so the focus stays.

## Reason of a refusal (CompanyNet / CompanySupplierNet) -> translation key of the line under the list.
const REASON_KEYS: Dictionary = {
	CompanySupplierNet.REASON_NO_FUNDS: "UI_SUPPLIER_NO_FUNDS",
	CompanySupplierNet.REASON_DAY_CLOSED: "UI_SUPPLIER_DAY_CLOSED",
	CompanySupplierNet.REASON_TOO_MUCH: "UI_SUPPLIER_TOO_MUCH",
}

var panel: SupplierOrderPanel
var net: CompanyNet
## What this peer's screen is filling in; kept between openings.
var cart: SupplierOrderCart = SupplierOrderCart.new()
var supplier_name: String = ""
## Returns the local player (or null); its input is off while the screen is open.
var player_of: Callable = Callable()
## Returns true while something else owns the screen (the build mode).
var busy: Callable = Callable()

## The request awaited (CompanyNet.request()'s id, 0 for none) and the total it was sent with.
var _pending_rid: int = 0
var _pending_total: int = 0
## True inside send(): a host answers its own request before request() returns.
var _sending: bool = false
var _answered: bool = false
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_off: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		var key: String = "UI_SUPPLIER_NAME_%s" % String(seller.id).to_upper()
		supplier_name = tr(key) if tr(key) != key else String(seller.id)
	if net == null:
		return
	net.event_applied.connect(_on_event_applied)
	net.company_state_restored.connect(_on_restored)
	net.request_rejected.connect(_on_rejected)


func is_open() -> bool:
	return panel != null and panel.visible


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
	_pending_rid = 0
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
		"day": int(company.get("day")) if company != null else CompanyTuning.STARTING_DAY,
		"supplier_name": supplier_name, "can_act": true, "request": send,
	}


## The panel's `request`: asks the host for an order of `lines` (CompanySupplierNet.ORDER) and returns
## the request id (0 when nobody could be asked or the lines do not make an order).
func send(lines: Array[Dictionary]) -> int:
	var data: Dictionary = CompanySupplierNet.request_data(lines)
	if net == null or data.is_empty():
		return 0
	_pending_total = cart.total()
	_answered = false
	_sending = true
	var rid: int = net.request(CompanySupplierNet.ORDER, data)
	_sending = false
	_pending_rid = 0 if _answered else rid
	return rid


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	var awaited: bool = _sending or _pending_rid != 0
	if kind == CompanySupplierNet.ORDERED and awaited and int(data.get("peer", 0)) == _my_id():
		_pending_rid = 0
		_answered = true
		panel.placed(SupplierSchedule.arrival_day(int(data.get("order_day", 0))))
	elif is_open():
		panel.update_totals(context())


func _on_restored(_snapshot_seq: int) -> void:
	if is_open():
		panel.update_totals(context())


func _on_rejected(rid: int, reason: StringName) -> void:
	if not _sending and (rid == 0 or rid != _pending_rid):
		return
	_pending_rid = 0
	_answered = true
	var key: String = String(REASON_KEYS.get(reason, "UI_SUPPLIER_REFUSED"))
	panel.refused(key, [_pending_total] if reason == CompanySupplierNet.REASON_NO_FUNDS else [])


func _my_id() -> int:
	return multiplayer.get_unique_id() if is_inside_tree() and multiplayer != null else 1


func _on_closed() -> void:
	Input.mouse_mode = _mouse_before
	if _player_off != null and is_instance_valid(_player_off):
		_player_off.set_process_unhandled_input(true)
	_player_off = null
