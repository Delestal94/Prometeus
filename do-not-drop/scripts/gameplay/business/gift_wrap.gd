class_name GiftWrap
extends RefCounted
## Gift paper on a packed box (expansion D-0723, "Modo Empresa").
##
## Static and stateless. A closed box can be wrapped once (PackedBox.gift_wrapped). A gift order
## (requirement id &"gift") delivered in a wrapped box pays CompanyTuning.GIFT_WRAP_BONUS of its pay
## on top of the requirement's own bonus; wrapping a box for any other order earns nothing. The
## paper's price (GIFT_WRAP_COST) is charged by whoever calls wrap(), like the rest of the packaging
## supplies.

const GIFT: StringName = &"gift"


## True when the order dictionary asks for a gift.
static func is_gift(order: Dictionary) -> bool:
	for raw: Variant in order.get("requirements", []):
		if StringName(str(raw)) == GIFT:
			return true
	return false


## Wraps the box. False, changing nothing, with no box, an untaped box or one already wrapped.
static func wrap(box: PackedBox) -> bool:
	if box == null or not box.taped or box.gift_wrapped:
		return false
	box.gift_wrapped = true
	return true


## Extra pay for a wrapped box on a gift order; 0 for anything else.
static func bonus(pay: int, box: PackedBox, order: Dictionary) -> int:
	if box == null or not box.gift_wrapped or not is_gift(order):
		return 0
	return roundi(pay * CompanyTuning.GIFT_WRAP_BONUS)
