class_name OrderSheet
extends RefCounted
## What the order sheet on a packing table shows (expansion D-0714, "Modo Empresa"): which order
## this box is for, what it must hold and how far the box is from ready.
##
## Static and stateless; the screen is OrderSheetPanel. build() reads an Order dictionary and the
## PackedBox on the table and returns a plain Dictionary, so a client draws the same sheet from
## what the host sends. No node, no autoload, no tr(): texts are translation keys or ids.
##
## Result keys: order (id), customer, address ({street_key, number}, empty without a house),
## items [{product, name, qty, packed, ok}], extra [{product, name, qty}] (units the box holds
## that the order does not ask for), requirements [{id, key, seals [{kind, done}]}], taped,
## labeled, minutes_left (negative once past due), late, pay and ready (the box could be
## dispatched as it is: right content, every seal, tape and the label of this order).

## Requirement id -> translation key of its name. Literal keys, so the translation test sees them.
const REQUIREMENT_KEYS: Dictionary = {
	&"fragile": "WORLD_REQ_FRAGILE",
	&"cold": "WORLD_REQ_COLD",
	&"gift": "WORLD_REQ_GIFT",
	&"urgent": "WORLD_REQ_URGENT",
	&"heavy": "WORLD_REQ_HEAVY",
	&"no_bend": "WORLD_REQ_NO_BEND",
}


## The sheet of `order` for the box on the table (null: nothing started yet). `products` maps
## product id -> ProductDefinition and only gives the names; an id without one shows as itself.
static func build(
	order: Dictionary, box: PackedBox, now_min: int, products: Dictionary = {}
) -> Dictionary:
	if order.is_empty():
		return {}
	var diff: Dictionary = BoxContentCheck.diff(order, box)
	var held: Dictionary = box.contents() if box != null else {}
	var items: Array[Dictionary] = []
	for item: Dictionary in order.get("items", []):
		var id := StringName(item["product"])
		var packed: int = int(held.get(id, 0))
		items.append(
			{
				"product": id,
				"name": product_name(id, products),
				"qty": int(item["qty"]),
				"packed": packed,
				"ok": not (diff["missing"] as Dictionary).has(id) and not (diff["extra"] as Dictionary).has(id),
			}
		)
	var extra: Array[Dictionary] = []
	for id: StringName in diff["extra"]:
		extra.append({"product": id, "name": product_name(id, products), "qty": int(diff["extra"][id])})
	var taped: bool = box != null and box.taped
	var labeled: bool = OrderLabel.matches(box, order)
	var minutes_left: int = int(order.get("due_min", 0)) - now_min
	return {
		"order": StringName(str(order.get("id", ""))),
		"customer": str(order.get("customer", "")),
		"address": OrderLabel.address(order),
		"items": items,
		"extra": extra,
		"requirements": _requirements(order, box),
		"taped": taped,
		"labeled": labeled,
		"minutes_left": minutes_left,
		"late": minutes_left < 0,
		"pay": int(order.get("pay", 0)),
		"ready":
		(
			box != null
			and BoxContentCheck.is_correct(order, box)
			and BoxSeals.is_valid(box, order)
			and taped
			and labeled
		),
	}


## Display name of a product: its content's translated name, or the id when it has none.
static func product_name(id: StringName, products: Dictionary) -> String:
	var def: ProductDefinition = products.get(id)
	if def != null and def.content != null:
		var shown: String = def.content.localized_name()
		if shown != "":
			return shown
	return String(id)


## One entry per requirement of the order, with the seals it asks for and whether the box has them.
static func _requirements(order: Dictionary, box: PackedBox) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in order.get("requirements", []):
		var id := StringName(str(raw))
		var seals: Array[Dictionary] = []
		var path: String = "%s/%s.tres" % [BoxSeals.REQUIREMENTS_DIR, id]
		var req: OrderRequirement = load(path) as OrderRequirement if ResourceLoader.exists(path) else null
		if req != null:
			for kind: StringName in req.required_seals:
				seals.append({"kind": kind, "done": box != null and box.stamps.has(kind)})
		out.append({"id": id, "key": String(REQUIREMENT_KEYS.get(id, "")), "seals": seals})
	return out
