class_name BoxSeals
extends RefCounted
## Seals on a packed box and what an order asks of them (expansion D-0708, "Modo Empresa").
##
## Static and stateless. A seal is a kind id stamped on PackedBox.stamps (PackagingSupplies.stamp
## pays it). The kinds are the ones OrderRequirement.required_seals names; the door of the house
## checks the box against its order with missing() / is_valid().

const REQUIREMENTS_DIR: String = "res://data/order_requirements"
## Seal kind ids a box can carry (the six requirements in data/order_requirements/ ask for these).
const KINDS: Array[StringName] = [&"fragile", &"no_bend", &"cold", &"gift", &"heavy"]


static func is_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


## Seals an order dictionary needs, without repeats, in the order its requirements list them.
## Requirement ids that have no resource are ignored.
static func required(order: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for raw: Variant in order.get("requirements", []):
		var path: String = "%s/%s.tres" % [REQUIREMENTS_DIR, str(raw)]
		var req: OrderRequirement = load(path) as OrderRequirement if ResourceLoader.exists(path) else null
		if req == null:
			continue
		for kind: StringName in req.required_seals:
			if not out.has(kind):
				out.append(kind)
	return out


## Seals the order needs that the box does not carry. Empty when the box is fine; a null box
## misses all of them.
static func missing(box: PackedBox, order: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in required(order):
		if box == null or not box.stamps.has(kind):
			out.append(kind)
	return out


## True when the box carries every seal its order requires (the door's check).
static func is_valid(box: PackedBox, order: Dictionary) -> bool:
	return missing(box, order).is_empty()
