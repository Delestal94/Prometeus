extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_rating.gd
##
## The customer's rating of a delivery (expansion D-0816, order_rating.gd), from the result of
## OrderSettlement.settle:
## - one case per star: clean and quick (tip) = 5, clean and slow = 4, late or mislabeled alone = 3,
##   a broken product = 2, a wrong box = 1;
## - with several failures the worst one decides, whatever the order they are listed in;
## - a result that is not ok (open order, unknown order, settled twice) rates 0;
## - rating changes no state: not the wallet, the reputation, the ledger nor the book, and the
##   result passed in stays as it was;
## - settle() reports the same stars, and the numbers come from CompanyTuning;
## - the labels exist in both languages for 1 to 5, and none for 0 or 6.

const KEYS: Array[String] = [
	"UI_ORDER_STARS_1", "UI_ORDER_STARS_2", "UI_ORDER_STARS_3", "UI_ORDER_STARS_4", "UI_ORDER_STARS_5",
]

var _failures: int = 0
var _products: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var def := ProductDefinition.new()
	def.id = &"avg"
	def.buy_price = 50
	def.cells = Vector3i(1, 1, 1)
	_products[&"avg"] = def
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_each_star()
	_test_combinations()
	_test_not_ok()
	_test_settle(state)
	_test_no_side_effects(state)
	_test_labels()
	state.reset()
	if _failures == 0:
		print("PASS: the customer rates a delivery from 1 to 5 stars")
	quit(_failures)


func _result(kinds: Array, tip: int = 0, ok: bool = true) -> Dictionary:
	var typed: Array[StringName] = []
	for kind: Variant in kinds:
		typed.append(StringName(kind))
	return {"ok": ok, "paid": 200, "tip": tip, "reputation": 0.0, "kinds": typed, "lost": 0}


func _test_each_star() -> void:
	_expect(OrderRating.stars(_result([], 30)) == 5, "clean and quick (tip) is 5 stars")
	_expect(OrderRating.stars(_result([], 0)) == 4, "clean but slow (no tip) is 4 stars")
	_expect(OrderRating.stars(_result([&"late"])) == 3, "late alone is 3 stars")
	_expect(OrderRating.stars(_result([&"mislabeled"])) == 3, "a label of another order alone is 3 stars")
	_expect(OrderRating.stars(_result([&"broken"])) == 2, "a broken product is 2 stars")
	_expect(OrderRating.stars(_result([&"wrong"])) == 1, "a wrong box is 1 star")
	_expect(
		CompanyTuning.STARS_MAX == 5 and CompanyTuning.STARS_MIN == 1, "the scale is 1 to 5 in the tuning"
	)


func _test_combinations() -> void:
	_expect(OrderRating.stars(_result([&"late", &"mislabeled"])) == 3, "late plus mislabeled: the worst, 3")
	_expect(OrderRating.stars(_result([&"broken", &"late"])) == 2, "broken plus late: 2")
	_expect(OrderRating.stars(_result([&"late", &"broken"])) == 2, "the order of the kinds does not matter")
	_expect(OrderRating.stars(_result([&"broken", &"mislabeled"])) == 2, "broken plus mislabeled: 2")
	_expect(OrderRating.stars(_result([&"wrong", &"late"])) == 1, "wrong plus late: 1")
	_expect(OrderRating.stars(_result([&"late", &"mislabeled", &"wrong"])) == 1, "three failures: 1")
	_expect(
		OrderRating.stars(_result([&"wrong", &"broken", &"late", &"mislabeled"])) == 1,
		"all four failures: 1"
	)
	_expect(OrderRating.stars(_result([&"late"], 30)) == 3, "a failure outweighs a tip left in the result")
	_expect(OrderRating.stars(_result([&"abandoned"])) == 1, "an unknown kind counts as the worst")
	for stars: int in [OrderRating.stars(_result([], 5)), OrderRating.stars(_result([&"x", &"late"]))]:
		_expect(stars >= 1 and stars <= 5, "always inside 1 to 5")


func _test_not_ok() -> void:
	_expect(OrderRating.stars(_result([], 30, false)) == 0, "not ok rates 0, even if it looks perfect")
	_expect(OrderRating.stars(_result([&"wrong"], 0, false)) == 0, "not ok with failures rates 0")
	_expect(OrderRating.stars({}) == 0, "an empty result rates 0")
	_expect(OrderRating.stars({"kinds": []}) == 0, "a result without ok rates 0")


func _book_out() -> OrderBook:
	var book := OrderBook.new()
	book.add(Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 60, _products))
	book.mark_packed(&"o1", &"box1")
	book.mark_out(&"o1", &"trip1")
	return book


func _box(units: int, label: StringName = &"o1") -> PackedBox:
	var box := PackedBox.new(&"M")
	for i in units:
		box.place(_products[&"avg"], Vector3i(i, 0, 0))
	box.label_order_id = label
	return box


func _test_settle(state: Node) -> void:
	state.new_company("Rating Co")
	# The order is out from minute 60 (window 60 to 300); quick is within the first half of it.
	var cases: Array[Dictionary] = [
		{"name": "quick and perfect", "box": _box(2), "now": 70, "broken": [], "stars": 5},
		{"name": "slow and perfect", "box": _box(2), "now": 250, "broken": [], "stars": 4},
		{"name": "late", "box": _box(2), "now": 301, "broken": [], "stars": 3},
		{"name": "mislabeled", "box": _box(2, &"other"), "now": 70, "broken": [], "stars": 3},
		{"name": "broken", "box": _box(2), "now": 70, "broken": [&"avg"], "stars": 2},
		{"name": "wrong box", "box": _box(1), "now": 70, "broken": [], "stars": 1},
		{"name": "wrong box and late", "box": _box(1), "now": 301, "broken": [], "stars": 1},
		{"name": "broken and late", "box": _box(2), "now": 301, "broken": [&"avg"], "stars": 2},
	]
	for c: Dictionary in cases:
		var book := _book_out()
		var result: Dictionary = OrderSettlement.settle(book, state, &"o1", c["box"], c["now"], c["broken"], _products)
		_expect(result["ok"] and result.get("stars") == c["stars"], "settle: %s is %d stars" % [c["name"], c["stars"]])
		_expect(OrderRating.stars(result) == result["stars"], "settle: %s matches OrderRating" % c["name"])
		book.free()
	var book := _book_out()
	var once: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	var twice: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	_expect(once["stars"] == 5 and twice["stars"] == 0, "settling twice rates the second one 0")
	_expect(not OrderSettlement.settle(null, state, &"o1", _box(2), 70, [], _products)["stars"], "no book: 0")
	book.free()
	var idle := OrderBook.new()
	idle.add(Order.make(&"o1", "C", &"centro", &"h", [{"product": &"avg", "qty": 2}], 60, _products))
	_expect(OrderSettlement.settle(idle, state, &"o1", _box(2), 70, [], _products)["stars"] == 0, "open order: 0")
	idle.free()


func _test_no_side_effects(state: Node) -> void:
	state.new_company("Quiet Co")
	var book := _book_out()
	var result: Dictionary = OrderSettlement.settle(book, state, &"o1", _box(2), 70, [], _products)
	var money: int = state.money
	var rep: float = state.reputation
	var ledger: int = state.ledger.size()
	var snapshot: Dictionary = book.to_dict()
	var before: Dictionary = result.duplicate(true)
	for i in 3:
		OrderRating.stars(result)
		OrderRating.label(OrderRating.stars(result))
	_expect(state.money == money and state.reputation == rep, "rating moves neither money nor reputation")
	_expect(state.ledger.size() == ledger, "rating writes no ledger line")
	_expect(book.to_dict() == snapshot, "rating leaves the book as it was")
	_expect(result == before, "rating leaves the result as it was")
	_expect(not book.get_order(&"o1").has("stars"), "the book keeps no stars yet (D-0816.b)")
	book.free()


func _test_labels() -> void:
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for stars in range(1, 6):
			var key: String = OrderRating.label_key(stars)
			_expect(key == KEYS[stars - 1], "key of %d stars is %s" % [stars, KEYS[stars - 1]])
			var text: String = OrderRating.label(stars)
			_expect(not text.is_empty() and text != key, "%s: %d stars has a label (got '%s')" % [locale, stars, text])
	TranslationServer.set_locale("es")
	var words: Dictionary = {}
	for stars in range(1, 6):
		words[OrderRating.label(stars)] = true
	_expect(words.size() == 5, "the five labels differ")
	for bad: int in [-1, 0, 6, 99]:
		_expect(OrderRating.label(bad) == "" and OrderRating.label_key(bad) == "", "no label for %d" % bad)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
