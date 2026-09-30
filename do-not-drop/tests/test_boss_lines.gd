extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_boss_lines.gd
##
## The Boss talks over the depot's radio (S-603, boss_lines.gd, docs/narrativa.md):
## - there is always a start line, for any order, campaign or seed, and the
##   pool has at least 20 delivery lines;
## - the draw is deterministic (same seed and day, same lines) and a different
##   seed or day can give another; lines travel as LocText ([key, args...]);
## - the lines follow the order (the hen is "Ruidoso", fireworks "Explosivo",
##   one house) and the campaign (rookie, veteran, till);
## - the reaction depends on the last run (first day, broken, lost, clean, a
##   streak) and is left out for an endless last run; endless days have their
##   own lines and no reaction;
## - the campaign log keeps the last run's summary (depot_campaign_board.gd);
## - every key exists in es and en with matching placeholders, and each line
##   renders without a raw key or a broken format;
## - in the depot (depot.gd) the lines are on the board (OrderBoard/Boss0..1),
##   in the depot panel, and the crew hears a toast once.

const Lines = preload("res://scripts/gameplay/depot/boss_lines.gd")
const Board = preload("res://scripts/gameplay/depot/depot_campaign_board.gd")
const OrderBoard = preload("res://scripts/gameplay/depot/depot_order_board.gd")
const ALL_TRAPS: Array[StringName] = [&"fragile", &"growing_weight", &"balance", &"noisy", &"liquid", &"explosive",
		&"hostile"]

var _failures: int = 0
var _notices: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_always_a_line()
	_test_deterministic()
	_test_follows_the_order()
	_test_follows_the_campaign()
	_test_reactions()
	_test_endless()
	_test_log_keeps_last_run()
	_test_translations()
	await _test_in_the_depot()
	if _failures == 0:
		print("PASS: the Boss's radio lines are always there, deterministic, follow the order and the last run")
	quit(_failures)


func _context(traps: Array, runs: int = 3, money: int = 100, last: Dictionary = {}, streak: int = 0,
		best: int = 0) -> Dictionary:
	var orders: Array = []
	for trap: Variant in traps:
		orders.append({"trap_id": String(trap)})
	return Lines.make_context(orders, runs, money, {"days": streak, "last": last}, best)


func _keys_of(lines: Array) -> Array:
	return lines.map(func(line: Array) -> String: return line[0])


func _test_always_a_line() -> void:
	var start_pool: int = (Lines.START_LINES as Array).size()
	_expect(start_pool >= 20, "At least 20 delivery start lines (got %d)" % start_pool)
	var empty_lines: int = 0
	var checked: int = 0
	for houses: int in range(0, 9):
		for runs: int in [0, 1, 5, 12]:
			for money: int in [0, 100, 500]:
				for seed_value: int in [0, 1, 7, 99999, -5]:
					var traps: Array = ALL_TRAPS.slice(0, houses)
					var lines: Array = Lines.pick(_context(traps, runs, money), seed_value)
					checked += 1
					if lines.is_empty() or not lines[0] is Array or (lines[0] as Array).is_empty():
						empty_lines += 1
	_expect(empty_lines == 0,
			"Every order, campaign and seed gets a start line (%d of %d without)" % [empty_lines, checked])


func _test_deterministic() -> void:
	var context: Dictionary = _context([&"noisy", &"fragile", &"hostile"], 4, 120,
			{"mode": "delivery", "delivered": true, "ruined": 2})
	var first: Array = Lines.pick(context, 424242)
	for repeat: int in range(5):
		_expect(Lines.pick(context, 424242) == first, "The same seed and day draw the same lines (%s)" % str(first))
	var seen: Dictionary = {}
	for seed_value: int in range(1, 60):
		seen[Lines.pick(_context([], 4), seed_value)[0][0]] = true
	_expect(seen.size() > 1, "Different seeds can draw different start lines (got %d)" % seen.size())
	var days: Dictionary = {}
	for runs: int in range(0, 12):
		days[Lines.pick(_context([&"fragile", &"noisy"], runs), 777)[0][0]] = true
	_expect(days.size() > 1, "A new day of the same session can give another line (got %d)" % days.size())
	var line: Array = first[0]
	_expect(line[0] is String, "Lines travel as [key, args...], not built text (got %s)" % str(line))


func _test_follows_the_order() -> void:
	var one: Dictionary = {}
	var hen: Dictionary = {}
	var fireworks: Dictionary = {}
	for seed_value: int in range(1, 200):
		one[_keys_of(Lines.pick(_context([&"fragile"]), seed_value))[0]] = true
		hen[_keys_of(Lines.pick(_context([&"noisy", &"fragile", &"balance"]), seed_value))[0]] = true
		fireworks[_keys_of(Lines.pick(_context([&"explosive", &"fragile"]), seed_value))[0]] = true
	_expect(one.has("WORLD_BOSS_START_ONE"), "With a single house the Boss can say so (got %s)" % str(one.keys()))
	_expect(hen.has("WORLD_BOSS_START_HEN"),
			"With a Ruidoso box the Boss can mention the hen (got %s)" % str(hen.keys()))
	_expect(fireworks.has("WORLD_BOSS_START_EXPLOSIVE"),
			"With an Explosivo box she talks about the fireworks (got %s)" % str(fireworks.keys()))
	_expect(not hen.has("WORLD_BOSS_START_EXPLOSIVE") and not fireworks.has("WORLD_BOSS_START_HEN"),
		"A trap's line only comes up when that trap is in the order")
	# The hen line carries the number of houses.
	var hen_line: Array = []
	for seed_value: int in range(1, 200):
		var lines: Array = Lines.pick(_context([&"noisy", &"fragile", &"balance"]), seed_value)
		if lines[0][0] == "WORLD_BOSS_START_HEN":
			hen_line = lines[0]
			break
	_expect(hen_line.size() == 2 and int(hen_line[1]) == 3,
			"The hen line says how many deliveries (got %s)" % str(hen_line))


func _test_follows_the_campaign() -> void:
	var rookie: Dictionary = {}
	var veteran: Dictionary = {}
	var rich: Dictionary = {}
	var poor: Dictionary = {}
	for seed_value: int in range(1, 200):
		rookie[Lines.pick(_context([&"fragile", &"balance"], 0), seed_value)[0][0]] = true
		veteran[Lines.pick(_context([&"fragile", &"balance"], 20), seed_value)[0][0]] = true
		rich[Lines.pick(_context([&"fragile", &"balance"], 5, 400), seed_value)[0][0]] = true
		poor[Lines.pick(_context([&"fragile", &"balance"], 5, 10), seed_value)[0][0]] = true
	_expect(rookie.has("WORLD_BOSS_START_ROOKIE") and not veteran.has("WORLD_BOSS_START_ROOKIE"),
			"New crews get the learning line, veterans don't")
	_expect(veteran.has("WORLD_BOSS_START_VETERAN") and not rookie.has("WORLD_BOSS_START_VETERAN"),
			"Veterans get the days-together line, new crews don't")
	_expect(rich.has("WORLD_BOSS_START_RICH") and not poor.has("WORLD_BOSS_START_RICH"), "A full till gets its line")
	_expect(poor.has("WORLD_BOSS_START_POOR") and not rich.has("WORLD_BOSS_START_POOR"), "An empty till gets its line")


func _test_reactions() -> void:
	var pick_reaction := func(last: Dictionary, runs: int = 5, streak: int = 0) -> String:
		var lines: Array = Lines.pick(_context([&"fragile", &"noisy"], runs, 100, last, streak), 11)
		return lines[1][0] if lines.size() > 1 else ""
	_expect(pick_reaction.call({}, 0) == "WORLD_BOSS_REACT_FIRST", "The first day has its own reaction")
	_expect(pick_reaction.call({}, 5) == "", "No last run on record after the first day: no reaction")
	var two_broken := {"mode": "delivery", "delivered": true, "ruined": 2, "lost": 0, "missed": 0,
			"houses_delivered": 3}
	_expect(pick_reaction.call(two_broken) == "WORLD_BOSS_REACT_RUINED_MANY",
			"Two broken boxes: 'Ayer rompieron dos cosas'")
	var lines: Array = Lines.pick(_context([&"fragile"], 5, 100, two_broken), 11)
	_expect(lines[1] == ["WORLD_BOSS_REACT_RUINED_MANY", 2],
			"...and the reaction carries how many (got %s)" % str(lines[1]))
	var one_broken := {"mode": "delivery", "delivered": true, "ruined": 1, "houses_delivered": 3}
	_expect(pick_reaction.call(one_broken) == "WORLD_BOSS_REACT_RUINED_ONE", "One broken box has its line")
	var two_lost := {"mode": "delivery", "delivered": true, "ruined": 0, "lost": 2, "houses_delivered": 1}
	_expect(pick_reaction.call(two_lost) == "WORLD_BOSS_REACT_LOST", "Lost deliveries have their line")
	var both := {"mode": "delivery", "delivered": true, "ruined": 1, "lost": 1, "houses_delivered": 1}
	_expect(pick_reaction.call(both) == "WORLD_BOSS_REACT_BOTH", "Broken and lost together have their line")
	var nothing := {"mode": "delivery", "delivered": false, "ruined": 3, "houses_delivered": 0}
	_expect(pick_reaction.call(nothing) == "WORLD_BOSS_REACT_NOTHING", "Nothing arriving has its line")
	var clean := {"mode": "delivery", "delivered": true, "ruined": 0, "lost": 0, "missed": 0, "houses_delivered": 3}
	_expect(pick_reaction.call(clean, 5, 1) == "WORLD_BOSS_REACT_PERFECT", "A clean run is 'todo entero. Sospechoso'")
	_expect(pick_reaction.call(clean, 5, 4) == "WORLD_BOSS_REACT_STREAK", "A streak of clean days is mentioned")
	_expect(pick_reaction.call({"mode": "endless", "delivered": false, "ruined": 0}) == "",
			"An endless last run gets no reaction on a delivery day")
	var seen: Dictionary = {}
	for last: Dictionary in [{}, two_broken, clean]:
		seen[pick_reaction.call(last, 0 if last.is_empty() else 5)] = true
	_expect(seen.size() == 3, "The reaction depends on the last run (got %s)" % str(seen.keys()))


func _test_endless() -> void:
	var endless_keys: Array = (Lines.ENDLESS_LINES as Array).map(func(entry: Dictionary) -> String: return entry.key)
	var no_best: Dictionary = {}
	var with_best: Dictionary = {}
	for seed_value: int in range(1, 100):
		var lines: Array = Lines.pick(_context([], 6, 100, {"mode": "delivery", "ruined": 3}), seed_value)
		_expect(lines.size() == 1, "Endless days have a line and no reaction (got %d lines)" % lines.size())
		no_best[lines[0][0]] = true
		with_best[Lines.pick(_context([], 6, 100, {}, 0, 850), seed_value)[0][0]] = true
	for key: String in no_best.keys() + with_best.keys():
		_expect(endless_keys.has(key), "Endless draws only from its own pool (%s)" % key)
	_expect(not no_best.has("WORLD_BOSS_ENDLESS_BEST"), "Without a record the Boss doesn't quote it")
	_expect(with_best.has("WORLD_BOSS_ENDLESS_BEST"), "With a record she can quote it")


func _test_log_keeps_last_run() -> void:
	var summary: Dictionary = Lines.summarize_run({"delivered": true, "cargo_ruined": 2, "houses_lost": 1,
			"houses_missed": 0, "houses_delivered": 2})
	var expected := {"mode": "delivery", "delivered": true, "ruined": 2, "lost": 1, "missed": 0, "houses_delivered": 2}
	_expect(summary == expected, "A run is summed up for tomorrow (got %s)" % str(summary))
	_expect(String(Lines.summarize_run({"distance_traveled": 900.0}).mode) == "endless",
			"An endless run is marked as such")
	_clear_log()
	_expect((Board.load_log().last as Dictionary).is_empty(), "No last run before the first")
	var log: Dictionary = Board.record_run({"delivered": true, "cargo_ruined": 2, "houses_delivered": 3}, {})
	_expect(int((log.last as Dictionary).ruined) == 2, "The log keeps the last run (got %s)" % str(log.last))
	_expect(int((Board.load_log().last as Dictionary).ruined) == 2, "...and it survives a reload from disk")
	_clear_log()


func _test_translations() -> void:
	var table: Dictionary = _read_csv("res://translations/strings_world.csv")
	var placeholder := RegEx.create_from_string("%[-+0-9.]*[dsf]")
	var keys: PackedStringArray = Lines.all_keys()
	_expect(keys.size() >= 32, "The module hands out all its lines (got %d keys)" % keys.size())
	keys.append_array(["WORLD_BOSS_RADIO", "WORLD_BOSS_NOTE"])
	for key: String in keys:
		_expect(table.has(key), "%s is in the world table" % key)
		if not table.has(key):
			continue
		var es: String = table[key][0]
		var en: String = table[key][1]
		_expect(not es.is_empty() and not en.is_empty(), "%s has both es and en" % key)
		var es_marks: Array = placeholder.search_all(es).map(func(m: RegExMatch) -> String: return m.get_string())
		var en_marks: Array = placeholder.search_all(en).map(func(m: RegExMatch) -> String: return m.get_string())
		_expect(es_marks == en_marks,
				"%s has the same placeholders in es and en (%s vs %s)" % [key, es_marks, en_marks])
	# Rendered: no raw key, no broken format, in both languages, with real args.
	var all_lines: Array = []
	for pool: Array[Dictionary] in [Lines.START_LINES, Lines.ENDLESS_LINES, Lines.REACTION_LINES]:
		for entry: Dictionary in pool:
			var args: Array = [] if not entry.has("args") else [7]
			all_lines.append(LocText.make(entry.key, args))
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for line: Array in all_lines:
			var text: String = LocText.render(line)
			_expect(not text.is_empty() and not text.begins_with("WORLD_BOSS") and text.length() <= 70,
				"%s renders in %s as a short line (got '%s')" % [line[0], locale, text])
	TranslationServer.set_locale("es")


func _test_in_the_depot() -> void:
	_clear_log()
	Board.save_log({"days": 0, "best": 0, "photos": [], "serial": 0,
		"last": {"mode": "delivery", "delivered": true, "ruined": 2, "lost": 0, "missed": 0, "houses_delivered": 2}})
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"depot_notice", func(text: String) -> void: _notices.append(text))
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	unlocks.set(&"completed_runs", 3)
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var depot: Node3D = level.get_node(^"World/Depot")
	var lines: Array = depot.get(&"boss_lines")
	_expect(lines.size() >= 1 and lines.size() <= 2, "The depot has the Boss's lines (got %s)" % str(lines))
	_expect(lines.size() == 2 and lines[1][0] == "WORLD_BOSS_REACT_RUINED_MANY",
			"...with her reaction to the last run (got %s)" % str(lines))
	var notes: Array = depot.call(&"boss_notes")
	var board_0: Label3D = depot.get_node(^"OrderBoard/Boss0")
	var board_1: Label3D = depot.get_node(^"OrderBoard/Boss1")
	_expect(notes.size() == 2 and board_0.text.contains(String(notes[0])),
			"The board shows the start line (got '%s')" % board_0.text)
	_expect(board_1.text == String(notes[1]), "...and the reaction under it (got '%s')" % board_1.text)
	var houses: int = (level.get_node(^"World/Route").get(&"houses") as Array).size()
	var orders: Array = depot.get(&"orders")
	_expect(orders.size() == houses and not String((orders[0] as Dictionary).get("trap_id", "")).is_empty(),
			"Orders carry their trap id (got %s)" % str(orders[0]))
	_expect(board_0.position.y < float(OrderBoard.ROWS_BOTTOM),
			"The note sits under the orders (y %.2f)" % board_0.position.y)

	# The panel puts the note on the order sheet.
	var panel: Control = load("res://scripts/ui/depot_panel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.call(&"open", &"orders", depot)
	await process_frame
	var texts: PackedStringArray = []
	_collect_labels(panel, texts)
	for note: String in notes:
		_expect(texts.has(note), "The order sheet shows '%s'" % note)
	panel.queue_free()

	# The toast, once: a little after the depot opens.
	await create_timer(float(depot.get(&"BOSS_TOAST_DELAY")) + 0.5).timeout
	var radio: String = tr("WORLD_BOSS_RADIO") % String(notes[0])
	_expect(_notices.count(radio) == 1, "The crew hears the start line as a toast, once (got %s)" % str(_notices))

	# Endless has its own lines on the same board.
	level.queue_free()
	await process_frame
	var endless: Node = load("res://scenes/gameplay/level_endless.tscn").instantiate()
	root.add_child(endless)
	current_scene = endless
	await process_frame
	await physics_frame
	var endless_depot: Node3D = endless.get_node(^"World/Depot")
	var endless_lines: Array = endless_depot.get(&"boss_lines")
	var endless_keys: Array = (Lines.ENDLESS_LINES as Array).map(func(entry: Dictionary) -> String: return entry.key)
	_expect(endless_lines.size() == 1 and endless_keys.has(endless_lines[0][0]),
			"The endless depot has one of its own lines (got %s)" % str(endless_lines))
	endless.queue_free()
	await process_frame
	unlocks.set(&"completed_runs", 0)
	_clear_log()


func _collect_labels(node: Node, into: PackedStringArray) -> void:
	if node is Label:
		into.append((node as Label).text)
	for child: Node in node.get_children():
		_collect_labels(child, into)


func _clear_log() -> void:
	if FileAccess.file_exists(Board.LOG_PATH):
		DirAccess.remove_absolute(Board.LOG_PATH)


func _read_csv(path: String) -> Dictionary:
	var table: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			table[row[0]] = [row[1], row[2]]
	return table


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
