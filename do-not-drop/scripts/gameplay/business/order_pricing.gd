class_name OrderPricing
extends RefCounted
## What an order pays (expansion D-0502, "Modo Empresa").
##
## Pure functions, no node, no autoload, no UI. The price of an order is the
## sold units, plus the zone's shipping fee, plus each requirement's bonus (the
## urgent one is reported apart as urgency). When the box is delivered a last
## bonus rewards a well packed box. Numbers come from CompanyTuning and from the
## OrderRequirement data; Order.make() and OrderGenerator share this math so the
## quote and the pay stored in the order never drift apart.


## Price breakdown of an order before delivery: {goods, shipping, requirements,
## urgency, total}. items is [{product, qty}], products maps product id ->
## ProductDefinition and catalog maps requirement id -> OrderRequirement.
## Unknown products and requirements add nothing.
static func quote(
	items: Array,
	zone: StringName,
	requirement_ids: Array,
	products: Dictionary,
	catalog: Dictionary,
) -> Dictionary:
	var goods: int = 0
	for item: Dictionary in items:
		var def: ProductDefinition = products.get(item["product"])
		if def != null:
			goods += def.get_sell_price() * int(item["qty"])
	var shipping: int = int(CompanyTuning.SHIPPING_FEE.get(zone, 0))
	var pay: int = goods + shipping
	var requirements: int = 0
	var urgency: int = 0
	for id: Variant in requirement_ids:
		var req: OrderRequirement = catalog.get(StringName(id))
		if req == null:
			continue
		var raised: int = req.paid(pay)
		if StringName(id) == &"urgent":
			urgency += raised - pay
		else:
			requirements += raised - pay
		pay = raised
	return {
		"goods": goods,
		"shipping": shipping,
		"requirements": requirements,
		"urgency": urgency,
		"total": pay,
	}


## pay with every listed requirement's bonus applied, one after the other.
static func with_requirements(pay: int, requirement_ids: Array, catalog: Dictionary) -> int:
	for id: Variant in requirement_ids:
		var req: OrderRequirement = catalog.get(StringName(id))
		if req != null:
			pay = req.paid(pay)
	return pay


## Extra pay for a well packed box: CONDITION_BONUS of the pay when quality
## (0-100) reaches CONDITION_BONUS_MIN_QUALITY, else 0.
static func condition_bonus(pay: int, quality: float) -> int:
	if quality < CompanyTuning.CONDITION_BONUS_MIN_QUALITY:
		return 0
	return roundi(pay * CompanyTuning.CONDITION_BONUS)


## What a delivered order pays at game minute now_min with a box of the given
## quality: the late-adjusted payout plus the condition bonus. A late box still
## earns the bonus if it arrives well packed.
static func settle(order: Dictionary, now_min: int, quality: float) -> int:
	var paid: int = Order.payout(order, now_min)
	return paid + condition_bonus(paid, quality)
