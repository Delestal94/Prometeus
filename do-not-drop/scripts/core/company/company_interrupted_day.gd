class_name CompanyInterruptedDay
extends RefCounted
## A company day the host's leaving cut short (expansion D-2005, "Modo Empresa"; like N-222).
##
## A client whose host goes away mid-day gets no day summary from the host: summary() is what this
## peer saw of the day instead, from its mirror of the host's company (day, clock, money, the
## wallet history of that day) and the stock it held. CompanyRoot builds it before the client's
## own company comes back, hold()s it and loads the main menu, which shows it once
## (take_pending_text()) next to the session's "host lost" message.
##
## Pure: it takes the company as a parameter (anything with day, clock_minutes, money, ledger and
## inventory, like CompanyState) and names no autoload (lesson N-919). The money of the day is
## DaySummary's (D-0508), the same figures the day's close will show.

## The summary kept for the main menu, {} for none (hold() / take_pending()).
static var _pending: Dictionary = {}


## What a peer saw of the day in progress, as plain values: DaySummary.build() of the company's day
## (day, income, costs, profit, opening, closing, income_by_reason, cost_by_reason, truncated) and
##   clock_minutes  `minute` when given (a running clock's minute), else the company's, held
##                  within the day
##   money          the wallet now
##   units          every unit in `stock` (the live one), else in the company's stored stock:
##                  shelves and pallets, but also hands, boxes and packages
static func summary(company: Object, stock: Inventory = null, minute: int = -1) -> Dictionary:
	var day: int = int(company.day) if company != null else 0
	var result: Dictionary = DaySummary.build(company, day)
	result["clock_minutes"] = 0
	result["money"] = 0
	result["units"] = 0
	if company == null:
		return result
	var clock: int = minute if minute >= 0 else int(company.clock_minutes)
	result["clock_minutes"] = clampi(clock, 0, CompanyTuning.MINUTES_PER_DAY - 1)
	result["money"] = int(company.money)
	var units: Inventory = stock
	if units == null:
		units = Inventory.new()
		var stored: Variant = company.inventory
		if stored is Dictionary:
			units.from_dict(stored)
	result["units"] = units.total_units()
	return result


## One line for the menu, in this peer's language; "" for an empty summary. A truncated ledger
## (movements of the day may be gone) marks income and costs as partial.
static func describe(day_summary: Dictionary) -> String:
	if day_summary.is_empty():
		return ""
	var minutes: int = int(day_summary.get("clock_minutes", 0))
	var clock: String = "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]
	var key: String = "UI_COMPANY_DAY_CUT"
	if bool(day_summary.get("truncated", false)):
		key = "UI_COMPANY_DAY_CUT_PARTIAL"
	return TranslationServer.translate(key) % [
		int(day_summary.get("day", 0)), clock, int(day_summary.get("income", 0)),
		int(day_summary.get("costs", 0)), int(day_summary.get("money", 0)),
		int(day_summary.get("units", 0))]


## Keeps `day_summary` for the menu, in place of any kept before.
static func hold(day_summary: Dictionary) -> void:
	_pending = day_summary.duplicate(true)


## A copy of the summary kept for the menu, leaving it kept ({} when there is none).
static func peek_pending() -> Dictionary:
	return _pending.duplicate(true)


## The summary kept for the menu, once: {} when there is none, and none after this.
static func take_pending() -> Dictionary:
	var kept: Dictionary = _pending
	_pending = {}
	return kept


## take_pending() as the menu's line ("" when there is none).
static func take_pending_text() -> String:
	return describe(take_pending())
