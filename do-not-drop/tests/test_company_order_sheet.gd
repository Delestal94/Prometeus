extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_order_sheet.gd
##
## The order sheet on a packing table (expansion D-0714, order_sheet.gd + order_sheet_panel.gd):
## - OrderSheet.build() names the customer and the address of the order, and lists each item with
##   how many units the box holds; an empty table shows every item pending, no tape, no label;
## - a short unit, an extra unit of a listed product and a product the order never asked for all
##   show as not ok; extras of unlisted products are listed apart;
## - the seals the requirements ask for are listed with done / pending, and `ready` turns true
##   only with the right content, every seal, tape and this order's label;
## - minutes_left counts down to due_min and goes negative (late) after it;
## - an empty order or a null box does not crash; PackingStation.sheet_for is the same sheet;
## - OrderSheetPanel draws the sheet from the dictionary alone, with a mark in front of each
##   line (not only colour), the late time in red, and "no order" for an empty sheet;
## - both languages have every key the sheet uses, requirement names included.

const KEYS: Array[String] = [
	"UI_ORDER_SHEET_TITLE", "UI_ORDER_SHEET_EMPTY", "UI_ORDER_SHEET_FOR", "UI_ORDER_SHEET_ADDRESS",
	"UI_ORDER_SHEET_ITEM", "UI_ORDER_SHEET_EXTRA", "UI_ORDER_SHEET_SEAL", "UI_ORDER_SHEET_TAPE",
	"UI_ORDER_SHEET_LABEL", "UI_ORDER_SHEET_LEFT", "UI_ORDER_SHEET_LATE", "UI_ORDER_SHEET_PAY",
	"UI_ORDER_SHEET_READY", "UI_ORDER_SHEET_NOT_READY", "WORLD_REQ_FRAGILE", "WORLD_REQ_COLD",
	"WORLD_REQ_GIFT", "WORLD_REQ_URGENT", "WORLD_REQ_HEAVY", "WORLD_REQ_NO_BEND",
]

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	_products = {&"mug": _product(&"mug"), &"book": _product(&"book"), &"lamp": _product(&"lamp")}
	_test_content()
	_test_seals_and_ready()
	_test_time_and_edges()
	await _test_panel()
	if _failures == 0:
		print("PASS: the order sheet shows the order, the box and what is left")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = Vector3i(1, 1, 1)
	p.buy_price = 20
	return p


func _order(requirements: Array[StringName] = []) -> Dictionary:
	return Order.make(
		&"o1", "Clara", &"centro", &"centro_house_7",
		[{"product": &"mug", "qty": 2}, {"product": &"book", "qty": 1}],
		0, _products, requirements,
	)


func _box_with(ids: Array) -> PackedBox:
	var box := PackedBox.new(&"M")
	for id: StringName in ids:
		var p: ProductDefinition = _products[id]
		var spot: Vector3i = box.first_fit(p)
		if spot == PackedBox.NO_SPOT or not box.place(p, spot):
			_expect(false, "setup could not place %s" % id)
	return box


func _item(sheet: Dictionary, id: StringName) -> Dictionary:
	for item: Dictionary in sheet["items"]:
		if item["product"] == id:
			return item
	return {}


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _test_content() -> void:
	var order: Dictionary = _order()
	var empty: Dictionary = OrderSheet.build(order, PackedBox.new(&"M"), 10, _products)
	_expect(empty["customer"] == "Clara" and empty["order"] == &"o1", "customer and id")
	_expect(empty["address"]["number"] == 7 and empty["address"]["street_key"] == &"WORLD_STREET_CENTRO",
			"the address is the label's: street and number 7")
	_expect(empty["items"].size() == 2, "one line per product")
	_expect(_item(empty, &"mug")["qty"] == 2 and _item(empty, &"mug")["packed"] == 0, "mug asks 2, holds 0")
	_expect(not _item(empty, &"mug")["ok"], "an empty box is not ok on any line")
	_expect(not empty["taped"] and not empty["labeled"] and not empty["ready"], "empty: no tape, no label, not ready")
	_expect(empty["pay"] == int(order["pay"]), "the pay is the order's")
	var short: Dictionary = OrderSheet.build(order, _box_with([&"mug", &"book"]), 10, _products)
	_expect(_item(short, &"mug")["packed"] == 1 and not _item(short, &"mug")["ok"], "one mug short")
	_expect(_item(short, &"book")["ok"], "the book is complete")
	var crowded: PackedBox = _box_with([&"mug", &"mug", &"mug", &"book", &"lamp"])
	var over: Dictionary = OrderSheet.build(order, crowded, 10, _products)
	_expect(not _item(over, &"mug")["ok"] and _item(over, &"mug")["packed"] == 3, "a third mug is not ok")
	_expect(over["extra"].size() == 2, "extra: the third mug and the lamp: %s" % [over["extra"]])
	var fine: Dictionary = OrderSheet.build(order, _box_with([&"mug", &"mug", &"book"]), 10, _products)
	var all_ok: bool = _item(fine, &"mug")["ok"] and _item(fine, &"book")["ok"]
	_expect(all_ok and fine["extra"].is_empty(), "exact content is ok")
	_expect(OrderSheet.product_name(&"ghost", _products) == "ghost", "an unknown product shows its id")


func _test_seals_and_ready() -> void:
	var order: Dictionary = _order([&"fragile"])
	var box: PackedBox = _box_with([&"mug", &"mug", &"book"])
	var sheet: Dictionary = OrderSheet.build(order, box, 10, _products)
	_expect(sheet["requirements"].size() == 1 and sheet["requirements"][0]["key"] == "WORLD_REQ_FRAGILE",
			"the requirement carries its name key")
	var seals: Array = sheet["requirements"][0]["seals"]
	_expect(seals.size() == 1 and seals[0]["kind"] == &"fragile" and not seals[0]["done"], "fragile seal pending")
	box.stamps.append(&"fragile")
	_expect(not OrderSheet.build(order, box, 10, _products)["ready"], "seal alone: no tape and no label yet")
	box.taped = true
	_expect(not OrderSheet.build(order, box, 10, _products)["ready"], "tape alone is not ready: no label")
	box.label_order_id = &"o1"
	var ready: Dictionary = OrderSheet.build(order, box, 10, _products)
	_expect(ready["requirements"][0]["seals"][0]["done"], "the seal shows done once stamped")
	_expect(ready["taped"] and ready["labeled"] and ready["ready"], "content, seal, tape and label: ready")
	box.label_order_id = &"other"
	_expect(not OrderSheet.build(order, box, 10, _products)["labeled"], "another order's label does not count")
	box.label_order_id = &"o1"
	box.stamps.clear()
	_expect(not OrderSheet.build(order, box, 10, _products)["ready"], "losing the seal makes it not ready")
	var odd: Dictionary = _order([&"made_up"])
	var odd_sheet: Dictionary = OrderSheet.build(odd, box, 10, _products)
	_expect(odd_sheet["requirements"][0]["seals"].is_empty() and odd_sheet["requirements"][0]["key"] == "",
			"an unknown requirement is listed without seals or name")


func _test_time_and_edges() -> void:
	var order: Dictionary = _order()
	var due: int = int(order["due_min"])
	_expect(OrderSheet.build(order, null, due - 30, _products)["minutes_left"] == 30, "30 minutes left")
	_expect(not OrderSheet.build(order, null, due, _products)["late"], "due exactly now is not late")
	var late: Dictionary = OrderSheet.build(order, null, due + 12, _products)
	_expect(late["late"] and late["minutes_left"] == -12, "12 minutes late")
	_expect(OrderSheet.build({}, PackedBox.new(&"S"), 0).is_empty(), "no order: an empty sheet")
	var no_box: Dictionary = OrderSheet.build(order, null, 0, _products)
	var nothing: bool = not no_box["ready"] and not no_box["taped"]
	_expect(nothing and _item(no_box, &"mug")["packed"] == 0, "no box: nothing done")
	var table: PackingStation = PackingStation.make(&"t1")
	table.start_box(&"M")
	_expect(table.sheet_for(order, 5, _products) == OrderSheet.build(order, table.box, 5, _products),
			"the table gives the same sheet")


func _test_panel() -> void:
	var panel: Control = (load("res://scripts/ui/order_sheet_panel.gd") as GDScript).new()
	root.add_child(panel)
	await process_frame
	_expect(_find(panel, "Empty") != null, "an empty sheet says there is no order")
	var order: Dictionary = _order([&"fragile"])
	var box: PackedBox = _box_with([&"mug", &"book", &"lamp"])
	box.stamps.append(&"fragile")
	panel.refresh(OrderSheet.build(order, box, int(order["due_min"]) + 5, _products))
	await process_frame
	_expect(_find(panel, "Empty") == null, "a real sheet replaces the empty text")
	_expect(_text(panel, "Customer") == "Para Clara", "customer line: %s" % _text(panel, "Customer"))
	_expect(_text(panel, "Address") == "Calle Central 7", "address line: %s" % _text(panel, "Address"))
	_expect(_text(panel, "Item_mug") == "○  mug  1/2", "a pending line is marked ○: %s" % _text(panel, "Item_mug"))
	_expect(_text(panel, "Item_book") == "✓  book  1/1", "a done line is marked ✓")
	var lamp: String = _text(panel, "Extra_lamp")
	_expect(lamp.begins_with("✗"), "an extra product is marked ✗: %s" % lamp)
	_expect(_text(panel, "Seal_fragile") == "✓  Sello: Frágil", "stamped seal: %s" % _text(panel, "Seal_fragile"))
	_expect(_text(panel, "Tape").begins_with("○") and _text(panel, "Label").begins_with("○"), "tape and label pending")
	_expect(_text(panel, "Time") == "Atrasado 5 min", "late time: %s" % _text(panel, "Time"))
	_expect((_find(panel, "Time") as Label).get_theme_color(&"font_color") == UiTheme.RED, "late time is red")
	_expect(_text(panel, "Verdict") == "○  Falta completar", "not finished: %s" % _text(panel, "Verdict"))
	box.stamps.clear()
	var full: PackedBox = _box_with([&"mug", &"mug", &"book"])
	full.stamps.append(&"fragile")
	full.taped = true
	full.label_order_id = &"o1"
	panel.refresh(OrderSheet.build(order, full, 0, _products))
	await process_frame
	_expect(_text(panel, "Verdict") == "✓  Lista para despachar", "ready: %s" % _text(panel, "Verdict"))
	_expect(_text(panel, "Time") == "Quedan %d min" % int(order["due_min"]), "time left")
	TranslationServer.set_locale("en")
	panel.refresh(OrderSheet.build(order, full, 0, _products))
	await process_frame
	_expect(_text(panel, "Verdict") == "✓  Ready to dispatch", "English verdict: %s" % _text(panel, "Verdict"))
	TranslationServer.set_locale("es")
	panel.queue_free()


func _find(parent: Node, node_name: String) -> Node:
	var found: Array[Node] = parent.find_children(node_name, "", true, false)
	return found[0] if not found.is_empty() else null


func _text(parent: Node, node_name: String) -> String:
	var node: Node = _find(parent, node_name)
	return (node as Label).text if node != null else "<missing %s>" % node_name
