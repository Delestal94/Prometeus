extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_indicators.gd
##
## The arrows over the shed's stations (expansion D-1907), checked on their nodes (no screenshot):
## - a packing table low on a supply (tape, filler, a box size) gets an orange arrow "Faltan insumos" over its
##   spot; restocked, the arrow goes;
## - a dispatch zone gets a red "N atrasados" arrow while open orders are past their due_min, and none otherwise;
## - storage pieces and tables with everything get nothing; one arrow per piece, billboard, at HEIGHT_M;
## - in the real company world (CompanyRoot) the indicators hang under the shed, in its overlay group (a redraw
##   keeps them), and a table emptied of tape gets its arrow;
## - both languages have the keys.

## The world saves here, never in the game's slot.
const DIR: String = "user://test_shed_indicators"
const KEYS: Array[String] =["WORLD_INDICATOR_SUPPLIES", "WORLD_INDICATOR_LATE"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")
	await _test_needs()
	await _test_world()
	if _failures == 0:
		print("PASS: an arrow stands over the table short of supplies and the dispatch zone with late orders")
	quit(_failures)


func _test_needs() -> void:
	var full := PackingStation.make(&"t1")
	var short := PackingStation.make(&"t2")
	short.supplies.stock[StationSupplies.TAPE] = 0
	var stations: Dictionary = {&"t1": full, &"t2": short}
	var orders: Array = [{"due_min": 900}]
	var minute: Array[float] = [600.0]
	var roles: Dictionary = {&"table": &"assembly", &"zone": &"dispatch", &"rack": &"storage"}
	var marks := ShedIndicators.new()
	marks.pieces_of = func() -> Array: return [
		{"uid": &"t1", "id": &"table"}, {"uid": &"t2", "id": &"table"}, {"uid": &"d1", "id": &"zone"},
		{"uid": &"s1", "id": &"rack"}, "broken",
	]
	marks.stations_of = func() -> Dictionary: return stations
	marks.role_of = func(id: StringName) -> StringName: return roles.get(id, &"")
	marks.spot_of = func(uid: StringName) -> Vector3: return Vector3(3.0, 0.0, -2.0) if uid == &"t2" else Vector3.ZERO
	marks.orders_of = func() -> Array: return orders
	marks.minute_of = func() -> float: return minute[0]
	root.add_child(marks)
	await process_frame
	marks.set_process(false)
	marks.refresh()
	_expect(marks.shown().keys() == [&"t2"], "only the table short of tape (got %s)" % [marks.shown()])
	var arrow := marks.get_node_or_null(^"Need_t2") as Label3D
	_expect(arrow != null and arrow.text == "Faltan insumos\n" + ShedIndicators.ARROW, "its line and arrow")
	_expect(arrow != null and arrow.modulate == UiTheme.ORANGE and arrow.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"orange, facing the camera")
	_expect(arrow != null and arrow.position.is_equal_approx(Vector3(3.0, ShedIndicators.HEIGHT_M, -2.0)),
		"over the table's spot")
	minute[0] = 950.0
	marks.refresh()
	_expect(marks.shown().get(&"d1", "") == "1 atrasados\n" + ShedIndicators.ARROW, "a late order: the dispatch zone")
	_expect((marks.get_node(^"Need_d1") as Label3D).modulate == UiTheme.RED, "late is red")
	short.supplies.restock_all()
	minute[0] = 600.0
	marks.refresh()
	await process_frame
	_expect(marks.shown().is_empty(), "restocked and in time: no arrow (got %s)" % [marks.shown()])
	_expect(marks.get_child_count() == 0, "the arrows are freed")
	marks.queue_free()
	await process_frame


func _test_world() -> void:
	var state: Node = root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"reset")
	var world := (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate() as CompanyRoot
	world.save_dir = DIR
	root.add_child(world)
	for i: int in 4:
		await process_frame
	var shed: CompanyShed = world.get(&"shed")
	var marks := shed.get_node_or_null(^"ShedIndicators") as ShedIndicators if shed != null else null
	_expect(marks != null and marks.is_in_group(CompanyShed.OVERLAY_GROUP), "the arrows hang under the shed")
	if marks != null and not shed.stations.is_empty():
		var uid: StringName = shed.stations.keys()[0]
		(shed.stations[uid] as PackingStation).supplies.stock[StationSupplies.TAPE] = 0
		marks.refresh()
		_expect(marks.shown().has(uid), "a real table out of tape gets its arrow (got %s)" % [marks.shown()])
	else:
		_expect(false, "the shed has its packing tables")
	world.queue_free()
	await process_frame
	if state != null:
		state.call(&"reset")
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
