extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_depot_panel.gd
##
## The depot's order sheet with a full crew (depot_panel.gd, N-228.6): eight
## players means seven houses, so seven orders:
## - one row per order ("Order_<i>") inside a scroll box ("OrdersScroll");
## - the whole card, Back button included, fits the base resolution (1280x720)
##   even with the Boss's two notes on it, and so does a short list;
## - when the list does not fit it scrolls: the box takes focus, up / down move
##   it and the mouse wheel works; at the ends focus moves on to Back;
## - a list that fits is not a focus stop (Back keeps the first focus).

const HOUSES_MAX: int = 7
const TRAPS: Array[String] = ["fragile", "balance", "noisy", "liquid", "explosive", "hostile", "growing_weight"]

var _failures: int = 0
var _depot: Node
var _panel: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The headless window has no fixed shape: pin it to the base resolution.
	root.size = Vector2i(1280, 720)
	_depot = _stub_depot()
	_panel = load("res://scripts/ui/depot_panel.gd").new()
	root.add_child(_panel)
	await process_frame
	var base := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var screen: Vector2 = _panel.get_viewport_rect().size
	_expect(screen == base,
			"The test viewport is the base resolution (got %s, base %s)" % [screen, base])

	# Seven orders, two Boss notes: the worst case.
	_depot.set(&"orders", _orders(HOUSES_MAX))
	_panel.call(&"open", &"orders", _depot)
	await process_frame
	await process_frame
	await process_frame
	var scroll: ScrollContainer = _panel.find_child("OrdersScroll", true, false)
	_expect(scroll != null, "The order rows sit in a scroll box")
	var rows: Array[Node] = _panel.find_children("Order_*", "HBoxContainer", true, false)
	_expect(rows.size() == HOUSES_MAX, "Seven orders make seven rows (got %d)" % rows.size())
	for index: int in rows.size():
		_expect(_panel.find_child("Order_%d" % index, true, false) != null, "Row Order_%d exists" % index)
	var back: Button = _back_button()
	_expect(back != null, "The Back button is there")
	_expect(_fits(_panel, base), "The whole card fits %s (card %s)" % [base, _card(_panel).get_global_rect()])
	if back != null:
		_expect(Rect2(Vector2.ZERO, base).encloses(back.get_global_rect()),
				"Back is on screen (got %s)" % back.get_global_rect())
	_expect(scroll != null and scroll.focus_mode == Control.FOCUS_ALL,
			"A list that does not fit becomes a focus stop")
	_expect(root.gui_get_focus_owner() == back, "Back still takes the first focus")

	# The pad can reach every row: up from Back lands on the list, down scrolls it.
	if scroll != null and back != null:
		scroll.grab_focus()
		_expect(root.gui_get_focus_owner() == scroll, "The scroll box can take focus")
		var before: int = scroll.scroll_vertical
		_press(scroll, &"ui_down")
		_expect(scroll.scroll_vertical > before, "Down scrolls the list (%d -> %d)" % [before, scroll.scroll_vertical])
		for _i: int in 20:
			_press(scroll, &"ui_down")
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		_expect(bar.value >= bar.max_value - bar.page - 0.5, "Down reaches the last row (at %s)" % bar.value)
		await process_frame
		var last: Control = _panel.find_child("Order_%d" % (HOUSES_MAX - 1), true, false)
		_expect(scroll.get_global_rect().encloses(last.get_global_rect()),
				"The last row is inside the box once scrolled (box %s, row %s)"
				% [scroll.get_global_rect(), last.get_global_rect()])
		for _i: int in 30:
			_press(scroll, &"ui_up")
		_expect(scroll.scroll_vertical == 0, "Up goes back to the first row (at %d)" % scroll.scroll_vertical)

	# A short list needs no scrolling and no extra stop.
	_depot.set(&"orders", _orders(2))
	_panel.call(&"open", &"orders", _depot)
	await process_frame
	await process_frame
	await process_frame
	scroll = _panel.find_child("OrdersScroll", true, false)
	_expect(_panel.find_children("Order_*", "HBoxContainer", true, false).size() == 2, "Two orders make two rows")
	_expect(_fits(_panel, base), "A short list fits too")
	_expect(scroll != null and scroll.focus_mode == Control.FOCUS_NONE and scroll.get_v_scroll_bar().max_value
			<= scroll.get_v_scroll_bar().page + 0.5, "A list that fits neither scrolls nor takes focus")

	# No orders (endless): just the hint, no scroll box.
	_depot.set(&"orders", [])
	_panel.call(&"open", &"orders", _depot)
	await process_frame
	_expect(_panel.find_child("OrdersScroll", true, false) == null, "No orders, no scroll box")
	_expect(_fits(_panel, base), "The empty sheet fits")

	_panel.queue_free()
	_depot.free()
	await process_frame
	if _failures == 0:
		print("PASS: seven orders fit the base screen with Back visible, and the list scrolls with the pad")
	quit(_failures)


func _stub_depot() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar orders: Array = []\nfunc boss_notes() -> Array:\n" \
			+ "\treturn [\"Hoy hay siete pedidos: no me hagas rogar, y ojo con la gallina.\"," \
			+ " \"Ayer se rompio todo, que no se repita, por favor, equipo.\"]\n"
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	root.add_child(stub)
	return stub


func _orders(count: int) -> Array:
	var list: Array = []
	for index: int in count:
		list.append({"house": index, "code": "A-%d%d" % [index + 1, index * 3], "trap": TRAPS[index % TRAPS.size()],
				"content": "Vajilla fragil", "package_id": StringName("pkg_%d" % index)})
	return list


func _card(panel: Control) -> Control:
	return (panel.find_children("*", "CenterContainer", true, false)[0] as Node).get_child(0)


## True when the card, shadow included, lies inside the screen.
func _fits(panel: Control, screen: Vector2) -> bool:
	var rect: Rect2 = _card(panel).get_global_rect()
	return Rect2(Vector2.ZERO, screen).encloses(rect.grow(2.0))


func _back_button() -> Button:
	var buttons: Array[Node] = _panel.find_children("*", "Button", true, false)
	return buttons[buttons.size() - 1] as Button if not buttons.is_empty() else null


func _press(target: Control, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	target.gui_input.emit(event)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
