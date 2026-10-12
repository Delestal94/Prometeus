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
## inventory, like CompanyState) and names no autoload (lesson N-919). The ledger movements of the
## day are split by sign the same way DaySummary (D-0508) does at the day's close.

## The summary kept for the main menu, {} for none (hold() / take_pending()).
static var _pending: Dictionary = {}


## What a peer saw of the day in progress, as plain values:
##   day            the company's day
##   clock_minutes  `minute` when given (a running clock's minute), else the company's
##   money          the balance now
##   opening        the balance when the day's first movement started (money with none)
##   income, costs  the day's movements in the ledger, by sign (costs is positive)
##   profit         income - costs
##   movements      how many movements of the day the ledger holds
##   units          units in `stock` (the live one), else in the company's stored stock
##   truncated      the ledger is full and starts on this day: movements of it may be gone
static func summary(company: Object, stock: Inventory = null, minute: int = -1) -> Dictionary:
	var result: Dictionary = {
		"day": 0,
		"clock_minutes": 0,
		"money": 0,
		"opening": 0,
		"income": 0,
		"costs": 0,
		"profit": 0,
		"movements": 0,
		"units": 0,
		"truncated": false,
	}
	if company == null:
		return result
	var day: int = int(company.day)
	var money: int = int(company.money)
	result["day"] = day
	result["money"] = money
	result["opening"] = money
	var clock: int = minute if minute >= 0 else int(company.clock_minutes)
	result["clock_minutes"] = clampi(clock, 0, CompanyTuning.MINUTES_PER_DAY - 1)
	var ledger: Array = company.ledger
	var first: Dictionary = {}
	for entry: Dictionary in ledger:
		if int(entry.get("day", -1)) != day:
			continue
		if first.is_empty():
			first = entry
		var amount: int = int(entry.get("amount", 0))
		if amount >= 0:
			result["income"] += amount
		else:
			result["costs"] -= amount
		result["movements"] += 1
	if not first.is_empty():
		result["opening"] = int(first.get("balance", 0)) - int(first.get("amount", 0))
	result["profit"] = int(result["income"]) - int(result["costs"])
	if not ledger.is_empty() and ledger.size() >= CompanyTuning.LEDGER_MAX:
		result["truncated"] = int((ledger[0] as Dictionary).get("day", day)) >= day
	var units: Inventory = stock
	if units == null:
		units = Inventory.new()
		var stored: Variant = company.inventory
		if stored is Dictionary:
			units.from_dict(stored)
	result["units"] = units.total_units()
	return result


## One line for the menu, in this peer's language; "" for an empty summary.
static func describe(day_summary: Dictionary) -> String:
	if day_summary.is_empty():
		return ""
	var minutes: int = int(day_summary.get("clock_minutes", 0))
	var clock: String = "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]
	return TranslationServer.translate("UI_COMPANY_DAY_CUT") % [
		int(day_summary.get("day", 0)), clock, int(day_summary.get("income", 0)),
		int(day_summary.get("costs", 0)), int(day_summary.get("money", 0)),
		int(day_summary.get("units", 0))]


## Keeps `day_summary` for the menu, in place of any kept before.
static func hold(day_summary: Dictionary) -> void:
	_pending = day_summary.duplicate(true)


## The summary kept for the menu, once: {} when there is none, and none after this.
static func take_pending() -> Dictionary:
	var kept: Dictionary = _pending
	_pending = {}
	return kept


## take_pending() as the menu's line ("" when there is none).
static func take_pending_text() -> String:
	return describe(take_pending())
