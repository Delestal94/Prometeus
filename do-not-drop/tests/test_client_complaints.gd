extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_client_complaints.gd
##
## Clients complain in their own voice (S-604, client_complaints.gd):
## - each of the ten recurring clients (docs/narrativa.md) has at least one
##   line for every result (ruined, at_risk, opened, wrong), and every line
##   is in strings_world.csv in Spanish and English with the same placeholders;
## - a client is the sender of the box a house ordered, or a stable draw from
##   the seed and the house; the same seed always picks the same line, and
##   the seed/house/result really vary it;
## - RunManager sends the line's KEY in the results (ruined, wrong-box and
##   dented complaints carry client + result + line), scoring is unchanged
##   (a "wrong" note costs nothing) and every peer's results screen shows the
##   client's name and the line in its own language (hud_results.gd).

const CSV_PATH: String = "res://translations/strings_world.csv"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: Dictionary = _read_csv()
	_pool_is_complete(table)
	_choice_is_deterministic()
	await _results_carry_the_voice()
	await _results_screen_shows_them()
	TranslationServer.set_locale("es")
	if _failures == 0:
		print("PASS: every client has lines for every result, picked per seed and shown in the results")
	quit(_failures)


func _pool_is_complete(table: Dictionary) -> void:
	_expect(ClientComplaints.CLIENTS.size() == 10,
			"There are ten recurring clients (got %d)" % ClientComplaints.CLIENTS.size())
	var placeholder := RegEx.create_from_string("%[-+0-9.]*[dsf%]")
	for client: StringName in ClientComplaints.CLIENTS:
		var content: Resource = load("res://data/contents/%s.tres" % client)
		_expect(content != null and not String(content.get(&"sender")).is_empty(),
				"%s is a content with a sender (its client)" % client)
		_expect(ClientComplaints.client_name(client) == String(content.get(&"sender")),
				"%s is named after the content's sender (got '%s')" % [client, ClientComplaints.client_name(client)])
		for result: StringName in ClientComplaints.RESULTS:
			var lines: Array = ClientComplaints.lines_for(client, result)
			_expect(lines.size() >= 2, "%s has 2+ lines for %s (got %d)" % [client, result, lines.size()])
			for key: String in lines:
				var prefix: String = "WORLD_COMPLAINT_%s_%s_" % [String(client).to_upper(), String(result).to_upper()]
				_expect(key.begins_with(prefix),
						"%s follows WORLD_COMPLAINT_<CLIENT>_<RESULT>_<n>" % key)
				_expect(table.has(key), "%s is in strings_world.csv" % key)
				if not table.has(key):
					continue
				var es: String = table[key][0]
				var en: String = table[key][1]
				_expect(not es.is_empty() and not en.is_empty(), "%s has Spanish and English text" % key)
				_expect(es.length() <= 80 and en.length() <= 80, "%s stays short enough for the results card" % key)
				_expect(placeholder.search_all(es).is_empty() and placeholder.search_all(en).is_empty(),
						"%s has no placeholders (the line is the client's words)" % key)
	_expect(ClientComplaints.all_keys().size() == ClientComplaints.CLIENTS.size() * 9,
			"Ruined has three variants and the rest two per client (got %d keys)" % ClientComplaints.all_keys().size())
	_expect(ClientComplaints.client_name(&"nobody").is_empty(), "Only the ten clients have a name")


func _choice_is_deterministic() -> void:
	# Same content: the client is the one who sends it; otherwise a stable draw.
	_expect(ClientComplaints.client_for(&"hen", 77, 3) == &"hen", "A known content's sender is the house's client")
	var drawn: StringName = ClientComplaints.client_for(&"", 1234, 2)
	_expect(ClientComplaints.is_client(drawn), "A house with no known box still gets one of the ten (got %s)" % drawn)
	_expect(drawn == ClientComplaints.client_for(&"", 1234, 2), "The same seed and house give the same client")
	var clients: Dictionary = {}
	for house: int in range(40):
		clients[ClientComplaints.client_for(&"", 99, house)] = true
	_expect(clients.size() >= 5, "Houses spread over the clients (%d of 10 in 40 houses)" % clients.size())
	# Same seed -> same line; different seeds/houses reach every variant.
	var first: String = ClientComplaints.pick_line(&"puppy", &"ruined", 4242, 1)
	_expect(not first.is_empty() and first == ClientComplaints.pick_line(&"puppy", &"ruined", 4242, 1),
			"The same seed, house, client and result pick the same line")
	_expect(ClientComplaints.lines_for(&"puppy", &"ruined").has(first), "The pick comes from that client's pool")
	var seen: Dictionary = {}
	for session_seed: int in range(60):
		seen[ClientComplaints.pick_line(&"puppy", &"ruined", session_seed, 1)] = true
	_expect(seen.size() == 3, "Across seeds a client says all three ruined lines (got %d)" % seen.size())
	_expect(ClientComplaints.pick_line(&"nobody", &"ruined", 1, 0).is_empty(), "No client, no line")
	_expect(ClientComplaints.result_for(&"delivered_ruined") == &"ruined"
			and ClientComplaints.result_for(&"delivered_at_risk") == &"at_risk"
			and ClientComplaints.result_for(&"delivered_at_risk", true) == &"opened"
			and ClientComplaints.result_for(&"delivered_ok").is_empty()
			and ClientComplaints.result_for(&"missed").is_empty(),
			"Outcomes map to results: ruined, dented, opened; nothing else complains")


func _results_carry_the_voice() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 3)
	manager.call(&"start_run")
	# The fourth entry is the box's content: house 0 is the hen's client, 1 the
	# wedding cake's, 2 the vase's.
	bus.emit_signal(&"houses_assigned", [
		[&"a", "HUD_TRAP_NOISY", "A1", &"hen"],
		[&"b", "HUD_TRAP_BALANCE", "B2", &"wedding_cake"],
		[&"c", "HUD_TRAP_FRAGILE", "C3", &"porcelain_vase"],
	])
	var assigned: Array = manager.get(&"house_assignments")
	_expect(ClientComplaints.client_of(assigned, 0, 9) == &"hen"
			and ClientComplaints.client_of(assigned, 2, 9) == &"porcelain_vase",
			"A house's client is the sender of the box it ordered")
	manager.set(&"cargo", {&"a": {"integrity": 0.0, "maximum": 100.0, "state": 2},
			&"b": {"integrity": 100.0, "maximum": 100.0, "state": 0},
			&"c": {"integrity": 100.0, "maximum": 100.0, "state": 0}})
	manager.call(&"register_delivery", 0, &"delivered_ruined", &"a")
	# The wedding cake's door was offered another box first, then got its own.
	bus.emit_signal(&"house_refused_package", 1, "Balance B2")
	manager.call(&"register_delivery", 1, &"delivered_ok", &"b")
	manager.call(&"register_delivery", 2, &"delivered_ok", &"c")
	# A dented-by-opening box only complains half the time (a dice roll), so ask
	# the complaint builder directly for what that complaint would say.
	var opened: Dictionary = ClientComplaints.make({"house": 2, "outcome": &"delivered_at_risk", "opened": true},
			false, assigned, 5150)
	_expect(opened["client"] == &"porcelain_vase" and opened["result"] == &"opened"
			and ClientComplaints.lines_for(&"porcelain_vase", &"opened").has(opened["line"]),
			"An opened box complains in its client's opened voice (got %s)" % opened)
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	var complaints: Array = results.get("complaints", [])
	var by_house: Dictionary = {}
	for complaint: Dictionary in complaints:
		by_house[int(complaint["house"])] = complaint
	var ruined: Dictionary = by_house.get(0, {})
	_expect(ruined.get("client", &"") == &"hen" and ruined.get("result", &"") == &"ruined"
			and ClientComplaints.lines_for(&"hen", &"ruined").has(ruined.get("line", ""))
			and not bool(ruined.get("dismissed", true)),
			"The ruined hen box complains in the hen client's voice, unsettled (got %s)" % ruined)
	var wrong: Dictionary = by_house.get(1, {})
	_expect(wrong.get("client", &"") == &"wedding_cake" and wrong.get("result", &"") == &"wrong"
			and bool(wrong.get("noted", false)) and bool(wrong.get("dismissed", false))
			and ClientComplaints.lines_for(&"wedding_cake", &"wrong").has(wrong.get("line", "")),
			"A door handed the wrong box first keeps a note in its client's voice, at no cost (got %s)" % wrong)
	var unanswered: int = 0
	for line: Dictionary in results.get("breakdown", []):
		if String(line["label"]) == "HUD_SCORE_COMPLAINTS":
			unanswered = int(line["count"])
	_expect(unanswered == 1, "Only the ruined delivery costs points; the wrong-box note is free (got %d)" % unanswered)
	# Same session seed, same lines: the host's choice is a function of the seed.
	var entry: Dictionary = {"house": 0, "outcome": &"delivered_ruined"}
	var first: Dictionary = ClientComplaints.make(entry, false, assigned, 5150)
	_expect(first == ClientComplaints.make(entry.duplicate(), false, assigned.duplicate(), 5150),
			"The same seed gives the same complaint twice")
	await process_frame
	manager.call(&"reset_run")


func _results_screen_shows_them() -> void:
	var complaints: Array = [
		{"house": 0, "dismissed": false, "client": &"hen", "result": &"ruined",
				"line": "WORLD_COMPLAINT_HEN_RUINED_1"},
		{"house": 1, "dismissed": true, "client": &"wedding_cake", "result": &"at_risk",
				"line": "WORLD_COMPLAINT_WEDDING_CAKE_AT_RISK_2"},
		{"house": 2, "dismissed": true, "noted": true, "client": &"porcelain_vase", "result": &"wrong",
				"line": "WORLD_COMPLAINT_PORCELAIN_VASE_WRONG_1"},
		{"house": 3, "dismissed": false},
	]
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		hud.results._on_ended(120, {
			"delivered": true, "reason": "", "elapsed_seconds": 40.0, "cargo_total": 0, "cargo_intact": 0,
			"cargo_ruined": 0, "cargo_points": 0, "time_bonus": 0, "houses_delivered": 3, "houses_missed": 0,
			"breakdown": [], "best_score": 120, "complaints": complaints.duplicate(true), "deliveries": [],
		})
		await process_frame
		var text: String = hud.complaints_label.text
		_expect(hud.complaints_label.visible, "The results show the complaints (%s)" % locale)
		_expect(text.contains("Norma Gutiérrez") and text.contains(tr("WORLD_COMPLAINT_HEN_RUINED_1")),
				"The unsettled complaint names its client and speaks their line (%s): %s" % [locale, text])
		_expect(text.contains("Ramiro") and text.contains(tr("WORLD_COMPLAINT_WEDDING_CAKE_AT_RISK_2"))
				and text.contains(tr("WORLD_COMPLAINT_PORCELAIN_VASE_WRONG_1")),
				"The other clients are there with their own lines (%s)" % locale)
		_expect(text.contains(tr("HUD_COMPLAINT_PAID") % 4),
				"A complaint without a client keeps the plain wording (%s)" % locale)
		var unsettled: String = hud.results.call(&"complaint_line", complaints[0])
		_expect(unsettled != hud.results.call(&"complaint_line", complaints[1]),
				"What became of each complaint is stated in words too (%s)" % locale)
		_expect(tr("WORLD_COMPLAINT_HEN_RUINED_1") != "WORLD_COMPLAINT_HEN_RUINED_1",
				"The line's key really has a text in %s" % locale)
	_expect(tr("WORLD_COMPLAINT_HEN_RUINED_1") == "Rosita came out of the box indignant. And rightly so.",
			"The English text is the English one")
	hud.free()


## key -> [es, en]
func _read_csv() -> Dictionary:
	var table: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	_expect(file != null, "The world table exists")
	if file == null:
		return table
	file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3 and not line[0].is_empty():
			table[line[0]] = [line[1], line[2]]
	return table


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
