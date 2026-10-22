class_name Bankruptcy
extends RefCounted
## What a negative balance means (expansion D-0510, "Modo Empresa"). Pure functions, no node, no
## state: the day's close (D-0203) settles the fixed costs (FixedCosts, D-0509) and the next day's
## opening asks here how many orders to generate. Design (diseno/economia.md): a company that
## closes in the red does not reset; it opens the next day with BANKRUPT_ORDER_SHARE of its
## orders and a warning. Closing at 0 or more is normal again, so there is no streak to save.

## Translation key of the warning the day's opening shows to a company in the red.
const WARNING_KEY: String = "UI_COMPANY_BANKRUPT_WARNING"


## True when the wallet is below zero. company is a node with money.
static func is_bankrupt(company: Object) -> bool:
	return company != null and int(company.get("money")) < 0


## Share of the usual orders the next day opens with: 1.0, or BANKRUPT_ORDER_SHARE in the red.
static func order_share(company: Object) -> float:
	return CompanyTuning.BANKRUPT_ORDER_SHARE if is_bankrupt(company) else 1.0


## Orders to generate for the next day out of the usual count: rounded, never below 1 while the
## usual count is above 0 (a bankrupt company can still climb out).
static func orders_for_day(usual: int, company: Object) -> int:
	if usual <= 0:
		return 0
	return maxi(1, roundi(usual * order_share(company)))


## The key of the warning to show at the day's opening, or "" for a company in the black.
static func opening_notice(company: Object) -> String:
	return WARNING_KEY if is_bankrupt(company) else ""


## The warning as the player reads it, in the current language, with the share of orders in
## percent taken from BANKRUPT_ORDER_SHARE; "" when there is nothing to warn about.
static func opening_text(company: Object) -> String:
	var key: String = opening_notice(company)
	if key.is_empty():
		return ""
	var template: String = TranslationServer.translate(key)
	if "%d" not in template:
		return template
	return template % roundi(CompanyTuning.BANKRUPT_ORDER_SHARE * 100.0)
