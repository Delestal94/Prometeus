class_name DaySummary
extends RefCounted
## Financial summary of a day (expansion D-0508, "Modo Empresa").
##
## Pure function over the wallet's ledger: no node, no autoload, no UI. The panel that
## shows it at the day's close (constructor-ui) only reads the dictionary build() returns.
## Income and costs are the signed ledger movements of that day split by sign, so every
## reason (order_paid, tip, supplier, boxes, packaging, rent...) shows up on its own
## without this class knowing it.


## {day, income, costs, profit, opening, closing, income_by_reason, cost_by_reason, truncated}.
## company is a node with day, money and ledger. costs is positive. The two *_by_reason
## dictionaries map reason -> positive amount. truncated is true when the ledger is full and its
## oldest entry is of this day or later: movements of the day may be gone (it holds LEDGER_MAX).
static func build(company: Object, for_day: int) -> Dictionary:
	var result: Dictionary = {
		"day": for_day,
		"income": 0,
		"costs": 0,
		"profit": 0,
		"opening": 0,
		"closing": 0,
		"income_by_reason": {},
		"cost_by_reason": {},
		"truncated": false,
	}
	if company == null:
		return result
	var ledger: Array = company.ledger
	var first: Dictionary = {}
	var last: Dictionary = {}
	for entry: Dictionary in ledger:
		if int(entry.get("day", -1)) != for_day:
			continue
		if first.is_empty():
			first = entry
		last = entry
		var amount: int = int(entry.get("amount", 0))
		var reason: String = str(entry.get("reason", ""))
		if amount >= 0:
			result["income"] += amount
			_add(result["income_by_reason"], reason, amount)
		else:
			result["costs"] -= amount
			_add(result["cost_by_reason"], reason, -amount)
	result["profit"] = int(result["income"]) - int(result["costs"])
	if first.is_empty():
		# A quiet day: the balance did not move. After the ledger's last entry it is the
		# wallet itself; before it, the balance the next day's first movement started from.
		var balance: int = company.money
		result["opening"] = balance
		result["closing"] = balance
	else:
		result["opening"] = int(first.get("balance", 0)) - int(first.get("amount", 0))
		result["closing"] = int(last.get("balance", 0))
	if not ledger.is_empty() and ledger.size() >= CompanyTuning.LEDGER_MAX:
		result["truncated"] = int(ledger[0].get("day", for_day)) >= for_day
	return result


## The reasons of a *_by_reason dictionary, biggest amount first (ties by name).
static func sorted_reasons(by_reason: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	for key: Variant in by_reason:
		reasons.append(str(key))
	reasons.sort_custom(
		func(a: String, b: String) -> bool:
			var amount_a: int = int(by_reason[a])
			var amount_b: int = int(by_reason[b])
			return a < b if amount_a == amount_b else amount_a > amount_b
	)
	return reasons


static func _add(into: Dictionary, reason: String, amount: int) -> void:
	into[reason] = int(into.get(reason, 0)) + amount
