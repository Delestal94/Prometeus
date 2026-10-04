extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_placeable_shop.gd
##
## Buying and selling warehouse objects (expansion D-0920, PlaceableShop):
## - buy() charges the price, adds a {id, x, z, turns} entry and logs "placeable_buy";
## - buy() with too little money changes nothing (no entry, no charge);
## - free = true adds a piece without charging (objects owned at start);
## - sell() removes the entry and pays floor(price x ratio), logged as "placeable_sell";
## - sell() with a bad index or unknown id changes nothing and returns -1;
## - buying then selling loses exactly price - refund.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Shop Co")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	_expect(shelf != null and PlaceableShop.definition(&"nope") == null, "definition() finds by id")
	var start: int = state.money
	_expect(PlaceableShop.buy(state, shelf, 3, 4, 5), "buy() with enough money works")
	_expect(state.money == start - shelf.price, "price charged (got %d)" % state.money)
	_expect(state.layout.size() == 1 and state.layout[0] == {"id": "shelf", "x": 3, "z": 4, "turns": 1},
		"entry has id, cell and turns wrapped to 0-3")
	_expect(state.ledger_total(PlaceableShop.REASON_BUY) == -shelf.price, "buy is in the ledger")
	_expect(PlaceableShop.buy(state, shelf, 0, 0, 0, true) and state.money == start - shelf.price,
		"free = true adds without charging")
	state.money = shelf.price - 1
	var size: int = state.layout.size()
	_expect(not PlaceableShop.buy(state, shelf, 1, 1), "buy() refuses when it cannot pay")
	_expect(state.layout.size() == size and state.money == shelf.price - 1, "a refused buy changes nothing")
	state.money = 1000
	_expect(PlaceableShop.sell(state, 99) == -1 and PlaceableShop.sell(state, -1) == -1,
		"sell() refuses a bad index")
	state.layout.append({"id": "ghost", "x": 0, "z": 0, "turns": 0})
	_expect(PlaceableShop.sell(state, state.layout.size() - 1) == -1, "sell() refuses an unknown id")
	_expect(state.layout.size() == size + 1 and state.money == 1000, "refusals change nothing")
	state.layout.pop_back()
	var refund: int = PlaceableShop.sell(state, 0)
	_expect(refund == shelf.refund() and refund == 40, "sell() returns the refund (got %d)" % refund)
	_expect(state.money == 1040 and state.layout.size() == size - 1, "refund paid and piece removed")
	_expect(state.ledger_total(PlaceableShop.REASON_SELL) == 40, "sell is in the ledger")
	_expect(PlaceableShop.round_trip_loss(shelf) == 40, "round trip loses price - refund")
	state.reset()
	if _failures == 0:
		print("PASS: placeable shop buys, sells with partial refund and refuses bad calls")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
