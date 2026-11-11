extends RefCounted
## Pure helpers for the run log (run_telemetry.gd): no state, no autoloads, so
## tests and the file format can lean on them directly.

## Bump when a field changes meaning, so tools/telemetry-summary.py can tell
## old files from new ones. Adding a field is not a change of meaning: the "kind"
## field (D-0239) was added without bumping, and a file without it is a "run".
const FORMAT_VERSION: int = 1

## "kind" of a delivery run record (S-805) and of a company day record (D-0239).
const KIND_RUN: String = "run"
const KIND_COMPANY_DAY: String = "company_day"


## "HUD_TRAP_GROWING_WEIGHT" -> "growing_weight": the trap's id, which is the
## same in every language (the name key is what travels over the network).
static func trap_id(name_key: String) -> String:
	if name_key.is_empty():
		return "unknown"
	# Two trims rather than one "HUD_..." literal: the translation test reads any
	# such string in scripts as a key that must exist in the table.
	return name_key.trim_prefix("HUD_").trim_prefix("TRAP_").to_lower()


## "2026-09-30_15-42-10": date and time, sortable, and free of the characters
## Windows refuses in a file name (":" above all).
static func file_stem(datetime: Dictionary) -> String:
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [int(datetime.get("year", 0)), int(datetime.get("month", 0)),
			int(datetime.get("day", 0)), int(datetime.get("hour", 0)), int(datetime.get("minute", 0)),
			int(datetime.get("second", 0))]


## "2026-09-30_15-42-10_day3": the run stem plus the company day, so a day file
## sorts by date with the runs and is told apart by name too.
static func day_file_stem(datetime: Dictionary, day: int) -> String:
	return "%s_day%d" % [file_stem(datetime), day]


## "run" or "company_day". A file written before D-0239 has no "kind" and is a run.
static func record_kind(record: Dictionary) -> String:
	return str(record.get("kind", KIND_RUN))


## event name -> how many times it appears in `events` (the day's event list).
static func day_event_counts(events: Array) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Variant in events:
		if entry is Dictionary:
			var name: String = str((entry as Dictionary).get("event", ""))
			if not name.is_empty():
				counts[name] = int(counts.get(name, 0)) + 1
	return counts


## Dictionaries and arrays with StringName and other engine types turned into
## plain JSON values (strings, numbers, bools), so a ledger reason or id can
## go into a record without surprises.
static func plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			out[str(key)] = plain(value[key])
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in value:
			list.append(plain(item))
		return list
	if value is StringName:
		return String(value)
	return value


## A company day record as readable lines: the day, the money, the orders and
## the money by reason. Works on a record read back from its JSON file (numbers
## come back as floats), which is how a person or a tool checks a playtest day.
static func describe_day(record: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var summary: Dictionary = record.get("summary", {}) as Dictionary
	var counts: Dictionary = record.get("counts", {}) as Dictionary
	if counts.is_empty():
		counts = day_event_counts(record.get("events", []) as Array)
	lines.append("Day %d (%s, crew %d)" % [int(record.get("day", 0)), str(record.get("role", "solo")),
			int(record.get("crew_size", 1))])
	lines.append("Income %d, costs %d, profit %d" % [int(summary.get("income", 0)), int(summary.get("costs", 0)),
			int(summary.get("profit", 0))])
	lines.append("Wallet %d -> %d" % [int(summary.get("opening", 0)), int(summary.get("closing", 0))])
	lines.append("Orders: %d added, %d packed, %d delivered" % [int(counts.get("order_added", 0)),
			int(counts.get("order_packed", 0)), int(counts.get("order_delivered", 0))])
	lines.append("Supplies arrived: %d, boxes sealed: %d" % [int(counts.get("supply_arrived", 0)),
			int(counts.get("box_sealed", 0))])
	var unlocks: int = int(counts.get("gate_opened", 0)) + int(counts.get("milestone_reached", 0))
	if unlocks > 0:
		lines.append("Gates opened: %d, milestones: %d" % [int(counts.get("gate_opened", 0)),
				int(counts.get("milestone_reached", 0))])
	lines.append_array(_reason_lines("Money in", summary.get("income_by_reason", {}) as Dictionary))
	lines.append_array(_reason_lines("Money out", summary.get("cost_by_reason", {}) as Dictionary))
	if bool(summary.get("truncated", false)):
		lines.append("Note: the ledger was full, the day's money may be incomplete")
	var dropped: int = int(record.get("events_dropped", 0))
	if dropped > 0:
		lines.append("Note: %d events past the cap were counted but not listed" % dropped)
	return lines


## "Money in: order_paid 120, tip 15", biggest first (ties by name); nothing for none.
static func _reason_lines(title: String, by_reason: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if by_reason.is_empty():
		return lines
	var reasons: Array = by_reason.keys()
	reasons.sort_custom(func(a: Variant, b: Variant) -> bool:
		var amount_a: int = int(by_reason[a])
		var amount_b: int = int(by_reason[b])
		return str(a) < str(b) if amount_a == amount_b else amount_a > amount_b)
	var parts := PackedStringArray()
	for reason: Variant in reasons:
		parts.append("%s %d" % [str(reason), int(by_reason[reason])])
	lines.append("%s: %s" % [title, ", ".join(parts)])
	return lines
