extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_event_feed.gd
##
## The shed's event feed (expansion D-1935, shed_event_feed.gd), checked on the lines it draws (no screenshot):
## - the events it tells become one line each in the current language: an order in and out of time, units put
##   in a box, a box labeled and sealed (with or without an order), the supplier order, units spoiled and the
##   supplier truck leaving; any other event (and a malformed one) draws nothing;
## - who: the event's `peer` or the hands the units came `from` (hands:<peer>), shown by the player's nickname,
##   "Alguien" when the player has none; events without a who say what happened;
## - the same player putting the same product in a box again adds up on the last line;
## - at most MAX_LINES lines, the oldest goes; a line fades out at the end and goes after LINE_SECONDS;
## - the feed never takes the mouse; add_to() puts it on its own layer and follows CompanyNet.event_applied;
##   CompanyRoot adds it (through CompanyUi);
## - both languages have every key.

const KEYS: Array[String] = [
	"UI_FEED_ORDER_ADDED", "UI_FEED_ORDER_EXPIRED", "UI_FEED_BOX_PLACED", "UI_FEED_BOX_LABELED",
	"UI_FEED_BOX_SEALED", "UI_FEED_BOX_SEALED_BLANK", "UI_FEED_SUPPLIER_ORDERED", "UI_FEED_SPOILED",
	"UI_FEED_TRUCK_LEFT", "UI_FEED_SOMEONE",
]

var _failures: int = 0


class FakeNet:
	extends Node
	signal event_applied(seq: int, kind: StringName, data: Dictionary)


class FakeRoot:
	extends Node
	var net: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	_test_keys()
	await _test_lines()
	await _test_merge_and_limit()
	await _test_add_to()
	_test_root_wiring()
	if _failures == 0:
		print("PASS: the shed's feed says who did what, merges repeats and lets lines go")
	quit(_failures)


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _new_feed() -> ShedEventFeed:
	var feed := ShedEventFeed.new()
	feed.name_of = func(peer: int) -> String: return "Ana" if peer == 7 else ""
	root.add_child(feed)
	await process_frame
	return feed


func _test_lines() -> void:
	var feed: ShedEventFeed = await _new_feed()
	_expect(feed.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the feed lets the mouse through")
	var hen: String = PickingCartPoint.product_name(&"hen")
	var events: Array = [
		[CompanyOrdersNet.ADDED, {"order": {"id": "d1_o04"}}, "Llegó el pedido d1_o04"],
		[CompanyOrdersNet.EXPIRED, {"order": "d1_o02", "minute": 600}, "Se venció el pedido d1_o02"],
		[CompanyTableNet.PLACED, {"product": &"hen", "from": &"hands:7"}, "Ana puso 1 %s en una caja" % hen],
		[CompanyTableNet.LABELED, {"order": &"d1_o04"}, "Caja etiquetada para el pedido d1_o04"],
		[CompanyTableNet.SEALED, {"order": &"d1_o04"}, "Caja cerrada para el pedido d1_o04"],
		[CompanyTableNet.SEALED, {"order": &""}, "Caja cerrada sin pedido"],
		[CompanySupplierNet.ORDERED, {"peer": 3, "lines": [{"qty": 4}, {"qty": 6}]},
			"Alguien le pidió 10 unidades al proveedor"],
		[CompanyColdNet.SPOILED, {"product": &"hen", "qty": 2}, "Se echaron a perder 2 %s" % hen],
		[CompanyPallets.DEPARTED, {}, "Se fue el camión del proveedor"],
	]
	for event: Array in events:
		var line: Dictionary = feed.line_for(event[0], event[1])
		_expect(not line.is_empty() and feed.text_of(line) == event[2],
			"%s reads \"%s\" (got \"%s\")" % [event[0], event[2], feed.text_of(line) if not line.is_empty() else ""])
	for kind: StringName in [&"units_moved", CompanyNet.DAY_PHASE, &"wallet_moved"]:
		_expect(feed.line_for(kind, {"from": &"hands:7"}).is_empty(), "%s is not told" % kind)
	_expect(feed.line_for(CompanyOrdersNet.ADDED, {"order": "broken"}).is_empty(), "an order without id is skipped")
	_expect(feed.line_for(CompanyColdNet.SPOILED, {"product": &"hen", "qty": 0}).is_empty(), "nothing spoiled")
	_expect(feed.line_for(CompanySupplierNet.ORDERED, {"peer": 7, "lines": []}).is_empty(), "an empty order")
	_expect(ShedEventFeed.actor_of({"from": &"hands:12"}) == 12, "the hands name the peer")
	_expect(ShedEventFeed.actor_of({"from": &"shelf:3"}) == 0 and ShedEventFeed.actor_of({"from": &"hands:x"}) == 0,
		"other places and broken hands name nobody")
	_expect(ShedEventFeed.actor_of({"peer": 5, "from": &"hands:7"}) == 5, "the event's peer comes first")
	feed.on_event(1, CompanyOrdersNet.ADDED, {"order": {"id": "d1_o04"}})
	feed.on_event(2, &"units_moved", {})
	_expect(_texts_are(feed, ["Llegó el pedido d1_o04"]), "one line drawn (got %s)" % [feed.texts()])
	var label := feed.find_child("Line_0", true, false) as Label
	_expect(label != null and label.text == "Llegó el pedido d1_o04", "the line is a label in the tree")
	TranslationServer.set_locale("en")
	_expect(_texts_are(feed, ["Order d1_o04 came in"]), "the line follows the language")
	TranslationServer.set_locale("es")
	feed.queue_free()
	await process_frame


func _test_merge_and_limit() -> void:
	var feed: ShedEventFeed = await _new_feed()
	var hen: String = PickingCartPoint.product_name(&"hen")
	for i: int in 3:
		feed.on_event(i, CompanyTableNet.PLACED, {"product": &"hen", "from": &"hands:7"})
	_expect(_texts_are(feed, ["Ana puso 3 %s en una caja" % hen]),
		"three units of hen by Ana are one line (got %s)" % [feed.texts()])
	feed.on_event(4, CompanyTableNet.PLACED, {"product": &"hen", "from": &"hands:9"})
	_expect(feed.texts().size() == 2, "another player starts a new line")
	for i: int in ShedEventFeed.MAX_LINES + 2:
		feed.on_event(10 + i, CompanyOrdersNet.ADDED, {"order": {"id": "o%d" % i}})
	var shown: Array[String] = feed.texts()
	_expect(shown.size() == ShedEventFeed.MAX_LINES, "at most %d lines" % ShedEventFeed.MAX_LINES)
	_expect(shown.back() == "Llegó el pedido o%d" % (ShedEventFeed.MAX_LINES + 1), "the newest is at the bottom")
	var lines: Node = feed.find_child("Lines", true, false)
	await process_frame
	_expect(lines != null and lines.get_child_count() == ShedEventFeed.MAX_LINES, "as many labels as lines")
	feed.set_process(false)
	feed.advance(ShedEventFeed.LINE_SECONDS - ShedEventFeed.FADE_SECONDS / 2.0)
	var first := lines.get_child(0) as CanvasItem
	_expect(first != null and first.modulate.a > 0.4 and first.modulate.a < 0.6, "a line fades out at the end")
	feed.on_event(30, CompanyPallets.DEPARTED, {})
	feed.advance(ShedEventFeed.FADE_SECONDS)
	_expect(_texts_are(feed, ["Se fue el camión del proveedor"]),
		"old lines go, the fresh one stays (got %s)" % [feed.texts()])
	feed.advance(ShedEventFeed.LINE_SECONDS)
	_expect(feed.texts().is_empty(), "every line goes in the end")
	feed.queue_free()
	await process_frame


func _test_add_to() -> void:
	var fake_root := FakeRoot.new()
	var net := FakeNet.new()
	fake_root.net = net
	fake_root.add_child(net)
	root.add_child(fake_root)
	var feed: ShedEventFeed = ShedEventFeed.add_to(fake_root)
	await process_frame
	_expect(feed.get_parent() is CanvasLayer, "the feed has its own layer")
	net.event_applied.emit(1, CompanyOrdersNet.EXPIRED, {"order": "d2_o01"})
	_expect(_texts_are(feed, ["Se venció el pedido d2_o01"]), "it follows the net's events")
	var nameless: Dictionary = {"kind": CompanyTableNet.PLACED, "actor": 4, "subject": "hen", "qty": 1}
	_expect(feed.text_of(nameless).begins_with("Alguien"),
		"a peer with no player in the world is Alguien")
	fake_root.queue_free()
	await process_frame


func _test_root_wiring() -> void:
	var root_source: String = FileAccess.get_file_as_string("res://scripts/gameplay/company_root.gd")
	var ui_source: String = FileAccess.get_file_as_string("res://scripts/ui/company_ui.gd")
	_expect(root_source.contains("CompanyUi.add_to(self)") and ui_source.contains("ShedEventFeed.add_to(root)"),
		"CompanyRoot adds the feed (through CompanyUi)")


func _texts_are(feed: ShedEventFeed, expected: Array) -> bool:
	return Array(feed.texts()) == expected


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
