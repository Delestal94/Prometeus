extends SceneTree
## Skeleton of the bot that plays a whole Modo Empresa day (D-2016, the closing criterion of the
## F1 vertical slice D-0111). Not a test_*.gd: the runner does not pick it up. Run:
##   <godot> --headless --path do-not-drop --script res://tests/bot_company_day.gd -- --players=2
## Opens the company world (scenes/gameplay/company_root.tscn, like bench_company.gd), waits for the
## day to reach OPENING (bounded, 10 s) and runs the stages in STAGES order. In this skeleton (D-2016.1)
## every stage returns `not_implemented`; D-2016.2 fills them in. Each stage returns
## {"status": "ok"|"fail"|"not_implemented", "reason": String} and is timed in ms.
## Prints:
##   BOT_FAIL not_implemented:<stage>   a stage with nothing behind it yet (the run goes on)
##   BOT_FAIL <stage>:<reason>          a failed stage (the run stops there)
##   BOT_FAIL no_opening                the day never reached OPENING
##   BOT_STAGE <stage> ok               a stage that passed
## then a summary block, one `BOT_COMPANY key=value` line each (players, money, deliveries, breaks,
## assembly_errors, stage_ms_<stage>), and the final line: `BOT_OK` if every stage was ok, else
## `BOT_FAIL stages_missing=<n>`.
## Exit codes: 0 BOT_OK, 1 any BOT_FAIL, 3 hard wall-clock timeout (`BOT_TIMEOUT`).
## Optional user args: -- --players=N (1..8, default 2; the skeleton only records it, the peers come
## with D-2016.2 / D-2017) --hard=<seconds> (the hard timeout, default 120).
## The company saves into a temp folder (user://bot_company_day), never the game's slot.
## The pure parts (stage_names, stage_line, summary_lines, final_line) and the world helpers
## (open_world, wait_opening, close_world) are static: tests/test_company_bot_day.gd drives them.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DAY_CYCLE: GDScript = preload("res://scripts/core/company/day_cycle.gd")
const SAVE_DIR: String = "user://bot_company_day"
const PREFIX: String = "BOT_COMPANY"
const STAGES: Array[String] = [
	"receive_pallet", "shelve_stock", "take_orders", "pack_boxes", "dispatch", "drive", "deliver",
	"return", "close_day",
]
const OPENING_WAIT_SECONDS: float = 10.0
const DEFAULT_PLAYERS: int = 2
const DEFAULT_HARD_SECONDS: float = 120.0

var _players: int = DEFAULT_PLAYERS
var _hard_seconds: float = DEFAULT_HARD_SECONDS
var _finished: bool = false


func _initialize() -> void:
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


## One `BOT_COMPANY key=value` line per key: the fixed counters, then stage_ms_<stage> in order.
static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in ["players", "money", "deliveries", "breaks", "assembly_errors"]:
		lines.append("%s %s=%s" % [PREFIX, key, str(stats.get(key, 0))])
	var times: Dictionary = stats.get("stage_ms", {})
	for stage: String in STAGES:
		lines.append("%s stage_ms_%s=%s" % [PREFIX, stage, str(times.get(stage, 0))])
	return lines


## BOT_OK only when every stage in STAGES has an "ok" result; else BOT_FAIL stages_missing=<n>.
static func final_line(results: Dictionary) -> String:
	var missing: int = 0
	for stage: String in STAGES:
		var result: Dictionary = results.get(stage, {})
		if str(result.get("status", "")) != "ok":
			missing += 1
	return "BOT_OK" if missing == 0 else "BOT_FAIL stages_missing=%d" % missing


# --- The world (static: the test drives them on its own tree) ---


## The company world with its save folder pointed at a temp dir, before it enters the tree.
static func open_world(tree: SceneTree) -> Node3D:
	clean_save_dir()
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
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


## Leaving the world: its exit saves into the temp folder, which is then removed, and the company
## and the mouse go back to how a test leaves them.
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


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	_players = clampi(int(_arg("players", str(DEFAULT_PLAYERS))), 1, 8)
	_hard_seconds = float(_arg("hard", str(DEFAULT_HARD_SECONDS)))
	create_timer(_hard_seconds, true, false, true).timeout.connect(_on_hard_timeout)

	var level: Node3D = await open_world(self)
	if not await wait_opening(self, level, OPENING_WAIT_SECONDS):
		close_world(self, level)
		_end("BOT_FAIL no_opening", 1)
		return

	var results: Dictionary = {}
	var times: Dictionary = {}
	for stage: String in STAGES:
		var start: int = Time.get_ticks_msec()
		var result: Dictionary = await call(&"_stage_" + stage)
		times[stage] = Time.get_ticks_msec() - start
		results[stage] = result
		var line: String = stage_line(stage, result)
		print(line if line != "" else stage_ok_line(stage))
		if str(result.get("status", "")) == "fail":
			break

	var money: int = 0
	var state: Node = root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		money = int(state.get("money"))
	var stats: Dictionary = {
		"players": _players, "money": money, "deliveries": 0, "breaks": 0,
		"assembly_errors": 0, "stage_ms": times,
	}
	close_world(self, level)
	for line: String in summary_lines(stats):
		print(line)
	var final: String = final_line(results)
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


# --- Stages (each a coroutine-compatible method; D-2016.2 fills them in) ---


## Pallet arrives at the dock and the bot opens it (pallet with N boxes D-0604, open pallet D-0607).
func _stage_receive_pallet() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Carry the stock to the labelled shelf slots (shelves D-0608).
func _stage_shelve_stock() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Read the day's orders from the order book (order generator D-0801, structure D-0802).
func _stage_take_orders() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Fill boxes at the packing station (station D-0701, box dispenser D-0702, items in box D-0703).
func _stage_pack_boxes() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Load the boxes on the truck and pick the route on the dispatch board (D-0310).
func _stage_dispatch() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Drive out of the shed gate along the road graph (gate D-0302, road graph D-0304).
func _stage_drive() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Hand the packages over at the delivery houses (fixed-map houses D-0311).
func _stage_deliver() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Drive back to the shed (return trip D-0307).
func _stage_return() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}


## Close the day through DayCycle (CLOSING, SUMMARY; trip result D-0320).
func _stage_close_day() -> Dictionary:
	return {"status": "not_implemented", "reason": "D-2016.2"}
