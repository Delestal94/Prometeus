class_name BoxScale
extends RefCounted
## Control scale: expected weight vs. real weight of a packed box (expansion D-0713).
##
## Static and stateless. The expected weight is what the order's products weigh
## (ProductDefinition.weight_kg); the real one is what the box holds. A different weight says
## "something is missing or extra" without showing which (BoxContentCheck says that). Padding
## and the box itself weigh nothing here. Like the content check, it only informs: the
## player may still tape and dispatch.

## Weight of order items [{product, qty}]; products maps id -> ProductDefinition.
## Unknown products add nothing.
static func expected_kg(order: Dictionary, products: Dictionary) -> float:
	var total: float = 0.0
	for item: Dictionary in order.get("items", []):
		var def: ProductDefinition = products.get(StringName(item["product"]))
		if def != null:
			total += def.weight_kg * int(item["qty"])
	return total


## Weight of what the box holds; 0 for a null box.
static func real_kg(box: PackedBox, products: Dictionary) -> float:
	var total: float = 0.0
	if box == null:
		return total
	var held: Dictionary = box.contents()
	for id: StringName in held:
		var def: ProductDefinition = products.get(id)
		if def != null:
			total += def.weight_kg * int(held[id])
	return total


## {expected, real, delta (real - expected), ok}. ok when |delta| <= SCALE_TOLERANCE_KG.
static func weigh(order: Dictionary, box: PackedBox, products: Dictionary) -> Dictionary:
	var expected: float = expected_kg(order, products)
	var real: float = real_kg(box, products)
	var delta: float = real - expected
	return {
		"expected": expected,
		"real": real,
		"delta": delta,
		"ok": absf(delta) <= CompanyTuning.SCALE_TOLERANCE_KG,
	}
