class_name OrderNotice
extends RefCounted
## The phone ping for orders that just came in (expansion D-0814, "Modo Empresa").
##
## Pure functions over order dictionaries: no node, no autoload. The text goes through tr()
## like OrderBoardPanel, so it follows the language. One order says who and where; a burst
## (the day opens with several at once) collapses into a count so the toast does not spam.

const PRIORITY_NORMAL: int = 20
const PRIORITY_URGENT: int = 30
const URGENT_REQUIREMENT: StringName = &"urgent"


## {text, priority} for the orders that arrived together; empty when there are none.
static func message(orders: Array) -> Dictionary:
	var fresh: Array[Dictionary] = []
	for order: Variant in orders:
		if order is Dictionary and not str(order.get("id", "")).is_empty():
			fresh.append(order)
	if fresh.is_empty():
		return {}
	var text: String
	if fresh.size() == 1:
		text = _one(fresh[0])
	else:
		text = tr_text("UI_ORDER_NOTICE_MANY") % fresh.size()
	return {"text": text, "priority": priority_of(fresh)}


## Urgent orders ring louder than the rest.
static func priority_of(orders: Array) -> int:
	for order: Dictionary in orders:
		if URGENT_REQUIREMENT in _requirements(order):
			return PRIORITY_URGENT
	return PRIORITY_NORMAL


static func _one(order: Dictionary) -> String:
	var customer: String = str(order.get("customer", ""))
	var address: Dictionary = OrderLabel.address(order)
	if address.is_empty():
		return tr_text("UI_ORDER_NOTICE_ONE_NO_ADDRESS") % customer
	return (
		tr_text("UI_ORDER_NOTICE_ONE")
		% [customer, tr_text(String(address["street_key"])), int(address["number"])]
	)


static func _requirements(order: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for req: Variant in order.get("requirements", []):
		out.append(StringName(str(req)))
	return out


## Static helper so the pure class can translate without being a Node.
static func tr_text(key: String) -> String:
	return TranslationServer.translate(key)
