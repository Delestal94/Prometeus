extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_dispatch_panel.gd
##
## The dispatch board (expansion D-0310, dispatch_board_panel.gd), driven by injected data only:
## - with 3 sealed boxes waiting, the focus starts on the first row; ui_accept picks it, ui_down
##   moves the focus down the column, and after picking 2 the focus reaches Load; ui_accept there
##   stages exactly those 2 boxes (and their orders) on the vehicle in CompanyTrips and the third
##   keeps waiting in the zone;
## - the vehicle's slots are drawn with shapes (filled / empty) and a mark in front of every row
##   ("✓" picked, "○" free), not only colour;
## - a box for a zone the vehicle cannot reach is "✗", cannot be picked and its row says why
##   (DispatchRules); picking more than the vehicle's slots or kg is refused with the reason;
## - a client (can_act false) sees Load disabled with the reason and loads nothing; no vehicle
##   at the yard disables it too; an empty zone says so and focuses Close;
## - every focus neighbour points at a live node, and ui_cancel closes the board;
## - with CompanyTuning.VEHICLES_FAR_MAX (2) vehicles out (CompanyTrips.departure_verdict(), D-0316)
##   a box can still be picked but Load is off, the status says why and nothing loads; once one is
##   back, Load works again;
## - both languages have every key the board uses (strings_ui.csv, and strings_world.csv for the
##   reasons that come from the world, like WORLD_DISPATCH_FAR_LIMIT).

const ZONE_DIR: String = "res://data/zones/"
const HEN: String = "res://data/products/hen.tres"
const GATE_DIR: String = "res://data/gates/"
const KEYS: Array[String] = [
	"UI_DISPATCH_TITLE", "UI_DISPATCH_HINT", "UI_DISPATCH_VEHICLE", "UI_DISPATCH_NO_VEHICLE",
	"UI_DISPATCH_CAPACITY", "UI_DISPATCH_EMPTY", "UI_DISPATCH_ROW", "UI_DISPATCH_PICK",
	"UI_DISPATCH_LOAD", "UI_DISPATCH_LOAD_N", "UI_DISPATCH_CLOSE", "UI_DISPATCH_LOADED",
	"UI_DISPATCH_HOST_ONLY", "WORLD_DISPATCH_FAR_LIMIT",
]
const CSVS: Array[String] = ["res://translations/strings_ui.csv", "res://translations/strings_world.csv"]

var _failures: int = 0
var _zones: Dictionary = {}
var _gates: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_zones = _load_dir(ZONE_DIR)
	_gates = _load_dir(GATE_DIR)
	_test_keys()
	await _test_pick_and_load()
	await _test_limits_and_rules()
	await _test_client_and_empty()
	await _test_far_cap()
	if _failures == 0:
		print("PASS: dispatch board loads the 2 picked boxes on the vehicle and the third waits")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _load_dir(dir: String) -> Dictionary:
	var result: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var res: Resource = load(dir + file)
			result[res.get("id")] = res
	return result


func _van(slots: int, kg: float) -> VehicleDefinition:
	var def := VehicleDefinition.new()
	def.id = &"van_test"
	def.fleet_key = &"van"
	def.cargo_slots = slots
	def.cargo_kg = kg
	return def


## Boxes box_<id> sealed and waiting in the zone, one per entry of `zones_of` (order id -> zone).
func _ctx(zones_of: Dictionary, vehicle: VehicleDefinition, can_act: bool = true) -> Dictionary:
	var book := OrderBook.new()
	var zone := DispatchZone.new(AABB(Vector3(0, 0, 4), Vector3(4, 2, 3)))
	var products: Dictionary = {&"hen": load(HEN)}
	var kg: Dictionary = {}
	for id: StringName in zones_of:
		var box := StringName("box_" + str(id))
		var items: Array = [{"product": &"hen", "qty": 1}]
		book.add(Order.make(id, "Cliente " + str(id), zones_of[id], &"house_1", items, 0, products))
		book.mark_packed(id, box)
		zone.update_box(box, id, Vector3(1, 0, 5), true, true, book)
		kg[box] = 3.0
	return {
		"zone": zone, "book": book, "trips": CompanyTrips.new(), "vehicle_id": &"van_1",
		"vehicle": vehicle, "vehicle_name": "Camioneta", "box_kg": kg, "zones": _zones,
		"gates": _gates, "owned": {}, "opened_gates": [], "can_act": can_act,
	}


func _panel(ctx: Dictionary) -> DispatchBoardPanel:
	var panel := DispatchBoardPanel.new()
	root.add_child(panel)
	panel.open(ctx)
	await process_frame
	await process_frame
	return panel


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		root.push_input(event)
	await process_frame


func _focus_name() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return String(owner.name) if owner != null else ""


func _test_keys() -> void:
	var rows: Dictionary = {}
	for csv: String in CSVS:
		var file := FileAccess.open(csv, FileAccess.READ)
		while not file.eof_reached():
			var cols: PackedStringArray = file.get_csv_line()
			if cols.size() >= 3:
				rows[cols[0]] = cols
	for key: String in KEYS:
		var both: bool = rows.has(key) and rows[key][1] != "" and rows[key][2] != ""
		_expect(both, "translation row with both languages: " + key)


func _test_pick_and_load() -> void:
	var ctx: Dictionary = _ctx({&"o1": &"centro", &"o2": &"centro", &"o3": &"centro"}, _van(4, 100.0))
	var panel: DispatchBoardPanel = await _panel(ctx)
	var zone: DispatchZone = ctx["zone"]
	var trips: CompanyTrips = ctx["trips"]
	_expect(panel.row_button(&"box_o1") != null and panel.row_button(&"box_o3") != null, "one row per waiting box")
	_expect(_focus_name() == "Box_box_o1", "focus starts on the first row (got %s)" % _focus_name())
	_expect(panel.row_button(&"box_o1").text.begins_with(DispatchBoardPanel.FREE), "free row starts with the open mark")
	_expect(_slots(panel) == "□ □ □ □", "four empty slot shapes (got %s)" % _slots(panel))
	_expect(panel.load_button().disabled, "Load is off with nothing picked")
	await _press(&"ui_accept")
	_expect(panel.selected() == [&"box_o1"], "ui_accept picks the focused box (got %s)" % [panel.selected()])
	_expect(panel.row_button(&"box_o1").text.begins_with(DispatchBoardPanel.PICKED), "picked row shows the check mark")
	_expect(_slots(panel) == "■ □ □ □", "one filled slot shape (got %s)" % _slots(panel))
	await _press(&"ui_down")
	_expect(_focus_name() == "Box_box_o2", "ui_down moves to the second row (got %s)" % _focus_name())
	await _press(&"ui_accept")
	_expect(panel.selected() == [&"box_o1", &"box_o2"], "second box picked (got %s)" % [panel.selected()])
	await _press(&"ui_down")
	_expect(_focus_name() == "Box_box_o3", "ui_down moves to the third row (got %s)" % _focus_name())
	await _press(&"ui_down")
	_expect(_focus_name() == "Load", "ui_down reaches Load (got %s)" % _focus_name())
	_expect(not panel.load_button().disabled, "Load is on with 2 picked")
	_expect(panel.load_button().text == tr_es("UI_DISPATCH_LOAD_N") % 2, "Load shows the count")
	var loaded: Array = []
	panel.loaded.connect(func(vehicle_id: StringName, _boxes: Array[StringName]) -> void: loaded.append(vehicle_id))
	await _press(&"ui_accept")
	var staged: Dictionary = trips._staged.get(&"van_1", {})
	_expect(staged.get("boxes", []) == [&"box_o1", &"box_o2"], "vehicle has the 2 picked boxes (got %s)" % [staged])
	_expect(staged.get("orders", []) == [&"o1", &"o2"], "and their orders (got %s)" % [staged])
	_expect(zone.boxes() == [&"box_o3"], "the third keeps waiting (got %s)" % [zone.boxes()])
	_expect(loaded.size() == 1 and loaded[0] == &"van_1", "loaded signal fired once for the vehicle")
	_expect(panel.row_button(&"box_o3") != null, "board still shows the box left")
	_expect(panel.row_button(&"box_o1") == null, "board no longer shows a loaded box")
	_expect(_focus_name() == "Box_box_o3", "focus returns to a live row (got %s)" % _focus_name())
	_check_focus_links(panel)
	await _press(&"ui_cancel")
	_expect(not panel.visible, "ui_cancel closes the board")
	panel.queue_free()
	await process_frame


func _test_limits_and_rules() -> void:
	var ctx: Dictionary = _ctx({&"o1": &"centro", &"o2": &"islas", &"o3": &"centro", &"o4": &"centro"}, _van(2, 100.0))
	var panel: DispatchBoardPanel = await _panel(ctx)
	var blocked: Dictionary = panel.toggle(&"box_o2")
	var needs: String = DispatchRules.NEEDS_VEHICLE
	_expect(not blocked["ok"] and blocked["key"] == needs, "Islas box by van is refused (got %s)" % [blocked])
	_expect(panel.selected().is_empty(), "a refused box is not picked")
	var row_text: String = panel.row_button(&"box_o2").text
	_expect(row_text.begins_with(DispatchBoardPanel.BLOCKED), "blocked row shows the cross mark")
	var reason: String = DispatchBoardPanel.reason_text(needs, blocked["args"])
	_expect(row_text.contains(reason), "blocked row says why (got %s)" % row_text)
	_expect(panel.status_text() == reason, "status line repeats the reason (got %s)" % panel.status_text())
	_expect(panel.toggle(&"box_o1")["ok"] and panel.toggle(&"box_o3")["ok"], "two boxes fit two slots")
	var full: Dictionary = panel.toggle(&"box_o4")
	_expect(not full["ok"] and full["key"] == DispatchLoading.NO_SLOTS, "third box refused: no slot (got %s)" % [full])
	_expect(panel.toggle(&"box_o1")["ok"] and panel.selected() == [&"box_o3"], "toggling a picked box drops it")
	panel.queue_free()
	await process_frame
	var heavy: Dictionary = _ctx({&"o1": &"centro", &"o2": &"centro"}, _van(5, 5.0))
	var heavy_panel: DispatchBoardPanel = await _panel(heavy)
	_expect(heavy_panel.toggle(&"box_o1")["ok"], "3 kg fits 5 kg")
	var over: Dictionary = heavy_panel.toggle(&"box_o2")
	_expect(not over["ok"] and over["key"] == DispatchLoading.NO_WEIGHT, "6 kg over 5 kg refused (got %s)" % [over])
	heavy_panel.queue_free()
	await process_frame


func _test_client_and_empty() -> void:
	var ctx: Dictionary = _ctx({&"o1": &"centro"}, _van(2, 100.0), false)
	var panel: DispatchBoardPanel = await _panel(ctx)
	panel.toggle(&"box_o1")
	_expect(panel.load_button().disabled, "client: Load is disabled, not hidden")
	_expect(panel.load_button().visible, "client: Load stays visible")
	var host_only: String = tr_es("UI_DISPATCH_HOST_ONLY")
	_expect(panel.status_text() == host_only, "client sees the reason (got %s)" % panel.status_text())
	_expect(panel.confirm() == 0 and (ctx["zone"] as DispatchZone).boxes().size() == 1, "client loads nothing")
	panel.queue_free()
	await process_frame
	var none: Dictionary = _ctx({&"o1": &"centro"}, null)
	var none_panel: DispatchBoardPanel = await _panel(none)
	_expect(not none_panel.toggle(&"box_o1")["ok"], "no vehicle: nothing can be picked")
	_expect(none_panel.load_button().disabled, "no vehicle: Load is off")
	var vehicle_line: Label = none_panel.find_child("Vehicle", true, false)
	_expect(vehicle_line.text == tr_es("UI_DISPATCH_NO_VEHICLE"), "no vehicle is said")
	none_panel.queue_free()
	await process_frame
	var empty_ctx: Dictionary = _ctx({}, _van(2, 100.0))
	var empty: DispatchBoardPanel = await _panel(empty_ctx)
	_expect(empty.find_child("Empty", true, false) != null, "empty zone says so")
	_expect(_focus_name() == "Close", "empty board focuses Close (got %s)" % _focus_name())
	_check_focus_links(empty)
	empty.queue_free()
	await process_frame


func _test_far_cap() -> void:
	var ctx: Dictionary = _ctx({&"o1": &"centro"}, _van(2, 100.0))
	var trips: CompanyTrips = ctx["trips"]
	trips.setup(Vector3(0, 0, -4), 2.0)
	var products: Dictionary = {&"hen": load(HEN)}
	for id: StringName in [&"x1", &"x2"]:
		var box := StringName("box_" + str(id))
		trips.book.add(Order.make(id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products))
		trips.book.mark_packed(id, box)
		var out_van := StringName("out_" + str(id))
		trips.stage_cargo(out_van, [id], [box])
		trips.track(out_van, Vector3(0, 0, -2))
		trips.track(out_van, Vector3(0, 0, -6))
	_expect(trips.trips_out() == 2, "two vehicles are out (got %d)" % trips.trips_out())
	var panel: DispatchBoardPanel = await _panel(ctx)
	_expect(panel.toggle(&"box_o1")["ok"], "with two out, a box can still be picked")
	_expect(panel.load_button().disabled, "with two out, Load is off")
	var reason: String = DispatchBoardPanel.reason_text(CompanyTrips.FAR_LIMIT, [CompanyTuning.VEHICLES_FAR_MAX])
	_expect(reason != CompanyTrips.FAR_LIMIT and reason.contains("2"), "the reason is translated (got %s)" % reason)
	_expect(panel.status_text() == reason, "the status says why (got %s)" % panel.status_text())
	_expect(panel.confirm() == 0 and (ctx["zone"] as DispatchZone).boxes().size() == 1, "nothing loads")
	trips.track(&"out_x1", Vector3(0, 0, -2))
	panel.refresh(ctx)
	_expect(not panel.load_button().disabled, "one back: Load is on again")
	_expect(panel.confirm() == 1, "and the box loads")
	panel.queue_free()
	await process_frame


func _slots(panel: DispatchBoardPanel) -> String:
	return (panel.find_child("Slots", true, false) as Label).text


func tr_es(key: String) -> String:
	return TranslationServer.translate(key)


func _check_focus_links(panel: DispatchBoardPanel) -> void:
	var controls: Array[Control] = [panel.load_button(), panel.close_button()]
	for child: Node in panel.find_children("Box_*", "Button", true, false):
		controls.append(child as Control)
	for control: Control in controls:
		for path: NodePath in [control.focus_neighbor_top, control.focus_neighbor_bottom]:
			if path.is_empty():
				continue
			var target: Node = control.get_node_or_null(path)
			var live: bool = target is Control and (target as Control).is_inside_tree()
			_expect(live, "focus neighbour of %s resolves" % control.name)
