extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_host_leaves.gd
##
## The host leaves mid-day (expansion D-2005, like N-222; company_root.gd, company_interrupted_day.gd,
## company_save.gd, main_menu.gd):
## - CompanyInterruptedDay.summary() of a hand-built company: the money of the day is DaySummary's
##   (only today's ledger movements: income, costs, profit, the opening balance, truncated), plus the
##   clock (or a running clock's minute, held within the day), the wallet and the units of the live
##   or the stored stock; describe() is UI_COMPANY_DAY_CUT, or UI_COMPANY_DAY_CUT_PARTIAL when the
##   ledger may have lost movements of the day; hold() keeps one summary that peek_pending() shows
##   and take_pending() gives once;
## - CompanySave: a save marked interrupted carries "interrupted": true and the day in progress;
##   was_interrupted() says so (also from the .bak a cut write left) and load_into() gives that day
##   with the clock at DAY_START_MIN and money, ledger and stock as saved; a plain save, a v1 file
##   without the key and a key that isn't a JSON true load unchanged (clock kept); save() never
##   overwrites a file from a newer build;
## - a host CompanyRoot (solo) that comes up with no company loads its slot first: a new company only
##   when the slot is empty or corrupt (kept as .bad), the saved one when there is one (an interrupted
##   day from the opening), and over a newer build's file it plays a new company that is never saved,
##   not even when it comes up again with that company still on;
## - CompanyRoot.stock_for_save() puts what every hands:<peer> held in SAVED_HANDS_LOCATION, totals and
##   reservations as a save keeps them (the same totals, nothing reserved: D-0252; the floor, boxes and
##   packages are test_company_save_stock's), without touching the stock it copies;
## - two ENet peers in one process, each with a CompanyRoot (its world left out): the host plays day 2
##   (11:15, money and stock moved by events), the client mirrors it (snapshot, then events) and takes
##   3 hens in its hands. The host leaves (its session closes, its world goes): the host's world saves
##   the day as it stood at the last applied event, interrupted, with every hand emptied onto the
##   floor; the client, on server_disconnected, keeps a summary with the host's day, clock, money,
##   today's income and costs and the live units, gets its own company back, stops its world and
##   loads the main menu, which shows that summary once, all without an engine error;
## - a client whose session fails with no server_disconnected (NetworkManager.session_failed, a
##   handshake that times out) does the same: summary, its own company back, world stopped, menu.
## - the same with a live GameClock and DayCycle in both worlds (D-0203): the host opens the day, the
##   client follows it; after the host leaves, and even once the client's session is an offline
##   one (where CompanyNet.is_host() is true), the client's DayCycle moves nothing: its net.seq and
##   its phase stay as they were, though the OPENING time is long over.
## Expected in the log: CompanySave's warnings for the corrupt slot it replaces and the newer file
## it doesn't overwrite, and CompanyRoot's warning that it could not save over the newer one.

const PORT: int = 24643
## Nobody listens here: a client to it stays connecting, never connected nor disconnected.
const CLOSED_PORT: int = 24644
const DIR: String = "user://test_company_host_leaves"
const SLOT: String = "host"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const LIVE_PORT: int = 24646
const CLOCK_MID_DAY: int = 11 * 60 + 15

var _failures: int = 0
var _catcher := ErrorCatcher.new()


## A CompanyRoot without its world (zones, shed, player): only what D-2005 is about, the business
## side _start_company() sets up, with the CompanyState this peer runs.
class NetOnlyRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)

	## No GameClock or DayCycle (D-0203): this test keeps the minute in the company itself, and a
	## running clock would write its own over it.
	func _add_day(_state: Node) -> void:
		pass


## The same root with its GameClock and DayCycle (_add_day() kept) and the host's day opened.
class LiveDayRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)
		_open_company_day.call_deferred()


## Engine errors (not warnings) logged while the host leaves.
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	CompanyInterruptedDay.take_pending()
	_clean()
	_check_summary()
	_check_saves()
	await _check_load_on_entry()
	_check_stock_for_save()
	await _check_host_leaves()
	CompanyInterruptedDay.take_pending()
	await _check_session_failed()
	CompanyInterruptedDay.take_pending()
	await _check_live_day_host_leaves()
	CompanyInterruptedDay.take_pending()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: host leaves mid-day: the client gets the day's summary in the menu and its own"
			+ " company back, the host saves the day interrupted (hands on the floor) and it loads"
			+ " from the opening; a host loads its slot on entry and never overwrites a newer save")
	quit(_failures)


## A CompanyState of its own (not the autoload), in the tree so its facts reach EventBus.
func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	root.add_child(state)
	return state


## Day 1: +300 and -100. Day 2 (today): +50 and -20. 7 hens and 2 puppies in the stored stock.
func _check_summary() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Summary SRL")
	state.call(&"earn", 300, &"order_paid")
	state.call(&"charge", 100, &"rent")
	state.set(&"day", 2)
	state.set(&"clock_minutes", 10 * 60)
	state.call(&"earn", 50, &"order_paid")
	state.call(&"spend", 20, &"supplier")
	var stored := Inventory.new()
	stored.receive(&"hen", 7, &"dock")
	stored.receive(&"puppy", 2, &"shelf:a_1")
	state.call(&"store_stock", stored)

	var seen: Dictionary = CompanyInterruptedDay.summary(state)
	_expect(seen.get("day") == 2 and seen.get("clock_minutes") == 600 and seen.get("money") == 730,
		"The summary has the company's day, clock and money (got %s)" % [seen])
	_expect(seen.get("income") == 50 and seen.get("costs") == 20 and seen.get("profit") == 30
		and seen.get("opening") == 700,
		"Only today's movements count: income 50, costs 20, profit 30, opening 700 (got %s)" % [seen])
	var day_summary: Dictionary = DaySummary.build(state, 2)
	var same_money: bool = true
	for key: String in day_summary:
		same_money = same_money and seen.get(key) == day_summary[key]
	_expect(same_money, "The money of the day is DaySummary.build()'s, key by key")
	_expect(seen.get("units") == 9 and seen.get("truncated") == false,
		"Without a live stock it counts the stored one, 9 units (got %s)" % seen.get("units"))
	var live := Inventory.new()
	live.receive(&"hen", 3, &"hands:5")
	var with_live: Dictionary = CompanyInterruptedDay.summary(state, live, 11 * 60 + 5)
	_expect(with_live.get("units") == 3 and with_live.get("clock_minutes") == 665,
		"A live stock and a running clock's minute win over the stored ones (got %s)" % [with_live])
	var late: Dictionary = CompanyInterruptedDay.summary(state, null, 30 * 60)
	_expect(late.get("clock_minutes") == CompanyTuning.MINUTES_PER_DAY - 1,
		"A minute past midnight is held within the day (got %s)" % late.get("clock_minutes"))

	state.set(&"day", 3)
	var quiet: Dictionary = CompanyInterruptedDay.summary(state)
	_expect(quiet.get("income") == 0 and quiet.get("costs") == 0 and quiet.get("opening") == 730
		and quiet.get("money") == 730,
		"A quiet day opens and stands at the wallet's balance (got %s)" % [quiet])
	var full: Array[Dictionary] = []
	for i: int in range(CompanyTuning.LEDGER_MAX):
		full.append({"day": 3, "minute": 500, "amount": 1, "reason": "tip", "balance": 731 + i})
	state.set(&"ledger", full)
	var cut: Dictionary = CompanyInterruptedDay.summary(state)
	_expect(cut.get("truncated") == true and cut.get("income") == CompanyTuning.LEDGER_MAX,
		"A full ledger that starts today may have lost movements of it: truncated (got %s)" % [cut])
	var partial: String = TranslationServer.translate("UI_COMPANY_DAY_CUT_PARTIAL") % [
		3, "10:00", CompanyTuning.LEDGER_MAX, 0, 730, 9]
	_expect(CompanyInterruptedDay.describe(cut) == partial,
		"...and its line marks income and costs as partial (got '%s')"
		% CompanyInterruptedDay.describe(cut))
	state.set(&"day", 4)
	_expect(CompanyInterruptedDay.summary(state).get("truncated") == false,
		"A full ledger that starts before today lost none of it")
	var empty: Dictionary = CompanyInterruptedDay.summary(null)
	_expect(empty.get("day") == 0 and empty.get("units") == 0, "No company gives a zero summary")

	_expect(CompanyInterruptedDay.describe({}) == "", "An empty summary has no line")
	var line: String = CompanyInterruptedDay.describe(seen)
	var wanted: String = TranslationServer.translate("UI_COMPANY_DAY_CUT") % [2, "10:00", 50, 20, 730, 9]
	_expect(line == wanted and line.contains("10:00"),
		"describe() fills UI_COMPANY_DAY_CUT with day, clock, income, costs, money, units (got '%s')"
		% line)
	CompanyInterruptedDay.hold(seen)
	seen["day"] = 99
	_expect(CompanyInterruptedDay.peek_pending().get("day") == 2
		and CompanyInterruptedDay.peek_pending().get("day") == 2,
		"hold() keeps a copy of the summary and peek_pending() shows it without taking it")
	_expect(CompanyInterruptedDay.take_pending().get("day") == 2, "take_pending() gives it")
	_expect(CompanyInterruptedDay.take_pending().is_empty() and CompanyInterruptedDay.take_pending_text() == ""
		and CompanyInterruptedDay.peek_pending().is_empty(),
		"...only once")
	state.free()


func _check_saves() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Saves SRL")
	state.set(&"day", 3)
	state.set(&"clock_minutes", 14 * 60 + 30)
	state.call(&"earn", 210, &"order_paid")
	var stock := Inventory.new()
	stock.receive(&"hen", 5, &"shelf:a_1")
	state.call(&"store_stock", stock)
	var before: Dictionary = state.call(&"to_dict")

	_expect(CompanySave.save(state, "cut", DIR, true), "An interrupted day is saved")
	var raw: Dictionary = _raw("cut")
	var company: Dictionary = raw.get("company", {})
	_expect(raw.get("interrupted") == true and int(company.get("day", 0)) == 3
		and int(raw.get("version", 0)) == CompanySave.VERSION,
		"The file says interrupted: true, keeps the day in progress and version 1 (got %s)"
		% [raw.keys()])
	_expect(CompanySave.was_interrupted("cut", DIR), "was_interrupted() reads it")
	var loaded: Node = _new_state()
	var result: CompanySave.LoadResult = CompanySave.load_into(loaded, "cut", DIR)
	_expect(result == CompanySave.LoadResult.LOADED and loaded.get(&"day") == 3
		and loaded.get(&"clock_minutes") == CompanyTuning.DAY_START_MIN,
		"Loading it gives day 3 from the opening (day %s, clock %s)"
		% [loaded.get(&"day"), loaded.get(&"clock_minutes")])
	var expected: Dictionary = before.duplicate(true)
	expected["clock_minutes"] = CompanyTuning.DAY_START_MIN
	_expect(_same(loaded.call(&"to_dict"), expected),
		"...with money, ledger and stock as saved (money %s)" % loaded.get(&"money"))

	# A write cut after the old file became .bak and before the new one took its place.
	_expect(CompanySave.save(state, "bak", DIR, true), "Another interrupted day is saved")
	var bak_path: String = CompanySave.path_for("bak", DIR)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(bak_path),
		ProjectSettings.globalize_path(bak_path + ".bak"))
	_expect(CompanySave.was_interrupted("bak", DIR) and FileAccess.file_exists(bak_path + ".bak"),
		"With only its .bak left, was_interrupted() reads the .bak and moves nothing")

	_expect(CompanySave.save(state, "plain", DIR), "A day not cut short is saved as before")
	_expect(_raw("plain").get("interrupted") == false and not CompanySave.was_interrupted("plain", DIR),
		"...not interrupted")
	loaded.call(&"reset")
	CompanySave.load_into(loaded, "plain", DIR)
	_expect(_same(loaded.call(&"to_dict"), before),
		"...and loads unchanged, clock kept (clock %s)" % loaded.get(&"clock_minutes"))

	var old_file: Dictionary = {"version": 1, "company": before}
	_write(CompanySave.path_for("old", DIR), JSON.stringify(old_file))
	old_file["interrupted"] = "yes"
	_write(CompanySave.path_for("odd", DIR), JSON.stringify(old_file))
	for slot: String in ["old", "odd"]:
		loaded.call(&"reset")
		var old_result: CompanySave.LoadResult = CompanySave.load_into(loaded, slot, DIR)
		_expect(old_result == CompanySave.LoadResult.LOADED and not CompanySave.was_interrupted(slot, DIR)
			and loaded.get(&"clock_minutes") == 14 * 60 + 30,
			"A v1 file %s is not interrupted: the clock is kept (got %s)"
			% ["without the key" if slot == "old" else "whose key isn't a JSON true",
				loaded.get(&"clock_minutes")])
	_expect(not CompanySave.was_interrupted("missing", DIR), "A missing slot is not interrupted")

	var newer: String = JSON.stringify({"version": CompanySave.VERSION + 1, "company": {"money": 1}})
	_write(CompanySave.path_for("newer", DIR), newer)
	_expect(not CompanySave.save(state, "newer", DIR, true)
		and FileAccess.get_file_as_string(CompanySave.path_for("newer", DIR)) == newer,
		"save() never overwrites a file from a newer build")
	loaded.free()
	state.free()


## A solo host root that comes up without a company: what its slot holds decides which one it
## plays, and whether leaving may write the slot.
func _check_load_on_entry() -> void:
	var state: Node = _new_state()
	var path: String = CompanySave.path_for("entry", DIR)

	var fresh: NetOnlyRoot = await _enter_solo(state, "entry")
	_expect(bool(state.call(&"is_active")) and state.get(&"money") == CompanyTuning.STARTING_MONEY,
		"An empty slot: the root starts a new company (money %s)" % state.get(&"money"))
	await _leave(fresh)
	_expect(CompanySave.was_interrupted("entry", DIR), "...and leaving saves it, interrupted")

	var saved := _new_state()
	saved.call(&"new_company", "Saved SRL")
	saved.set(&"day", 4)
	saved.set(&"clock_minutes", 15 * 60)
	saved.call(&"earn", 734, &"order_paid")
	CompanySave.save(saved, "entry", DIR, true)
	saved.free()
	state.call(&"reset")
	var resumed: NetOnlyRoot = await _enter_solo(state, "entry")
	_expect(state.get(&"company_name") == "Saved SRL" and state.get(&"money") == 1234
		and state.get(&"day") == 4 and state.get(&"clock_minutes") == CompanyTuning.DAY_START_MIN,
		"A saved slot: the root plays that company, day 4 from the opening (got '%s', %s, day %s, %s)"
		% [state.get(&"company_name"), state.get(&"money"), state.get(&"day"),
			state.get(&"clock_minutes")])
	state.call(&"earn", 10, &"tip")
	await _leave(resumed)
	_expect(int((_raw("entry").get("company", {}) as Dictionary).get("money", 0)) == 1244,
		"...and leaving saves what was played on it (money 1244)")

	_write(path, "{ not json")
	state.call(&"reset")
	var mended: NetOnlyRoot = await _enter_solo(state, "entry")
	_expect(bool(state.call(&"is_active")) and state.get(&"money") == CompanyTuning.STARTING_MONEY
		and FileAccess.file_exists(path + ".bad"),
		"A corrupt slot: kept as .bad and a new company is played")
	await _leave(mended)
	_expect(CompanySave.was_interrupted("entry", DIR) and FileAccess.file_exists(path + ".bad"),
		"...which leaving saves, the .bad left alone")

	var newer: String = JSON.stringify({"version": CompanySave.VERSION + 1, "company": {"money": 1}})
	_write(path, newer)
	state.call(&"reset")
	var guest: NetOnlyRoot = await _enter_solo(state, "entry")
	_expect(bool(state.call(&"is_active")) and state.get(&"money") == CompanyTuning.STARTING_MONEY,
		"A newer build's slot: the root plays a new company")
	_expect(not guest.save_interrupted_day(), "...that it doesn't save over that file")
	await _leave(guest)
	var again: NetOnlyRoot = await _enter_solo(state, "entry")
	await _leave(again)
	_expect(FileAccess.get_file_as_string(path) == newer,
		"...neither leaving nor coming up again with it still on touches the newer file")
	state.free()


## A host root's stock as it is saved: hands emptied onto SAVED_HANDS_LOCATION.
func _check_stock_for_save() -> void:
	var live := Inventory.new()
	live.receive(&"hen", 6, &"dock")
	live.move(&"hen", 2, &"dock", &"hands:1")
	live.receive(&"puppy", 3, &"hands:7")
	live.receive(&"hen", 1, CompanyRoot.SAVED_HANDS_LOCATION)
	live.reserve(&"hen", 2, &"order_9")
	var before: Dictionary = live.to_dict()
	var kept: Inventory = CompanyRoot.stock_for_save(live)
	_expect(live.to_dict() == before, "stock_for_save() leaves the live stock as it was")
	_expect(kept.count(&"hen", CompanyRoot.SAVED_HANDS_LOCATION) == 3
		and kept.count(&"puppy", CompanyRoot.SAVED_HANDS_LOCATION) == 3
		and kept.contents_at(&"hands:1").is_empty() and kept.contents_at(&"hands:7").is_empty(),
		"Every hand's units lie in %s (got %s)" % [CompanyRoot.SAVED_HANDS_LOCATION, kept.to_dict()])
	_expect(kept.total_units() == live.total_units() and kept.count(&"hen", &"dock") == 4,
		"...the rest and the totals unchanged")
	_expect(kept.reserved_by(&"order_9").is_empty() and (kept.to_dict()["reserved"] as Dictionary).is_empty()
		and live.reserved_by(&"order_9") == {&"hen": 2},
		"...and nothing reserved in the copy (D-0252), the live reservation kept (got %s)"
		% [kept.to_dict()["reserved"]])


func _check_host_leaves() -> void:
	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 2) == OK, "The test hosts an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server

	# The host's company, on day 2 at 11:15: yesterday +300 -100, today +120 -40 +25; 10 hens.
	var host_state: Node = _new_state()
	host_state.call(&"new_company", "Host SRL")
	host_state.call(&"earn", 300, &"order_paid")
	host_state.call(&"charge", 100, &"rent")
	host_state.set(&"day", 2)
	host_state.set(&"clock_minutes", CLOCK_MID_DAY)
	host_state.call(&"earn", 120, &"order_paid")
	host_state.call(&"spend", 40, &"supplier")
	host_state.call(&"earn", 25, &"tip")
	var stock := Inventory.new()
	stock.receive(&"hen", 10, &"dock")
	host_state.call(&"store_stock", stock)
	var host_root := NetOnlyRoot.new()
	host_root.name = "CompanyRoot"
	host_root.company_state = host_state
	host_root.save_slot = SLOT
	host_root.save_dir = DIR
	host_side.add_child(host_root)
	var host_net: CompanyNet = host_root.net
	host_net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	host_net.player_origin = func(_peer: int) -> Variant: return Vector3(0.0, 0.0, 1.0)
	_play(host_net, 3)
	_expect(host_net.seq == 3 and host_root.host_day_seen().is_empty(),
		"The host plays 3 events and has no host's day to sum up (seq %d)" % host_net.seq)

	# The client has a company of its own, which must come back.
	var client_state: Node = _new_state()
	client_state.call(&"new_company", "Mine")
	client_state.call(&"earn", 42, &"tip")
	var own: Dictionary = client_state.call(&"to_dict")
	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = client
	var client_root := NetOnlyRoot.new()
	client_root.name = "CompanyRoot"
	client_root.company_state = client_state
	client_side.add_child(client_root)
	var client_net: CompanyNet = client_root.net
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 \
			and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if not connected:
		_end(host_side, client_side, [server, client], [host_state, client_state])
		return
	var client_id: int = client_side.multiplayer.get_unique_id()
	var client_hands: StringName = CompanyNet.hands_location(client_id)
	host_net.send_snapshot(client_id)
	_play(host_net, 2)
	client_net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 3})
	var mirrored: bool = await _wait_for(func() -> bool:
		return client_net.seq == 6 and not client_net.awaiting_snapshot())
	_expect(mirrored and client_state.get(&"company_name") == "Host SRL"
		and client_net.inventory.to_dict() == host_net.inventory.to_dict(),
		"The client mirrors the host's day: snapshot, then 3 events (client seq %d)" % client_net.seq)
	_expect(host_net.inventory.count(&"hen", client_hands) == 3
		and host_net.inventory.count(&"hen", CompanyNet.hands_location(1)) == 2,
		"The client holds 3 hens and the host 2 when the host leaves (%s)" % [host_net.inventory.to_dict()])
	_expect(host_root.save_interrupted_day() and host_net.inventory.count(&"hen", client_hands) == 3,
		"Saving the day mid-play leaves the live stock's hands as they are")

	# What the client holds the moment it hears the host is gone, before the menu loads.
	var at_loss: Dictionary = {}
	client_side.multiplayer.server_disconnected.connect(func() -> void:
		at_loss.merge({
			"pending": CompanyInterruptedDay.peek_pending(),
			"company": client_state.call(&"to_dict"),
			"active": client_state.call(&"is_active"),
			"mode": client_root.process_mode,
		}))
	var host_stock: Inventory = Inventory.new()
	host_stock.from_dict(host_net.inventory.to_dict())
	OS.add_logger(_catcher)
	_catcher.take()
	# The host leaves, as hud_pause.leave_to_menu() does: its session closes, then its world goes.
	server.close()
	host_side.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	host_root.queue_free()
	var in_menu: bool = await _wait_for(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_MENU)
	for _i: int in range(3):
		await process_frame
	var errors: Array[String] = _catcher.take()
	OS.remove_logger(_catcher)

	_expect(errors.is_empty(), "No engine error while the host leaves (got %s)" % [errors])
	_expect(not at_loss.is_empty(), "The client hears the host is gone (server_disconnected)")
	var seen: Dictionary = at_loss.get("pending", {})
	_expect(seen.get("day") == 2 and seen.get("clock_minutes") == CLOCK_MID_DAY
		and seen.get("money") == 805 and seen.get("opening") == 700,
		"It keeps the host's day 2 at 11:15 with 805 in the wallet, 700 at the opening (got %s)" % [seen])
	_expect(seen.get("income") == 145 and seen.get("costs") == 40,
		"...today's income 145 and costs 40, not yesterday's (got %s)" % [seen])
	_expect(seen.get("units") == host_stock.total_units(),
		"...and the units of the live stock it mirrored, hands included (got %s)" % seen.get("units"))
	_expect(at_loss.get("company") == own and at_loss.get("active") == true,
		"Its own company is back as soon as the summary is kept (name '%s')"
		% (at_loss.get("company", {}) as Dictionary).get("company_name"))
	_expect(at_loss.get("mode") == Node.PROCESS_MODE_DISABLED, "Its world stops")
	await _check_menu_shows(in_menu, seen)

	_expect(CompanySave.was_interrupted(SLOT, DIR),
		"The host's world saved the day as interrupted when it closed")
	var saved: Dictionary = _raw(SLOT).get("company", {})
	_expect(int(saved.get("day", 0)) == 2 and int(saved.get("clock_minutes", 0)) == CLOCK_MID_DAY
		and int(saved.get("money", 0)) == 805,
		"...as it stood: day 2 at 11:15 with 805 (got %s)" % [saved])
	var reloaded: Node = _new_state()
	var result: CompanySave.LoadResult = CompanySave.load_into(reloaded, SLOT, DIR)
	var reloaded_stock: Inventory = reloaded.call(&"stock")
	_expect(result == CompanySave.LoadResult.LOADED and reloaded.get(&"day") == 2
		and reloaded.get(&"clock_minutes") == CompanyTuning.DAY_START_MIN
		and reloaded.get(&"money") == 805,
		"Loading the host's save starts day 2 from the opening with 805 (day %s, clock %s)"
		% [reloaded.get(&"day"), reloaded.get(&"clock_minutes")])
	_expect(reloaded_stock.total_units() == host_stock.total_units()
		and reloaded_stock.count(&"hen", &"cart:c1") == host_stock.count(&"hen", &"cart:c1")
		and reloaded_stock.count(&"hen", CompanyRoot.SAVED_HANDS_LOCATION) == 5,
		"...and the stock at the last applied event, the 5 hens in hands on the floor (%s)"
		% [reloaded_stock.to_dict()])
	_expect(reloaded_stock.contents_at(client_hands).is_empty()
		and reloaded_stock.contents_at(CompanyNet.hands_location(1)).is_empty(),
		"...and nobody holds anything in the save")
	reloaded.free()

	_close_menu()
	_end(host_side, client_side, [server, client], [host_state, client_state])
	await process_frame


## Host and client with a live day; the host leaves; the client's DayCycle must not take over.
func _check_live_day_host_leaves() -> void:
	var host_side := Node.new()
	host_side.name = "LiveHostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "LiveClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(LIVE_PORT, 2) == OK, "The test hosts a live day on localhost:%d" % LIVE_PORT)
	host_side.multiplayer.multiplayer_peer = server
	var host_state: Node = _new_state()
	host_state.call(&"new_company", "Live SRL")
	var host_root := LiveDayRoot.new()
	host_root.name = "CompanyRoot"
	host_root.company_state = host_state
	host_root.save_slot = "live"
	host_root.save_dir = DIR
	host_side.add_child(host_root)
	await process_frame
	await process_frame
	_expect(host_root.day_cycle.phase() == DayCycle.Phase.OPENING and host_root.day_cycle.current_day() == 1,
		"The host's world opens its day (got %s)" % host_root.day_cycle.phase_name())
	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", LIVE_PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = client
	var client_state: Node = _new_state()
	client_state.call(&"new_company", "Mine")
	var client_root := LiveDayRoot.new()
	client_root.name = "CompanyRoot"
	client_root.company_state = client_state
	client_side.add_child(client_root)
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 \
			and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if not connected:
		_end(host_side, client_side, [server, client], [host_state, client_state])
		return
	host_root.net.send_snapshot(client_side.multiplayer.get_unique_id())
	var cycle: DayCycle = client_root.day_cycle
	var followed: bool = await _wait_for(func() -> bool:
		return cycle.phase() == DayCycle.Phase.OPENING and not client_root.net.awaiting_snapshot())
	_expect(followed, "The client's day cycle follows the host's (got %s)" % cycle.phase_name())
	# The OPENING time is long over for this client: were it the host, its next poll would move on.
	cycle.ticks = func() -> int: return Time.get_ticks_msec() + 60_000
	var seq: int = client_root.net.seq

	server.close()
	host_side.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	host_root.queue_free()
	var in_menu: bool = await _wait_for(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_MENU)
	_expect(in_menu and client_root.process_mode == Node.PROCESS_MODE_DISABLED,
		"The client's world stops when the host leaves")
	# Its session is now an offline one, where CompanyNet.is_host() is true.
	client_side.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for _i: int in range(40):
		await process_frame
	_expect(client_root.net.seq == seq and cycle.phase() == DayCycle.Phase.OPENING,
		"...and its day cycle moves nothing (seq %d of %d, phase %s)"
		% [client_root.net.seq, seq, cycle.phase_name()])
	_close_menu()
	_end(host_side, client_side, [server, client], [host_state, client_state])
	await process_frame


## A client whose session fails before any server_disconnected (a handshake that times out):
## NetworkManager.session_failed alone takes it to the menu the same way.
func _check_session_failed() -> void:
	var host_state: Node = _new_state()
	host_state.call(&"new_company", "Far SRL")
	host_state.set(&"day", 5)
	host_state.set(&"clock_minutes", 9 * 60)
	host_state.call(&"earn", 60, &"order_paid")
	var host := CompanyNet.new()
	host.company = host_state
	host.inventory.receive(&"puppy", 4, &"dock")
	host.seq = 3

	var side := Node.new()
	side.name = "LateSide"
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var peer := ENetMultiplayerPeer.new()
	_expect(peer.create_client("127.0.0.1", CLOSED_PORT) == OK, "A client starts joining a silent host")
	side.multiplayer.multiplayer_peer = peer
	var client_state: Node = _new_state()
	client_state.call(&"new_company", "Mine too")
	var own: Dictionary = client_state.call(&"to_dict")
	var client_root := NetOnlyRoot.new()
	client_root.name = "CompanyRoot"
	client_root.company_state = client_state
	side.add_child(client_root)
	await process_frame
	var disconnected: Array[bool] = []
	side.multiplayer.server_disconnected.connect(func() -> void: disconnected.append(true))
	_expect(client_root.net.apply_snapshot(host.snapshot())
		and client_state.get(&"company_name") == "Far SRL",
		"The client mirrors the host's company from a snapshot")

	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	_expect(network != null, "NetworkManager is there to fail the session")
	if network != null:
		network.emit_signal(&"session_failed", "timeout")
	# The menu loads deferred: what the client kept is still pending right after the signal.
	var seen: Dictionary = CompanyInterruptedDay.peek_pending()
	_expect(seen.get("day") == 5 and seen.get("clock_minutes") == 9 * 60 and seen.get("money") == 560
		and seen.get("income") == 60 and seen.get("units") == 4,
		"session_failed alone keeps the host's day 5 at 09:00 with 560 and 4 units (got %s)" % [seen])
	_expect(client_root.process_mode == Node.PROCESS_MODE_DISABLED,
		"...stops the client's world")
	_expect(client_state.call(&"to_dict") == own and bool(client_state.call(&"is_active")),
		"...and gives it its own company back")
	var in_menu: bool = await _wait_for(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MAIN_MENU)
	_expect(disconnected.is_empty(), "No server_disconnected came")
	await _check_menu_shows(in_menu, seen)

	_close_menu()
	peer.close()
	set_multiplayer(null, side.get_path())
	side.free()
	host.free()
	host_state.free()
	client_state.free()
	await process_frame


## The client landed in the main menu, which shows `seen`'s line once.
func _check_menu_shows(in_menu: bool, seen: Dictionary) -> void:
	_expect(in_menu, "The client lands in the main menu (current scene %s)"
		% (current_scene.scene_file_path if current_scene != null else "none"))
	if in_menu:
		var status: Label = current_scene.get(&"_status_label")
		var wanted: String = CompanyInterruptedDay.describe(seen)
		_expect(status != null and status.visible and status.text == wanted,
			"The menu shows the day's summary '%s' (got '%s')"
			% [wanted, status.text if status != null else ""])
	_expect(CompanyInterruptedDay.peek_pending().is_empty(), "...once: the menu took it")
	await process_frame


func _close_menu() -> void:
	if current_scene != null:
		var menu: Node = current_scene
		current_scene = null
		menu.queue_free()


## A solo host root (this tree's offline multiplayer) on `state`, saving to `slot` in DIR.
func _enter_solo(state: Node, slot: String) -> NetOnlyRoot:
	var solo := NetOnlyRoot.new()
	solo.company_state = state
	solo.save_slot = slot
	solo.save_dir = DIR
	root.add_child(solo)
	await process_frame
	return solo


func _leave(solo: Node) -> void:
	solo.queue_free()
	await process_frame


## `count` host requests, units_take and units_store by turns: 2 hens at a time from the dock to
## the hands, then into the cart.
func _play(net: CompanyNet, count: int) -> void:
	for i: int in range(count):
		if net.seq % 2 == 0:
			net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 2})
		else:
			net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 2})


static func _stations() -> Dictionary:
	return {
		&"dock": {"location": &"dock", "spot": Vector3(-1.0, 0.0, 0.0)},
		&"bin": {"location": &"cart:c1", "spot": Vector3(-1.0, 0.0, 1.0)},
	}


func _end(host_side: Node, client_side: Node, peers: Array, states: Array) -> void:
	for peer: MultiplayerPeer in peers:
		peer.close()
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	for state: Node in states:
		state.free()


func _raw(slot: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CompanySave.path_for(slot, DIR)))
	return raw if raw is Dictionary else {}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Same company after a JSON round trip (ints come back as floats, ids as Strings).
static func _same(a: Dictionary, b: Dictionary) -> bool:
	return _canonical(a) == _canonical(b)


static func _canonical(value: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
