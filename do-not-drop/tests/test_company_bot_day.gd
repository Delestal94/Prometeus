extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bot_day.gd
##
## Guards the skeleton of the company-day bot (tests/bot_company_day.gd, D-2016.1) so D-2016.2 can
## fill it in without breaking its contract:
## - the stage list and its order (receive_pallet ... close_day);
## - stage_line: not_implemented -> "BOT_FAIL not_implemented:<stage>", fail -> "BOT_FAIL
##   <stage>:<reason>", ok -> "" (the bot prints BOT_STAGE <stage> ok instead);
## - final_line is BOT_OK only when every stage is ok, else BOT_FAIL stages_missing=<n> (a bot that
##   always said OK would hide the missing stages);
## - summary_lines keys and the BOT_COMPANY prefix;
## - integration: the bot's own open_world/wait_opening open the company world (company_root.tscn)
##   and the day reaches OPENING within the bounded wait; closing leaves no error behind.

const BOT: String = "res://tests/bot_company_day.gd"
const DAY_CYCLE := preload("res://scripts/core/company/day_cycle.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bot: GDScript = load(BOT) as GDScript
	_expect(bot != null, "The bot script loads (got %s)" % bot)
	if bot == null:
		quit(1)
		return
	_check_pure(bot)
	await _check_world(bot)
	if _failures == 0:
		print("PASS: company bot skeleton contract and OPENING reached")
	quit(_failures)


func _check_pure(bot: GDScript) -> void:
	var expected := PackedStringArray([
		"receive_pallet", "shelve_stock", "take_orders", "pack_boxes", "dispatch", "drive",
		"deliver", "return", "close_day",
	])
	var names: PackedStringArray = bot.call(&"stage_names")
	_expect(names == expected, "Stages in order (got %s)" % names)

	var todo: Dictionary = {"status": "not_implemented", "reason": "D-2016.2"}
	var line: String = bot.call(&"stage_line", "drive", todo)
	_expect(line == "BOT_FAIL not_implemented:drive", "not_implemented line (got %s)" % line)
	line = bot.call(&"stage_line", "deliver", {"status": "fail", "reason": "no_house"})
	_expect(line == "BOT_FAIL deliver:no_house", "fail line (got %s)" % line)
	line = bot.call(&"stage_line", "drive", {"status": "ok", "reason": ""})
	_expect(line == "", "ok prints no BOT_FAIL line (got %s)" % line)
	line = bot.call(&"stage_ok_line", "drive")
	_expect(line == "BOT_STAGE drive ok", "ok stage line (got %s)" % line)

	var results: Dictionary = {}
	for stage: String in names:
		results[stage] = {"status": "ok", "reason": ""}
	var final: String = bot.call(&"final_line", results)
	_expect(final == "BOT_OK", "All ok gives BOT_OK (got %s)" % final)
	results["drive"] = todo
	final = bot.call(&"final_line", results)
	_expect(final == "BOT_FAIL stages_missing=1", "One missing (got %s)" % final)
	final = bot.call(&"final_line", {})
	_expect(final == "BOT_FAIL stages_missing=9", "Nothing run (got %s)" % final)
	results["drive"] = {"status": "fail", "reason": "x"}
	final = bot.call(&"final_line", results)
	_expect(final != "BOT_OK", "A failed stage is not BOT_OK (got %s)" % final)

	var stats: Dictionary = {
		"players": 2, "money": 500, "deliveries": 0, "breaks": 0, "assembly_errors": 0,
		"stage_ms": {"drive": 7},
	}
	var lines: PackedStringArray = bot.call(&"summary_lines", stats)
	_expect(lines.size() == 5 + names.size(), "Summary line count (got %d)" % lines.size())
	_expect(lines[0] == "BOT_COMPANY players=2", "First line (got %s)" % lines[0])
	_expect(lines[1] == "BOT_COMPANY money=500", "Money line (got %s)" % lines[1])
	_expect("BOT_COMPANY stage_ms_drive=7" in lines, "Stage ms line (got %s)" % [lines])
	_expect("BOT_COMPANY stage_ms_close_day=0" in lines, "Missing ms is 0 (got %s)" % [lines])
	for text: String in lines:
		_expect(text.begins_with("BOT_COMPANY ") and "=" in text, "Prefix and key=value (%s)" % text)


func _check_world(bot: GDScript) -> void:
	var level: Node3D = await bot.call(&"open_world", self)
	_expect(level is CompanyRoot, "The company world opens (got %s)" % level)
	var reached: bool = await bot.call(&"wait_opening", self, level, 10.0)
	_expect(reached, "The day reaches OPENING within the bounded wait")
	var cycle: Node = level.get("day_cycle") as Node
	var phase: int = int(cycle.call(&"phase")) if cycle != null else -1
	_expect(phase == DAY_CYCLE.Phase.OPENING, "Phase is OPENING (got %d)" % phase)
	bot.call(&"close_world", self, level)
	await process_frame
	_expect(not is_instance_valid(level), "The world is freed on close")
	_expect(current_scene == null or current_scene != level, "No stale current scene")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
