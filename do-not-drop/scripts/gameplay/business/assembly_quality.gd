class_name AssemblyQuality
extends RefCounted
## How well a box was packed, 0 to 100 (expansion D-0709, "Modo Empresa").
##
## Static and stateless. Starts at CompanyTuning.QUALITY_MAX and loses points for wrong contents,
## empty unpadded space (more if a product is fragile), each required seal that is missing, and a
## box without tape or label. D-0710 turns the quality into the trap's intensity; D-0502 pays the
## condition bonus from it. Numbers live in CompanyTuning.


## Quality of the box for its order. products maps id -> ProductDefinition (only fragile is read;
## an id missing there counts as not fragile). A null box has quality 0.
static func score(box: PackedBox, order: Dictionary, products: Dictionary = {}) -> float:
	if box == null:
		return 0.0
	var lost: float = 0.0
	for value: float in breakdown(box, order, products).values():
		lost += value
	return clampf(CompanyTuning.QUALITY_MAX - lost, 0.0, CompanyTuning.QUALITY_MAX)


## Points lost per reason: content, gaps, seals, closure. All zero is a perfect box.
static func breakdown(box: PackedBox, order: Dictionary, products: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"content": 0.0, "gaps": 0.0, "seals": 0.0, "closure": 0.0}
	if box == null:
		return out
	if not OrderPenalties.matches_order(order, box):
		out["content"] = CompanyTuning.QUALITY_WRONG_CONTENT
	var gap_weight: float = CompanyTuning.QUALITY_GAP_WEIGHT
	if _has_fragile(box, products):
		gap_weight *= CompanyTuning.QUALITY_GAP_FRAGILE_FACTOR
	# free_ratio(): share of the whole box neither product nor padding.
	out["gaps"] = gap_weight * box.free_ratio()
	out["seals"] = CompanyTuning.QUALITY_MISSING_SEAL * BoxSeals.missing(box, order).size()
	if not box.taped or box.label_order_id == &"":
		out["closure"] = CompanyTuning.QUALITY_UNSEALED
	return out


static func _has_fragile(box: PackedBox, products: Dictionary) -> bool:
	for item: Dictionary in box.items:
		var def: ProductDefinition = products.get(item["product"]) as ProductDefinition
		if def != null and def.fragile:
			return true
	return false
