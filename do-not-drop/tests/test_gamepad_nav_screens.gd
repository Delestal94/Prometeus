extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gamepad_nav_screens.gd
##
## Gamepad navigation of every new company screen (expansion D-1948), the way a pad moves: from the focus a screen
## takes when it opens, the four directions (Control.find_valid_focus_neighbor: the neighbours a screen sets, or the
## nearest control on that side) and next / previous reach every control that takes focus, so nothing on screen is
## out of the pad's reach; and B (ui_cancel) leaves the screen.
## Screens: the day's closing screen, the company pause menu, the company shop, the dispatch board (with boxes, one
## of them blocked), the clipboard's Stock and Supplier sheets, and the main menu's company page and its form.
## (The phone, D-1923, and the credits, D-1940, check their own pad paths in their tests.)

const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
const HEN: String = "res://data/products/hen.tres"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	root.size = Vector2i(1280, 720)
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"new_company", "Pad Co")
	await _summary()
	await _pause()
	await _shop(state)
	await _dispatch()
	await _clipboard()
	await _slots()
	state.call(&"reset")
	if _failures == 0:
		print("PASS: every new company screen is reachable end to end with a pad, and B leaves it")
	quit(_failures)


func _summary() -> void:
	var screen := DaySummaryPanel.new()
	root.add_child(screen)
	await process_frame
	screen.set_shop_available(true)
	screen.open({"day": 3, "income_by_reason": {"order_paid": 90}})
	await _check("closing screen", screen)
	_cancel()
	_expect(not screen.visible, "closing screen: B continues")
	screen.queue_free()


func _pause() -> void:
	var screen := CompanyPauseMenu.new()
	root.add_child(screen)
	await process_frame
	screen.open(true)
	await _check("pause menu", screen)
	var resumed: Array[bool] = [false]
	screen.resume_requested.connect(func() -> void: resumed[0] = true)
	screen.back()
	_expect(resumed[0], "pause menu: B (back) resumes")
	screen.queue_free()


func _shop(state: Node) -> void:
	state.set(&"money", 100000)
	var screen := CompanyShopPanel.new()
	root.add_child(screen)
	await process_frame
	screen.open({"company": state, "can_act": true})
	await _check("shop", screen)
	var closed: Array[bool] = [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	_cancel()
	_expect(closed[0], "shop: B closes")
	screen.queue_free()


func _dispatch() -> void:
	var zones: Dictionary = _load_dir("res://data/zones/")
	var gates: Dictionary = _load_dir("res://data/gates/")
	var book := OrderBook.new()
	var zone := DispatchZone.new(AABB(Vector3(0, 0, 4), Vector3(4, 2, 3)))
	var products: Dictionary = {&"hen": load(HEN)}
	var kg: Dictionary = {}
	for entry: Array in [[&"o1", &"centro"], [&"o2", &"islas"], [&"o3", &"centro"]]:
		var box := StringName("box_" + str(entry[0]))
		book.add(Order.make(entry[0], "Cliente", entry[1], &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
		book.mark_packed(entry[0], box)
		zone.update_box(box, entry[0], Vector3(1, 0, 5), true, true, book)
		kg[box] = 3.0
	var van := VehicleDefinition.new()
	van.id = &"van_test"
	van.fleet_key = &"van"
	van.cargo_slots = 4
	van.cargo_kg = 100.0
	var screen := DispatchBoardPanel.new()
	root.add_child(screen)
	await process_frame
	screen.open({"zone": zone, "book": book, "trips": CompanyTrips.new(), "vehicle_id": &"van_1", "vehicle": van,
		"vehicle_name": "Camioneta", "box_kg": kg, "zones": zones, "gates": gates, "owned": {}, "opened_gates": [],
		"can_act": true})
	await _check("dispatch board", screen)
	_cancel()
	_expect(not screen.visible, "dispatch board: B closes")
	screen.queue_free()


func _clipboard() -> void:
	var stock := StockPanel.new()
	var supplier := SupplierOrderPanel.new()
	var frame := ClipboardFrame.new()
	root.add_child(frame)
	await process_frame
	frame.add_sheet(&"stock", "Stock", stock)
	frame.add_sheet(&"supplier", "Proveedor", supplier)
	stock.set_embedded(true)
	supplier.set_embedded(true)
	frame.show()
	var inventory := Inventory.new()
	var hen: ProductDefinition = load(HEN)
	inventory.receive(&"hen", 4, &"shelf:shelf_1_0")
	stock.open({"inventory": inventory, "products": {&"hen": hen}})
	frame.mark(&"stock")
	await _check("clipboard Stock sheet", stock)
	stock.hide()
	var cart := SupplierOrderCart.new()
	cart.products = {&"hen": hen}
	supplier.open({"cart": cart, "wallet": null, "schedule": SupplierSchedule.new(), "day": 1})
	frame.mark(&"supplier")
	await _check("clipboard Supplier sheet", supplier)
	frame.queue_free()


func _slots() -> void:
	var holder := VBoxContainer.new()
	root.add_child(holder)
	var page := CompanySlotsPage.new()
	page.save_dir = "user://test_gamepad_nav_screens"
	holder.add_child(page)
	await process_frame
	page.open()
	await _check("company page", page)
	(page.find_child("NewCompany", true, false) as Button).pressed.emit()
	await process_frame
	await _check("new company form", page)
	_expect(page.back(), "new company form: B goes back to the list")
	holder.queue_free()


## From the focus the screen took, the pad reaches every focusable control in it.
func _check(screen_name: String, screen: Control) -> void:
	await process_frame
	await process_frame
	var start: Control = root.gui_get_focus_owner()
	_expect(start != null and screen.is_ancestor_of(start), "%s takes the focus (%s)" % [screen_name, start])
	if start == null:
		return
	var seen: Dictionary = {start: true}
	var queue: Array[Control] = [start]
	while not queue.is_empty():
		var at: Control = queue.pop_front()
		var next: Array[Control] = [at.find_next_valid_focus(), at.find_prev_valid_focus()]
		for side: Side in SIDES:
			next.append(at.find_valid_focus_neighbor(side))
		for other: Control in next:
			if other != null and not seen.has(other) and screen.is_ancestor_of(other):
				seen[other] = true
				queue.append(other)
	var missing: Array[String] = []
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree() and not seen.has(control):
			missing.append(str(screen.get_path_to(control)))
	_expect(missing.is_empty(), "%s: every focusable control is in the pad's reach (missing %s)" % [screen_name,
		missing])


func _cancel() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	root.push_input(event)


func _load_dir(dir: String) -> Dictionary:
	var result: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var res: Resource = load(dir + file)
			result[res.get("id")] = res
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
