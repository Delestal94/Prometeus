extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ui_transitions.gd
##
## The company screens come in instead of popping (expansion D-1941, with D-1934 "transiciones animadas"): opening
## the day's closing screen, the company pause menu, the shop or the dispatch board starts its card transparent and
## a touch small (UiTheme.POP_FROM_SCALE) and brings it whole within UiTheme.POP_SECONDS; a screen opened again does
## it again; the card ends exactly at full size and opacity (nothing left half-faded).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"new_company", "Pop Co")
	var summary := DaySummaryPanel.new()
	var pause := CompanyPauseMenu.new()
	var shop := CompanyShopPanel.new()
	var board := DispatchBoardPanel.new()
	var screens: Array = [
		[summary, func() -> void: summary.open({"day": 2})],
		[pause, func() -> void: pause.open(true)],
		[shop, func() -> void: shop.open({"company": state, "can_act": true})],
		[board, func() -> void: board.open({})],
	]
	for entry: Array in screens:
		var screen: Control = entry[0]
		root.add_child(screen)
		await process_frame
		for lap: int in 2:
			(entry[1] as Callable).call()
			var card := screen.find_children("*", "PanelContainer", true, false)[0] as Control
			var name: String = screen.get_script().resource_path.get_file()
			_expect(card.modulate.a < 0.05 and card.scale.x < 1.0, "%s starts its card faded and small (lap %d)"
				% [name, lap])
			await create_timer(UiTheme.POP_SECONDS + 0.1).timeout
			_expect(is_equal_approx(card.modulate.a, 1.0) and card.scale.is_equal_approx(Vector2.ONE),
				"%s brings its card whole (lap %d: %.2f, %s)" % [name, lap, card.modulate.a, card.scale])
		screen.queue_free()
		await process_frame
	state.call(&"reset")
	if _failures == 0:
		print("PASS: the company screens come in with a short fade and grow, and end whole")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
