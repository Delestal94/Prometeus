extends SceneTree
## Bot that plays a whole Modo Empresa day (D-2016, the closing criterion of the F1 vertical slice D-0111;
## D-2016.4 moved it onto the game's own paths). Not a test_*.gd: the runner does not pick it up. Run:
##   <godot> --headless --path do-not-drop --script res://tests/bot_company_day.gd -- --players=2
## Opens the company world (scenes/gameplay/company_root.tscn, like bench_company.gd) on a new company of seed
## ORDERS_SEED, waits for the day to reach OPENING (bounded, 10 s) and runs the stages in STAGES order on that one
## world, each one using what the one before left. Each stage returns {"status": "ok"|"fail"|"not_implemented",
## "reason"} and is timed in ms.
##
## Who plays (bot_company_crew.gd): the host's own player and, with --players=2 or more, a second player of the crew
## in the host's world whose requests go through the host's own check of a peer's request (no transport: D-2017
## plays the pair over ENet). Both are moved by teleport next to what they use, so every reach check is a real one.
## Everything the game can do, the bot does through the game: CompanyNet requests at the stations the world itself
## resolves (CompanyShed.station_for; CompanyRoot sets it as CompanyNet.stations, the bot never replaces it), boxes
## carried by hand, the dispatch board, the fleet's van under its own physics, the day's own phases and save.
##   receive_pallet  the first truck's pallets are in reception (in the stock, drawn), a sealed one gives nothing.
##                   STUB pallet_unload: the bot opens them and takes their units itself (D-0607.c)
##   shelve_stock    a slot labelled for another product refuses the handful (wrong_product); every unit goes to the
##                   slot labelled for it with units_store at ShelfPicking's station, the players taking turns
##   take_orders     the world plans the day at its OPENING and brings each order into the shared book as the
##                   shed's minute reaches it (D-0813.1); the bot jumps the clock (BOT_SKIP) to the arrival that
##                   completes BOXES_GOAL orders it can pack and keeps those, copied nowhere
##   pack_boxes      one box per order (BOXES_GOAL), the players taking turns at the tables: box_start, units_take
##                   at the shelves, box_place unit by unit, box_fill, box_label, box_stamp, box_tape (box_restock
##                   when a table runs out). Each taped box is a DeliveryPackage under World/Packages with its order.
##                   STUBS table_use (nothing in the game sends the box_* requests: D-0701.b) and order_claim (the bot
##                   tells CompanyTableNet.order_of which order a table packs: D-0804 / D-0807)
##   dispatch        each packer carries its box to the dispatch zone and sets it down; the host's player uses the
##                   dispatch station, picks every box on the board and presses Load: DispatchZone.load_boxes ->
##                   CompanyTrips.stage_cargo, DispatchRack.store (the boxes ride the van's rack) and the trip
##                   book learns the orders (CompanyDispatch._bridge)
##   drive           the player opens the cab, takes the wheel, presses the pedal; the gate starts the Trip (the
##                   orders go OUT); the autopilot (D-2016.3) follows the street graph to the first stop's house.
##                   With two players the second stays in the shed and packs the orders still coming in, at a
##                   person's pace, until the van is back
##   deliver         stop by stop the van goes to the house (HouseMap, in the order's zone). STUB door_settle: the
##                   bot settles each order itself (OrderSettlement.settle + Trip.record_settled: D-0340 + D-0815.b)
##   return          the autopilot drives back (K-turn, avenue, the yard's leg); the gate closes the Trip
##   close_day       the clock jumps to 20:00 (BOT_SKIP); DayCycle goes OPERATING, CLOSING, SUMMARY; the summary
##                   carries the packing costs and the rent the game charged at CLOSING (D-0509.b); the game saved
##                   the closed day itself at SUMMARY (CompanyRoot.save_closed_day): the bot only reads that save
## Prints, in order: BOT_STAGE <stage> ok or BOT_FAIL <stage>:<reason> (the run stops at a failed stage), one
## `BOT_STUB <stage> <id> [<tasks>] <what>` per shortcut taken, the BOT_SKIP lines, with two players `BOT_INFO
## stay_waits no_order=<n> no_stock=<n>` (the steps the one who stayed found nothing to pack, and why), `BOT_ERROR
## <message>` per engine error logged during the run (a Logger, ErrorCatcher), the summary block (`BOT_COMPANY
## key=value`: players, money, profit (closing - opening money, corte-vertical.md §4.4), deliveries, boxes, breaks,
## assembly_errors,
## engine_errors, return_bundle_units, idle_max_s_<peer> per player, stage_ms_<stage>) and the final line: BOT_OK
## only when every stage was ok, no shortcut was taken, the profit is over 0, no engine error was logged and no
## player spent more than CREW.IDLE_LIMIT_SECONDS with neither a box in the hands nor a wheel; else `BOT_FAIL` and
## what failed (stages_missing=<n> stubs=<n> profit=<n> engine_errors=<n> idle_<peer>=<s>).
## Exit codes: 0 BOT_OK, 1 any BOT_FAIL, 3 hard wall-clock timeout (`BOT_TIMEOUT`).
## Optional user args: -- --players=N (1..8, default 2; it sizes the day's orders through CompanyRoot.order_crew;
## two of them play, the rest is the stub crew_size) --hard=<seconds> (the hard timeout, default 900: six boxes and
## a van that visits three to six houses, about 85 s each way to Centro).
## new_context(players, drive_cap_m): with drive_cap_m > 0 the autopilot drives only that many metres of street out
## of the yard and deliver does not drive (test_company_bot_day uses it); the bot run by hand does all of it (cap 0).
## The company saves into a temp folder (user://bot_company_day), never the game's slot.
## The pure parts (stage_names, stage_line, summary_lines, final_line), the world helpers (open_world, wait_opening,
## close_world) and the stages (new_context, run_stage) are static: tests/test_company_bot_day.gd drives them.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DAY_CYCLE: GDScript = preload("res://scripts/core/company/day_cycle.gd")
const SAVE_DIR: String = "user://bot_company_day"
const PREFIX: String = "BOT_COMPANY"
const STAGES: Array[String] = [
	"receive_pallet", "shelve_stock", "take_orders", "pack_boxes", "dispatch", "drive", "deliver",
	"return", "close_day",
]
## The stages with nothing behind them yet: stage -> the F1 tasks that are missing.
const PENDING: Dictionary = {}
const OPENING_WAIT_SECONDS: float = 10.0
const DEFAULT_PLAYERS: int = 2
const DEFAULT_HARD_SECONDS: float = 900.0
## Boxes the day packs and loads (D-2016.4).
const BOXES_GOAL: int = 6
## Engine errors printed one by one (the count is always printed).
const MAX_ERROR_LINES: int = 20

## The bot's company seed (CompanyState.company_seed, D-0246): the same day of orders on every run.
const ORDERS_SEED: int = 2016
## Frames a phase change may take (DayCycle moves one step per poll()) before the stage fails.
const PHASE_FRAMES: int = 120
## How far ahead the day's own timer is moved so OPENING does not make the bot wait its 5 s: the clock is jumped to
## 20:00 anyway.
const SKIP_OPENING_MSEC: int = 10000
## The stages that drive the van (drive, deliver, return: the autopilot, D-2016.3).
const TRIP := preload("res://tests/bot_company_trip.gd")
## The shed's stages (receive_pallet ... dispatch) and the crew they share.
const SHED := preload("res://tests/bot_company_shed.gd")
const CREW := preload("res://tests/bot_company_crew.gd")

var _players: int = DEFAULT_PLAYERS
var _hard_seconds: float = DEFAULT_HARD_SECONDS
var _finished: bool = false
var _catcher := ErrorCatcher.new()


## Engine errors (not warnings) logged during the run, from any thread (net_pair_company.gd's).
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


# --- Pure parts (static, no world) ---


static func stage_names() -> PackedStringArray:
	return PackedStringArray(STAGES)


## The line a stage prints: "" for ok (see stage_ok_line), BOT_FAIL ... otherwise.
static func stage_line(stage: String, result: Dictionary) -> String:
	var status: String = str(result.get("status", "fail"))
	match status:
		"ok":
			return ""
		"not_implemented":
			return "BOT_FAIL not_implemented:%s" % stage
		_:
			return "BOT_FAIL %s:%s" % [stage, str(result.get("reason", "unknown"))]


static func stage_ok_line(stage: String) -> String:
	return "BOT_STAGE %s ok" % stage


## One `BOT_COMPANY key=value` line per key: the fixed counters, idle_max_s_<peer> per player (stats.idle: peer ->
## seconds), then stage_ms_<stage> in order.
static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in [
		"players", "money", "profit", "deliveries", "boxes", "breaks", "assembly_errors", "engine_errors",
		"return_bundle_units",
	]:
		lines.append("%s %s=%s" % [PREFIX, key, str(stats.get(key, 0))])
	var idle: Dictionary = stats.get("idle", {})
	var peers: Array = idle.keys()
	peers.sort()
	for peer: Variant in peers:
		lines.append("%s idle_max_s_%d=%.1f" % [PREFIX, int(peer), float(idle[peer])])
	var times: Dictionary = stats.get("stage_ms", {})
	for stage: String in STAGES:
		lines.append("%s stage_ms_%s=%s" % [PREFIX, stage, str(times.get(stage, 0))])
	return lines


## The BOT_STUB line of every shortcut the run took (stats.stubs: ids of CREW.STUBS), in the order taken.
static func stub_lines(stubs: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for id: Variant in stubs:
		lines.append(CREW.stub_line(StringName(id)))
	return lines


## BOT_OK only when every stage in STAGES is "ok" and the day was played for real (stats): no shortcut taken
## (stubs), a profit over 0, no engine error and no player idle over CREW.IDLE_LIMIT_SECONDS. Else `BOT_FAIL` and
## each thing that failed: stages_missing=<n>, stubs=<n>, profit=<n>, engine_errors=<n>, idle_<peer>=<s>. A key
## missing from stats counts as failed (a run that measured nothing is no BOT_OK).
static func final_line(results: Dictionary, stats: Dictionary) -> String:
	var problems := PackedStringArray()
	var missing: int = 0
	for stage: String in STAGES:
		var result: Dictionary = results.get(stage, {})
		if str(result.get("status", "")) != "ok":
			missing += 1
	if missing > 0:
		problems.append("stages_missing=%d" % missing)
	var stubs: Array = stats.get("stubs", [])
	if not stubs.is_empty():
		problems.append("stubs=%d" % stubs.size())
	if int(stats.get("profit", 0)) <= 0:
		problems.append("profit=%d" % int(stats.get("profit", 0)))
	if int(stats.get("engine_errors", -1)) != 0:
		problems.append("engine_errors=%d" % int(stats.get("engine_errors", -1)))
	var idle: Dictionary = stats.get("idle", {})
	if idle.is_empty():
		problems.append("idle_unmeasured")
	var peers: Array = idle.keys()
	peers.sort()
	for peer: Variant in peers:
		if float(idle[peer]) > CREW.IDLE_LIMIT_SECONDS:
			problems.append("idle_%d=%.0f" % [int(peer), float(idle[peer])])
	return "BOT_OK" if problems.is_empty() else "BOT_FAIL " + " ".join(problems)


# --- The world (static: the test drives them on its own tree) ---


## The company world with its save folder pointed at a temp dir, before it enters the tree, on a new company of seed
## ORDERS_SEED (the same orders every run) whose orders are planned for `players` (0: the session's crew, one).
static func open_world(tree: SceneTree, players: int = 0) -> Node3D:
	clean_save_dir()
	var state: Node = tree.root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"new_company", "", ORDERS_SEED)
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	level.order_crew = players
	tree.root.add_child(level)
	tree.current_scene = level
	await tree.process_frame
	return level


## Polls per frame until the day is OPENING; false after `max_seconds` of wall time.
static func wait_opening(tree: SceneTree, level: Node3D, max_seconds: float) -> bool:
	var start: int = Time.get_ticks_msec()
	while true:
		var cycle: Node = level.get("day_cycle") as Node
		if cycle != null and int(cycle.call(&"phase")) == DAY_CYCLE.Phase.OPENING:
			return true
		if (Time.get_ticks_msec() - start) / 1000.0 >= max_seconds:
			return false
		await tree.process_frame
	return false


## Leaving the world: its exit saves into the temp folder, which is then removed, and the company and the mouse go
## back to how a test leaves them.
static func close_world(tree: SceneTree, level: Node3D) -> void:
	tree.root.remove_child(level)
	level.free()
	clean_save_dir()
	var state: Node = tree.root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"reset")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func clean_save_dir() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


# --- The run ---


func _arg(arg_name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % arg_name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	_players = clampi(int(_arg("players", str(DEFAULT_PLAYERS))), 1, 8)
	_hard_seconds = float(_arg("hard", str(DEFAULT_HARD_SECONDS)))
	create_timer(_hard_seconds, true, false, true).timeout.connect(_on_hard_timeout)

	var level: Node3D = await open_world(self, _players)
	if not await wait_opening(self, level, OPENING_WAIT_SECONDS):
		close_world(self, level)
		_end("BOT_FAIL no_opening", 1)
		return

	var ctx: Dictionary = new_context(_players)
	var results: Dictionary = {}
	var times: Dictionary = {}
	for stage: String in STAGES:
		var start: int = Time.get_ticks_msec()
		var result: Dictionary = await run_stage(self, level, stage, ctx)
		times[stage] = Time.get_ticks_msec() - start
		results[stage] = result
		var line: String = stage_line(stage, result)
		print(line if line != "" else stage_ok_line(stage))
		if str(result.get("status", "")) == "fail":
			break

	CREW.stop_idle(ctx)
	SHED.stop_staying(ctx)
	var stats: Dictionary = stats_of(level as CompanyRoot, ctx)
	stats["stage_ms"] = times
	close_world(self, level)
	var errors: Array[String] = _catcher.take()
	stats["engine_errors"] = errors.size()
	for line: String in stub_lines(ctx["stubs"]):
		print(line)
	for line: String in ctx["skips"]:
		print(line)
	var waits: Dictionary = ctx["stay_waits"]
	if not waits.is_empty():
		print("BOT_INFO stay_waits no_order=%d no_stock=%d (steps of %.0f s with nothing to pack)" % [
			int(waits.get("no_order", 0)), int(waits.get("no_stock", 0)), CREW.STEP_SECONDS])
	for index: int in mini(errors.size(), MAX_ERROR_LINES):
		print("BOT_ERROR %s" % errors[index])
	for line: String in summary_lines(stats):
		print(line)
	var final: String = final_line(results, stats)
	_end(final, 0 if final == "BOT_OK" else 1)


func _end(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	print(message)
	quit(code)


func _on_hard_timeout() -> void:
	if _finished:
		return
	_finished = true
	print("BOT_TIMEOUT after %.0f s" % _hard_seconds)
	quit(3)


# --- Stages (static: each takes the tree, the opened world and the run's context) ---


## What the stages hand to each other, and the counters of the summary. `players` sizes the orders (and, with 2 or
## more, a second player plays).
static func new_context(players: int, drive_cap_m: float = 0.0) -> Dictionary:
	return {
		"players": players, "assembly_errors": 0, "breaks": 0, "deliveries": 0, "return_bundle_units": 0,
		# The crew (CREW.ensure): [{peer, player}], the shortcuts taken (CREW.STUBS ids), the clock jumps (lines), the
		# world's IdleWatch and, once the day is over, its numbers (peer -> seconds).
		"crew": [], "stubs": [], "skips": [], "idle_watch": null, "idle": {},
		# The wallet when the first stage ran, and at the day's SUMMARY (profit = closing - opening).
		"money_open": null, "money_close": null,
		"boxes_goal": BOXES_GOAL,
		# Catalog (SHED.products_of), pallets opened (id -> Pallet dictionary) and where they are drawn, what the host
		# holds after receive_pallet ({product, qty, pallet}).
		"products": {}, "opened": {}, "pallet_spots": {}, "hands": {},
		# The orders taken (the shared book's dictionaries), and every order id someone took to pack.
		"orders": [], "taken": {},
		# The boxes packed and loaded ({order_id, box_id, peer, table, errors, quality}); the ones the second player
		# packed while the van was out; table -> the order it packs (the stub order_claim).
		"packed": [], "extra": [], "table_orders": {},
		# Spots of the dispatch zone used so far; whether the one who stays in the shed works, and what went wrong.
		"zone_used": 0, "worker_on": false, "worker_failure": "",
		# The steps the one who stays found nothing to pack, by why (SHED._note_wait): no_order, no_stock.
		"stay_waits": {},
		# The vehicle dispatch loaded, and the trip it is on (deliver -> return).
		"vehicle_id": &"", "trip": null,
		# Metres the van covered from its parking spot to where it stopped outside the yard.
		"drive_m": 0.0,
		# Autopilot (D-2016.3): 0 drives the whole way along the street graph to the houses of the trip and back;
		# > 0 (a test) ends the way out after that many metres of the street past the yard's leg and deliver does not
		# drive nor check the distance to the house. The way back is always the whole one.
		"drive_cap_m": drive_cap_m,
		# Where the van stood parked and where it stopped outside the yard, with the way it looked.
		"park_point": Vector2.ZERO, "yard_exit": Vector2.ZERO, "yard_dir": Vector2.UP,
		# What the autopilot reported on each leg: stage -> drive_to()'s result (metres, off_road_max...).
		"autopilot": {},
	}


## Runs one stage by name on the world `level` (a CompanyRoot opened by open_world) and returns its result. A
## coroutine. The crew is made on the first stage (CREW.ensure). An unknown name fails.
static func run_stage(tree: SceneTree, level: Node3D, stage: String, ctx: Dictionary) -> Dictionary:
	if PENDING.has(stage):
		return _pending(str(PENDING[stage]))
	var missing: String = _missing_part(level)
	if missing != "":
		return _fail(missing)
	var root := level as CompanyRoot
	var crew: String = CREW.ensure(root, ctx)
	if crew != "":
		return _fail(crew)
	if ctx["money_open"] == null:
		ctx["money_open"] = int(root.net.company.get("money"))
	match stage:
		"receive_pallet":
			return await SHED.receive_pallet(tree, root, ctx)
		"shelve_stock":
			return await SHED.shelve_stock(tree, root, ctx)
		"take_orders":
			return await SHED.take_orders(tree, root, ctx)
		"pack_boxes":
			return await SHED.pack_boxes(tree, root, ctx)
		"dispatch":
			return await SHED.dispatch(tree, root, ctx)
		"drive":
			return await _drive(tree, root, ctx)
		"deliver":
			return await TRIP.deliver(tree, root, ctx, SHED.products_of(ctx))
		"return":
			return await _come_back(tree, root, ctx)
		"close_day":
			return await _close_day(tree, root, ctx)
	return _fail("unknown_stage")


## The numbers of the summary from the world and the run's context (before the world closes).
static func stats_of(level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var money: int = int(level.net.company.get("money")) if level != null and level.net != null else 0
	var opening: int = int(ctx["money_open"]) if ctx["money_open"] != null else money
	var closing: int = int(ctx["money_close"]) if ctx["money_close"] != null else money
	return {
		"players": int(ctx["players"]), "money": money, "profit": closing - opening,
		"deliveries": int(ctx["deliveries"]), "boxes": (ctx["packed"] as Array).size() + (ctx["extra"] as Array).size(),
		"breaks": int(ctx["breaks"]), "assembly_errors": int(ctx["assembly_errors"]),
		"return_bundle_units": int(ctx["return_bundle_units"]), "idle": CREW.idle_report(ctx), "stubs": ctx["stubs"],
	}


## The van leaves (TRIP.drive); with two players the second stays in the shed packing the orders still coming in
## (SHED.stay_behind, beside the drive until the van is back).
static func _drive(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var result: Dictionary = await TRIP.drive(tree, level, ctx)
	if result["status"] == "ok" and (ctx["crew"] as Array).size() >= 2:
		SHED.stay_behind(tree, level, ctx)
	return result


## The van comes back (TRIP.come_back) and whoever stayed in the shed stops; its work has to have gone well.
static func _come_back(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var result: Dictionary = await TRIP.come_back(tree, level, ctx)
	var worker: String = SHED.stop_staying(ctx)
	if result["status"] == "ok" and worker != "":
		return _fail("stayed_%s" % worker)
	return result


## The day closes the way its clock does: 20:00 comes (BOT_SKIP), OPERATING goes to CLOSING and, with no trip out, to
## SUMMARY. The summary must carry what the day cost (packing and the rent the game charged at CLOSING) and the game
## must have saved the closed day itself (CompanyRoot.save_closed_day at SUMMARY): the bot only reads that save.
static func _close_day(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var cycle: DayCycle = level.day_cycle
	var state: Node = level.net.company as Node
	CREW.skip(ctx, "close_day", level.day_cycle.shed_minute(), float(CompanyTuning.DAY_END_MIN))
	if not level.clock.start(float(CompanyTuning.DAY_END_MIN)):
		return _fail("clock_not_started")
	# The opening's 5 s of real time are skipped; the clock jump above is the same kind of skip.
	cycle.ticks = func() -> int: return Time.get_ticks_msec() + SKIP_OPENING_MSEC
	# The phase it starts from too: after a real drive the day may be OPERATING already.
	var seen: Array[int] = [int(cycle.phase())]
	var came: int = seen[0]
	# Only the bot polls while it watches: the host's BusinessTick (4 Hz) polls the same cycle and could cross a phase
	# between two of the bot's reads, so CLOSING would go unseen.
	var tick: BusinessTick = level.business_tick
	if tick != null:
		tick.set_process(false)
	for _frame: int in PHASE_FRAMES:
		cycle.poll()
		if seen[seen.size() - 1] != int(cycle.phase()):
			seen.append(int(cycle.phase()))
		if cycle.phase() == DayCycle.Phase.SUMMARY:
			break
		await tree.process_frame
	if tick != null:
		tick.set_process(true)
	CREW.stop_idle(ctx)
	var path: Array[int] = [DayCycle.Phase.OPERATING, DayCycle.Phase.CLOSING, DayCycle.Phase.SUMMARY]
	if cycle.phase() != DayCycle.Phase.SUMMARY:
		return _fail("no_summary")
	# The real clock runs while the van drives (90 s an hour): the day may be CLOSING, or closed, when it gets here;
	# the rest of the path must be walked, in order, from the phase it started from.
	if path.find(came) < 0 or seen != path.slice(path.find(came)):
		return _fail("phases_skipped")
	var summary: Dictionary = cycle.summary
	if int(summary.get("day", -1)) != int(state.get("day")):
		return _fail("summary_day")
	var costs: Dictionary = summary.get("cost_by_reason", {})
	if not costs.has("boxes") or not costs.has("packaging"):
		return _fail("summary_without_packing_costs")
	# The game charges the rent at CLOSING, not the bot (D-0509.b).
	if int(costs.get("rent", 0)) != CompanyTuning.RENT_PER_DAY:
		return _fail("summary_without_rent")
	if int(summary.get("closing", -1)) != int(state.get("money")):
		return _fail("summary_money")
	ctx["money_close"] = int(summary["closing"])
	return _check_saved(level, state, ctx)


## The save the game wrote at SUMMARY (D-0236): the next day's opening, day + 1, with the same money, ledger and
## stock (as a save keeps it, CompanyRoot.stock_for_save). The units it left in the return bundle go to ctx (D-0252).
static func _check_saved(level: CompanyRoot, state: Node, ctx: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(CompanySave.path_for(level.save_slot, level.save_dir)):
		return _fail("day_not_saved")
	var scratch: Node = CompanyRoot.COMPANY_STATE.new()
	var loaded: int = CompanySave.load_into(scratch, level.save_slot, level.save_dir)
	var stock: Inventory = scratch.call(&"stock") as Inventory
	var same: bool = (
		loaded == CompanySave.LoadResult.LOADED
		and int(scratch.get("money")) == int(state.get("money"))
		and int(scratch.get("day")) == int(state.get("day")) + 1
		and (scratch.get("ledger") as Array).size() == (state.get("ledger") as Array).size()
		and stock != null and stock.total_units() == level.net.inventory.total_units()
	)
	if stock != null:
		ctx["return_bundle_units"] = CompanyAsk.units_at(stock, CompanyRoot.SAVED_HANDS_LOCATION)
	scratch.free()
	return _ok() if same else _fail("saved_day_differs")


# --- Helpers of the stages ---


static func _ok() -> Dictionary:
	return {"status": "ok", "reason": ""}


static func _fail(reason: String) -> Dictionary:
	return {"status": "fail", "reason": reason}


static func _pending(tasks: String) -> Dictionary:
	return {"status": "not_implemented", "reason": tasks}


## "" when the world has what the stages drive, else the reason (a client has no trips).
static func _missing_part(level: Node3D) -> String:
	var root := level as CompanyRoot
	if root == null:
		return "no_company_world"
	if root.net == null or not root.net.is_host():
		return "not_host"
	if root.shed == null or root.player == null or root.trips == null:
		return "world_incomplete"
	if root.day_cycle == null or root.clock == null:
		return "no_day"
	return ""
