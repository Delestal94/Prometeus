class_name OrderTips
extends RefCounted
## Tip for a perfect and quick delivery (expansion D-0507, "Modo Empresa").
##
## Pure functions, no node, no autoload, no UI. A delivery tips only when
## OrderPenalties found nothing wrong with it (no kinds) and it arrived within
## the first TIP_FAST_WINDOW_SHARE of the order's window. The tip is a share of
## the order's base pay and comes on top of it. Numbers live in CompanyTuning.

const REASON_TIP: StringName = &"tip"


## {tip, reputation} for a delivery at game minute now_min. verdict is what
## OrderPenalties.assess returned for it. Both are 0 when anything went wrong or
## the delivery was not quick.
static func assess(order: Dictionary, verdict: Dictionary, now_min: int) -> Dictionary:
	var none: Dictionary = {"tip": 0, "reputation": 0.0}
	if not verdict.get("kinds", [null]).is_empty():
		return none
	var created: int = int(order.get("created_min", 0))
	var window: int = int(order.get("due_min", 0)) - created
	if window <= 0 or now_min < created:
		return none
	if float(now_min - created) > window * CompanyTuning.TIP_FAST_WINDOW_SHARE:
		return none
	return {
		"tip": roundi(int(verdict.get("base", order.get("pay", 0))) * CompanyTuning.TIP_RATE),
		"reputation": CompanyTuning.TIP_REPUTATION,
	}


## Pays the tip into the company's wallet (reason tip) and adds its reputation.
## company is a node with earn() and add_reputation(). Returns the tip paid.
static func apply(company: Object, result: Dictionary) -> int:
	var tip: int = int(result.get("tip", 0))
	if company == null or tip <= 0:
		return 0
	company.earn(tip, REASON_TIP)
	company.add_reputation(float(result.get("reputation", 0.0)))
	return tip
