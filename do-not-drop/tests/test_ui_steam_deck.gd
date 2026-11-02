extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_ui_steam_deck.gd
##
## The expansion's screens fit small screens (expansion D-1910, "captura a 800p" checked on the numbers): each one
## is built in a viewport of 1280x720 (the project's base size, the tightest with stretch "expand") and of 1280x800
## (the Steam Deck), with the menu text at 1x and at 1.5x (GameSettings.MENU_TEXT_SCALES' largest, applied to the
## screen alone, so the player's settings are not touched), and its panel must lie inside the viewport:
## - the day's closing screen with every part full (ten reasons a side, the delivery note, milestones, wages,
##   tomorrow): its body scrolls, title and Continue stay on screen, and ui_down / ui_up scroll it on a pad;
## - the company pause menu, the company shop, the dispatch board and the clipboard with its two sheets;
## - a short day's closing screen does not scroll (the body is as tall as its content).

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1280, 800)]
const SCALES: Array[float] = [1.0, 1.5]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"new_company", "Deck Co")
	for size: Vector2i in SIZES:
		for scale: float in SCALES:
			await _check_all(size, scale, state)
	await _check_scroll()
	await _check_short_day()
	state.call(&"reset")
	if _failures == 0:
		print("PASS: the expansion's screens fit 1280x720 and the Steam Deck's 1280x800, with 1.5x text too")
	quit(_failures)


func _check_all(size: Vector2i, scale: float, state: Node) -> void:
	var summary := DaySummaryPanel.new()
	var pause := CompanyPauseMenu.new()
	var shop := CompanyShopPanel.new()
	var board := DispatchBoardPanel.new()
	var clip := ClipboardFrame.new()
	var screens: Array = [
		[summary, func() -> void: _open_heavy(summary)],
		[pause, func() -> void: pause.open(true)],
		[shop, func() -> void: shop.open({"company": state, "can_act": true})],
		[board, func() -> void: board.open({})],
		[clip, func() -> void:
			clip.add_sheet(&"stock", "Stock", StockPanel.new())
			clip.add_sheet(&"supplier", "Proveedor", SupplierOrderPanel.new())
			clip.show()],
	]
	for entry: Array in screens:
		var view: SubViewport = await _show(entry[0], entry[1], size, scale)
		var screen: Control = entry[0]
		var name: String = screen.get_script().resource_path.get_file()
		var panel := screen.find_children("*", "PanelContainer", true, false)[0] as PanelContainer
		_expect(_inside(panel, size), "%s fits %s at %.1fx (panel %s)" % [name, size, scale, panel.get_global_rect()])
		if screen == summary:
			var go := summary.find_child("Continue", true, false) as Control
			_expect(go != null and _inside(go, size), "Continue is on screen at %s %.1fx" % [size, scale])
		view.queue_free()
		await process_frame


func _check_scroll() -> void:
	var summary := DaySummaryPanel.new()
	var view: SubViewport = await _show(summary, func() -> void: _open_heavy(summary), Vector2i(1280, 720), 1.0)
	var body := summary.find_child("Body", true, false) as ScrollContainer
	_expect(body != null and body.get_v_scroll_bar().max_value > body.size.y, "a full day scrolls at 720")
	if body != null:
		var before: int = body.scroll_vertical
		_press(&"ui_down", view)
		await process_frame
		_expect(body.scroll_vertical > before, "ui_down scrolls the body (%d -> %d)" % [before, body.scroll_vertical])
		_press(&"ui_up", view)
		await process_frame
		_expect(body.scroll_vertical == before, "ui_up scrolls it back")
	_expect(summary.visible, "scrolling does not close it")
	view.queue_free()
	await process_frame


func _check_short_day() -> void:
	var summary := DaySummaryPanel.new()
	var opener: Callable = func() -> void: summary.open({"day": 2, "income_by_reason": {"order_paid": 80}})
	var view: SubViewport = await _show(summary, opener, Vector2i(1280, 800), 1.0)
	var body := summary.find_child("Body", true, false) as ScrollContainer
	var content := body.get_child(0) as Control
	_expect(is_equal_approx(body.custom_minimum_size.y, content.get_combined_minimum_size().y),
		"a short day's body is as tall as its content")
	view.queue_free()
	await process_frame


func _show(screen: Control, opener: Callable, size: Vector2i, scale: float) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.disable_3d = true
	view.gui_disable_input = false
	root.add_child(view)
	view.add_child(screen)
	await process_frame
	opener.call()
	UiTheme._refresh_text_scale(scale, screen)
	if screen.has_method(&"fit_body"):
		screen.call(&"fit_body")
	for i: int in 3:
		await process_frame
	return view


func _open_heavy(summary: DaySummaryPanel) -> void:
	var income: Dictionary = {"milestone:first_earnings": 150}
	var costs: Dictionary = {"wages": 240}
	for i: int in 10:
		income["income_%d" % i] = 100 + i
		costs["cost_%d" % i] = 50 + i
	var notes: Array = []
	for i: int in 9:
		notes.append({"product": "hen_%d" % i, "ordered": 10, "received": 4, "missing": 6, "extra": 0})
	var wages: Array = []
	for who: String in ["Ana", "Beto", "Caro", "Dani"]:
		wages.append({"name": who, "wage": 60})
	summary.note_milestone(&"clean_week")
	summary.open({"day": 12, "income": 2000, "costs": 900, "profit": 1100, "opening": 500, "closing": 1600,
		"income_by_reason": income, "cost_by_reason": costs, "truncated": true},
		notes, 30, {"employees": wages, "tomorrow": ["market", "inspection"]})


func _press(action: StringName, view: Viewport) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		view.push_input(event)


static func _inside(control: Control, size: Vector2i) -> bool:
	var rect: Rect2 = control.get_global_rect()
	return rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= size.x + 0.5 \
		and rect.end.y <= size.y + 0.5


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
