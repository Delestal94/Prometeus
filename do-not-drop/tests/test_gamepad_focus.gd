extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gamepad_focus.gd
##
## Every menu opened with a gamepad must put focus somewhere useful, let B
## close it, and return focus to the button that opened it. The cosmetics
## grids also keep directional focus inside their own row/column layout.

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
	depot_panel.queue_free()
	await process_frame

	var hud: CanvasLayer = load("res://scripts/ui/prototype_hud.gd").new()
	root.add_child(hud)
	await process_frame
	_expect(_focus_is_inside(hud.overlay), "The start/results overlay focuses its first action")
	hud.call(&"_primary_action")
	hud.set(&"_soft_pause", true)
	hud.set(&"overlay_mode", "pause")
	hud.overlay.show()
	hud.call(&"_set_buttons", "Continuar", true, true, true)
	_expect(_focus_is_inside(hud.overlay), "Pause focuses Continue")
	_send_cancel(hud)
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


func _check_cosmetic_neighbors(panel: Control) -> void:
	var buttons: Array = panel.get(&"_face_buttons")
	for button: Button in buttons:
		for property: StringName in [&"focus_neighbor_left", &"focus_neighbor_right", &"focus_neighbor_top", &"focus_neighbor_bottom"]:
			var neighbor := button.get_node_or_null(button.get(property)) as Button
			_expect(neighbor != null and neighbor.get_meta(&"kind") == button.get_meta(&"kind"),
				"Cosmetic grid keeps %s navigation inside the %s choices" % [String(property).trim_prefix("focus_neighbor_"), button.get_meta(&"kind")])


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
