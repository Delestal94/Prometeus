extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gamepad_focus.gd
##
## Every menu opened with a gamepad must put focus somewhere useful, let B
## close it, and return focus to the button that opened it. The cosmetics
## grids also keep directional focus inside their own row/column layout, and
## the depot's lockers (the same screen) focus a card and close with B.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	await _check_menu_panel(menu, "Opciones", menu.get(&"_options") as Control)
	await _check_menu_panel(menu, "Cómo jugar", menu.get(&"_tutorial") as Control)
	menu.call(&"_show_page", 3)
	var cosmetics := menu.get(&"_cosmetics") as Control
	await _check_menu_panel(menu, "Apariencia", cosmetics)
	_check_cosmetic_neighbors(cosmetics)
	await _check_menu_panel(menu, "Progreso", menu.get(&"_progress") as Control)
	await _check_menu_panel(menu, "Récords", menu.get(&"_leaderboard") as Control)
	menu.queue_free()
	await process_frame
	await process_frame

	var depot_panel: Control = load("res://scripts/ui/depot_panel.gd").new()
	root.add_child(depot_panel)
	await process_frame
	depot_panel.call(&"open", &"orders", null)
	await process_frame
	_expect(_focus_is_inside(depot_panel), "Depot panel focuses its first action when opened")
	_send_cancel(depot_panel)
	await process_frame
	_expect(not depot_panel.visible, "B closes the depot panel")
	# The lockers show the appearance screen inside the depot panel (N-506).
	depot_panel.call(&"open", &"wardrobe", null)
	await process_frame
	await process_frame
	var wardrobe: Node = depot_panel.get_node_or_null(^"Wardrobe")
	_expect(wardrobe != null and _focus_is_inside(wardrobe), "The lockers focus a card when opened")
	if wardrobe != null:
		_send_cancel(wardrobe)
	await process_frame
	_expect(not depot_panel.visible, "B closes the lockers and the depot panel")
	depot_panel.queue_free()
	await process_frame

	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	_expect(_focus_is_inside(hud.overlay), "The start/results overlay focuses its first action")
	hud.pause.primary_action()
	hud.soft_pause = true
	hud.set(&"overlay_mode", "pause")
	hud.overlay.show()
	hud.results.set_buttons("Continuar", true, true, true)
	_expect(_focus_is_inside(hud.overlay), "Pause focuses Continue")
	_send_cancel(hud.pause)
	await process_frame
	_expect(not hud.overlay.visible, "B closes pause and returns to play")
	hud.free()

	if _failures == 0:
		print("PASS: every menu focuses, restores and closes cleanly with a gamepad")
	quit(_failures)


func _check_menu_panel(menu: Control, button_text: String, panel: Control) -> void:
	var opener: Button = _button_named(menu, button_text)
	_expect(opener != null, "%s has an opener" % button_text)
	if opener == null:
		return
	opener.grab_focus()
	opener.pressed.emit()
	await process_frame
	await process_frame
	_expect(panel.visible, "%s opens" % button_text)
	_expect(_focus_is_inside(panel), "%s focuses its first action" % button_text)
	_send_cancel(panel)
	await process_frame
	_expect(not panel.visible, "B closes %s" % button_text)
	_expect(root.gui_get_focus_owner() == opener, "%s restores focus to its opener" % button_text)
	if panel.visible:
		panel.hide()
		panel.emit_signal(&"closed")


## The face cards (N-506: ready-made faces, eyes, mouths): arrows stay among
## them, except left out of the first column (the nickname field, N-606.1), up
## out of the top row (the tabs) and down out of the last row (Done).
func _check_cosmetic_neighbors(panel: Control) -> void:
	var cards: Array = panel.get(&"_cards")
	for button: Button in cards:
		if not button.get_meta(&"kind") in ["preset", "eyes", "mouth"]:
			continue
		for property: StringName in [&"focus_neighbor_left", &"focus_neighbor_right", &"focus_neighbor_top",
				&"focus_neighbor_bottom"]:
			var target: Node = button.get_node_or_null(button.get(property))
			var way: String = String(property).trim_prefix("focus_neighbor_")
			if target is LineEdit:
				_expect(way == "left" and target.name == &"NicknameEdit",
						"Only left out of the grid reaches the nickname")
			elif target != null and String(target.name).begins_with("Tab_"):
				_expect(way == "top" and button.get_meta(&"kind") == "preset",
						"Only up from the top row reaches the tabs")
			elif target != null and target.name == &"Done":
				_expect(way == "bottom" and button.get_meta(&"kind") == "mouth",
						"Only down from the last row reaches Done")
			else:
				_expect(target is Button and (target as Button).get_meta(&"kind", "") in ["preset", "eyes", "mouth"],
						"The face grid keeps %s navigation among the face cards (%s)" % [way, button.name])


func _button_named(parent: Node, text: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text and button.is_visible_in_tree():
			return button
	return null


func _focus_is_inside(panel: Node) -> bool:
	var focus: Control = root.gui_get_focus_owner()
	return focus != null and (focus == panel or panel.is_ancestor_of(focus))


func _send_cancel(target: Node) -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	target.call(&"_unhandled_input", event)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
