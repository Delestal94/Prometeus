class_name SupplierAutoOrderHook
extends Node
## Host: sends the automatic supplier order when the day goes to CLOSING (expansion D-0151.3b; rule in
## SupplierAutoOrder). It follows CompanyNet's day_phase events itself, so DayCycle and CompanyRoot do not
## know about it: the 20:00 transition and DayCycle.close_early() are the same event.
##
## The order is checked by CompanySupplierNet.ask() like a player's (catalog, supplier, wallet, MAX_DAY_QTY) and
## published as the same supplier_ordered every peer applies to its calendar, with peer AUTO_PEER so the day's
## summary can tell it (CompanySupplierNet.auto_units()). Once per day: a CLOSING event can repeat (the shed
## freezing or thawing is a day_phase too), and an order for tomorrow already in the calendar stops the rule.
## A client's hook does nothing.

var net: CompanyNet = null
## The last day this hook ran for.
var _done_day: int = 0


## Hooks a new hook, child of `parent`, to `company_net`'s events. Null without a CompanyNet.
static func attach(parent: Node, company_net: CompanyNet) -> SupplierAutoOrderHook:
	if parent == null or company_net == null:
		return null
	var hook := SupplierAutoOrderHook.new()
	hook.name = "SupplierAutoOrderHook"
	hook.net = company_net
	company_net.event_applied.connect(hook._on_event_applied)
	parent.add_child(hook)
	return hook


func _exit_tree() -> void:
	if net != null and is_instance_valid(net) and net.event_applied.is_connected(_on_event_applied):
		net.event_applied.disconnect(_on_event_applied)


func _on_event_applied(_seq: int, kind: StringName, data: Dictionary) -> void:
	if kind != CompanyNet.DAY_PHASE or data.get("phase") != DayCycle.PHASE_NAMES[DayCycle.Phase.CLOSING]:
		return
	var day: int = int(data.get("day", 0))
	if day < 1 or day == _done_day or net == null or not is_instance_valid(net) or not net.is_host():
		return
	_done_day = day
	send()


## Host: the units sent for the company's day (0: nothing to send, or the host refused it).
func send() -> int:
	var company: Object = net.company
	if company == null or not net.is_host():
		return 0
	var book_orders: Array = net.orders.book.to_dict().get("orders", [])
	var order_lines: Array[Dictionary] = SupplierAutoOrder.lines(
		int(company.get(&"money")), net.supplier.schedule, SupplierAutoOrder.todays_orders(book_orders),
		SupplierAutoOrder.stock_units(net.inventory, net.supplier.products), net.supplier.products,
		net.supplier.supplier, int(company.get(&"day")))
	if order_lines.is_empty():
		return 0
	var ask: Dictionary = net.supplier.ask(
		net, CompanySupplierNet.AUTO_PEER, CompanySupplierNet.request_data(order_lines))
	if ask.get("reason", &"x") != &"" or not net.publish(ask["kind"], ask["data"]):
		return 0
	return SupplierAutoOrder.units_of(order_lines)
