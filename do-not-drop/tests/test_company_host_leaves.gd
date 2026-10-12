extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_host_leaves.gd
##
## The host leaves mid-day (expansion D-2005, like N-222; company_root.gd, company_interrupted_day.gd,
## company_save.gd, main_menu.gd):
## - CompanyInterruptedDay.summary() of a hand-built company: only today's ledger movements count
##   (income, costs by sign, profit, the opening balance before today's first one), the clock (or a
##   running clock's minute, held within the day), the units of the live or the stored stock, a quiet
##   day, a full ledger that starts today (truncated) or before; describe() is UI_COMPANY_DAY_CUT;
##   hold() keeps one summary that take_pending() gives once;
## - CompanySave: a save marked interrupted carries "interrupted": true and the day in progress;
##   was_interrupted() says so and load_into() gives that day with the clock at DAY_START_MIN and
##   money, ledger and stock as saved; a plain save, a v1 file without the key and a key that isn't a
##   JSON true load unchanged (clock kept);
## - two ENet peers in one process, each with a CompanyRoot (its world left out): the host plays day 2
##   (11:15, money and stock moved by events), the client mirrors it (snapshot, then events). The host
##   leaves (its session closes, its world goes): the host's world saves the day as it stood at the
##   last applied event, interrupted; the client, on server_disconnected, keeps a summary with the
##   host's day, clock, money, today's income and costs and the live units, gets its own company back,
##   stops its world and loads the main menu, which shows that summary once, all without an engine
##   error.

const PORT: int = 24643
const DIR: String = "user://test_company_host_leaves"
const SLOT: String = "host"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const CLOCK_MID_DAY: int = 11 * 60 + 15

var _failures: int = 0
var _catcher := ErrorCatcher.new()


## A CompanyRoot without its world (zones, shed, player): only what D-2005 is about, the business
## side _start_company() sets up, with the CompanyState this peer runs.
class NetOnlyRoot extends CompanyRoot:
	var company_state: Node

	func _ready() -> void:
		_start_company(company_state)


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
	await _check_host_leaves()
	CompanyInterruptedDay.take_pending()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: host leaves mid-day: the client gets the day's summary in the menu and its own"
			+ " company back, the host saves the day interrupted and it loads from the opening")
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
		and seen.get("movements") == 2,
		"Only today's movements count: income 50, costs 20, profit 30 in 2 movements (got %s)" % [seen])
	_expect(seen.get("opening") == 700,
		"The opening balance is the one before today's first movement (got %s)" % seen.get("opening"))
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
	_expect(quiet.get("income") == 0 and quiet.get("costs") == 0 and quiet.get("movements") == 0
		and quiet.get("opening") == 730 and quiet.get("money") == 730,
		"A quiet day opens and stands at the wallet's balance (got %s)" % [quiet])
	var full: Array[Dictionary] = []
	for i: int in range(CompanyTuning.LEDGER_MAX):
		full.append({"day": 3, "minute": 500, "amount": 1, "reason": "tip", "balance": 731 + i})
	state.set(&"ledger", full)
	var cut: Dictionary = CompanyInterruptedDay.summary(state)
	_expect(cut.get("truncated") == true and cut.get("income") == CompanyTuning.LEDGER_MAX,
		"A full ledger that starts today may have lost movements of it: truncated (got %s)" % [cut])
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
	_expect(CompanyInterruptedDay.take_pending().get("day") == 2,
		"hold() keeps a copy of the summary and take_pending() gives it")
	_expect(CompanyInterruptedDay.take_pending().is_empty() and CompanyInterruptedDay.take_pending_text() == "",
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
	loaded.free()
	state.free()


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
	host_net.send_snapshot(client_id)
	_play(host_net, 2)
	var mirrored: bool = await _wait_for(func() -> bool:
		return client_net.seq == 5 and not client_net.awaiting_snapshot())
	_expect(mirrored and client_state.get(&"company_name") == "Host SRL"
		and client_net.inventory.to_dict() == host_net.inventory.to_dict(),
		"The client mirrors the host's day: snapshot, then 2 events (client seq %d)" % client_net.seq)

	# What the client holds the moment it hears the host is gone, before the menu loads.
	var at_loss: Dictionary = {}
	client_side.multiplayer.server_disconnected.connect(func() -> void:
		at_loss.merge({
			"pending": CompanyInterruptedDay._pending.duplicate(true),
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
	_expect(seen.get("income") == 145 and seen.get("costs") == 40 and seen.get("movements") == 3,
		"...today's income 145 and costs 40, not yesterday's (got %s)" % [seen])
	_expect(seen.get("units") == host_stock.total_units(),
		"...and the units of the live stock it mirrored (got %s)" % seen.get("units"))
	_expect(at_loss.get("company") == own and at_loss.get("active") == true,
		"Its own company is back as soon as the summary is kept (name '%s')"
		% (at_loss.get("company", {}) as Dictionary).get("company_name"))
	_expect(at_loss.get("mode") == Node.PROCESS_MODE_DISABLED, "Its world stops")
	_expect(in_menu, "The client lands in the main menu (current scene %s)"
		% (current_scene.scene_file_path if current_scene != null else "none"))
	if in_menu:
		var status: Label = current_scene.get(&"_status_label")
		_expect(status != null and status.visible and status.text == CompanyInterruptedDay.describe(seen),
			"The menu shows the day's summary (got '%s')" % (status.text if status != null else ""))
	_expect(CompanyInterruptedDay.take_pending().is_empty(), "...once: the menu took it")

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
	_expect(reloaded_stock.to_dict() == host_stock.to_dict()
		and reloaded_stock.count(&"hen", &"cart:c1") == host_stock.count(&"hen", &"cart:c1"),
		"...and the stock at the last applied event, not the one the day started with (%s)"
		% [reloaded_stock.to_dict()])
	reloaded.free()

	if current_scene != null:
		var menu: Node = current_scene
		current_scene = null
		menu.queue_free()
	_end(host_side, client_side, [server, client], [host_state, client_state])
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
