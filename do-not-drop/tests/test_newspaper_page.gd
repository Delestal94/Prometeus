extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_newspaper_page.gd
##
## The next-day newspaper's page and where it sits in the HUD (N-606.2,
## newspaper_page.gd, hud_newspaper.gd, hud_results.gd):
## - with the host's newspaper_ready waiting, run_ended shows the page first and
##   the results card only after the player closes it (Continue, back or pause),
##   with the button focused so a gamepad can close it;
## - the page reads in the language of whoever looks: masthead with the town,
##   the front story, the ones under it and the classified, nothing cut at 1280x720
##   (the button and the sheet stay inside the screen) nor at narrower or bigger ones;
## - with no paper, or one that can't be read, the results come up as always;
## - a paper is shown once; a new run forgets one nobody read;
## - losing the host under the page closes it and leaves the results (greyed retry).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var settings: Node = root.get_node(^"/root/GameSettings")
	var desk: GDScript = load("res://scripts/presentation/newspaper/news_desk.gd")
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.pause.primary_action()
	var facts: Array = [{"kind": "deer_hit", "house": -1, "tags": [], "peer": 1},
			{"kind": "missed", "house": 1, "tags": ["cake"], "peer": 0},
			{"kind": "abandoned", "house": 0, "tags": ["hen"], "peer": 0},
			{"kind": "fault_mirror", "house": -1, "tags": [], "peer": 0}]
	var context: Dictionary = {"seed": 9, "town": "Villa Frágil", "km": 1.5, "minutes": 3,
			"crew": [{"peer": 1, "nick": "Turbo"}]}
	var paper: Dictionary = desk.call(&"compose", facts, context)
	var results: Dictionary = {"delivered": true, "elapsed_seconds": 100.0, "score": 120, "cargo_total": 1,
			"cargo_intact": 1,
			"houses_delivered": 1, "best_score": 500, "breakdown": [], "deliveries": []}

	# Without a paper the results come up as always.
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and hud.overlay.visible and not hud.newspaper.is_open(),
			"With no paper the results come straight up (mode %s)" % hud.overlay_mode)
	hud.overlay.hide()
	hud.overlay_mode = "run"

	# With one, the page first.
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	_expect(hud.newspaper.is_open() and hud.overlay_mode == "newspaper",
			"The page comes up before the results (mode %s)" % hud.overlay_mode)
	_expect(not hud.overlay.visible, "The results card waits behind the page")
	await process_frame
	await process_frame
	var page: Control = hud.newspaper.page
	_expect(page.visible and page.get_parent() == hud.root, "The page covers the HUD")
	var continue_button: Button = page.find_child("Continue", true, false) as Button
	_expect(continue_button != null and continue_button.has_focus(),
			"The button that closes it has the focus (for a gamepad)")
	_expect(continue_button != null and continue_button.text == tr("HUD_NEWS_CONTINUE"), "It says what comes next")
	var texts: Array = _texts(page)
	var town: String = "Villa Frágil"
	_expect(texts.has(tr("HUD_NEWS_MASTHEAD") % town), "The masthead names the town (%s)" % str(texts.slice(0, 6)))
	_expect(texts.has(tr("HUD_NEWS_MOTTO")), "The motto is there")
	_expect(page.find_child("Front", true, false) != null, "The front page story is there")
	_expect(page.find_children("Story_*", "", true, false).size() == (paper["stories"] as Array).size(),
			"Every story under it is there")
	_expect(page.find_child("Classified", true, false) != null, "The classified is there")
	var front: Dictionary = desk.call(&"read", paper["front"])
	_expect(texts.has(front["headline"]) and texts.has(front["body"]),
			"It prints the front story as this peer reads it (%s)" % front["headline"])

	# English reads in English.
	settings.call(&"set_language", "en")
	hud.newspaper.dismiss()
	_expect(hud.overlay_mode == "results", "Closing the page shows the results (mode %s)" % hud.overlay_mode)
	_expect(not hud.newspaper.is_open() and hud.overlay.visible, "The page is gone and the card is up")
	_expect(hud.action_button.visible and (hud.action_button.has_focus() or hud.menu_button.has_focus()),
			"The results card has focus again")
	hud.overlay.hide()
	hud.overlay_mode = "run"
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	await process_frame
	var english: Array = _texts(hud.newspaper.page)
	_expect(english.has(tr("HUD_NEWS_MASTHEAD") % town) and tr("HUD_NEWS_MASTHEAD") % town != "El Eco de Villa Frágil",
			"In English the masthead is English (%s)" % str(english.slice(0, 3)))
	_expect(english.has(desk.call(&"read", paper["front"])["headline"]), "In English the front story is English")
	settings.call(&"set_language", "es")

	# Sizes: nothing cut, the button and the sheet stay on screen.
	var sheet: Control = hud.newspaper.page.get("sheet")
	for window_size: Vector2 in [Vector2(1280, 720), Vector2(960, 720), Vector2(1920, 1080), Vector2(1024, 600)]:
		hud.newspaper.page.size = window_size
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, window_size)
		_expect(bounds.encloses(sheet.get_global_rect()),
				"At %s the sheet is inside the screen (%s)" % [window_size, sheet.get_global_rect()])
		var button_rect: Rect2 = continue_button_of(hud.newspaper.page).get_global_rect()
		_expect(bounds.encloses(button_rect) and sheet.get_global_rect().encloses(button_rect),
				"At %s the button is on the sheet and on screen (%s)" % [window_size, button_rect])
	hud.newspaper.page.call(&"close")
	_expect(hud.overlay_mode == "results", "Continue shows the results")
	hud.overlay.hide()
	hud.overlay_mode = "run"

	# A paper is shown once, and a paper nobody could read isn't shown.
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A paper is shown once")
	hud.overlay.hide()
	hud.overlay_mode = "run"
	var broken: Dictionary = paper.duplicate(true)
	broken["front"]["id"] = "not_a_story"
	bus.newspaper_ready.emit(broken)
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A paper that can't be read is skipped")
	hud.overlay.hide()
	hud.overlay_mode = "run"
	bus.newspaper_ready.emit(paper)
	bus.run_started.emit(&"test_route", [1])
	bus.run_ended.emit(120, results)
	_expect(hud.overlay_mode == "results" and not hud.newspaper.is_open(), "A new run forgets a paper nobody read")
	hud.overlay.hide()
	hud.overlay_mode = "run"

	# Keys: back closes it too.
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	await process_frame
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	hud.newspaper.page.call(&"_unhandled_input", cancel)
	_expect(hud.overlay_mode == "results", "Back closes the page like Continue")
	hud.overlay.hide()
	hud.overlay_mode = "run"

	# The host goes while the page is up: results stay, retry greyed out.
	hud.prompts.set(&"session_lost", false)
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	await process_frame
	network.session_failed.emit("host lost")
	await process_frame
	_expect(not hud.newspaper.is_open() and hud.overlay_mode == "results",
			"Losing the host closes the page and leaves the results (mode %s)" % hud.overlay_mode)
	_expect(hud.action_button.disabled, "The retry is greyed out, as on any results screen without its host")

	hud.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: the newspaper page comes before the results, reads in the viewer's language and fits every screen")
	quit(_failures)


func continue_button_of(page: Control) -> Button:
	return page.find_child("Continue", true, false) as Button


func _texts(node: Node) -> Array:
	var found: Array = []
	for label: Node in node.find_children("*", "Label", true, false):
		found.append((label as Label).text)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
