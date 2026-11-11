extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_dev_flags.gd
##
## Development flags of the Modo Empresa (expansion D-0238; company_dev_flags.gd, company_root.gd):
## - parse() reads --company-day=<n>, --district=<id> and --money=<n>, the last of a repeated flag
##   winning, and leaves out a day under 1, a day or money that is not a whole number and an empty
##   district; other arguments are ignored;
## - apply() puts the company on day n at DAY_START_MIN, sets its money (negative too) and opens every
##   gate of the zone (suburbio: gate_suburbio), with an open zone (centro) opening nothing and an
##   unknown zone dropped from what it reports; no flags change nothing;
## - a host CompanyRoot (solo) handed dev_args applies them to the company it starts: its DayCycle
##   opens day n, the wallet holds the money and the zone's gates are open; without flags a new
##   company keeps day 1 and its STARTING_MONEY.

const DIR: String = "user://test_company_dev_flags"
const SLOT: String = "dev_flags"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"

var _failures: int = 0


## A CompanyRoot without its world (zones, shed, player): the business side and the host's day.
class LiveDayRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)
		_open_company_day.call_deferred()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_clean()
	_check_parse()
	_check_apply()
	await _check_root_applies()
	await _check_root_without_flags()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: --company-day, --district and --money parse, apply to the company and reach the"
			+ " host's CompanyRoot; bad values are left out")
	quit(_failures)


func _check_parse() -> void:
	var flags: Dictionary = CompanyDevFlags.parse(PackedStringArray([
		"--autostart-company", "--company-day=3", "--district=suburbio", "--money=9000", "--company-day=7"]))
	_expect(flags.get("day") == 7, "The last --company-day wins (got %s)" % [flags])
	_expect(flags.get("district") == &"suburbio", "--district gives the zone id (got %s)" % [flags])
	_expect(flags.get("money") == 9000, "--money gives the amount (got %s)" % [flags])
	_expect(flags.size() == 3, "Other arguments are ignored (got %s)" % [flags])
	var bad: Dictionary = CompanyDevFlags.parse(PackedStringArray([
		"--company-day=0", "--company-day=abc", "--money=12.5", "--money=", "--district="]))
	_expect(bad.is_empty(), "A day under 1, non-whole numbers and an empty district are left out (got %s)" % [bad])
	_expect(CompanyDevFlags.parse(PackedStringArray(["--money=-200"])).get("money") == -200,
		"--money takes a debt")


func _check_apply() -> void:
	var zones: Array[ZoneDefinition] = CompanyRoot.load_zones()
	var state: Node = _new_state()
	state.call(&"new_company", "Dev SRL")
	state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN + 90)
	var applied: Dictionary = CompanyDevFlags.apply(state,
		PackedStringArray(["--company-day=5", "--money=-200", "--district=suburbio"]), zones)
	_expect(applied.size() == 3, "apply() reports the three flags (got %s)" % [applied])
	_expect(int(state.get(&"day")) == 5, "--company-day=5 puts the company on day 5 (got %s)" % [state.get(&"day")])
	_expect(int(state.get(&"clock_minutes")) == CompanyTuning.DAY_START_MIN,
		"The day starts at its opening (got %s)" % [state.get(&"clock_minutes")])
	_expect(int(state.get(&"money")) == -200, "--money=-200 sets the wallet (got %s)" % [state.get(&"money")])
	_expect(bool(state.call(&"is_gate_open", &"gate_suburbio")), "--district=suburbio opens gate_suburbio")

	var gates_before: int = (state.get(&"opened_gates") as Array).size()
	applied = CompanyDevFlags.apply(state, PackedStringArray(["--district=centro"]), zones)
	_expect(applied.get("district") == &"centro"
		and (state.get(&"opened_gates") as Array).size() == gates_before,
		"An open zone (centro) is applied and opens no gate (got %s)" % [state.get(&"opened_gates")])
	applied = CompanyDevFlags.apply(state, PackedStringArray(["--district=atlantida"]), zones)
	_expect(not applied.has("district"), "An unknown zone is dropped (got %s)" % [applied])

	var fresh: Node = _new_state()
	fresh.call(&"new_company", "Plain SRL")
	_expect(CompanyDevFlags.apply(fresh, PackedStringArray(), zones).is_empty()
		and int(fresh.get(&"day")) == CompanyTuning.STARTING_DAY
		and int(fresh.get(&"money")) == CompanyTuning.STARTING_MONEY,
		"No flags change nothing")
	_expect(CompanyDevFlags.apply(null, PackedStringArray(["--money=1"]), zones).is_empty(),
		"Without a company nothing is applied")
	state.queue_free()
	fresh.queue_free()


func _check_root_applies() -> void:
	var state: Node = _new_state()
	var host: LiveDayRoot = await _enter(state,
		PackedStringArray(["--company-day=4", "--money=12345", "--district=campo"]))
	_expect(bool(state.call(&"is_active")), "The host started a company")
	_expect(host.day_cycle.current_day() == 4,
		"The host's DayCycle opens day 4 (got %d)" % host.day_cycle.current_day())
	_expect(int(state.get(&"money")) == 12345, "The wallet holds 12345 (got %s)" % [state.get(&"money")])
	var campo: Array = _zone_gates(&"campo")
	_expect(not campo.is_empty(), "campo has gates to open (got %s)" % [campo])
	for gate_id: StringName in campo:
		_expect(bool(state.call(&"is_gate_open", gate_id)), "--district=campo opens %s" % gate_id)
	host._hosted_state = null
	await _leave(host)
	state.queue_free()


func _check_root_without_flags() -> void:
	_clean()
	var state: Node = _new_state()
	var host: LiveDayRoot = await _enter(state, PackedStringArray())
	_expect(host.day_cycle.current_day() == CompanyTuning.STARTING_DAY
		and int(state.get(&"money")) == CompanyTuning.STARTING_MONEY,
		"Without flags a new company opens day 1 with its starting money (got day %d, %s)"
		% [host.day_cycle.current_day(), state.get(&"money")])
	host._hosted_state = null
	await _leave(host)
	state.queue_free()


func _zone_gates(id: StringName) -> Array:
	for zone: ZoneDefinition in CompanyRoot.load_zones():
		if zone.id == id:
			return zone.gates
	return []


func _enter(state: Node, args: PackedStringArray) -> LiveDayRoot:
	var host := LiveDayRoot.new()
	host.company_state = state
	host.save_slot = SLOT
	host.save_dir = DIR
	host.dev_args = args
	root.add_child(host)
	await process_frame
	await process_frame
	return host


func _leave(host: Node) -> void:
	host.queue_free()
	await process_frame


## A CompanyState of its own (not the autoload), in the tree so its facts reach EventBus.
func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	root.add_child(state)
	return state


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
