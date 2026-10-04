extends Node
## Persistent state of the company ("Modo Empresa", expansion D-0202).
##
## Layer 1 of docs/arquitectura.md section 10: money, day, clock, reputation,
## opened gates, fleet, employees, milestones, shed layout and stock. The host
## owns it (a client holds a mirror fed by the host's snapshot, D-0219 / D-2001)
## and no RPC lives here. It is simulation only: no node besides this autoload,
## no UI class and no other autoload (lesson N-919, so a --script run can name
## it). Delivery and Endless ignore it: is_active() stays false until
## new_company() or from_dict() switches it on, and reset() switches it off.
##
## Money of the company lives here; CrewProgression.team_money stays the money
## of Delivery and Endless (S8). The file format and slots are D-0206.

var money: int = CompanyTuning.STARTING_MONEY
var day: int = CompanyTuning.STARTING_DAY
## Game minutes since midnight (08:00 = 480).
var clock_minutes: int = CompanyTuning.DAY_START_MIN
var reputation: float = CompanyTuning.STARTING_REPUTATION
## zone id -> reputation 0-100 in that zone.
var district_reputation: Dictionary = {}
var opened_gates: Array[StringName] = []
## Equipment the company owns (chains, winter coat, thermal suit...). GateRequirement reads it.
var equipment: Array[StringName] = []
var fleet: Array[Dictionary] = []
var employees: Array[Dictionary] = []
var milestones_done: Array[StringName] = []
## Shed layout: one entry per placed piece.
var layout: Array[Dictionary] = []
## Stock, in the Inventory.to_dict() form (use stock() / store_stock()).
var inventory: Dictionary = {}
var company_name: String = ""
## Wallet history (D-0501), oldest first, at most CompanyTuning.LEDGER_MAX entries:
## {day, minute, amount (signed), reason, balance (after the movement)}.
var ledger: Array[Dictionary] = []

var _active: bool = false


func _init() -> void:
	_set_defaults()


## True only while a company is loaded: false at boot and outside Company mode.
func is_active() -> bool:
	return _active


## Starts a fresh company with the starting money, day, clock and reputation.
func new_company(new_name: String = "") -> void:
	_set_defaults()
	company_name = new_name
	_active = true


## Back to the boot state: defaults and inactive. Call it on leaving Company mode.
func reset() -> void:
	_set_defaults()
	_active = false


## Everything a save or a snapshot needs. Deep copy: changing it changes nothing here.
func to_dict() -> Dictionary:
	return {
		"company_name": company_name,
		"money": money,
		"day": day,
		"clock_minutes": clock_minutes,
		"reputation": reputation,
		"district_reputation": district_reputation.duplicate(true),
		"opened_gates": opened_gates.duplicate(),
		"equipment": equipment.duplicate(),
		"fleet": fleet.duplicate(true),
		"employees": employees.duplicate(true),
		"milestones_done": milestones_done.duplicate(),
		"layout": layout.duplicate(true),
		"inventory": inventory.duplicate(true),
		"ledger": ledger.duplicate(true),
	}


## Loads what to_dict() wrote, also after a JSON round trip (ids come back as
## String, numbers as float). A missing or malformed field takes its default and
## numbers are clamped to their range. An empty dictionary loads nothing and
## returns false; otherwise the company becomes active and it returns true.
func from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	_set_defaults()
	company_name = str(data.get("company_name", ""))
	money = int(_num(data.get("money"), CompanyTuning.STARTING_MONEY))
	day = maxi(int(_num(data.get("day"), CompanyTuning.STARTING_DAY)), 1)
	clock_minutes = clampi(
		int(_num(data.get("clock_minutes"), CompanyTuning.DAY_START_MIN)),
		0,
		CompanyTuning.MINUTES_PER_DAY - 1
	)
	reputation = _clamp_reputation(_num(data.get("reputation"), CompanyTuning.STARTING_REPUTATION))
	var by_zone: Variant = data.get("district_reputation", {})
	if by_zone is Dictionary:
		for zone: Variant in by_zone:
			if _is_id(zone) and _is_num(by_zone[zone]):
				district_reputation[StringName(zone)] = _clamp_reputation(float(by_zone[zone]))
	opened_gates = _ids(data.get("opened_gates", []))
	equipment = _ids(data.get("equipment", []))
	milestones_done = _ids(data.get("milestones_done", []))
	fleet = _entries(data.get("fleet", []))
	employees = _entries(data.get("employees", []))
	layout = _entries(data.get("layout", []))
	var saved_stock: Variant = data.get("inventory", {})
	if saved_stock is Dictionary:
		var stock_in := Inventory.new()
		stock_in.from_dict(saved_stock)
		inventory = stock_in.to_dict()
	ledger = _entries(data.get("ledger", []))
	if ledger.size() > CompanyTuning.LEDGER_MAX:
		ledger = ledger.slice(ledger.size() - CompanyTuning.LEDGER_MAX)
	_active = true
	return true


## Adds money to the wallet and records it. A zero or negative amount does nothing
## (returns false): use spend() to take money out.
func earn(amount: int, reason: StringName) -> bool:
	if amount <= 0:
		return false
	_record(amount, reason)
	return true


## True when the wallet covers the amount (a spend never leaves the money below zero).
func can_afford(amount: int) -> bool:
	return amount >= 0 and money >= amount


## Takes money out and records it. False, and nothing changes, when the amount is
## negative or the wallet does not cover it. Charges that must go through even into
## the red (rent, penalties) use charge().
func spend(amount: int, reason: StringName) -> bool:
	if amount <= 0 or not can_afford(amount):
		return false
	_record(-amount, reason)
	return true


## Takes money out even if the balance goes negative (rent and penalties; what
## happens with a negative balance is D-0510). A zero or negative amount does nothing.
func charge(amount: int, reason: StringName) -> bool:
	if amount <= 0:
		return false
	_record(-amount, reason)
	return true


## Sum of the movements still in the ledger that have this reason (signed).
func ledger_total(reason: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in ledger:
		if StringName(str(entry.get("reason", ""))) == reason:
			total += int(entry.get("amount", 0))
	return total


## True once the gate was opened. An opened gate is never closed again (map decision, point 7).
func is_gate_open(gate_id: StringName) -> bool:
	return opened_gates.has(gate_id)


## Opens a gate for good. False when it was already open.
func open_gate(gate_id: StringName) -> bool:
	if gate_id == &"" or opened_gates.has(gate_id):
		return false
	opened_gates.append(gate_id)
	return true


## What a GateRequirement needs to know about the company, as plain values.
func gate_owned() -> Dictionary:
	var vehicles: Array[StringName] = []
	for entry: Dictionary in fleet:
		var key: Variant = entry.get("vehicle", entry.get("key", ""))
		if typeof(key) == TYPE_STRING or typeof(key) == TYPE_STRING_NAME:
			vehicles.append(StringName(key))
	return {"milestones": milestones_done, "equipment": equipment, "vehicles": vehicles}


## A copy of the stock as an Inventory, ready to use. Writes go back through
## store_stock(): the dictionary is the stored form, not a live view.
func stock() -> Inventory:
	var result := Inventory.new()
	result.from_dict(inventory)
	return result


func store_stock(stock_in: Inventory) -> void:
	inventory = stock_in.to_dict()


func _record(signed_amount: int, reason: StringName) -> void:
	money += signed_amount
	ledger.append(
		{
			"day": day,
			"minute": clock_minutes,
			"amount": signed_amount,
			"reason": String(reason),
			"balance": money,
		}
	)
	if ledger.size() > CompanyTuning.LEDGER_MAX:
		ledger.pop_front()


func _set_defaults() -> void:
	money = CompanyTuning.STARTING_MONEY
	day = CompanyTuning.STARTING_DAY
	clock_minutes = CompanyTuning.DAY_START_MIN
	reputation = CompanyTuning.STARTING_REPUTATION
	district_reputation = {}
	opened_gates = []
	equipment = []
	fleet = []
	employees = []
	milestones_done = []
	layout = []
	inventory = Inventory.new().to_dict()
	ledger = []
	company_name = ""


func _clamp_reputation(value: float) -> float:
	return clampf(value, CompanyTuning.REPUTATION_MIN, CompanyTuning.REPUTATION_MAX)


## Only an int or a float counts as a number; anything else (null, String, Array)
## takes the fallback instead of breaking the load.
static func _num(raw: Variant, fallback: float) -> float:
	return float(raw) if _is_num(raw) else fallback


static func _is_num(raw: Variant) -> bool:
	return typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT


static func _is_id(raw: Variant) -> bool:
	return typeof(raw) == TYPE_STRING or typeof(raw) == TYPE_STRING_NAME


static func _ids(raw: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if raw is Array:
		for item: Variant in raw:
			if _is_id(item):
				result.append(StringName(item))
	return result


static func _entries(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw is Array:
		for item: Variant in raw:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result
