extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_stock_panel.gd
##
## The stock list of the clipboard (expansion D-0612), driven by injected data only:
## - StockView (stock_view.gd) buckets locations by prefix (shelf: shelves, pallet: and dock
##   reception, hands:, box:, anything else other), adds the totals, sorts by product id, lists a
##   product that is only in the shortages (0 units) flagged, and tells a covered shortage (a
##   supplier order closes the gap) from a missing one; a product that is not short has the
##   short fields at their defaults;
## - StockPanel (stock_panel.gd) shows one row per product with its numbers, a text mark besides
##   colour on short products ("⚠" missing, "⟳" on the way), refresh() after a move changes the
##   numbers, an empty inventory says so and focuses Close;
## - a list longer than the panel opens at the top, with the first row in view;
## - the focus starts on the first row, ui_down reaches Close, every focus neighbour points at a
##   live node and ui_cancel closes the panel;
## - both languages have every UI_STOCK_ key the panel uses.

const KEYS: Array[String] = [
	"UI_STOCK_TITLE", "UI_STOCK_HINT", "UI_STOCK_EMPTY", "UI_STOCK_ROW", "UI_STOCK_ROW_MORE",
	"UI_STOCK_SHORT", "UI_STOCK_SHORT_COMING", "UI_STOCK_COVERED", "UI_STOCK_TOTALS", "UI_STOCK_CLOSE",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	_test_view_buckets()
	_test_view_shortages()
	await _test_panel_rows()
	await _test_panel_refresh_and_focus()
	await _test_panel_empty()
	await _test_panel_long_list_at_top()
	if _failures == 0:
		print("PASS: stock list buckets units by place, flags short products and the panel follows moves")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _inventory() -> Inventory:
	var inv := Inventory.new()
	inv.receive(&"hen", 3, &"shelf:a")
	inv.receive(&"hen", 2, &"shelf:b")
	inv.receive(&"hen", 4, &"pallet:p1")
	inv.receive(&"hen", 1, &"dock")
	inv.receive(&"hen", 1, &"hands:1")
	inv.receive(&"hen", 5, &"box:b1")
	inv.receive(&"hen", 2, &"cart:c1")
	inv.receive(&"hen", 1, &"floor:x")
	inv.receive(&"brick", 6, &"shelf:c")
	return inv


func _row_of(list: Array[Dictionary], product: StringName) -> Dictionary:
	for row: Dictionary in list:
		if row["product"] == product:
			return row
	return {}


func _shortage(product: StringName, missing: int, incoming: int, covered: bool) -> Dictionary:
	return {
		"product": product, "needed": 10, "have": 2, "incoming": incoming, "missing": missing,
		"due_min": 30, "covered": covered,
	}


func _test_keys() -> void:
	var rows: Dictionary = {}
	var file := FileAccess.open("res://translations/strings_ui.csv", FileAccess.READ)
	while not file.eof_reached():
		var cols: PackedStringArray = file.get_csv_line()
		if cols.size() >= 3:
			rows[cols[0]] = cols
	for key: String in KEYS:
		var both: bool = rows.has(key) and rows[key][1] != "" and rows[key][2] != ""
		_expect(both, "translation row with both languages: " + key)


func _test_view_buckets() -> void:
	var list: Array[Dictionary] = StockView.rows(_inventory())
	_expect(list.size() == 2, "two products listed (got %d)" % list.size())
	_expect(list[0]["product"] == &"brick" and list[1]["product"] == &"hen", "sorted by product id (got %s)" % [list])
	var hen: Dictionary = _row_of(list, &"hen")
	_expect(hen["shelves"] == 5, "shelf: units add up (got %s)" % [hen])
	_expect(hen["reception"] == 5, "pallet: and dock count as reception (got %s)" % [hen])
	_expect(hen["hands"] == 1, "hands: bucket (got %s)" % [hen])
	_expect(hen["boxes"] == 5, "box: bucket (got %s)" % [hen])
	_expect(hen["other"] == 3, "cart: and floor: are other (got %s)" % [hen])
	_expect(hen["total"] == 19, "total is every unit (got %s)" % [hen])
	var calm: bool = hen["missing"] == 0 and hen["incoming"] == 0 and not hen["covered"]
	_expect(not hen["short"] and calm, "not short: defaults")
	var totals: Dictionary = StockView.totals(list)
	_expect(totals["products"] == 2 and totals["units"] == 25 and totals["short"] == 0, "totals (got %s)" % [totals])
	_expect(StockView.rows(Inventory.new()).is_empty(), "empty inventory, no rows")


func _test_view_shortages() -> void:
	var shortages: Array = [
		_shortage(&"hen", 4, 0, false), _shortage(&"glue", 8, 0, false), _shortage(&"tape", 0, 10, true),
	]
	var list: Array[Dictionary] = StockView.rows(_inventory(), shortages)
	_expect(list.size() == 4, "a shortage-only product is listed (got %d)" % list.size())
	_expect(list.map(func(r: Dictionary) -> StringName: return r["product"]) == [&"brick", &"glue", &"hen", &"tape"],
		"sorted with the shortage-only ones in place")
	var glue: Dictionary = _row_of(list, &"glue")
	var flagged: bool = glue["total"] == 0 and glue["short"] and glue["missing"] == 8
	_expect(flagged, "glue has 0 units and is flagged (got %s)" % [glue])
	var tape: Dictionary = _row_of(list, &"tape")
	var covered: bool = tape["short"] and tape["covered"] and tape["missing"] == 0 and tape["incoming"] == 10
	_expect(covered, "covered (got %s)" % [tape])
	_expect(_row_of(list, &"hen")["short"] and not _row_of(list, &"hen")["covered"], "missing is not covered")
	_expect(not _row_of(list, &"brick")["short"], "a product not in the shortages is not flagged")
	var totals: Dictionary = StockView.totals(list)
	_expect(totals["short"] == 3 and totals["products"] == 4, "totals count the short ones (got %s)" % [totals])


func _panel(ctx: Dictionary) -> StockPanel:
	var panel := StockPanel.new()
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
	var holder: Control = root.gui_get_focus_owner()
	return String(holder.name) if holder != null else ""


func _test_panel_rows() -> void:
	var shortages: Array = [
		_shortage(&"hen", 4, 0, false), _shortage(&"glue", 8, 3, false), _shortage(&"tape", 0, 10, true),
	]
	var ctx: Dictionary = {"inventory": _inventory(), "shortages": shortages}
	var panel: StockPanel = await _panel(ctx)
	_expect(panel.row_count() == 4, "one row per product (got %d)" % panel.row_count())
	_expect(panel.products() == [&"brick", &"glue", &"hen", &"tape"], "rows in id order (got %s)" % [panel.products()])
	var brick: String = panel.row_text(&"brick")
	_expect(brick == tr("UI_STOCK_ROW") % ["brick", 6, 0, 6], "brick row shows its numbers (got %s)" % brick)
	_expect(not brick.contains("⚠") and not brick.contains("⟳"), "a product that is not short has no mark")
	var hen: String = panel.row_text(&"hen")
	_expect(hen.contains(tr("UI_STOCK_SHORT") % 4), "short row has the missing mark (got %s)" % hen)
	_expect(hen.contains("⚠"), "the mark is a symbol, not only colour")
	_expect(hen.contains(tr("UI_STOCK_ROW_MORE") % [1, 5, 3]), "hen row lists hands, boxes and other (got %s)" % hen)
	_expect(panel.row_text(&"glue").contains(tr("UI_STOCK_SHORT_COMING") % [8, 3]), "partial cover says what is coming")
	_expect(panel.row_text(&"glue").contains(tr("UI_STOCK_ROW") % ["glue", 0, 0, 0]), "a shortage-only row shows zeros")
	var tape: String = panel.row_text(&"tape")
	var on_way: bool = tape.contains(tr("UI_STOCK_COVERED") % 10) and tape.contains("⟳")
	_expect(on_way, "covered row says it is on the way (got %s)" % tape)
	_expect(not tape.contains("⚠"), "covered is not shown as missing")
	_expect(panel.totals_text() == tr("UI_STOCK_TOTALS") % [25, 4], "totals line (got %s)" % panel.totals_text())
	panel.queue_free()
	await process_frame


func _test_panel_refresh_and_focus() -> void:
	var inv: Inventory = _inventory()
	var ctx: Dictionary = {"inventory": inv, "shortages": []}
	var panel: StockPanel = await _panel(ctx)
	_expect(_focus_name() == "Row_brick", "focus starts on the first row (got %s)" % _focus_name())
	_expect(panel.row_text(&"brick").contains(tr("UI_STOCK_ROW") % ["brick", 6, 0, 6]), "before the move")
	inv.move(&"brick", 4, &"shelf:c", &"hands:1")
	inv.receive(&"nails", 2, &"pallet:p2")
	panel.refresh(ctx)
	await process_frame
	await process_frame
	var brick: String = panel.row_text(&"brick")
	_expect(brick.contains(tr("UI_STOCK_ROW") % ["brick", 2, 0, 6]), "refresh shows the shelf units (got %s)" % brick)
	_expect(brick.contains(tr("UI_STOCK_ROW_MORE") % [4, 0, 0]), "and the ones in hands (got %s)" % brick)
	_expect(panel.row_count() == 3 and panel.row_text(&"nails") != "", "a new product appears on refresh")
	_expect(_focus_name() == "Row_brick", "focus stays on the same product (got %s)" % _focus_name())
	for i: int in 3:
		await _press(&"ui_down")
	_expect(_focus_name() == "Close", "ui_down reaches Close (got %s)" % _focus_name())
	await _press(&"ui_up")
	_expect(_focus_name() == "Row_nails", "ui_up goes back up the column (got %s)" % _focus_name())
	_check_focus_links(panel)
	await _press(&"ui_cancel")
	_expect(not panel.visible, "ui_cancel closes the panel")
	panel.queue_free()
	await process_frame


func _test_panel_empty() -> void:
	var panel: StockPanel = await _panel({"inventory": Inventory.new()})
	_expect(panel.row_count() == 0, "no rows with no stock")
	var empty: Label = panel.find_child("Empty", true, false)
	_expect(empty != null and empty.text == tr("UI_STOCK_EMPTY"), "empty inventory says so")
	_expect(_focus_name() == "Close", "empty panel focuses Close (got %s)" % _focus_name())
	_check_focus_links(panel)
	var closed: Array = []
	panel.closed.connect(func() -> void: closed.append(true))
	panel.close_button().pressed.emit()
	_expect(not panel.visible and closed.size() == 1, "Close hides the panel and emits closed")
	panel.queue_free()
	await process_frame


func _test_panel_long_list_at_top() -> void:
	var inv := Inventory.new()
	for i: int in 14:
		inv.receive(StringName("p%02d" % i), 3, &"shelf:a")
	inv.receive(&"p00", 2, &"hands:1")
	# Opened a frame after it entered the tree, as StockBoard does: opened in the same frame the list
	# never scrolled, so _panel() would not show the bug.
	var panel := StockPanel.new()
	root.add_child(panel)
	await process_frame
	panel.open({"inventory": inv, "shortages": [_shortage(&"p01", 4, 0, false)]})
	for _i: int in 5:
		await process_frame
	var scroll: ScrollContainer = panel.list_scroll()
	var bar_max: float = scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page
	_expect(bar_max > 0.0, "14 products do not fit in the panel (scroll room %.0f)" % bar_max)
	_expect(scroll.scroll_vertical == 0, "a long list opens at the top (got %d)" % scroll.scroll_vertical)
	_expect(_focus_name() == "Row_p00", "with the first row focused (got %s)" % _focus_name())
	panel.queue_free()
	await process_frame


func _check_focus_links(panel: StockPanel) -> void:
	var controls: Array[Control] = [panel.close_button()]
	for child: Node in panel.find_children("Row_*", "Button", true, false):
		controls.append(child as Control)
	for control: Control in controls:
		for path: NodePath in [control.focus_neighbor_top, control.focus_neighbor_bottom]:
			if path.is_empty():
				continue
			var target: Node = control.get_node_or_null(path)
			var live: bool = target is Control and (target as Control).is_inside_tree()
			_expect(live, "focus neighbour of %s resolves" % control.name)
