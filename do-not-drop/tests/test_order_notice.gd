extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_notice.gd
##
## The phone notice for new orders (expansion D-0814, order_notice.gd + order_notice_feed.gd):
## - one order says its customer and address, in Spanish and in English;
## - several orders at once collapse into one line with the count;
## - an order with the urgent requirement rings with the higher priority;
## - no orders (or entries without an id) give no notice;
## - OrderNoticeFeed turns a burst of order_added in one frame into a single notice, a later
##   order into another one, and stops after watch(null);
## - both languages have every key the notice uses.

const KEYS: Array[String] = [
	"UI_ORDER_NOTICE_ONE", "UI_ORDER_NOTICE_ONE_NO_ADDRESS", "UI_ORDER_NOTICE_MANY",
]

var _failures: int = 0
var _products: Dictionary = {}
var _heard: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("es")
	var mug := ProductDefinition.new()
	mug.id = &"mug"
	mug.cells = Vector3i(1, 1, 1)
	mug.buy_price = 20
	_products = {&"mug": mug}
	_test_keys()
	_test_message()
	await _test_feed()
	if _failures == 0:
		print("PASS: new orders ring the phone once per burst")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _order(id: StringName, requirements: Array[StringName] = []) -> Dictionary:
	return Order.make(
		id, "Clara", &"centro", &"centro_house_7", [{"product": &"mug", "qty": 1}],
		0, _products, requirements,
	)


func _test_keys() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			_expect(TranslationServer.translate(key) != key, "%s has %s" % [locale, key])
	TranslationServer.set_locale("es")


func _test_message() -> void:
	var one: Dictionary = OrderNotice.message([_order(&"a")])
	_expect(one["text"] == "Pedido nuevo: Clara — Calle Central 7", "one order: %s" % one["text"])
	_expect(one["priority"] == OrderNotice.PRIORITY_NORMAL, "plain order is normal priority")
	var nowhere: Dictionary = _order(&"b")
	nowhere["house_id"] = &"nowhere"
	_expect(OrderNotice.message([nowhere])["text"] == "Pedido nuevo: Clara", "no address: name only")
	var many: Dictionary = OrderNotice.message([_order(&"a"), _order(&"b"), _order(&"c")])
	_expect(many["text"] == "3 pedidos nuevos", "burst: %s" % many["text"])
	var urgent: Array[StringName] = [&"urgent"]
	_expect(
		OrderNotice.message([_order(&"a"), _order(&"u", urgent)])["priority"] == OrderNotice.PRIORITY_URGENT,
		"an urgent order raises the priority"
	)
	_expect(OrderNotice.message([]).is_empty(), "no orders, no notice")
	_expect(OrderNotice.message([{"customer": "x"}]).is_empty(), "entry without id ignored")
	TranslationServer.set_locale("en")
	_expect(
		OrderNotice.message([_order(&"a")])["text"] == "New order: Clara — Central Street 7",
		"English: %s" % OrderNotice.message([_order(&"a")])["text"]
	)
	TranslationServer.set_locale("es")


func _on_notice(text: String, priority: int) -> void:
	_heard.append({"text": text, "priority": priority})


func _test_feed() -> void:
	var book := OrderBook.new()
	root.add_child(book)
	var feed := OrderNoticeFeed.new()
	root.add_child(feed)
	feed.notice.connect(_on_notice)
	feed.watch(book)
	book.add(_order(&"a"))
	book.add(_order(&"b"))
	await process_frame
	_expect(_heard.size() == 1, "two orders in a frame: one notice (%d)" % _heard.size())
	_expect(_heard[0]["text"] == "2 pedidos nuevos", "burst text: %s" % _heard[0]["text"])
	book.add(_order(&"c"))
	await process_frame
	_expect(_heard.size() == 2 and _heard[1]["text"].begins_with("Pedido nuevo: Clara"), "later order rings again")
	feed.watch(null)
	book.add(_order(&"d"))
	await process_frame
	_expect(_heard.size() == 2, "a feed that watches nothing stays quiet")
	feed.queue_free()
	book.queue_free()
