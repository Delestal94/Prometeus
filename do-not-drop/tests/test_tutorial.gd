extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_tutorial.gd
## Covers S-506: complete trap cards, unlocked-page filtering, first-run
## highlighting and one-time persistence for in-game tips.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var tutorial_data: Script = load("res://scripts/ui/tutorial_catalog.gd")
	var profile: Node = root.get_node(^"/root/UnlockManager")
	var original: Dictionary = {
		"completed_runs": profile.completed_runs,
		"unlocked": profile.unlocked.duplicate(true),
		"seen_tips": profile.seen_tips.duplicate(true),
	}
	profile.completed_runs = 0
	profile.unlocked = {&"starter_kit": true}
	profile.seen_tips = {}

	for trap_id: StringName in tutorial_data.TRAP_ORDER:
		var card: Dictionary = tutorial_data.card(trap_id)
		_expect(not card.is_empty(), "%s has a tutorial card" % trap_id)
		for field: String in ["title", "glyph", "breaks", "action", "keyboard", "gamepad", "control_label"]:
			_expect(not String(card.get(field, "")).is_empty(), "%s card has %s" % [trap_id, field])

	var panel: Control = load("res://scripts/ui/tutorial_panel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.open()
	var starter_titles: PackedStringArray = panel.page_titles()
	_expect(starter_titles.has("Frágil") and starter_titles.has("Equilibrio"), "Starter traps have tutorial pages")
	_expect(not starter_titles.has("Explosivo"), "Locked traps stay out of the profile tutorial")
	profile.unlocked[&"explosive_trap"] = true
	panel.open()
	_expect(panel.page_titles().has("Explosivo"), "A newly unlocked trap gets its tutorial page")

	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var how_to_button: Button = _button_named(menu, "Cómo jugar")
	_expect(how_to_button != null and bool(how_to_button.get_meta(&"first_run_highlighted", false)),
		"A profile without completed runs highlights Cómo jugar")

	var tip_events: Array[String] = []
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.tutorial_tip_requested.connect(func(text: String) -> void: tip_events.append(text))
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var package := DeliveryPackage.new()
	package.trap_definition = load("res://data/traps/fragile.tres")
	player.call(&"_show_first_trap_tip", package)
	player.call(&"_show_first_trap_tip", package)
	_expect(tip_events.size() == 1, "A first-time trap tip is emitted only once")
	_expect(not tip_events.is_empty() and tip_events[0].contains("Frágil"), "The tip identifies the trap")
	profile.seen_tips = {}
	profile.call(&"load_profile")
	_expect(bool(profile.seen_tips.get(&"fragile", false)), "Seen tips survive a profile reload")
	_expect(not bool(profile.call(&"mark_tip_seen", &"fragile")), "A seen tip remains seen in the profile")

	player.free()
	package.free()
	menu.free()
	panel.free()
	profile.completed_runs = original["completed_runs"]
	profile.unlocked = original["unlocked"]
	profile.seen_tips = original["seen_tips"]
	profile.call(&"save_profile")
	if _failures == 0:
		print("PASS: tutorial pages, unlock filtering and first-time tips")
	quit(_failures)


func _button_named(parent: Node, text: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text and button.is_visible_in_tree():
			return button
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
