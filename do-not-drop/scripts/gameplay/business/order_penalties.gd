class_name OrderPenalties
extends RefCounted
## What goes wrong at the customer's door (expansion D-0506, "Modo Empresa").
##
## Pure functions, no node, no autoload, no UI. Four failures cost money and
## reputation: a wrong or missing product (the box pays 0), a broken product
## (its share of the pay is lost), a late delivery (Order.payout) and a box
## labeled for another order. assess() returns the final pay and the reputation
## change; apply_reputation() hands the latter to the company. Numbers live in
## CompanyTuning.

const KIND_WRONG: StringName = &"wrong"
const KIND_BROKEN: StringName = &"broken"
const KIND_LATE: StringName = &"late"
const KIND_MISLABELED: StringName = &"mislabeled"
const KIND_ABANDONED: StringName = &"abandoned"


## True when the box holds exactly the products and quantities the order asks for.
static func matches_order(order: Dictionary, box: PackedBox) -> bool:
	if box == null:
		return false
	var wanted: Dictionary = {}
	for item: Dictionary in order.get("items", []):
		wanted[StringName(item["product"])] = int(item["qty"])
	return wanted == box.contents()


## Verdict for a delivery at game minute now_min. broken is the ids of the
## products that arrived broken (one entry per unit). Returns {pay, base, kinds,
## reputation, lost}: pay is what the customer pays, kinds the failures that
## happened and reputation the (negative or zero) change, capped.
static func assess(
	order: Dictionary,
	box: PackedBox,
	now_min: int,
	broken: Array,
	products: Dictionary,
) -> Dictionary:
	var base: int = int(order.get("pay", 0))
	var kinds: Array[StringName] = []
	var reputation: float = 0.0
	var pay: float = float(base)
	if not matches_order(order, box):
		kinds.append(KIND_WRONG)
		pay = base * CompanyTuning.WRONG_BOX_PAY_FACTOR
		reputation += CompanyTuning.WRONG_BOX_REPUTATION
	else:
		var broken_loss: int = _broken_loss(broken, products, base)
		if broken_loss > 0 or not broken.is_empty():
			kinds.append(KIND_BROKEN)
			pay = maxf(0.0, pay - broken_loss * (1.0 - CompanyTuning.BROKEN_PRODUCT_PAY_FACTOR))
			reputation += CompanyTuning.BROKEN_PRODUCT_REPUTATION * broken.size()
	if now_min > int(order.get("due_min", 0)):
		kinds.append(KIND_LATE)
		pay *= 1.0 - CompanyTuning.LATE_PENALTY
	if box != null and box.label_order_id != StringName(order.get("id", "")):
		kinds.append(KIND_MISLABELED)
		pay *= 1.0 - CompanyTuning.MISLABEL_PAY_LOSS
		reputation += CompanyTuning.MISLABEL_REPUTATION
	var final_pay: int = roundi(pay)
	return {
		"pay": final_pay,
		"base": base,
		"lost": base - final_pay,
		"kinds": kinds,
		"reputation": maxf(reputation, CompanyTuning.PENALTY_REPUTATION_CAP),
	}


## Verdict for an order the customer gave up on (OrderBook.abandon): pays 0 and costs reputation.
static func abandoned(order: Dictionary) -> Dictionary:
	var base: int = int(order.get("pay", 0))
	return {
		"pay": 0,
		"base": base,
		"lost": base,
		"kinds": [KIND_ABANDONED] as Array[StringName],
		"reputation": maxf(CompanyTuning.ABANDONED_REPUTATION, CompanyTuning.PENALTY_REPUTATION_CAP),
	}


## Applies a verdict's reputation change to the company (a node with add_reputation).
static func apply_reputation(company: Object, verdict: Dictionary) -> void:
	var delta: float = float(verdict.get("reputation", 0.0))
	if company != null and delta != 0.0:
		company.add_reputation(delta)


## Pay lost to the listed broken units: each one's sell price, never more than the pay.
static func _broken_loss(broken: Array, products: Dictionary, base: int) -> int:
	var loss: int = 0
	for id: Variant in broken:
		var def: ProductDefinition = products.get(StringName(id))
		if def != null:
			loss += def.get_sell_price()
	return mini(loss, base)
