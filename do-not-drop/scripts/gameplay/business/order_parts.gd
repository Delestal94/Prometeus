class_name OrderParts
extends RefCounted
## One order in two or three boxes (expansion D-0729, "Modo Empresa").
##
## Static and stateless. An order that needs more room than one XL box (CompanyTuning.MULTI_BOX_FILL of
## its cells) is split into parts, one per box, by split(): a deterministic function of the order's items,
## so nothing new is stored in the order or sent over the network. Each part is an order-shaped
## Dictionary (id "<order>#<n>", the items it holds) that BoxContentCheck already understands, so every
## box is checked with the rule of a single-box order. match() pairs the boxes handed over with the
## parts; the order pays only when every part has its box and no box is left over (door_accepts).

const SEPARATOR: String = "#"


## Cells of one product unit; unknown products count as the largest the XL box admits.
static func _unit_cells(product: StringName, products: Dictionary) -> int:
	var def: ProductDefinition = products.get(product)
	if def == null:
		var xl: Vector3i = CompanyTuning.BOX_CELLS[&"XL"]
		return xl.x * xl.y * xl.z
	return def.cells.x * def.cells.y * def.cells.z


## Cells one box takes before the order is split (the XL box scaled by MULTI_BOX_FILL).
static func box_capacity() -> int:
	var xl: Vector3i = CompanyTuning.BOX_CELLS[&"XL"]
	return floori(xl.x * xl.y * xl.z * CompanyTuning.MULTI_BOX_FILL)


## Total cells of the order's products.
static func total_cells(order: Dictionary, products: Dictionary) -> int:
	var total: int = 0
	for item: Dictionary in order.get("items", []):
		total += _unit_cells(StringName(item["product"]), products) * int(item["qty"])
	return total


## True when the order does not fit one box and travels in several.
static func is_multi(order: Dictionary, products: Dictionary) -> bool:
	return total_cells(order, products) > box_capacity()


## The parts of the order, 1 to ORDER_BOXES_MAX. Units go biggest first into the first part with room
## (ties by product id, so every peer gets the same split); a unit that fits nowhere goes to the part
## with the most room left, so the count never passes ORDER_BOXES_MAX. An order that fits one box
## returns itself as its only part.
static func split(order: Dictionary, products: Dictionary) -> Array[Dictionary]:
	var id: String = str(order.get("id", ""))
	if not is_multi(order, products):
		return [order.duplicate(true)]
	var units: Array[Dictionary] = []
	for item: Dictionary in order.get("items", []):
		var product := StringName(item["product"])
		for _n: int in int(item["qty"]):
			units.append({"product": product, "cells": _unit_cells(product, products)})
	units.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["cells"] != b["cells"]:
				return a["cells"] > b["cells"]
			return str(a["product"]) < str(b["product"])
	)
	var capacity: int = box_capacity()
	var used: Array[int] = []
	var held: Array[Dictionary] = []
	for unit: Dictionary in units:
		var target: int = -1
		for i: int in used.size():
			if used[i] + int(unit["cells"]) <= capacity:
				target = i
				break
		if target == -1 and used.size() < CompanyTuning.ORDER_BOXES_MAX:
			used.append(0)
			held.append({})
			target = used.size() - 1
		if target == -1:
			target = 0
			for i: int in used.size():
				if used[i] < used[target]:
					target = i
		used[target] += int(unit["cells"])
		held[target][unit["product"]] = int(held[target].get(unit["product"], 0)) + 1
	var parts: Array[Dictionary] = []
	for i: int in held.size():
		var items: Array[Dictionary] = []
		var ids: Array = held[i].keys()
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
		for product: StringName in ids:
			items.append({"product": product, "qty": int(held[i][product])})
		var part: Dictionary = order.duplicate(true)
		part["id"] = StringName("%s%s%d" % [id, SEPARATOR, i + 1])
		part["items"] = items
		parts.append(part)
	return parts


## The order a part id belongs to (the id itself when it has no part number).
static func order_id_of(part_id: StringName) -> StringName:
	return StringName(str(part_id).get_slice(SEPARATOR, 0))


## Pairs the boxes with the parts: {ok, pairs, missing, extra}. pairs maps a part index to the index
## of the box that holds exactly it; missing lists the parts with no box, extra the boxes that match
## no part. ok when every part has its box and no box is left over.
static func match(order: Dictionary, products: Dictionary, boxes: Array) -> Dictionary:
	var parts: Array[Dictionary] = split(order, products)
	var pairs: Dictionary = {}
	var taken: Dictionary = {}
	var missing: Array[int] = []
	for p: int in parts.size():
		var found: int = -1
		for b: int in boxes.size():
			if not taken.has(b) and BoxContentCheck.is_correct(parts[p], boxes[b]):
				found = b
				break
		if found == -1:
			missing.append(p)
		else:
			pairs[p] = found
			taken[found] = true
	var extra: Array[int] = []
	for b: int in boxes.size():
		if not taken.has(b):
			extra.append(b)
	return {"ok": missing.is_empty() and extra.is_empty(), "pairs": pairs, "missing": missing, "extra": extra}


## The door's verdict for the boxes delivered together.
static func door_accepts(order: Dictionary, products: Dictionary, boxes: Array) -> bool:
	return bool(match(order, products, boxes)["ok"])
