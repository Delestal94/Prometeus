class_name OrderSettlement
extends RefCounted
## What happens when an order is handed over at the customer's door (expansion D-0815, "Modo Empresa").
##
## Pure functions, no node of its own, no UI. settle() joins the pieces that already exist: the
## verdict of OrderPenalties (pay lost to a wrong box, broken units, lateness or a wrong label),
## OrderBook.mark_delivered (closes the order with that pay), the company wallet (reason order_paid),
## the reputation (the verdict's loss, or CLEAN_DELIVERY_REPUTATION when nothing went wrong) and the
## tip of OrderTips. The company is a node with earn() and add_reputation() (CompanyState). The host
## calls it once per order; clients get the result through CompanyNet (D-2001).

const REASON_PAID: StringName = &"order_paid"


## Settles the order delivered in `box` at game minute now_min. broken is the ids of the products that
## arrived broken (one entry per unit). Returns {ok, paid, tip, reputation, kinds, lost, stars}: ok is
## false, and nothing changes, when the order is not deliverable now (not out on the road or late from
## there). reputation is the net change applied, including the tip's. stars is the customer's rating
## 1-5 (OrderRating, D-0816; 0 when not ok): it is reported, not stored in the book nor paid.
static func settle(
	book: OrderBook,
	company: Object,
	order_id: StringName,
	box: PackedBox,
	now_min: int,
	broken: Array,
	products: Dictionary,
) -> Dictionary:
	var failed: Dictionary = {
		"ok": false,
		"paid": 0,
		"tip": 0,
		"reputation": 0.0,
		"kinds": [] as Array[StringName],
		"lost": 0,
		"stars": 0,
	}
	if book == null or company == null or not book.has(order_id):
		return failed
	var order: Dictionary = book.get_order(order_id)
	var verdict: Dictionary = OrderPenalties.assess(order, box, now_min, broken, products)
	var base: int = maxi(int(verdict["base"]), 1)
	var quality: int = clampi(roundi(100.0 * float(verdict["pay"]) / base), 0, 100)
	var paid: int = book.mark_delivered(order_id, quality, broken.is_empty(), now_min, int(verdict["pay"]))
	if paid < 0:
		return failed
	company.earn(paid, REASON_PAID)
	var reputation: float = float(verdict["reputation"])
	OrderPenalties.apply_reputation(company, verdict)
	if verdict["kinds"].is_empty():
		reputation += CompanyTuning.CLEAN_DELIVERY_REPUTATION
		company.add_reputation(CompanyTuning.CLEAN_DELIVERY_REPUTATION)
	var tip_result: Dictionary = OrderTips.assess(order, verdict, now_min)
	var tip: int = OrderTips.apply(company, tip_result)
	if tip > 0:
		reputation += float(tip_result["reputation"])
	var result: Dictionary = {
		"ok": true,
		"paid": paid,
		"tip": tip,
		"reputation": reputation,
		"kinds": verdict["kinds"],
		"lost": int(verdict["lost"]),
	}
	result["stars"] = OrderRating.stars(result)
	return result
