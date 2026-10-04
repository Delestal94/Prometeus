class_name Order
extends RefCounted
## Structure of a customer order (expansion D-0802, "Modo Empresa").
##
## An order is a plain Dictionary so OrderBook (D-0210) can store it, the
## network can send it and a save can hold it. This class only builds, checks
## and normalizes those dictionaries; it never holds one. Pure data: no node,
## no autoload, no UI.
##
## Keys: id, customer, zone, house_id, items [{product, qty}], requirements
## [StringName], created_min, due_min, pay, state. Times are game minutes since
## the day opened.

const STATE_OPEN: StringName = &"open"
const STATE_PACKED: StringName = &"packed"
const STATE_OUT: StringName = &"out"
const STATE_DELIVERED: StringName = &"delivered"
const STATE_LATE: StringName = &"late"
const STATE_FAILED: StringName = &"failed"
const STATE_CANCELLED: StringName = &"cancelled"
const STATES: Array[StringName] = [
	STATE_OPEN,
	STATE_PACKED,
	STATE_OUT,
	STATE_DELIVERED,
	STATE_LATE,
	STATE_FAILED,
	STATE_CANCELLED,
]

## The numbers live in CompanyTuning (D-0202); these names stay as the Order API.
const WINDOW_MIN: int = CompanyTuning.ORDER_WINDOW_MIN
const LATE_PENALTY: float = CompanyTuning.LATE_PENALTY
const SHIPPING_FEE: Dictionary = CompanyTuning.SHIPPING_FEE
const MAX_ITEMS: int = CompanyTuning.ORDER_ITEMS_MAX


## Builds a valid order. items is [{product, qty}] and may repeat a product;
## repeated entries are merged. The pay is the sold units plus the zone's
## shipping fee, and due_min defaults to created_min + WINDOW_MIN.
## products maps product id -> ProductDefinition (only its sell price is read).
static func make(
	id: StringName,
	customer: String,
	zone: StringName,
	house_id: StringName,
	items: Array,
	created_min: int,
	products: Dictionary,
	requirements: Array[StringName] = [],
	due_min: int = -1,
) -> Dictionary:
	var merged: Array[Dictionary] = _merge_items(items)
	var pay: int = int(SHIPPING_FEE.get(zone, 0))
	for item: Dictionary in merged:
		var def: ProductDefinition = products.get(item["product"])
		if def != null:
			pay += def.get_sell_price() * int(item["qty"])
	return {
		"id": id,
		"customer": customer,
		"zone": zone,
		"house_id": house_id,
		"items": merged,
		"requirements": requirements.duplicate(),
		"created_min": created_min,
		"due_min": due_min if due_min >= 0 else created_min + WINDOW_MIN,
		"pay": pay,
		"state": STATE_OPEN,
	}


## Empty when the order is well formed, else one message per problem.
static func validate(order: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in ["id", "customer", "zone", "house_id"]:
		if str(order.get(key, "")) == "":
			errors.append("missing %s" % key)
	var items: Array = order.get("items", [])
	if items.is_empty() or items.size() > MAX_ITEMS:
		errors.append("items must hold 1 to %d products" % MAX_ITEMS)
	var seen: Dictionary = {}
	for item: Variant in items:
		if (
			not item is Dictionary
			or str(item.get("product", "")) == ""
			or int(item.get("qty", 0)) <= 0
		):
			errors.append("bad item %s" % str(item))
			continue
		if seen.has(item["product"]):
			errors.append("repeated product %s" % item["product"])
		seen[item["product"]] = true
	if int(order.get("due_min", 0)) <= int(order.get("created_min", 0)):
		errors.append("due_min must come after created_min")
	if int(order.get("pay", -1)) < 0:
		errors.append("pay must not be negative")
	if not StringName(order.get("state", "")) in STATES:
		errors.append("unknown state %s" % str(order.get("state", "")))
	return errors


## Same order with the types a JSON round trip loses restored (StringName ids,
## int times, typed item entries), so equality with the original holds.
static func normalize(raw: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	for item: Dictionary in raw.get("items", []):
		items.append(
			{"product": StringName(item.get("product", "")), "qty": int(item.get("qty", 0))}
		)
	var requirements: Array[StringName] = []
	for req: Variant in raw.get("requirements", []):
		requirements.append(StringName(req))
	return {
		"id": StringName(raw.get("id", "")),
		"customer": str(raw.get("customer", "")),
		"zone": StringName(raw.get("zone", "")),
		"house_id": StringName(raw.get("house_id", "")),
		"items": items,
		"requirements": requirements,
		"created_min": int(raw.get("created_min", 0)),
		"due_min": int(raw.get("due_min", 0)),
		"pay": int(raw.get("pay", 0)),
		"state": StringName(raw.get("state", STATE_OPEN)),
	}


## JSON text of an order, and the way back.
static func to_json(order: Dictionary) -> String:
	return JSON.stringify(order)


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	return normalize(parsed)


## What the order pays when it is delivered at game minute now_min: the full
## pay, minus LATE_PENALTY if now_min is past due_min.
static func payout(order: Dictionary, now_min: int) -> int:
	var pay: int = int(order.get("pay", 0))
	if now_min > int(order.get("due_min", 0)):
		return roundi(pay * (1.0 - LATE_PENALTY))
	return pay


static func _merge_items(items: Array) -> Array[Dictionary]:
	var qty_by_product: Dictionary = {}
	var order_seen: Array[StringName] = []
	for item: Dictionary in items:
		var product := StringName(item.get("product", ""))
		if not qty_by_product.has(product):
			order_seen.append(product)
		qty_by_product[product] = int(qty_by_product.get(product, 0)) + int(item.get("qty", 0))
	var merged: Array[Dictionary] = []
	for product: StringName in order_seen:
		merged.append({"product": product, "qty": qty_by_product[product]})
	return merged
