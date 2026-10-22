extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_autosave.gd
##
## Automatic save at the day's close and on leaving (expansion D-0236; company_root.gd, day_cycle.gd,
## company_save.gd), with a host CompanyRoot (solo) and its live GameClock and DayCycle:
## - day 1 runs OPENING, OPERATING, CLOSING (the clock at 20:00) and SUMMARY; the SUMMARY saves the
##   slot at once, not interrupted, as day 2's opening (DAY_START_MIN) with the day's money and the
##   stock, hands emptied onto SAVED_HANDS_LOCATION; the company in play keeps day 1;
## - the game "killed" mid day 2 (next_day(), money earned, the root dropped from the tree without its
##   _exit_tree save, as a killed process never runs it): loading the slot gives the last close, day 2
##   from the opening without what day 2 earned;
## - leaving during the summary keeps that close (day 2, not interrupted) instead of saving day 1
##   interrupted, which would play the closed day again;
## - a company the root comes up with and no save in the slot gets its opening saved at once (D-0251);
## - leaving mid-day writes nothing of the day (D-0251): with money earned and charged, units moved and
##   held, the slot is that opening (day 1, STARTING_MONEY, an empty ledger, the stock as it opened)
##   marked interrupted (D-2005); loading it gives the same, and so does the company in play once its
##   world is gone; save_closed_day() outside SUMMARY saves nothing.
## - D-0253: the host closes day 1 early from OPERATING (DayClose.close()): with no trip out the next
##   poll is SUMMARY, the clock still before 20:00, and the slot is day 2's opening, not interrupted,
##   with the day's money; leaving afterwards keeps that close.
## - N-989: a shop purchase made in SUMMARY (shop_bought) saves the close again, so the slot keeps the
##   purchase and the money it cost.

const DIR: String = "user://test_company_autosave"
const SLOT: String = "auto"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Real msec the DayCycle reads: far past the OPENING's few seconds.
const LATER_MSEC: int = 60_000

var _failures: int = 0


## A CompanyRoot without its world (zones, shed, player): the business side, with the GameClock and
## DayCycle _add_day() gives it, and the host's day opened.
class LiveDayRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)
		_open_company_day.call_deferred()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_clean()
	await _check_close_and_kill()
	await _check_leave_in_summary()
	await _check_leave_mid_day()
	await _check_close_early()
	await _check_buy_in_summary()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: the closed day is saved as the next day's opening, a killed game comes back at"
			+ " its last close, leaving in the summary keeps it, leaving mid-day saves interrupted and closing"
			+ " early saves like a close")
	quit(_failures)


func _check_close_and_kill() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Auto SRL")
	var stock: Inventory = state.call(&"stock")
	stock.receive(&"hen", 5, &"dock")
	state.call(&"store_stock", stock)
	var host: LiveDayRoot = await _enter(state)
	_expect(host.day_cycle.phase() == DayCycle.Phase.OPENING and host.day_cycle.current_day() == 1,
		"The host opens day 1 (got %s, day %d)" % [host.day_cycle.phase_name(), host.day_cycle.current_day()])
	_expect(not host.save_closed_day(), "save_closed_day() during OPENING saves nothing")
	_expect(CompanySave.exists(SLOT, DIR) and int((_raw().get("company", {}) as Dictionary).get("day", 0)) == 1
		and not CompanySave.was_interrupted(SLOT, DIR),
		"...the slot holds day 1's opening, saved when the world came up (D-0251)")
	state.call(&"earn", 250, &"order_paid")
	host.net.inventory.move(&"hen", 2, &"dock", &"hands:1")
	_close_day(host)
	_expect(host.day_cycle.phase() == DayCycle.Phase.SUMMARY,
		"Day 1 reaches SUMMARY (got %s)" % host.day_cycle.phase_name())
	var raw: Dictionary = _raw()
	var company: Dictionary = raw.get("company", {})
	_expect(CompanySave.exists(SLOT, DIR) and not CompanySave.was_interrupted(SLOT, DIR),
		"The SUMMARY saves the slot at once, not interrupted")
	_expect(int(company.get("day", 0)) == 2 and int(company.get("clock_minutes", 0)) == CompanyTuning.DAY_START_MIN,
		"...as day 2's opening (got day %s at %s)" % [company.get("day"), company.get("clock_minutes")])
	_expect(int(company.get("money", 0)) == CompanyTuning.STARTING_MONEY + 250,
		"...with the day's money (got %s)" % company.get("money"))
	var saved_stock := Inventory.new()
	saved_stock.from_dict(company.get("inventory", {}))
	_expect(saved_stock.count(&"hen") == 5
		and saved_stock.count(&"hen", CompanyRoot.SAVED_HANDS_LOCATION) == 2,
		"...and the stock, what was in hand on the floor (hens %d, on the floor %d)"
		% [saved_stock.count(&"hen"), saved_stock.count(&"hen", CompanyRoot.SAVED_HANDS_LOCATION)])
	_expect(int(state.get(&"day")) == 1, "The company in play keeps day 1 until next_day()")

	_expect(host.day_cycle.next_day(), "The host moves on to day 2")
	_expect(int(state.get(&"day")) == 2, "...which the company takes (got %s)" % state.get(&"day"))
	state.call(&"earn", 400, &"order_paid")
	await _kill(host)
	var loaded: Node = _new_state()
	var result: CompanySave.LoadResult = CompanySave.load_into(loaded, SLOT, DIR)
	_expect(result == CompanySave.LoadResult.LOADED and int(loaded.get(&"day")) == 2
		and int(loaded.get(&"clock_minutes")) == CompanyTuning.DAY_START_MIN
		and int(loaded.get(&"money")) == CompanyTuning.STARTING_MONEY + 250,
		"Killed mid day 2, the slot loads the last close: day 2 from the opening, without day 2's money"
		+ " (got day %s at %s, money %s)" % [loaded.get(&"day"), loaded.get(&"clock_minutes"), loaded.get(&"money")])
	loaded.free()
	state.free()
	_clean()


func _check_leave_in_summary() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Summary SRL")
	var host: LiveDayRoot = await _enter(state)
	_close_day(host)
	state.call(&"earn", 30, &"tip")
	await _leave(host)
	var company: Dictionary = _raw().get("company", {})
	_expect(not CompanySave.was_interrupted(SLOT, DIR) and int(company.get("day", 0)) == 2
		and int(company.get("money", 0)) == CompanyTuning.STARTING_MONEY + 30,
		"Leaving during the summary keeps the close: day 2, not interrupted, money 530 (got day %s, %s,"
		% [company.get("day"), company.get("money")] + " interrupted %s)" % CompanySave.was_interrupted(SLOT, DIR))
	state.free()
	_clean()


func _check_leave_mid_day() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Mid SRL")
	var stock: Inventory = state.call(&"stock")
	stock.receive(&"hen", 5, &"dock")
	state.call(&"store_stock", stock)
	var host: LiveDayRoot = await _enter(state)
	var opening: Dictionary = _raw().get("company", {})
	host.day_cycle.ticks = func() -> int: return Time.get_ticks_msec() + LATER_MSEC
	host.day_cycle.poll()
	_expect(host.day_cycle.phase() == DayCycle.Phase.OPERATING,
		"Day 1 is OPERATING (got %s)" % host.day_cycle.phase_name())
	state.call(&"earn", 180, &"order_paid")
	state.call(&"charge", 60, &"rent")
	host.net.inventory.move(&"hen", 2, &"dock", &"hands:1")
	host.net.inventory.move(&"hen", 1, &"dock", &"box:b1")
	_expect(not host.save_closed_day(), "save_closed_day() mid-day saves nothing")
	await _leave(host)
	var raw: Dictionary = _raw()
	var company: Dictionary = raw.get("company", {})
	_expect(CompanySave.was_interrupted(SLOT, DIR) and int(company.get("day", 0)) == 1,
		"Leaving mid-day marks day 1 interrupted (D-2005) (got day %s)" % company.get("day"))
	_expect(company == opening,
		"...and writes nothing of it: the company in the slot is the opening, untouched (D-0251)")
	var loaded: Node = _new_state()
	CompanySave.load_into(loaded, SLOT, DIR)
	var loaded_stock: Inventory = loaded.call(&"stock")
	_expect(int(loaded.get(&"money")) == CompanyTuning.STARTING_MONEY
		and (loaded.get(&"ledger") as Array).size() == (opening.get("ledger", []) as Array).size()
		and int(loaded.get(&"clock_minutes")) == CompanyTuning.DAY_START_MIN,
		"Loading it gives the opening's money and ledger at 08:00, not the day's (got %s, ledger %s)"
		% [loaded.get(&"money"), loaded.get(&"ledger")])
	_expect(loaded_stock.count(&"hen", &"dock") == 5 and loaded_stock.total_units() == 5,
		"...and the opening's stock: the 5 hens on the dock (got %s)" % [loaded_stock.to_dict()])
	_expect(int(state.get(&"money")) == CompanyTuning.STARTING_MONEY and int(state.get(&"day")) == 1
		and (state.get(&"ledger") as Array).size() == (opening.get("ledger", []) as Array).size(),
		"The company in play went back to that opening when its world went (money %s)" % state.get(&"money"))
	loaded.free()
	state.free()
	_clean()


func _check_close_early() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Early SRL")
	var host: LiveDayRoot = await _enter(state)
	host.day_cycle.ticks = func() -> int: return Time.get_ticks_msec() + LATER_MSEC
	host.day_cycle.poll()
	state.call(&"earn", 120, &"order_paid")
	_expect(DayClose.close(host.day_cycle) and host.day_cycle.phase() == DayCycle.Phase.CLOSING,
		"The host closes day 1 early from OPERATING (got %s)" % host.day_cycle.phase_name())
	host.day_cycle.poll()
	_expect(host.day_cycle.phase() == DayCycle.Phase.SUMMARY
		and host.clock.minute_now() < float(CompanyTuning.DAY_END_MIN),
		"...and with no trip out the summary comes before 20:00 (got %s at %.0f min)"
		% [host.day_cycle.phase_name(), host.clock.minute_now()])
	var company: Dictionary = _raw().get("company", {})
	_expect(CompanySave.exists(SLOT, DIR) and not CompanySave.was_interrupted(SLOT, DIR)
		and int(company.get("day", 0)) == 2
		and int(company.get("money", 0)) == CompanyTuning.STARTING_MONEY + 120,
		"Closing early saves day 2's opening, not interrupted, with the day's money (got day %s, %s)"
		% [company.get("day"), company.get("money")])
	await _leave(host)
	_expect(not CompanySave.was_interrupted(SLOT, DIR) and int(_raw().get("company", {}).get("day", 0)) == 2,
		"...and leaving afterwards keeps that close")
	state.free()
	_clean()

## OPENING, OPERATING, CLOSING and SUMMARY of the open day: the OPENING's seconds pass on the
## DayCycle's ticks, the clock jumps to 20:00, no trip is out.
func _check_buy_in_summary() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Shop SRL")
	var host: LiveDayRoot = await _enter(state)
	_close_day(host)
	var price: int = CompanyShopNet.new().find(&"upgrade_1").price
	host.net.request(CompanyShopNet.BUY, {"item": &"upgrade_1"})
	var company: Dictionary = _raw().get("company", {})
	_expect(int(company.get("money", 0)) == CompanyTuning.STARTING_MONEY - price,
		"A purchase in SUMMARY is in the saved close, money %d (got %s)"
		% [CompanyTuning.STARTING_MONEY - price, company.get("money")])
	var loaded: Node = _new_state()
	var result: CompanySave.LoadResult = CompanySave.load_into(loaded, SLOT, DIR)
	_expect(result == CompanySave.LoadResult.LOADED and (loaded.get(&"equipment") as Array).has(&"upgrade_1"),
		"...and reloading it keeps the upgrade")
	loaded.free()
	await _leave(host)
	state.free()
	_clean()


func _close_day(host: LiveDayRoot) -> void:
	host.day_cycle.ticks = func() -> int: return Time.get_ticks_msec() + LATER_MSEC
	host.day_cycle.poll()
	host.clock.start(float(CompanyTuning.DAY_END_MIN))
	host.day_cycle.poll()
	host.day_cycle.poll()


func _enter(state: Node) -> LiveDayRoot:
	var host := LiveDayRoot.new()
	host.company_state = state
	host.save_slot = SLOT
	host.save_dir = DIR
	root.add_child(host)
	await process_frame
	await process_frame
	return host


func _leave(host: Node) -> void:
	host.queue_free()
	await process_frame


## As a killed process: the root goes without its _exit_tree() save. Its company is cut loose first,
## so the save on leaving the tree finds none.
func _kill(host: LiveDayRoot) -> void:
	host._hosted_state = null
	host.queue_free()
	await process_frame


## A CompanyState of its own (not the autoload), in the tree so its facts reach EventBus.
func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	root.add_child(state)
	return state


func _raw() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CompanySave.path_for(SLOT, DIR)))
	return raw if raw is Dictionary else {}


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
