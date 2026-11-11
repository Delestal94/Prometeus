class_name CompanyDevFlags
extends RefCounted
## Development flags of the "Modo Empresa" (expansion D-0238), for tests and captures:
##   --company-day=<n>   the company plays day n (n >= 1), from its opening (DAY_START_MIN)
##   --district=<id>     every gate of zone <id> (data/zones/<id>.tres) is open
##   --money=<n>         the company's wallet holds n (any integer; no ledger entry)
## CompanyRoot applies them on the host (solo too) when its world comes up, after the slot is loaded
## or a new company started, so a render_* script that loads company_root.tscn takes them from its
## own command line (`-- --company-day=5 --money=9000`). A client never applies them: its company is
## the host's. What they change is the company itself, and is saved with it like any other change.
##
## A value that does not parse, or a zone that does not exist, is left out with a warning.
## Pure: it takes the company as a parameter (anything with day, clock_minutes, money and
## open_gate(), like CompanyState) and names no autoload (lesson N-919).

const DAY_PREFIX: String = "--company-day="
const DISTRICT_PREFIX: String = "--district="
const MONEY_PREFIX: String = "--money="


## The flags in `args` that parse, as {"day": int, "district": StringName, "money": int}; a key is
## missing when its flag is absent or wrong. The last of a repeated flag wins.
static func parse(args: PackedStringArray) -> Dictionary:
	var flags: Dictionary = {}
	for arg: String in args:
		if arg.begins_with(DAY_PREFIX):
			var day: String = arg.trim_prefix(DAY_PREFIX)
			if day.is_valid_int() and day.to_int() >= 1:
				flags["day"] = day.to_int()
			else:
				push_warning("CompanyDevFlags: %s wants a day of 1 or more" % arg)
		elif arg.begins_with(DISTRICT_PREFIX):
			var district: String = arg.trim_prefix(DISTRICT_PREFIX)
			if district.is_empty():
				push_warning("CompanyDevFlags: %s names no zone" % arg)
			else:
				flags["district"] = StringName(district)
		elif arg.begins_with(MONEY_PREFIX):
			var money: String = arg.trim_prefix(MONEY_PREFIX)
			if money.is_valid_int():
				flags["money"] = money.to_int()
			else:
				push_warning("CompanyDevFlags: %s wants a whole number" % arg)
	return flags


## Applies the flags of `args` to `company` and returns the ones applied (parse()'s keys).
## `zones` are the map's zones (CompanyRoot.load_zones()); a --district not among them is dropped.
static func apply(company: Object, args: PackedStringArray, zones: Array[ZoneDefinition]) -> Dictionary:
	var flags: Dictionary = parse(args)
	if company == null:
		return {}
	if flags.has("day"):
		company.day = int(flags["day"])
		company.clock_minutes = CompanyTuning.DAY_START_MIN
	if flags.has("money"):
		company.money = int(flags["money"])
	if flags.has("district"):
		var zone: ZoneDefinition = _zone(zones, flags["district"])
		if zone == null:
			push_warning("CompanyDevFlags: no zone %s in data/zones/" % flags["district"])
			flags.erase("district")
		else:
			for gate_id: StringName in zone.gates:
				company.open_gate(gate_id)
	return flags


static func _zone(zones: Array[ZoneDefinition], id: StringName) -> ZoneDefinition:
	for zone: ZoneDefinition in zones:
		if zone.id == id:
			return zone
	return null
