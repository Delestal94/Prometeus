class_name DayCloseReport
extends RefCounted
## What the closing screen of a company day shows besides the money (expansion D-1905): the milestones
## reached, the wages paid and the events of tomorrow. Pure functions, no node and no autoload, so the
## panel (DaySummaryPanel) and its tests read the same rows.
##
## - Ledger reasons with a prefix are named here: `milestone:<id>` (a milestone's prize, diseno/hitos.md) is
##   "Hito: <name>" and `day_event:<id>` (diseno/eventos-del-dia.md §2.6) is "Evento: <name>". A milestone's
##   or event's name is the key WORLD_MILESTONE_<ID> / WORLD_DAY_EVENT_<ID> when the table has it, else the id.
## - Wages: one row per employee of CompanyState.employees ({name?, level, wage?}), the wage read from the
##   entry or from the level's table (EmployeeLevels, D-0515).
## - Milestones: the ids of the `milestone:` income of the day plus the ones the panel heard during the day
##   (EventBus.milestone_reached), each once, in order.
## - Tomorrow: the ids of the day events announced the eve before (`extras.tomorrow`), one "Mañana:" line each.
## Hiring (D-1001), the milestones themselves (group 04) and the day events (D-0123) fill these when they exist;
## until then every section is empty and the panel hides it.

const MILESTONE_PREFIX: String = "milestone:"
const EVENT_PREFIX: String = "day_event:"
const WAGES_REASON: String = "wages"
const MILESTONE_REASON_KEY: String = "UI_DAYCLOSE_REASON_MILESTONE"
const EVENT_REASON_KEY: String = "UI_DAYCLOSE_REASON_EVENT"
const TOMORROW_KEY: String = "UI_DAYCLOSE_TOMORROW"


## The extras the panel draws for `day`: {employees, tomorrow}. `net` is CompanyNet (its `company` holds the
## employees); null or without a company gives empty lists.
static func extras(net: Object, _day: int) -> Dictionary:
	var employees: Array = []
	var company: Object = net.get(&"company") if net != null else null
	if company != null and &"employees" in company:
		employees = company.employees
	return {"employees": employees.duplicate(true), "tomorrow": []}


## The shown name of a prefixed ledger reason, or "" when `reason` has no known prefix.
static func reason_name(reason: String) -> String:
	if reason.begins_with(MILESTONE_PREFIX):
		return TranslationServer.translate(MILESTONE_REASON_KEY) % milestone_name(reason.trim_prefix(MILESTONE_PREFIX))
	if reason.begins_with(EVENT_PREFIX):
		return TranslationServer.translate(EVENT_REASON_KEY) % event_name(reason.trim_prefix(EVENT_PREFIX))
	return ""


static func milestone_name(id: String) -> String:
	return _named("WORLD_MILESTONE_%s" % id.to_upper(), id)


static func event_name(id: String) -> String:
	return _named("WORLD_DAY_EVENT_%s" % id.to_upper(), id)


## The milestones of the day: the `milestone:` income reasons of `summary`, then `heard`, each id once.
static func milestones(summary: Dictionary, heard: Array = []) -> Array[String]:
	var found: Array[String] = []
	var income: Variant = summary.get("income_by_reason", {})
	if income is Dictionary:
		for reason: Variant in DaySummary.sorted_reasons(income):
			if str(reason).begins_with(MILESTONE_PREFIX):
				_add_once(found, str(reason).trim_prefix(MILESTONE_PREFIX))
	for id: Variant in heard:
		_add_once(found, str(id))
	return found


## Wage rows: [shown name, daily wage] per employee entry; an entry that is not a dictionary or has no wage
## (no `wage` and an unknown level) is skipped.
static func wage_rows(employees: Array) -> Array:
	var result: Array = []
	for raw: Variant in employees:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var level := StringName(str(entry.get("level", "")))
		var wage: int = int(entry.get("wage", EmployeeLevels.wage_for(level) if level != &"" else 0))
		if wage <= 0:
			continue
		result.append([_employee_name(entry, level), wage])
	return result


static func wages_total(rows: Array) -> int:
	var total: int = 0
	for row: Array in rows:
		total += int(row[1])
	return total


## The "Mañana:" lines of the day events in `ids`.
static func tomorrow_lines(ids: Array) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in ids:
		if str(id) != "":
			lines.append(TranslationServer.translate(TOMORROW_KEY) % event_name(str(id)))
	return lines


static func _employee_name(entry: Dictionary, level: StringName) -> String:
	var given: String = str(entry.get("name", ""))
	if given != "":
		return given
	var known: EmployeeLevel = EmployeeLevels.find(level) if level != &"" else null
	return TranslationServer.translate(known.display_key) if known != null else str(level)


static func _named(key: String, fallback: String) -> String:
	var text: String = TranslationServer.translate(key)
	return fallback if text == key else text


static func _add_once(into: Array[String], id: String) -> void:
	if id != "" and not into.has(id):
		into.append(id)
