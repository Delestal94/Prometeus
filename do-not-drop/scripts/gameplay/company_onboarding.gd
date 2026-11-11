class_name CompanyOnboarding
extends RefCounted
## The first week of the company mode, one objective at a time (expansion D-1901, diseno/onboarding.md §2-4).
##
## Pure and static: current() reads what the player has in hand and the company's state and returns the one line
## to show, so the guide never gets out of step with what was done (out of order, undone, done by somebody else).
## No node, no autoload, no tr(): texts are translation keys (UI_ONBOARD_<ID>), the action is shown with its key.
##
## Day 1 is the whole loop (§3), in DAY_ONE order: stock_pallet, pick, pack, drive, deliver, return. The line looks
## at the player first: driving, it is the next of drive / deliver / return; at a packing table, pack; with units in
## the hands, pick or pack; otherwise the first of the loop this player has not done. A step that cannot be done any
## more (stock_pallet with no pallet left to put away) counts as done. After the loop, the rows of §2 whose trigger
## fired and whose first day came (LATER, in table order). Past GUIDE_LAST_DAY nothing shows.
##
## seen: id -> true, this player's (the profile's company_onboard_<id> tips, CompanyOnboardingTracker).

const STOCK_PALLET: StringName = &"stock_pallet"
const PICK: StringName = &"pick"
const PACK: StringName = &"pack"
const DRIVE: StringName = &"drive"
const DELIVER: StringName = &"deliver"
const RETURN: StringName = &"return"
const RESTOCK: StringName = &"restock"
const UNLOAD: StringName = &"unload"
const ORDER_MORE: StringName = &"order_more"
const FILL: StringName = &"fill"

const DAY_ONE: Array[StringName] = [STOCK_PALLET, PICK, PACK, DRIVE, DELIVER, RETURN]
## The rows after the loop: id -> the first day it may show (§2).
const LATER: Dictionary = {RESTOCK: 1, UNLOAD: 2, ORDER_MORE: 2, FILL: 2}
const LATER_ORDER: Array[StringName] = [RESTOCK, UNLOAD, ORDER_MORE, FILL]
## The guide ends once day 7 is closed (the 8th day opens without it).
const GUIDE_LAST_DAY: int = 7
## Profile tip ids: TIP_PREFIX + id.
const TIP_PREFIX: String = "company_onboard_"

## id -> translation key of its line. Literal keys, so the translation test sees them.
const KEYS: Dictionary = {
	&"stock_pallet": "UI_ONBOARD_STOCK_PALLET",
	&"pick": "UI_ONBOARD_PICK",
	&"pack": "UI_ONBOARD_PACK",
	&"drive": "UI_ONBOARD_DRIVE",
	&"deliver": "UI_ONBOARD_DELIVER",
	&"return": "UI_ONBOARD_RETURN",
	&"restock": "UI_ONBOARD_RESTOCK",
	&"unload": "UI_ONBOARD_UNLOAD",
	&"order_more": "UI_ONBOARD_ORDER_MORE",
	&"fill": "UI_ONBOARD_FILL",
}
## id -> the input action the line names (keyboard or gamepad, by the screen that draws it).
const ACTIONS: Dictionary = {
	&"stock_pallet": &"interact",
	&"pick": &"interact",
	&"pack": &"interact",
	&"drive": &"drive_accelerate",
	&"deliver": &"interact",
	&"return": &"drive_accelerate",
	&"restock": &"interact",
	&"unload": &"interact",
	&"order_more": &"company_clipboard",
	&"fill": &"interact",
}


## The line for this player now: {id, key, action}, or {} when there is nothing to teach.
## player_ctx: {driving: bool, packing: bool, holding: bool}.
## company_ctx: {day: int, pallet_left: bool (units still wait on a supplier pallet), assisted_packing: bool,
##   triggers: {id: true} (the LATER rows whose trigger fired)}.
static func current(player_ctx: Dictionary, company_ctx: Dictionary, seen: Dictionary) -> Dictionary:
	var day: int = int(company_ctx.get("day", 1))
	if day > GUIDE_LAST_DAY:
		return {}
	var done: Dictionary = seen.duplicate()
	if not bool(company_ctx.get("pallet_left", true)):
		done[STOCK_PALLET] = true
	var id: StringName = _day_one(player_ctx, done)
	if id == &"":
		id = _later(company_ctx, done, day)
	return {} if id == &"" else line(id)


## {id, key, action} of a row.
static func line(id: StringName) -> Dictionary:
	return {"id": id, "key": String(KEYS[id]), "action": ACTIONS[id]}


## True when the whole day-1 loop is done for this player.
static func loop_done(seen: Dictionary) -> bool:
	for id: StringName in DAY_ONE:
		if not bool(seen.get(id, false)):
			return false
	return true


static func tip_id(id: StringName) -> StringName:
	return StringName(TIP_PREFIX + String(id))


## The day-1 step of what the player is doing, else the first one they have not done.
static func _day_one(player_ctx: Dictionary, done: Dictionary) -> StringName:
	if bool(player_ctx.get("driving", false)):
		var road: StringName = _first_pending([DRIVE, DELIVER, RETURN], done)
		if road != &"":
			return road
	if bool(player_ctx.get("packing", false)) and not done.has(PACK):
		return PACK
	if bool(player_ctx.get("holding", false)):
		var hands: StringName = _first_pending([PICK, PACK], done)
		if hands != &"":
			return hands
	return _first_pending(DAY_ONE, done)


static func _later(company_ctx: Dictionary, done: Dictionary, day: int) -> StringName:
	var triggers: Dictionary = company_ctx.get("triggers", {})
	for id: StringName in LATER_ORDER:
		if done.has(id) or day < int(LATER[id]) or not bool(triggers.get(id, false)):
			continue
		if id == FILL and bool(company_ctx.get("assisted_packing", false)):
			continue
		return id
	return &""


static func _first_pending(ids: Array[StringName], done: Dictionary) -> StringName:
	for id: StringName in ids:
		if not bool(done.get(id, false)):
			return id
	return &""
